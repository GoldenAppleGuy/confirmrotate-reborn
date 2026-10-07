// ConfirmRotate Reborn - asks before the screen rotates (a modern take on ConfirmRotate, iOS 15 to 17).
//
// The tweak holds the screen in its current orientation, so it stays put when the phone is turned. A
// button then appears, turned to match the new physical orientation; tapping it moves the hold there,
// which rotates the screen. How the hold works depends on the iOS version:
// - iOS 17: orientation is decided by SpringBoard's traits pipeline, which reads the device orientation
//   from SBTraitsEmbeddedDisplayPipelineManager -inputs. The tweak replaces that orientation with the held
//   one, and asks the pipeline to run again when the hold moves.
// - iOS 15 (the older path, without that pipeline): every orientation change reaches SpringBoard through
//   -[SpringBoard _deviceOrientationChanged:]. While holding, only the held orientation is let through;
//   moving the hold passes the new orientation through it.
//
// The button: tap to rotate; long press to rotate and add the app to the blacklist; swipe to dismiss.
// With auto-rotate on, it rotates by itself after a delay (a ring fills around it as it counts down);
// with Tap to Cancel as well, it reads "Cancel?" instead and a tap keeps the screen as it is.
//
// The Control Center lock still wins: while it is on, nothing is held and no button shows.
// Settings: TweakSettings > ConfirmRotate Reborn (domain com.goldenappleguy.confirmrotatereborn; settings from
// the first versions, under com.goldenappleguy.confirmrotate17, are copied over once).

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>
#import <rootless.h>

#define CR_PREFS_DOMAIN CFSTR("com.goldenappleguy.confirmrotatereborn")
#define CR_OLD_PREFS_DOMAIN CFSTR("com.goldenappleguy.confirmrotate17")
#define CR_PREFS_CHANGED "com.goldenappleguy.confirmrotatereborn/changed"
#define CR_DEBUG_FLAG @"/var/mobile/Documents/confirmrotate.debug" // present: write the log below
#define CR_DEBUG_LOG @"/var/mobile/Documents/confirmrotate.log"

@interface SBOrientationLockManager : NSObject
+ (instancetype)sharedInstance;
- (void)lock;
- (void)unlock;
- (BOOL)isUserLocked;
@end

@interface TRAArbitrationDeviceOrientationInputs : NSObject
- (instancetype)initWithCurrentDeviceOrientation:(long long)current nonFlatDeviceOrientation:(long long)nonFlat;
- (long long)currentDeviceOrientation;
@end

@interface TRAArbitrationInputs : NSObject
- (instancetype)initWithInterfaceIdiomInputs:(id)idiom userInterfaceStyleInputs:(id)style deviceOrientationInputs:(id)orientation keyboardInputs:(id)keyboard ambientPresentationInputs:(id)ambient;
- (id)interfaceIdiomInputs;
- (id)userInterfaceStyleInputs;
- (TRAArbitrationDeviceOrientationInputs *)deviceOrientationInputs;
- (id)keyboardInputs;
- (id)ambientPresentationInputs;
@end

@interface TRAArbiter : NSObject
- (void)_setNeedsUpdateArbitrationWithReason:(NSString *)reason animated:(BOOL)animated;
- (void)updateArbitrationIfNeeded;
@end

@interface SBTraitsPipelineManager : NSObject
- (TRAArbiter *)arbiter;
- (TRAArbitrationInputs *)inputs;
@end

@interface SBLayoutElement : NSObject
- (NSString *)uniqueIdentifier; // "sceneID:<bundle ID>-<UUID>"
- (long long)layoutRole;        // 1: primary
@end

@interface SBLayoutState : NSObject
- (NSSet<SBLayoutElement *> *)elements;
@end

@interface SBLayoutStateTransitionContext : NSObject
- (SBLayoutState *)fromLayoutState;
- (SBLayoutState *)toLayoutState;
@end

@interface SBTraitsEmbeddedDisplayPipelineManager : SBTraitsPipelineManager
- (void)_noteInputsNeedUpdateAnimated:(BOOL)animated reason:(NSString *)reason;
@end

@interface SBSceneManagerCoordinator : NSObject
+ (id)mainDisplaySceneManager;
@end

@interface SBSceneManager : NSObject
- (NSSet *)externalForegroundApplicationSceneHandles;
@end

@interface SBApplication : NSObject
- (NSString *)bundleIdentifier;
@end

@interface SBSceneHandle : NSObject
- (id)scene;
- (SBApplication *)application;
@end

@interface FBScene : NSObject
- (id)clientSettings;
@end

@interface SpringBoard : UIApplication
- (UIInterfaceOrientation)activeInterfaceOrientation;
- (void)_deviceOrientationChanged:(long long)orientation;       // iOS 15 path
- (long long)rawDeviceOrientationIgnoringOrientationLocks;
@end

@interface SBLayoutStateTransitionCoordinator : NSObject
- (SBLayoutStateTransitionContext *)transitionContext;
@end

@interface CRWindow : UIWindow
@end

@implementation CRWindow
// Only the button takes touches; everything else falls through to what is underneath.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self || hit == self.rootViewController.view) ? nil : hit;
}
@end

@interface CRController : NSObject
+ (instancetype)shared;
- (void)start;
- (void)deviceOrientationChanged;
- (void)prefsChanged;
@end

// Debug log, written only while CR_DEBUG_FLAG exists (read over SSH)
static BOOL gDebugLog;

static void CRLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void CRLog(NSString *format, ...) {
    if (!gDebugLog) return;
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:CR_DEBUG_LOG];
    if (!handle) {
        [[NSFileManager defaultManager] createFileAtPath:CR_DEBUG_LOG contents:nil attributes:nil];
        handle = [NSFileHandle fileHandleForWritingAtPath:CR_DEBUG_LOG];
    }
    [handle seekToEndOfFile];
    [handle writeData:[[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

static CRWindow *gWindow;
static UIView *gButton;
static CAShapeLayer *gRing;    // auto-rotate countdown around the button
static UIInterfaceOrientation gTarget;
static BOOL gShown;
static BOOL gStarted;
static NSUInteger gToken;      // pending "phone settled" check
static NSUInteger gHideToken;  // pending auto-hide
static NSUInteger gAutoToken;  // pending auto-rotate
static BOOL gHolding;
static UIDeviceOrientation gRawDevice; // physical orientation, as the traits pipeline receives it before the lock
static __weak SBTraitsPipelineManager *gPipelineManager; // iOS 17 traits pipeline that decides orientation
static UIInterfaceOrientation gHeld;
static BOOL gLegacy;   // iOS 15 path (no traits pipeline): holds by filtering -[SpringBoard _deviceOrientationChanged:]
static BOOL gPassing;  // iOS 15 path: our own call into _deviceOrientationChanged:, let it through

// Settings
static BOOL gEnabled = YES;
static CGFloat gButtonSize = 56.0;
static BOOL gRoundedSquare;            // button shape: circle or rounded square
static CGFloat gButtonOpacity = 1.0;
static NSString *gIconColor = @"Default";
// Button position: on a long side of the screen, 10% in from the edge, at this fraction of the side's
// length from the top of the phone (where the status bar is in portrait). In landscape it sits on the
// bottom edge; returning to portrait, it stays at the same physical spot.
static CGFloat gDistanceFromStatusBar = 0.25;
#define CR_EDGE_INSET 0.10
static NSTimeInterval gHideAfter = 5.0;
static NSTimeInterval gAutoRotateAfter;   // 0: off
static BOOL gTapToCancel = YES;           // with auto-rotate: the button reads "Cancel?" and a tap cancels
static BOOL gHaptics = YES;
static BOOL gPortraitOnAppSwitch;
static NSSet<NSString *> *gAlwaysShowApps; // apps that rotate themselves without declaring it
static NSSet<NSString *> *gWhitelistApps;  // when not empty, the only apps the tweak acts in
static NSSet<NSString *> *gBlacklistApps;  // apps the tweak leaves alone (they rotate freely)
static NSString *gFrontBundle = @"";       // front app ("" for the home screen)
static BOOL gExcluded;                     // front app is outside the whitelist or in the blacklist

static BOOL CREnabled(void) {
    return gEnabled;
}

static double CRPrefNumber(CFStringRef key, double fallback, double min, double max) {
    CFPropertyListRef value = CFPreferencesCopyAppValue(key, CR_PREFS_DOMAIN);
    double result = [(__bridge id)value respondsToSelector:@selector(doubleValue)] ? [(__bridge id)value doubleValue] : fallback;
    if (value) CFRelease(value);
    return MIN(MAX(result, min), max);
}

static NSString *CRPrefString(CFStringRef key, NSString *fallback) {
    CFPropertyListRef value = CFPreferencesCopyAppValue(key, CR_PREFS_DOMAIN);
    NSString *result = [(__bridge id)value isKindOfClass:[NSString class]] ? [(__bridge NSString *)value copy] : fallback;
    if (value) CFRelease(value);
    return result;
}

static NSSet<NSString *> *CRPrefAppSet(CFStringRef key) {
    CFPropertyListRef value = CFPreferencesCopyAppValue(key, CR_PREFS_DOMAIN);
    NSSet *result = [(__bridge id)value isKindOfClass:[NSArray class]] ? [NSSet setWithArray:(__bridge NSArray *)value] : [NSSet set];
    if (value) CFRelease(value);
    return result;
}

// Settings saved by the first versions (old domain) are copied to the new one, once
static void CRMigrateOldPrefs(void) {
    CFArrayRef newKeys = CFPreferencesCopyKeyList(CR_PREFS_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL hasNew = newKeys && CFArrayGetCount(newKeys) > 0;
    if (newKeys) CFRelease(newKeys);
    if (hasNew) return;
    CFArrayRef oldKeys = CFPreferencesCopyKeyList(CR_OLD_PREFS_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (!oldKeys) return;
    for (NSString *key in (__bridge NSArray *)oldKeys) {
        CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, CR_OLD_PREFS_DOMAIN);
        if (value) {
            CFPreferencesSetAppValue((__bridge CFStringRef)key, value, CR_PREFS_DOMAIN);
            CFRelease(value);
        }
    }
    CFRelease(oldKeys);
    CFPreferencesAppSynchronize(CR_PREFS_DOMAIN);
    CRLog(@"copied settings from the old domain");
}

static BOOL CRIsExcluded(NSString *bundle) {
    if (bundle.length == 0) bundle = @"com.apple.springboard";
    if ([gBlacklistApps containsObject:bundle]) return YES;
    return gWhitelistApps.count > 0 && ![gWhitelistApps containsObject:bundle];
}

// "sceneID:<bundle ID>-<UUID>" or "sceneID:<bundle ID>-default" -> bundle ID ("" for none)
static NSString *CRBundleForScene(NSString *scene) {
    if (![scene hasPrefix:@"sceneID:"]) return @"";
    NSString *rest = [scene substringFromIndex:8];
    if ([rest hasSuffix:@"-default"]) return [rest substringToIndex:rest.length - 8];
    if (rest.length > 37 && [rest characterAtIndex:rest.length - 37] == '-') rest = [rest substringToIndex:rest.length - 37];
    return rest;
}

// Updates the front app; YES if that changed whether the tweak is excluded from it
static BOOL CRSetFrontBundle(NSString *bundle) {
    BOOL wasExcluded = gExcluded;
    gFrontBundle = bundle ?: @"";
    gExcluded = CRIsExcluded(gFrontBundle);
    return gExcluded != wasExcluded;
}

static void CRLoadPrefs(void) {
    gDebugLog = [[NSFileManager defaultManager] fileExistsAtPath:CR_DEBUG_FLAG];
    CFPreferencesAppSynchronize(CR_PREFS_DOMAIN);
    gEnabled = CRPrefNumber(CFSTR("Enabled"), 1, 0, 1) != 0;
    gPortraitOnAppSwitch = CRPrefNumber(CFSTR("PortraitOnAppSwitch"), 0, 0, 1) != 0;
    gButtonSize = round(CRPrefNumber(CFSTR("ButtonSize"), 56, 44, 96));
    gRoundedSquare = CRPrefNumber(CFSTR("ButtonShape"), 0, 0, 1) == 1;
    gButtonOpacity = round(CRPrefNumber(CFSTR("ButtonOpacity"), 100, 20, 100)) / 100.0;
    gIconColor = CRPrefString(CFSTR("IconColor"), @"Default");
    gDistanceFromStatusBar = round(CRPrefNumber(CFSTR("DistanceFromStatusBar"), 25, 5, 95)) / 100.0;
    gHideAfter = round(CRPrefNumber(CFSTR("HideAfter"), 5, 1, 15));
    // Auto-Rotate switch (with Tap to Cancel and the delay as its options). Earlier versions had only the
    // delay, 0 meaning off: a delay already set turns the switch on, once.
    CFPropertyListRef autoRotate = CFPreferencesCopyAppValue(CFSTR("AutoRotate"), CR_PREFS_DOMAIN);
    if (autoRotate) CFRelease(autoRotate);
    else if (CRPrefNumber(CFSTR("AutoRotateAfter"), 0, 0, 10) >= 1) {
        CFPreferencesSetAppValue(CFSTR("AutoRotate"), kCFBooleanTrue, CR_PREFS_DOMAIN);
        CFPreferencesAppSynchronize(CR_PREFS_DOMAIN);
    }
    BOOL autoRotateOn = CRPrefNumber(CFSTR("AutoRotate"), 0, 0, 1) != 0;
    gAutoRotateAfter = autoRotateOn ? round(CRPrefNumber(CFSTR("AutoRotateAfter"), 3, 1, 10)) : 0;
    gTapToCancel = CRPrefNumber(CFSTR("TapToCancel"), 1, 0, 1) != 0;
    gHaptics = CRPrefNumber(CFSTR("Haptics"), 1, 0, 1) != 0;
    gAlwaysShowApps = CRPrefAppSet(CFSTR("AlwaysShowApps"));
    gWhitelistApps = CRPrefAppSet(CFSTR("WhitelistApps"));
    gBlacklistApps = CRPrefAppSet(CFSTR("BlacklistApps"));
}

// The button's text, translated: the tweak has no bundle of its own, so its strings live in the settings
// bundle (Tweak.strings in each language folder)
static NSString *CRLocalized(NSString *key) {
    static NSBundle *bundle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ bundle = [NSBundle bundleWithPath:ROOT_PATH_NS(@"/Library/PreferenceBundles/ConfirmRotateRebornPrefs.bundle")]; });
    return bundle ? [bundle localizedStringForKey:key value:key table:@"Tweak"] : key;
}

static void CRHaptic(UIImpactFeedbackStyle style) {
    if (gHaptics) [[[UIImpactFeedbackGenerator alloc] initWithStyle:style] impactOccurred];
}

static UIColor *CRAccentColor(void) {
    NSDictionary<NSString *, UIColor *> *colors = @{
        @"Blue": [UIColor systemBlueColor], @"Green": [UIColor systemGreenColor], @"Orange": [UIColor systemOrangeColor],
        @"Pink": [UIColor systemPinkColor], @"Purple": [UIColor systemPurpleColor], @"Red": [UIColor systemRedColor],
        @"Teal": [UIColor systemTealColor], @"Yellow": [UIColor systemYellowColor],
    };
    return colors[gIconColor] ?: [UIColor labelColor]; // Default: follows light / dark mode
}

static SBOrientationLockManager *CRLockManager(void) {
    return [objc_getClass("SBOrientationLockManager") sharedInstance];
}

static UIInterfaceOrientation CRActiveOrientation(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if ([app respondsToSelector:@selector(activeInterfaceOrientation)]) {
        return [(SpringBoard *)app activeInterfaceOrientation];
    }
    return UIInterfaceOrientationPortrait;
}

// Makes a changed hold take effect without the phone moving: iOS 17 runs the traits pipeline again;
// the iOS 15 path passes the orientation SpringBoard should now have (the held one, or the physical
// one when not holding) through _deviceOrientationChanged:.
static void CRRequestArbitration(void) {
    if (gLegacy) {
        long long orientation = (gHolding && !gExcluded) ? gHeld : gRawDevice;
        SpringBoard *springBoard = (SpringBoard *)[UIApplication sharedApplication];
        if (orientation <= 0 || ![springBoard respondsToSelector:@selector(_deviceOrientationChanged:)]) return;
        gPassing = YES;
        [springBoard _deviceOrientationChanged:orientation];
        gPassing = NO;
        return;
    }
    if ([gPipelineManager respondsToSelector:@selector(_noteInputsNeedUpdateAnimated:reason:)]) {
        [(SBTraitsEmbeddedDisplayPipelineManager *)gPipelineManager _noteInputsNeedUpdateAnimated:YES reason:@"ConfirmRotateReborn"];
        return;
    }
    TRAArbiter *arbiter = [gPipelineManager arbiter];
    if (![arbiter respondsToSelector:@selector(_setNeedsUpdateArbitrationWithReason:animated:)]) return;
    [arbiter _setNeedsUpdateArbitrationWithReason:@"ConfirmRotateReborn" animated:YES];
    [arbiter updateArbitrationIfNeeded];
}

// Pins the interface to an orientation; moving the pin rotates the screen there. Applied in the
// -inputs hook (iOS 17) or the _deviceOrientationChanged: hook (iOS 15) below.
static void CRHold(UIInterfaceOrientation orientation) {
    if (gHolding && gHeld == orientation) return;
    gHolding = YES;
    gHeld = orientation;
    CRLog(@"hold %ld", (long)orientation);
    CRRequestArbitration();
}

static void CRRelease(void) {
    if (!gHolding) return;
    gHolding = NO;
    CRLog(@"release");
    CRRequestArbitration();
}

// Calls an orientation-mask getter only if it really returns an integer (private API; types can change).
static BOOL CRMask(id object, SEL selector, UIInterfaceOrientationMask *out) {
    Method method = object ? class_getInstanceMethod([object class], selector) : NULL;
    if (!method) return NO;
    char type[8];
    method_getReturnType(method, type, sizeof(type));
    if (type[0] != 'Q' && type[0] != 'q') return NO;
    *out = ((UIInterfaceOrientationMask (*)(id, SEL))method_getImplementation(method))(object, selector);
    return YES;
}

// Whether the front app currently supports an orientation, as it last reported to SpringBoard (its
// scene's client settings follow whatever screen it is showing). With no app in front (home or lock
// screen), only portrait counts on iPhone. Apps in the Always Show In list always count: some (such as
// video apps) report portrait only and switch to landscape themselves when they see the phone turn.
static BOOL CRFrontAppSupports(UIInterfaceOrientation orientation) {
    Class coordinator = objc_getClass("SBSceneManagerCoordinator");
    SBSceneManager *manager = [coordinator respondsToSelector:@selector(mainDisplaySceneManager)] ? [coordinator mainDisplaySceneManager] : nil;
    if (![manager respondsToSelector:@selector(externalForegroundApplicationSceneHandles)]) return YES; // unknown: don't hide the button
    NSSet *handles = [manager externalForegroundApplicationSceneHandles];
    if (handles.count == 0) {
        return orientation == UIInterfaceOrientationPortrait || [UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad;
    }
    for (SBSceneHandle *handle in handles) {
        SBApplication *app = [handle respondsToSelector:@selector(application)] ? [handle application] : nil;
        if ([app respondsToSelector:@selector(bundleIdentifier)] && [gAlwaysShowApps containsObject:[app bundleIdentifier]]) return YES;
        FBScene *scene = [handle respondsToSelector:@selector(scene)] ? [handle scene] : nil;
        id clientSettings = [scene respondsToSelector:@selector(clientSettings)] ? [scene clientSettings] : nil;
        UIInterfaceOrientationMask mask = 0;
        if (!CRMask(clientSettings, @selector(supportedInterfaceOrientations), &mask) || mask == 0) {
            if (!CRMask(handle, @selector(supportedInterfaceOrientations), &mask) || mask == 0) return YES;
        }
        if (mask & (1 << orientation)) return YES;
    }
    return NO;
}

// Physical orientation -> the interface orientation it produces (UIKit names the landscape cases
// the other way round, so the raw values match). NO for flat / unknown, and for upside-down on phones.
static BOOL CRInterfaceOrientationFor(UIDeviceOrientation device, UIInterfaceOrientation *out) {
    switch (device) {
        case UIDeviceOrientationPortrait: *out = UIInterfaceOrientationPortrait; return YES;
        case UIDeviceOrientationLandscapeLeft: *out = UIInterfaceOrientationLandscapeRight; return YES;
        case UIDeviceOrientationLandscapeRight: *out = UIInterfaceOrientationLandscapeLeft; return YES;
        case UIDeviceOrientationPortraitUpsideDown:
            if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
                *out = UIInterfaceOrientationPortraitUpsideDown;
                return YES;
            }
            return NO;
        default: return NO;
    }
}

// Rotation (UIKit convention, clockwise positive) that makes content look upright when the
// phone is held in this orientation, measured against the panel's native portrait layout.
static CGFloat CRUprightAngle(UIDeviceOrientation device) {
    switch (device) {
        case UIDeviceOrientationLandscapeLeft: return M_PI_2;
        case UIDeviceOrientationLandscapeRight: return -M_PI_2;
        case UIDeviceOrientationPortraitUpsideDown: return M_PI;
        default: return 0;
    }
}

static UIWindowScene *CRWindowScene(void) {
    id app = [UIApplication sharedApplication];
    id manager = [app respondsToSelector:@selector(windowSceneManager)] ? [app performSelector:@selector(windowSceneManager)] : nil;
    id scene = [manager respondsToSelector:@selector(embeddedDisplayWindowScene)] ? [manager performSelector:@selector(embeddedDisplayWindowScene)] : nil;
    if ([scene isKindOfClass:[UIWindowScene class]]) return scene;
    for (UIScene *candidate in [UIApplication sharedApplication].connectedScenes) {
        if ([candidate isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)candidate;
    }
    return nil;
}

// Stops the auto-rotate countdown (the ring disappears)
static void CRCancelAutoRotate(void) {
    gAutoToken++;
    [gRing removeAllAnimations];
    [gRing removeFromSuperlayer];
    gRing = nil;
}

static void CRHide(BOOL animated);

static void CRScheduleHide(NSTimeInterval delay) {
    NSUInteger token = ++gHideToken;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token != gHideToken || !gShown) return;
        CRLog(@"auto-hide");
        CRHide(YES);
    });
}

static void CRHide(BOOL animated) {
    gHideToken++;
    CRCancelAutoRotate();
    if (!gShown) return;
    gShown = NO;
    UIView *button = gButton;
    CRWindow *window = gWindow;
    void (^finish)(void) = ^{
        if (gShown) return; // shown again in the meantime
        [button removeFromSuperview];
        window.hidden = YES;
        if (gButton == button) gButton = nil;
    };
    if (animated) {
        CGAffineTransform t = button.transform;
        [UIView animateWithDuration:0.1 animations:^{
            button.alpha = 0;
            button.transform = CGAffineTransformScale(t, 0.7, 0.7);
        } completion:^(BOOL done) { finish(); }];
    } else {
        finish();
    }
}

static void CRConfirm(void) {
    if (!gShown) return;
    CRLog(@"confirmed");
    CRHaptic(UIImpactFeedbackStyleMedium);
    UIInterfaceOrientation target = gTarget;
    CRHide(YES);
    CRHold(target);
}

// Long press: rotate, and add the front app to the blacklist so it rotates freely from now on
static void CRConfirmAndBlacklist(void) {
    if (!gShown) return;
    if (gFrontBundle.length == 0) { // home screen: nothing to add
        CRConfirm();
        return;
    }
    CRLog(@"blacklisting %@", gFrontBundle);
    NSMutableArray *list = [gBlacklistApps.allObjects mutableCopy];
    if (![list containsObject:gFrontBundle]) [list addObject:gFrontBundle];
    CFPreferencesSetAppValue(CFSTR("BlacklistApps"), (__bridge CFArrayRef)list, CR_PREFS_DOMAIN);
    CFPreferencesAppSynchronize(CR_PREFS_DOMAIN);
    gBlacklistApps = [NSSet setWithArray:list];
    // Tell the settings page (its count), as a settings change from there would
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(CR_PREFS_CHANGED), NULL, NULL, YES);

    if (gHaptics) [[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:UINotificationFeedbackTypeSuccess];
    CRHide(YES);
    CRSetFrontBundle(gFrontBundle); // now excluded: the pipeline gets the physical orientation again
    CRRequestArbitration();
}

// Swipe: the button follows the finger, and is dismissed if thrown far or fast enough
@interface CRButtonGestures : NSObject
@end

@implementation CRButtonGestures {
    CGPoint _startCenter;
}

- (void)tapped:(UITapGestureRecognizer *)gesture {
    if (gAutoRotateAfter > 0 && gTapToCancel) { // the button reads "Cancel?": keep the screen as it is
        if (!gShown) return;
        CRLog(@"cancelled");
        CRHaptic(UIImpactFeedbackStyleLight);
        CRHide(YES);
        return;
    }
    CRConfirm();
}

- (void)longPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) CRConfirmAndBlacklist();
}

- (void)panned:(UIPanGestureRecognizer *)gesture {
    UIView *button = gesture.view;
    UIView *container = button.superview;
    CGPoint translation = [gesture translationInView:container];
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
            _startCenter = button.center;
            CRCancelAutoRotate();
            gHideToken++; // no auto-hide while held
            break;
        case UIGestureRecognizerStateChanged:
            button.center = CGPointMake(_startCenter.x + translation.x, _startCenter.y + translation.y);
            break;
        default: {
            CGPoint velocity = [gesture velocityInView:container];
            CGFloat distance = hypot(translation.x, translation.y), speed = hypot(velocity.x, velocity.y);
            if (gesture.state == UIGestureRecognizerStateEnded && (distance > 60 || speed > 600)) {
                CGFloat dx = speed > 1 ? velocity.x / speed : translation.x / MAX(distance, 1);
                CGFloat dy = speed > 1 ? velocity.y / speed : translation.y / MAX(distance, 1);
                CRLog(@"swiped away");
                gShown = NO;
                gHideToken++;
                CRWindow *window = gWindow;
                [UIView animateWithDuration:0.2 animations:^{
                    button.center = CGPointMake(button.center.x + dx * 300, button.center.y + dy * 300);
                    button.alpha = 0;
                } completion:^(BOOL done) {
                    [button removeFromSuperview];
                    if (!gShown) window.hidden = YES;
                    if (gButton == button) gButton = nil;
                }];
            } else {
                [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0 options:0 animations:^{
                    button.center = self->_startCenter;
                } completion:nil];
                CRScheduleHide(gHideAfter);
            }
            break;
        }
    }
}

@end

static CRButtonGestures *gGestures;

static UIView *CRMakeButton(void) {
    UIView *button = [[UIView alloc] initWithFrame:CGRectMake(0, 0, gButtonSize, gButtonSize)];
    CGFloat cornerRadius = gRoundedSquare ? gButtonSize * 0.25 : gButtonSize / 2;
    button.layer.cornerRadius = cornerRadius;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.layer.masksToBounds = YES;
    UIColor *accent = CRAccentColor();

    // System material: follows light / dark mode
    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterial]];
    blur.frame = button.bounds;
    blur.userInteractionEnabled = NO;
    [button addSubview:blur];

    // Control Center's rotation lock symbol over a "Rotate?" caption ("Cancel?" with auto-rotate on),
    // both scaled with the button
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:round(gButtonSize * 0.34) weight:UIImageSymbolWeightSemibold];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lock.rotation" withConfiguration:config]];
    icon.tintColor = accent;
    [icon sizeToFit];

    UILabel *caption = [UILabel new];
    BOOL cancels = gAutoRotateAfter > 0 && gTapToCancel;
    caption.text = CRLocalized(cancels ? @"Cancel?" : @"Rotate?");
    caption.font = [UIFont systemFontOfSize:MAX(9.0, round(gButtonSize * 0.16)) weight:UIFontWeightSemibold];
    caption.textColor = accent;
    caption.adjustsFontSizeToFitWidth = YES;
    caption.minimumScaleFactor = 0.7;
    caption.textAlignment = NSTextAlignmentCenter;
    [caption sizeToFit];
    CGFloat captionWidth = MIN(caption.bounds.size.width, gButtonSize * (gRoundedSquare ? 0.86 : 0.74));
    CGFloat spacing = round(gButtonSize * 0.03);
    CGFloat contentHeight = icon.bounds.size.height + spacing + caption.bounds.size.height;
    CGFloat top = (gButtonSize - contentHeight) / 2;
    icon.center = CGPointMake(gButtonSize / 2, top + icon.bounds.size.height / 2);
    caption.frame = CGRectMake((gButtonSize - captionWidth) / 2, top + icon.bounds.size.height + spacing, captionWidth, caption.bounds.size.height);
    icon.userInteractionEnabled = NO;
    caption.userInteractionEnabled = NO;
    [button addSubview:icon];
    [button addSubview:caption];

    if (!gGestures) gGestures = [CRButtonGestures new];
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:gGestures action:@selector(longPressed:)];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:gGestures action:@selector(tapped:)];
    [tap requireGestureRecognizerToFail:longPress];
    [button addGestureRecognizer:tap];
    [button addGestureRecognizer:longPress];
    [button addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:gGestures action:@selector(panned:)]];

    button.accessibilityLabel = CRLocalized(cancels ? @"Cancel rotation" : @"Rotate screen");
    button.isAccessibilityElement = YES;
    button.accessibilityTraits = UIAccessibilityTraitButton;
    return button;
}

// Auto-rotate: a ring fills around the button's edge; when it closes, the screen rotates
static void CRStartAutoRotate(UIView *button) {
    if (gAutoRotateAfter <= 0) return;
    CGFloat width = MAX(2.5, round(gButtonSize * 0.05));
    CGRect ringRect = CGRectInset(button.bounds, width / 2, width / 2);
    UIBezierPath *path;
    if (gRoundedSquare) {
        path = [UIBezierPath bezierPathWithRoundedRect:ringRect cornerRadius:gButtonSize * 0.25 - width / 2];
    } else {
        path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(gButtonSize / 2, gButtonSize / 2) radius:ringRect.size.width / 2
                                          startAngle:-M_PI_2 endAngle:3 * M_PI_2 clockwise:YES];
    }
    gRing = [CAShapeLayer layer];
    gRing.path = path.CGPath;
    gRing.fillColor = nil;
    gRing.strokeColor = CRAccentColor().CGColor;
    gRing.lineWidth = width;
    gRing.lineCap = kCALineCapRound;
    gRing.strokeEnd = 1;
    [button.layer addSublayer:gRing];
    CABasicAnimation *fill = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    fill.fromValue = @0;
    fill.toValue = @1;
    fill.duration = gAutoRotateAfter;
    [gRing addAnimation:fill forKey:@"countdown"];

    NSUInteger token = ++gAutoToken;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(gAutoRotateAfter * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token != gAutoToken || !gShown) return;
        CRLog(@"auto-rotate");
        CRConfirm();
    });
}

static void CRShow(UIDeviceOrientation device, UIInterfaceOrientation target) {
    UIWindowScene *scene = CRWindowScene();
    if (!scene) return;

    if (gShown) CRHide(NO);

    if (!gWindow) {
        gWindow = [[CRWindow alloc] initWithWindowScene:scene];
        gWindow.windowLevel = UIWindowLevelAlert + 3200.0;
        gWindow.backgroundColor = [UIColor clearColor];
        UIViewController *root = [UIViewController new];
        root.view.backgroundColor = [UIColor clearColor];
        gWindow.rootViewController = root;
    }
    gWindow.frame = [UIScreen mainScreen].bounds;
    gWindow.hidden = NO;
    UIView *rootView = gWindow.rootViewController.view;
    rootView.frame = gWindow.bounds;

    // Work out where the button goes in the panel's fixed (always portrait) space, which is
    // independent of whatever orientation the window is currently in, then convert.
    id<UICoordinateSpace> fixed = [UIScreen mainScreen].fixedCoordinateSpace;
    CGRect fb = fixed.bounds;
    BOOL landscape = UIDeviceOrientationIsLandscape(device);
    CGFloat userWidth = landscape ? fb.size.height : fb.size.width;
    CGFloat userHeight = landscape ? fb.size.width : fb.size.height;
    // Position as the phone is held (fractions of the screen; x from the left, y from the top), kept
    // 12 pt inside the screen edge. Landscape: on the bottom edge, measured from the side the top of the
    // phone points to. Portrait: on the side that was the bottom in the landscape being left.
    CGFloat d = gDistanceFromStatusBar, edge = 1 - CR_EDGE_INSET;
    CGPoint position;
    if (device == UIDeviceOrientationLandscapeLeft) {           // top turned left
        position = CGPointMake(d, edge);
    } else if (device == UIDeviceOrientationLandscapeRight) {   // top turned right
        position = CGPointMake(1 - d, edge);
    } else if (CRActiveOrientation() == UIInterfaceOrientationLandscapeLeft) { // leaving top-turned-right
        position = CGPointMake(edge, d);
    } else {
        position = CGPointMake(1 - edge, d);
    }
    CGFloat maxX = userWidth / 2 - gButtonSize / 2 - 12.0;
    CGFloat maxY = userHeight / 2 - gButtonSize / 2 - 12.0;
    CGPoint offset = CGPointMake(MAX(-maxX, MIN(maxX, userWidth * (position.x - 0.5))),
                                 MAX(-maxY, MIN(maxY, userHeight * (position.y - 0.5))));
    CGFloat theta = CRUprightAngle(device);
    CGPoint centerFixed = CGPointMake(CGRectGetMidX(fb) + offset.x * cos(theta) - offset.y * sin(theta),
                                      CGRectGetMidY(fb) + offset.x * sin(theta) + offset.y * cos(theta));

    CGPoint a = [rootView convertPoint:CGPointZero fromCoordinateSpace:fixed];
    CGPoint b = [rootView convertPoint:CGPointMake(100, 0) fromCoordinateSpace:fixed];
    CGFloat psi = atan2(b.y - a.y, b.x - a.x); // how the window turns fixed-space directions

    UIView *button = CRMakeButton();
    button.center = [rootView convertPoint:centerFixed fromCoordinateSpace:fixed];
    CGAffineTransform upright = CGAffineTransformMakeRotation(theta + psi);
    button.transform = CGAffineTransformScale(upright, 0.6, 0.6);
    button.alpha = 0;
    [rootView addSubview:button];
    gButton = button;
    gTarget = target;
    gShown = YES;
    [UIView animateWithDuration:0.12 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0 options:0 animations:^{
        button.alpha = gButtonOpacity;
        button.transform = upright;
    } completion:nil];

    CRStartAutoRotate(button);
    // With auto-rotate on, the delay takes the place of Hide After: the button goes when it rotates (or is
    // cancelled); this is only a backstop
    CRScheduleHide(gAutoRotateAfter > 0 ? gAutoRotateAfter + 1 : gHideAfter);
}

static void CRLogPrefs(void) {
    CRLog(@"prefs: enabled=%d appSwitch=%d size=%.0f opacity=%.2f color=%@ hide=%.0f auto=%.0f cancel=%d haptics=%d always=%@ white=%@ black=%@ (front %@, excluded %d)",
          gEnabled, gPortraitOnAppSwitch, gButtonSize, gButtonOpacity, gIconColor, gHideAfter, gAutoRotateAfter, gTapToCancel, gHaptics,
          [gAlwaysShowApps.allObjects componentsJoinedByString:@","], [gWhitelistApps.allObjects componentsJoinedByString:@","],
          [gBlacklistApps.allObjects componentsJoinedByString:@","], gFrontBundle, gExcluded);
}

// The front app right now, from SpringBoard's foreground scenes ("" for the home screen)
static NSString *CRCurrentFrontBundle(void) {
    Class coordinator = objc_getClass("SBSceneManagerCoordinator");
    SBSceneManager *manager = [coordinator respondsToSelector:@selector(mainDisplaySceneManager)] ? [coordinator mainDisplaySceneManager] : nil;
    if (![manager respondsToSelector:@selector(externalForegroundApplicationSceneHandles)]) return @"";
    for (SBSceneHandle *handle in [manager externalForegroundApplicationSceneHandles]) {
        SBApplication *app = [handle respondsToSelector:@selector(application)] ? [handle application] : nil;
        if ([app respondsToSelector:@selector(bundleIdentifier)] && [app bundleIdentifier]) return [app bundleIdentifier];
    }
    return @"";
}

@implementation CRController
+ (instancetype)shared {
    static CRController *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [CRController new]; });
    return instance;
}

- (void)start {
    if (gLegacy) gRawDevice = (UIDeviceOrientation)[(SpringBoard *)[UIApplication sharedApplication] rawDeviceOrientationIgnoringOrientationLocks];
    CRMigrateOldPrefs();
    CRLoadPrefs();
    CRSetFrontBundle(CRCurrentFrontBundle());
    CRLogPrefs();
    if (CREnabled() && ![CRLockManager() isUserLocked]) CRHold(CRActiveOrientation());
    gStarted = YES;
    CRLog(@"started (%@ path, locked=%d, orientation=%ld)", gLegacy ? @"iOS 15" : @"iOS 17", [CRLockManager() isUserLocked], (long)gRawDevice);
}

- (void)prefsChanged {
    CRLoadPrefs();
    if (CRSetFrontBundle(gFrontBundle)) {
        if (gExcluded) CRHide(NO);
        CRRequestArbitration();
    }
    CRLogPrefs();
    if (!CREnabled()) {
        CRRelease();
        CRHide(NO);
    } else if (![CRLockManager() isUserLocked]) {
        CRHold(CRActiveOrientation());
    }
}

- (void)deviceOrientationChanged {
    if (!gStarted) return;
    CRLog(@"physical orientation %ld", (long)gRawDevice);
    // Wait for the phone to settle; it passes through other orientations while turning.
    NSUInteger token = ++gToken;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token == gToken) [self evaluate];
    });
}

- (void)evaluate {
    if (!CREnabled() || [CRLockManager() isUserLocked]) { // off, or the user's own lock is on
        CRRelease();
        CRHide(NO);
        return;
    }
    if (gExcluded) { // whitelist / blacklist: this app rotates freely
        CRHide(NO);
        return;
    }
    if (!gHolding) CRHold(CRActiveOrientation());
    UIDeviceOrientation device = gRawDevice;
    UIInterfaceOrientation target;
    if (!CRInterfaceOrientationFor(device, &target)) return; // flat or unknown: leave things as they are
    if (target == CRActiveOrientation()) {
        CRHide(YES);
    } else if (!CRFrontAppSupports(target)) {
        CRLog(@"front app does not support %ld", (long)target);
        CRHide(YES);
    } else if (!(gShown && gTarget == target)) {
        CRLog(@"show button for %ld (active %ld)", (long)target, (long)CRActiveOrientation());
        CRShow(device, target);
    }
}
@end

%group Common
%hook SBOrientationLockManager
// Turning the user lock off: pin the current orientation first so the screen does not rotate
// to the physical orientation by itself.
- (void)unlock {
    if (CREnabled()) CRHold(CRActiveOrientation());
    %orig;
}

// Turning it on: the user lock takes over.
- (void)lock {
    %orig;
    CRRelease();
    CRHide(NO);
}
%end
%end

// The primary app scene of a layout state ("" for the home screen)
static NSString *CRPrimaryScene(SBLayoutState *state) {
    if (![state respondsToSelector:@selector(elements)]) return @"";
    for (SBLayoutElement *element in [state elements]) {
        if ([element respondsToSelector:@selector(layoutRole)] && [element layoutRole] != 1) continue;
        if ([element respondsToSelector:@selector(uniqueIdentifier)]) return [element uniqueIdentifier] ?: @"";
    }
    return @"";
}

// A layout transition is starting (an app opening, the app switcher, going home). Handled before the
// new app is laid out, so it appears in the right orientation from the start:
// - an app the whitelist / blacklist excludes: stop holding, so it follows the phone
// - Portrait on App Switch: hold portrait
// - back from an excluded app: hold whatever orientation it was left in
static void CRLayoutTransitionBegan(SBLayoutStateTransitionContext *context) {
    if (![context respondsToSelector:@selector(fromLayoutState)] || ![context respondsToSelector:@selector(toLayoutState)]) return;
    NSString *from = CRPrimaryScene([context fromLayoutState]), *to = CRPrimaryScene([context toLayoutState]);
    if ([from isEqualToString:to]) return;
    BOOL exclusionChanged = CRSetFrontBundle(CRBundleForScene(to));
    BOOL active = gStarted && CREnabled() && ![CRLockManager() isUserLocked];
    if (gExcluded) {
        CRLog(@"app switch to %@: excluded", gFrontBundle);
        CRHide(NO);
        if (exclusionChanged) CRRequestArbitration();
    } else if (active && gPortraitOnAppSwitch) {
        CRLog(@"app switch to %@: portrait", gFrontBundle.length ? gFrontBundle : @"home screen");
        CRHide(NO);
        CRHold(UIInterfaceOrientationPortrait);
        if (exclusionChanged) CRRequestArbitration();
    } else if (active && exclusionChanged) {
        CRLog(@"app switch to %@: hold current", gFrontBundle.length ? gFrontBundle : @"home screen");
        gHeld = CRActiveOrientation();
        gHolding = YES;
        CRRequestArbitration();
    }
}

// iOS 17: the traits pipeline
%group Modern
%hook SBTraitsPipelineManager
- (id)initWithArbiter:(id)arbiter sceneDelegate:(id)delegate {
    id result = %orig;
    gPipelineManager = result;
    return result;
}
%end

%hook SBTraitsEmbeddedDisplayPipelineManager
- (void)layoutStateTransitionCoordinator:(id)coordinator transitionDidBeginWithTransitionContext:(SBLayoutStateTransitionContext *)context {
    if (self == gPipelineManager) CRLayoutTransitionBegan(context);
    %orig;
}

// The pipeline's inputs: the physical orientation is read here (UIDevice in SpringBoard only follows
// the interface), and while holding it is replaced by the held orientation. The user's own lock is
// applied later in the pipeline, so it still wins.
- (TRAArbitrationInputs *)inputs {
    TRAArbitrationInputs *inputs = %orig;
    if (self != gPipelineManager || ![inputs respondsToSelector:@selector(deviceOrientationInputs)]) return inputs;

    UIDeviceOrientation raw = (UIDeviceOrientation)[[inputs deviceOrientationInputs] currentDeviceOrientation];
    if (raw != gRawDevice) {
        gRawDevice = raw;
        dispatch_async(dispatch_get_main_queue(), ^{ [[CRController shared] deviceOrientationChanged]; });
    }
    if (!gHolding || gExcluded) return inputs;

    // UIKit's interface and device orientation enums share raw values (landscape names swapped)
    TRAArbitrationDeviceOrientationInputs *held = [[objc_getClass("TRAArbitrationDeviceOrientationInputs") alloc]
        initWithCurrentDeviceOrientation:gHeld nonFlatDeviceOrientation:gHeld];
    return [[objc_getClass("TRAArbitrationInputs") alloc] initWithInterfaceIdiomInputs:[inputs interfaceIdiomInputs]
        userInterfaceStyleInputs:[inputs userInterfaceStyleInputs] deviceOrientationInputs:held
        keyboardInputs:[inputs keyboardInputs] ambientPresentationInputs:[inputs ambientPresentationInputs]];
}
%end
%end

// iOS 15: the older path
%group Legacy
%hook SpringBoard
// Every orientation change reaches SpringBoard here, physical ones included while holding (unlike the
// system's lock overrides, which stop them). The physical orientation is recorded; while holding, only
// the held orientation is let through, so the screen stays put.
- (void)_deviceOrientationChanged:(long long)orientation {
    if (!gPassing) {
        if (orientation != gRawDevice) {
            gRawDevice = (UIDeviceOrientation)orientation;
            dispatch_async(dispatch_get_main_queue(), ^{ [[CRController shared] deviceOrientationChanged]; });
        }
        if (gHolding && !gExcluded && orientation != gHeld) return;
    }
    %orig;
}
%end

%hook SBLayoutStateTransitionCoordinator
- (void)beginTransitionForWorkspaceTransaction:(id)transaction {
    %orig;
    if ([self respondsToSelector:@selector(transitionContext)]) CRLayoutTransitionBegan([self transitionContext]);
}
%end
%end

static void CRPrefsChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{ [[CRController shared] prefsChanged]; });
}

%ctor {
    // iOS 17's traits pipeline, or else the older path through -[SpringBoard _deviceOrientationChanged:]
    gLegacy = !objc_getClass("SBTraitsEmbeddedDisplayPipelineManager");
    if (gLegacy && ![objc_getClass("SpringBoard") instancesRespondToSelector:@selector(_deviceOrientationChanged:)]) return;
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, CRPrefsChangedCallback,
                                    CFSTR(CR_PREFS_CHANGED), NULL, CFNotificationSuspensionBehaviorCoalesce);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[CRController shared] start];
    });
    %init(Common);
    if (gLegacy) %init(Legacy);
    else %init(Modern);
}
