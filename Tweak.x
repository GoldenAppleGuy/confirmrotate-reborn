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
// Settings: TweakSettings or Settings > ConfirmRotate Reborn (domain com.goldenappleguy.confirmrotatereborn).

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>
#import <dlfcn.h>
#import <sys/sysctl.h>
#import <objc/message.h>
#import <sys/stat.h>

#define CR_PREFS_DOMAIN CFSTR("com.goldenappleguy.confirmrotatereborn")
#define CR_PREFS_CHANGED "com.goldenappleguy.confirmrotatereborn/changed"
#ifndef CR_VERSION
#define CR_VERSION "?"
#endif
// Log and status, shared through the settings page (Diagnostics > Share Log)
#if TARGET_OS_SIMULATOR // simulator test build (make SIM=1): /var/mobile isn't there, so a host folder
#define CR_LOG_DIR @"/tmp/ConfirmRotateReborn"
#define CR_GUARD_FILE "/tmp/ConfirmRotateReborn/guard"
#else
#define CR_LOG_DIR @"/var/mobile/Documents/ConfirmRotateReborn"
#define CR_GUARD_FILE "/var/mobile/Documents/ConfirmRotateReborn/guard" // crash-loop guard (plain text, see CRCrashGuardTripped)
#endif
#define CR_LOG_FILE CR_LOG_DIR @"/log.txt"
#define CR_STATUS_FILE CR_LOG_DIR @"/status.plist"
#define CR_LOG_LIMIT (256 * 1024)          // bytes; the oldest half is dropped beyond this
#define CR_RESPRING_NOTIFICATION "com.goldenappleguy.confirmrotatereborn/respring"
#define CR_ROTATION_TEST_NOTIFICATION "com.goldenappleguy.confirmrotatereborn/rotationtest"
#define CR_SURVEY_FILE CR_LOG_DIR @"/runtime.txt"
#if TARGET_OS_SIMULATOR
#define CR_ROTATION_TEST_SECONDS 600.0 // simulator test build: long enough to turn it by hand
#else
#define CR_ROTATION_TEST_SECONDS 30.0
#endif

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
- (void)accelerometer:(id)accelerometer didChangeDeviceOrientation:(long long)orientation; // iOS 16 path
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

// Log: CRLogInfo always (startup, checks, settings, actions, problems); CRLog only with Detailed Logging
// on (every orientation event). Written on a background queue, kept under CR_LOG_LIMIT.
static BOOL gDetailedLog;

static void CRWriteLogLine(NSString *line) {
    static dispatch_queue_t queue;
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("com.goldenappleguy.confirmrotatereborn.log", DISPATCH_QUEUE_SERIAL);
        formatter = [NSDateFormatter new];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });
    NSString *stamped = [NSString stringWithFormat:@"%@ %@\n", [formatter stringFromDate:[NSDate date]], line];
    dispatch_async(queue, ^{
        NSFileManager *files = [NSFileManager defaultManager];
        [files createDirectoryAtPath:CR_LOG_DIR withIntermediateDirectories:YES attributes:nil error:nil];
        NSDictionary *attributes = [files attributesOfItemAtPath:CR_LOG_FILE error:nil];
        if ([attributes fileSize] > CR_LOG_LIMIT) { // keep the newer half
            NSData *data = [NSData dataWithContentsOfFile:CR_LOG_FILE];
            NSData *tail = [data subdataWithRange:NSMakeRange(data.length / 2, data.length - data.length / 2)];
            [tail writeToFile:CR_LOG_FILE atomically:YES];
        }
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:CR_LOG_FILE];
        if (!handle) {
            [files createFileAtPath:CR_LOG_FILE contents:nil attributes:nil];
            handle = [NSFileHandle fileHandleForWritingAtPath:CR_LOG_FILE];
        }
        [handle seekToEndOfFile];
        [handle writeData:[stamped dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    });
}

static void CRLogInfo(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void CRLogInfo(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    CRWriteLogLine(line);
}

static void CRLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void CRLog(NSString *format, ...) {
    if (!gDetailedLog) return;
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    CRWriteLogLine(line);
}

// Where the jailbreak lives ("" rootful, "/var/jb" rootless, a .jbroot path on roothide), from where
// this dylib was loaded: the tweak's other files (settings bundle, translations) are under it
static NSString *CRJailbreakRoot(void) {
    static NSString *root;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Dl_info info;
        NSString *path = dladdr((const void *)&CRJailbreakRoot, &info) && info.dli_fname ? @(info.dli_fname) : @"";
        root = @"/var/jb";
        for (NSString *marker in @[@"/Library/MobileSubstrate/DynamicLibraries/", @"/usr/lib/TweakInject/"]) {
            NSRange range = [path rangeOfString:marker];
            if (range.location != NSNotFound) { root = [path substringToIndex:range.location]; break; }
        }
    });
    return root;
}

// Only the type is reported: the actual folders carry per-device or random IDs (Dopamine's /var/jb
// resolves to /private/preboot/<device ID>/..., roothide uses a random .jbroot folder)
static NSString *CRJailbreakType(void) {
    NSString *root = CRJailbreakRoot();
    if (root.length == 0) return @"rootful";
    if ([root containsString:@".jbroot"]) return @"roothide";
    NSString *varJB = [[NSFileManager defaultManager] destinationOfSymbolicLinkAtPath:@"/var/jb" error:nil];
    if ([root isEqualToString:@"/var/jb"] || [root hasPrefix:@"/private/preboot/"] || (varJB.length && [root hasPrefix:varJB])) return @"rootless";
    return @"other";
}

static NSString *CRSysctlString(const char *name) {
    size_t size = 0;
    if (sysctlbyname(name, NULL, &size, NULL, 0) != 0 || size == 0) return @"?";
    char *value = malloc(size);
    NSString *result = sysctlbyname(name, value, &size, NULL, 0) == 0 ? @(value) : @"?";
    free(value);
    return result;
}

// Status for the settings page: which method runs, or why the tweak is inactive
static void CRWriteStatus(NSString *state, NSString *method, NSArray<NSString *> *missing) {
    NSDictionary *status = @{
        @"state": state, @"method": method ?: @"none", @"missing": missing ?: @[],
        @"version": @CR_VERSION, @"updated": [NSDate date],
    };
    [[NSFileManager defaultManager] createDirectoryAtPath:CR_LOG_DIR withIntermediateDirectories:YES attributes:nil error:nil];
    [status writeToFile:CR_STATUS_FILE atomically:YES];
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
static CFAbsoluteTime gHeldAt;   // when the hold last moved
static BOOL gLegacy;   // iOS 15 path (no traits pipeline): holds by filtering -[SpringBoard _deviceOrientationChanged:]
static BOOL gPipelineEvents; // iOS 16 path (earlier traits pipeline): holds by filtering the pipeline manager's
                             // accelerometer:didChangeDeviceOrientation:, which -inputs doesn't reflect there
static __weak id gAccelerometer; // iOS 16 path: the pipeline manager's accelerometer, for our own calls
static BOOL gPassing;  // iOS 15/16 paths: our own call into the hooked method, let it through

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
static NSTimeInterval gShowAfter = 0.3;  // the phone has to stay turned this long before the button shows
static NSTimeInterval gHideAfter = 5.0;
static NSInteger gTheme;                  // button look: 0 follows light / dark mode, 1 light, 2 dark
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
    CFPreferencesAppSynchronize(CR_PREFS_DOMAIN);
    gEnabled = CRPrefNumber(CFSTR("Enabled"), 1, 0, 1) != 0;
    gPortraitOnAppSwitch = CRPrefNumber(CFSTR("PortraitOnAppSwitch"), 0, 0, 1) != 0;
    gButtonSize = round(CRPrefNumber(CFSTR("ButtonSize"), 56, 44, 96));
    gRoundedSquare = CRPrefNumber(CFSTR("ButtonShape"), 0, 0, 1) == 1;
    gButtonOpacity = round(CRPrefNumber(CFSTR("ButtonOpacity"), 100, 20, 100)) / 100.0;
    gIconColor = CRPrefString(CFSTR("IconColor"), @"Default");
    gDistanceFromStatusBar = round(CRPrefNumber(CFSTR("DistanceFromStatusBar"), 25, 5, 95)) / 100.0;
    gHideAfter = round(CRPrefNumber(CFSTR("HideAfter"), 5, 1, 15));
    gShowAfter = round(CRPrefNumber(CFSTR("ShowAfter"), 0.3, 0, 3) * 10) / 10;
    gTheme = (NSInteger)round(CRPrefNumber(CFSTR("Theme"), 0, 0, 2));
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
    gDetailedLog = CRPrefNumber(CFSTR("DetailedLogging"), 0, 0, 1) != 0;
    gAlwaysShowApps = CRPrefAppSet(CFSTR("AlwaysShowApps"));
    gWhitelistApps = CRPrefAppSet(CFSTR("WhitelistApps"));
    gBlacklistApps = CRPrefAppSet(CFSTR("BlacklistApps"));
}

// The button's text, translated: the tweak has no bundle of its own, so its strings live in the settings
// bundle (Tweak.strings in each language folder)
static NSString *CRLocalized(NSString *key) {
    static NSBundle *bundle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        bundle = [NSBundle bundleWithPath:[CRJailbreakRoot() stringByAppendingPathComponent:@"Library/PreferenceBundles/ConfirmRotateRebornPrefs.bundle"]];
    });
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

// The Theme setting as a style for the button (unspecified: follow the system)
static UIUserInterfaceStyle CRThemeStyle(void) {
    return gTheme == 1 ? UIUserInterfaceStyleLight : gTheme == 2 ? UIUserInterfaceStyleDark : UIUserInterfaceStyleUnspecified;
}

// A dynamic color as the button shows it: views follow the button's style, layer colors need resolving
static CGColorRef CRResolvedCGColor(UIColor *color, UIView *view) {
    UITraitCollection *traits = view ? view.traitCollection : [UITraitCollection currentTraitCollection];
    if (gTheme) traits = [UITraitCollection traitCollectionWithTraitsFromCollections:@[traits, [UITraitCollection traitCollectionWithUserInterfaceStyle:CRThemeStyle()]]];
    return [color resolvedColorWithTraitCollection:traits].CGColor;
}

static SBOrientationLockManager *CRLockManager(void) {
    return [objc_getClass("SBOrientationLockManager") sharedInstance];
}

// The user's own rotation lock (checked at startup to exist)
static BOOL CRUserLocked(void) {
    SBOrientationLockManager *manager = CRLockManager();
    return [manager respondsToSelector:@selector(isUserLocked)] && [manager isUserLocked];
}

static UIInterfaceOrientation CRActiveOrientation(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if ([app respondsToSelector:@selector(activeInterfaceOrientation)]) {
        return [(SpringBoard *)app activeInterfaceOrientation];
    }
    return UIInterfaceOrientationPortrait;
}

// Makes a changed hold take effect without the phone moving: iOS 17 runs the traits pipeline again;
// the iOS 16 path passes the orientation through the pipeline manager's accelerometer callback; the iOS 15 path passes the orientation SpringBoard should now have (the held one, or the physical
// For the log: whether the traits pipeline is set up to receive turns (private API, so only
// boolean getters that exist are called)
static NSString *CRBoolGetter(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    Method method = object ? class_getInstanceMethod([object class], selector) : NULL;
    char type[8] = {0};
    if (method) method_getReturnType(method, type, sizeof(type));
    if (!method || (strcmp(type, "B") != 0 && strcmp(type, "c") != 0) || method_getNumberOfArguments(method) != 2) return nil;
    return [NSString stringWithFormat:@"%@=%d", name, ((BOOL (*)(id, SEL))objc_msgSend)(object, selector)];
}

static NSString *CRPipelineState(void) {
    id manager = gPipelineManager;
    if (!manager) return @"pipeline manager not seen yet";
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *name in @[@"_isBacklightOn", @"supportsLiveDeviceRotation"]) {
        NSString *part = CRBoolGetter(manager, name);
        if (part) [parts addObject:part];
    }
    Ivar ivar = class_getInstanceVariable([manager class], "_accelerometer");
    id accelerometer = ivar ? object_getIvar(manager, ivar) : nil;
    if (!accelerometer) [parts addObject:@"no accelerometer"];
    for (NSString *name in @[@"orientationEventsEnabled", @"accelerometerEventsEnabled", @"passiveOrientationEvents"]) {
        NSString *part = CRBoolGetter(accelerometer, name);
        if (part) [parts addObject:part];
    }
    return [parts componentsJoinedByString:@", "];
}

// one when not holding) through _deviceOrientationChanged:.
static void CRRequestArbitration(void) {
    if (gPipelineEvents) {
        long long orientation = (gHolding && !gExcluded) ? gHeld : gRawDevice;
        if (orientation <= 0 || !gPipelineManager) return;
        gPassing = YES;
        [(SBTraitsEmbeddedDisplayPipelineManager *)gPipelineManager accelerometer:gAccelerometer didChangeDeviceOrientation:orientation];
        gPassing = NO;
        return;
    }
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
    gHeldAt = CFAbsoluteTimeGetCurrent();
    CRLog(@"hold %ld", (long)orientation);
    CRRequestArbitration();
}

// An app can turn the screen by itself (YouTube leaving fullscreen goes back to portrait while the hold
// is still landscape). The hold then follows what the screen shows, so the next confirm is a real change
// the app sees. Not within 1.5 s of the hold moving: the screen may still be rotating to it.
static void CRSyncHoldToScreen(void) {
    UIInterfaceOrientation active = CRActiveOrientation();
    if (!gHolding || active == gHeld || CFAbsoluteTimeGetCurrent() - gHeldAt < 1.5) return;
    CRLog(@"screen turned by the app (%ld, held %ld): holding %ld", (long)active, (long)gHeld, (long)active);
    gHeld = active;
    gHeldAt = CFAbsoluteTimeGetCurrent();
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
    CRLogInfo(@"confirmed: rotating to %ld", (long)gTarget);
    CRHaptic(UIImpactFeedbackStyleMedium);
    UIInterfaceOrientation target = gTarget;
    CRHide(YES);
    if (gHolding && gHeld == target && CRActiveOrientation() != target) {
        // Already holding the target, but the app turned the screen away from it by itself: hold what the
        // screen shows first, then the target, so the app sees the phone turn again
        CRLog(@"re-holding %ld before %ld", (long)CRActiveOrientation(), (long)target);
        gHeld = CRActiveOrientation();
        CRRequestArbitration();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CRHold(target); });
        return;
    }
    CRHold(target);
}

// Long press: rotate, and add the front app to the blacklist so it rotates freely from now on
static void CRConfirmAndBlacklist(void) {
    if (!gShown) return;
    if (gFrontBundle.length == 0) { // home screen: nothing to add
        CRConfirm();
        return;
    }
    CRLogInfo(@"long press: rotating and blacklisting %@", gFrontBundle);
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
    button.overrideUserInterfaceStyle = CRThemeStyle(); // material and colors below follow it
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
    gRing.strokeColor = CRResolvedCGColor(CRAccentColor(), button);
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
    CRLogInfo(@"settings: enabled=%d appSwitch=%d size=%.0f opacity=%.2f color=%@ theme=%ld show=%.1f hide=%.0f auto=%.0f cancel=%d haptics=%d always=%@ white=%@ black=%@ (front %@, excluded %d)",
          gEnabled, gPortraitOnAppSwitch, gButtonSize, gButtonOpacity, gIconColor, (long)gTheme, gShowAfter, gHideAfter, gAutoRotateAfter, gTapToCancel, gHaptics,
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
    SpringBoard *springBoard = (SpringBoard *)[UIApplication sharedApplication];
    if (gLegacy && [springBoard respondsToSelector:@selector(rawDeviceOrientationIgnoringOrientationLocks)]) {
        gRawDevice = (UIDeviceOrientation)[springBoard rawDeviceOrientationIgnoringOrientationLocks];
    }
    CRLoadPrefs();
    CRSetFrontBundle(CRCurrentFrontBundle());
    CRLogPrefs();
    if (CREnabled() && !CRUserLocked()) CRHold(CRActiveOrientation());
    gStarted = YES;
    CRLogInfo(@"started (%@ method, rotation lock %@, orientation %ld%@)", gLegacy ? @"iOS 15" : gPipelineEvents ? @"iOS 16" : @"iOS 17",
              CRUserLocked() ? @"on" : @"off", (long)gRawDevice, gLegacy ? @"" : [@"; pipeline: " stringByAppendingString:CRPipelineState()]);
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
    } else if (!CRUserLocked()) {
        CRHold(CRActiveOrientation());
    }
}

- (void)deviceOrientationChanged {
    if (!gStarted) return;
    CRLog(@"physical orientation %ld", (long)gRawDevice);
    // Wait Show After before showing the button (0.3 s by default). iOS already filters out the in-between
    // orientations of a turn, apart from flat ones, which are ignored.
    NSUInteger token = ++gToken;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(gShowAfter * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token == gToken) [self evaluate];
    });
}

- (void)evaluate {
    if (!CREnabled() || CRUserLocked()) { // off, or the user's own lock is on
        CRRelease();
        CRHide(NO);
        return;
    }
    if (gExcluded) { // whitelist / blacklist: this app rotates freely
        CRHide(NO);
        return;
    }
    if (!gHolding) CRHold(CRActiveOrientation());
    CRSyncHoldToScreen();
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
    BOOL active = gStarted && CREnabled() && !CRUserLocked();
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
static BOOL gInputsBroken; // an unexpected error rewriting the inputs: stop rewriting them, never crash

// The pipeline's inputs with the device orientation replaced by the held one. The initializers differ
// between iOS versions, so the first that exists is used; failing that, a copy with only the orientation
// field set (only when the copy is a separate object, so SpringBoard's own inputs are never changed).
// Returns the inputs unchanged if none applies.
static id CRCopyWithIvar(id object, const char *name, void (^set)(id copy, Ivar ivar)) {
    Ivar ivar = object ? class_getInstanceVariable([object class], name) : NULL;
    if (!ivar || ![object conformsToProtocol:@protocol(NSCopying)]) return nil;
    id copy = [object copy];
    if (copy == object) return nil; // immutable classes may return themselves
    set(copy, ivar);
    return copy;
}

static id CRInputsWithOrientation(id inputs, long long orientation) {
    static NSString *usedMethod;
    Class orientationClass = objc_getClass("TRAArbitrationDeviceOrientationInputs");
    id held = nil;
    if ([orientationClass instancesRespondToSelector:@selector(initWithCurrentDeviceOrientation:nonFlatDeviceOrientation:)]) {
        held = [[orientationClass alloc] initWithCurrentDeviceOrientation:orientation nonFlatDeviceOrientation:orientation];
    } else {
        held = CRCopyWithIvar([inputs deviceOrientationInputs], "_currentDeviceOrientation", ^(id copy, Ivar ivar) {
            *(long long *)((__bridge void *)copy + ivar_getOffset(ivar)) = orientation;
            Ivar nonFlat = class_getInstanceVariable([copy class], "_nonFlatDeviceOrientation");
            if (nonFlat) *(long long *)((__bridge void *)copy + ivar_getOffset(nonFlat)) = orientation;
        });
    }
    if (!held) return inputs;

    Class inputsClass = [inputs class];
    id result = nil;
    NSString *method = nil;
    SEL withStyleAndAmbient = NSSelectorFromString(@"initWithInterfaceIdiomInputs:userInterfaceStyleInputs:deviceOrientationInputs:keyboardInputs:ambientPresentationInputs:");
    SEL withStyle = NSSelectorFromString(@"initWithInterfaceIdiomInputs:userInterfaceStyleInputs:deviceOrientationInputs:keyboardInputs:");
    SEL withAmbient = NSSelectorFromString(@"initWithInterfaceIdiomInputs:deviceOrientationInputs:keyboardInputs:ambientPresentationInputs:");
    SEL plain = NSSelectorFromString(@"initWithInterfaceIdiomInputs:deviceOrientationInputs:keyboardInputs:");
    id (*send4)(id, SEL, id, id, id, id) = (id (*)(id, SEL, id, id, id, id))objc_msgSend;
    id (*send5)(id, SEL, id, id, id, id, id) = (id (*)(id, SEL, id, id, id, id, id))objc_msgSend;
    id (*send3)(id, SEL, id, id, id) = (id (*)(id, SEL, id, id, id))objc_msgSend;
    id idiom = [inputs respondsToSelector:@selector(interfaceIdiomInputs)] ? [inputs interfaceIdiomInputs] : nil;
    id style = [inputs respondsToSelector:@selector(userInterfaceStyleInputs)] ? [inputs userInterfaceStyleInputs] : nil;
    id keyboard = [inputs respondsToSelector:@selector(keyboardInputs)] ? [inputs keyboardInputs] : nil;
    id ambient = [inputs respondsToSelector:@selector(ambientPresentationInputs)] ? [inputs ambientPresentationInputs] : nil;
    if ([inputsClass instancesRespondToSelector:withStyleAndAmbient] && [inputs respondsToSelector:@selector(ambientPresentationInputs)]) {
        result = send5([inputsClass alloc], withStyleAndAmbient, idiom, style, held, keyboard, ambient); method = @"initializer with style and ambient";
    } else if ([inputsClass instancesRespondToSelector:withStyle]) {
        result = send4([inputsClass alloc], withStyle, idiom, style, held, keyboard); method = @"initializer with style";
    } else if ([inputsClass instancesRespondToSelector:withAmbient] && [inputs respondsToSelector:@selector(ambientPresentationInputs)]) {
        result = send4([inputsClass alloc], withAmbient, idiom, held, keyboard, ambient); method = @"initializer with ambient";
    } else if ([inputsClass instancesRespondToSelector:plain]) {
        result = send3([inputsClass alloc], plain, idiom, held, keyboard); method = @"plain initializer";
    } else {
        result = CRCopyWithIvar(inputs, "_deviceOrientationInputs", ^(id copy, Ivar ivar) { object_setIvar(copy, ivar, held); });
        method = @"copy";
    }
    if (!usedMethod) {
        usedMethod = result ? method : @"none";
        CRLogInfo(@"rotation inputs rewritten with: %@", usedMethod);
    }
    return result ?: inputs;
}

%group Modern
%hook SBTraitsEmbeddedDisplayPipelineManager
// The pipeline's inputs: the physical orientation is read here (UIDevice in SpringBoard only follows
// the interface), and while holding it is replaced by the held orientation. The user's own lock is
// applied later in the pipeline, so it still wins.
- (TRAArbitrationInputs *)inputs {
    TRAArbitrationInputs *inputs = %orig;
    if (!gPipelineManager) gPipelineManager = self;
    if (self != gPipelineManager || gInputsBroken || ![inputs respondsToSelector:@selector(deviceOrientationInputs)]) return inputs;
    @try {
        UIDeviceOrientation raw = (UIDeviceOrientation)[[inputs deviceOrientationInputs] currentDeviceOrientation];
        if (raw != gRawDevice) {
            gRawDevice = raw;
            dispatch_async(dispatch_get_main_queue(), ^{ [[CRController shared] deviceOrientationChanged]; });
        }
        if (!gHolding || gExcluded) return inputs;
        // UIKit's interface and device orientation enums share raw values (landscape names swapped)
        return CRInputsWithOrientation(inputs, gHeld);
    } @catch (NSException *exception) {
        gInputsBroken = YES;
        CRLogInfo(@"ERROR rewriting the rotation inputs, hold switched off: %@ %@", exception.name, exception.reason);
        return inputs;
    }
}
%end
%end

// iOS 16: the traits pipeline exists, but a turn reaches the pipeline manager here and goes straight on to
// SpringBoard's orientation update, without new -inputs. The physical orientation is recorded; while
// holding, the held orientation is passed on instead, so the screen stays put.
%group PipelineEvents
%hook SBTraitsEmbeddedDisplayPipelineManager
- (void)accelerometer:(id)accelerometer didChangeDeviceOrientation:(long long)orientation {
    if (!gPipelineManager) gPipelineManager = self;
    if (self != gPipelineManager || gPassing) {
        %orig;
        return;
    }
    if (accelerometer) gAccelerometer = accelerometer;
    if (orientation != gRawDevice) {
        gRawDevice = (UIDeviceOrientation)orientation;
        dispatch_async(dispatch_get_main_queue(), ^{ [[CRController shared] deviceOrientationChanged]; });
    }
    %orig(accelerometer, (gHolding && !gExcluded) ? gHeld : orientation);
}
%end
%end

// App switches on iOS 16 and 17 (optional: only hooked when the method exists)
%group ModernTransitions
%hook SBTraitsEmbeddedDisplayPipelineManager
- (void)layoutStateTransitionCoordinator:(id)coordinator transitionDidBeginWithTransitionContext:(SBLayoutStateTransitionContext *)context {
    if (self == gPipelineManager) CRLayoutTransitionBegan(context);
    %orig;
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
%end

// App switches on iOS 15 (optional)
%group LegacyTransitions
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

// Runtime survey, for iOS versions the tweak doesn't know yet: SpringBoard's orientation-related classes
// and the methods of the key ones, written to runtime.txt (attached by Share Log). Read-only; once per
// tweak version and iOS build.
static void CRAppendClass(NSMutableString *out, Class cls, NSString *filter) {
    [out appendFormat:@"\n== %s : %s\n", class_getName(cls), class_getSuperclass(cls) ? class_getName(class_getSuperclass(cls)) : "-"];
    for (int meta = 0; meta < 2; meta++) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(meta ? object_getClass(cls) : cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            NSString *name = NSStringFromSelector(method_getName(methods[i]));
            if (filter && [name rangeOfString:filter options:NSCaseInsensitiveSearch | NSRegularExpressionSearch].location == NSNotFound) continue;
            [out appendFormat:@"%c %@ %s\n", meta ? '+' : '-', name, method_getTypeEncoding(methods[i]) ?: ""];
        }
        free(methods);
    }
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList(cls, &count);
    for (unsigned int i = 0; i < count; i++) [out appendFormat:@"  ivar %s %s\n", ivar_getName(ivars[i]), ivar_getTypeEncoding(ivars[i]) ?: ""];
    free(ivars);
}

static void CRWriteRuntimeSurvey(void) {
    NSString *stamp = [NSString stringWithFormat:@"%s %@", CR_VERSION, CRSysctlString("kern.osversion")];
    NSString *existing = [NSString stringWithContentsOfFile:CR_SURVEY_FILE encoding:NSUTF8StringEncoding error:nil];
    if ([existing hasPrefix:[NSString stringWithFormat:@"runtime survey %@\n", stamp]]) return;

    NSMutableString *out = [NSMutableString stringWithFormat:@"runtime survey %@\n", stamp];
    NSRegularExpression *interesting = [NSRegularExpression regularExpressionWithPattern:@"orientation|rotat|traits|^TRA[A-Z]|arbit|LayoutStateTransition" options:NSRegularExpressionCaseInsensitive error:nil];
    NSRegularExpression *key = [NSRegularExpression regularExpressionWithPattern:@"PipelineManager|Arbiter$|ArbitrationInputs$|DeviceOrientationInputs$|InputsValidator$|OrientationLock|DeviceOrientationUpdateManager|LayoutStateTransition(Coordinator|Context)$" options:0 error:nil];
    NSMutableArray<NSString *> *keyClasses = [NSMutableArray array];
    [out appendString:@"\n-- classes (framework :: class)\n"];
    unsigned int imageCount = 0;
    const char **images = objc_copyImageNames(&imageCount);
    for (unsigned int i = 0; i < imageCount; i++) {
        const char *image = images[i];
        if (!strstr(image, "SpringBoard") && !strstr(image, "FrontBoard") && !strstr(image, "Traits") && !strstr(image, "BackBoard")) continue;
        unsigned int classCount = 0;
        const char **names = objc_copyClassNamesForImage(image, &classCount);
        for (unsigned int j = 0; j < classCount; j++) {
            NSString *name = @(names[j]);
            NSRange all = NSMakeRange(0, name.length);
            if (![interesting firstMatchInString:name options:0 range:all]) continue;
            const char *slash = strrchr(image, '/');
            [out appendFormat:@"%s :: %@\n", slash ? slash + 1 : image, name];
            if ([key firstMatchInString:name options:0 range:all] && keyClasses.count < 40) [keyClasses addObject:name];
        }
        free(names);
    }
    free(images);
    [out appendString:@"\n-- SpringBoard orientation methods"];
    CRAppendClass(out, objc_getClass("SpringBoard"), @"rient|otat");
    [out appendString:@"\n-- key classes"];
    for (NSString *name in keyClasses) CRAppendClass(out, objc_getClass(name.UTF8String), nil);
    [[NSFileManager defaultManager] createDirectoryAtPath:CR_LOG_DIR withIntermediateDirectories:YES attributes:nil error:nil];
    [out writeToFile:CR_SURVEY_FILE atomically:YES encoding:NSUTF8StringEncoding error:nil];
    CRLogInfo(@"runtime survey written (%lu classes listed, %lu in detail)", (unsigned long)[out componentsSeparatedByString:@" :: "].count - 1, (unsigned long)keyClasses.count);
}

// Rotation test (Settings > Diagnostics > Record Rotation Test): for 30 s, the orientation methods
// SpringBoard calls are logged as they happen. The hooks below only log and pass everything through;
// each is installed only where the method exists with the expected argument types.
static BOOL gTracing;

static void CRTrace(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void CRTrace(NSString *format, ...) {
    if (!gTracing) return;
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    CRWriteLogLine([@"trace: " stringByAppendingString:line]);
}

static void CRRotationTestRequested(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{
        static NSUInteger token;
        NSUInteger mine = ++token;
        gTracing = YES;
        NSString *pipelineState = CRPipelineState();
#if TARGET_OS_SIMULATOR
        // Simulator test build: iOS 18 simulators leave the pipeline's orientation events off; switch them on
        id manager = gPipelineManager;
        Ivar ivar = manager ? class_getInstanceVariable([manager class], "_accelerometer") : NULL;
        id accelerometer = ivar ? object_getIvar(manager, ivar) : nil;
        if ([accelerometer respondsToSelector:@selector(setOrientationEventsEnabled:)]) {
            if ([CRBoolGetter(accelerometer, @"orientationEventsEnabled") hasSuffix:@"=0"]) pipelineState = [pipelineState stringByAppendingString:@" (simulator: switched on)"];
            ((void (*)(id, SEL, BOOL))objc_msgSend)(accelerometer, @selector(setOrientationEventsEnabled:), YES);
        }
#endif
        CRLogInfo(@"rotation test: recording for %.0f s (active orientation %ld, physical %ld, holding %d at %ld, rotation lock %@; pipeline: %@)",
                  CR_ROTATION_TEST_SECONDS, (long)CRActiveOrientation(), (long)gRawDevice, gHolding, (long)gHeld, CRUserLocked() ? @"on" : @"off", pipelineState);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(CR_ROTATION_TEST_SECONDS * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (mine != token) return;
            gTracing = NO;
            CRLogInfo(@"rotation test: done (active orientation %ld)", (long)CRActiveOrientation());
        });
    });
}

// Whether a method exists with the given type encoding (offsets ignored), e.g. "v@:q". Plain C: it runs
// in the constructor, while SpringBoard is still loading.
static BOOL CRHasMethod(NSString *className, NSString *selector, NSString *types) {
    Method method = class_getInstanceMethod(objc_getClass(className.UTF8String), sel_registerName(selector.UTF8String));
    const char *encoding = method ? method_getTypeEncoding(method) : NULL;
    if (!encoding) return NO;
    char stripped[256];
    size_t length = 0;
    for (const char *c = encoding; *c && length < sizeof(stripped) - 1; c++) {
        if (*c < '0' || *c > '9') stripped[length++] = *c;
    }
    stripped[length] = 0;
    return strcmp(stripped, types.UTF8String) == 0;
}

// Startup self-check: what each method needs from SpringBoard on this iOS version. A missing item
// leaves that method out (or the tweak inactive) rather than risking a crash.
static NSArray<NSString *> *CRMissing(NSArray<NSArray *> *requirements) {
    NSMutableArray *missing = [NSMutableArray array];
    for (NSArray *item in requirements) { // @[class, selector or @"" for the class itself, @(class method)]
        Class cls = objc_getClass([item[0] UTF8String]);
        NSString *selector = item[1];
        BOOL classMethod = item.count > 2 && [item[2] boolValue];
        BOOL ok = cls && (selector.length == 0 ||
                          (classMethod ? [cls respondsToSelector:NSSelectorFromString(selector)]
                                       : [cls instancesRespondToSelector:NSSelectorFromString(selector)]));
        if (!ok) [missing addObject:selector.length ? [NSString stringWithFormat:@"%@%@ %@", classMethod ? @"+" : @"-", item[0], selector] : item[0]];
    }
    return missing;
}

// Crash-loop guard: SpringBoard starts counted until the tweak has run for 30 s. Two starts in a row
// that never got there (SpringBoard keeps restarting) pause the tweak for this version, before the
// jailbreak's safe mode would kick in. Settings > Diagnostics > Try Again deletes the file.
// Plain C file calls: this runs in the constructor, while SpringBoard is still loading, where Foundation
// file and property-list APIs deadlocked on iOS 15 (they wait for the loader that is running the tweak).
#define CR_STABLE_AFTER 30.0
static int gUnstableStarts;

static void CRWriteGuard(int unstable, int tripped) {
    mkdir([CR_LOG_DIR fileSystemRepresentation], 0755);
    FILE *file = fopen(CR_GUARD_FILE, "w");
    if (!file) return;
    fprintf(file, "%s %d %d\n", CR_VERSION, unstable, tripped);
    fclose(file);
}

static BOOL CRCrashGuardTripped(void) {
    char version[64] = "";
    int unstable = 0, tripped = 0;
    FILE *file = fopen(CR_GUARD_FILE, "r");
    if (file) {
        if (fscanf(file, "%63s %d %d", version, &unstable, &tripped) != 3) version[0] = 0;
        fclose(file);
    }
    if (strcmp(version, CR_VERSION) != 0) unstable = tripped = 0; // a new version gets a fresh start
    gUnstableStarts = unstable;
    if (tripped) return YES;
    BOOL trip = unstable >= 2;
    CRWriteGuard(trip ? unstable : unstable + 1, trip);
    return trip;
}

static void CRMarkStable(void) {
    CRWriteGuard(0, 0);
}

// Settings > Diagnostics > Try Again: respring (works even while the tweak is paused)
static void CRRespringRequested(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{
        CRLogInfo(@"respring requested from settings");
        id springBoard = [UIApplication sharedApplication];
        if ([springBoard respondsToSelector:@selector(_relaunchSpringBoardNow)]) [springBoard performSelector:@selector(_relaunchSpringBoardNow)];
        else exit(0);
    });
}

// Rotation test hooks (log only)
%group TraceDeviceOrientationChanged
%hook SpringBoard
- (void)_deviceOrientationChanged:(long long)orientation {
    CRTrace(@"-[SpringBoard _deviceOrientationChanged:%lld]%@", orientation, gPassing ? @" (from the tweak)" : @"");
    %orig;
}
%end
%end

%group TraceSetDeviceOrientation
%hook SpringBoard
- (void)_setDeviceOrientation:(long long)orientation animated:(BOOL)animated logMessage:(id)message {
    CRTrace(@"-[SpringBoard _setDeviceOrientation:%lld animated:%d] %@", orientation, animated, message);
    %orig;
}
%end
%end

%group TraceNoteInterfaceOrientation
%hook SpringBoard
- (void)noteInterfaceOrientationChanged:(long long)orientation duration:(double)duration updateMirroredDisplays:(BOOL)mirrored force:(BOOL)force logMessage:(id)message {
    CRTrace(@"-[SpringBoard noteInterfaceOrientationChanged:%lld] %@", orientation, message);
    %orig;
}
%end
%end

%group TraceEnqueue
%hook SBDeviceOrientationUpdateManager
- (void)_enqueueOrientationUpdateToDeviceOrientation:(long long)orientation {
    CRTrace(@"-[SBDeviceOrientationUpdateManager _enqueueOrientationUpdateToDeviceOrientation:%lld]", orientation);
    %orig;
}
%end
%end

%group TraceLegacyEnqueue
%hook SBDeviceOrientationUpdateManager
- (void)_legacy_enqueueOrientationUpdateToDeviceOrientation:(long long)orientation source:(id)source {
    CRTrace(@"-[SBDeviceOrientationUpdateManager _legacy_enqueueOrientationUpdateToDeviceOrientation:%lld source:%@]", orientation, source);
    %orig;
}
%end
%end

%group TraceLockValidator
%hook SBTraitsInputsOrientationLockValidator
- (void)setLockOrientation:(long long)orientation {
    CRTrace(@"-[SBTraitsInputsOrientationLockValidator setLockOrientation:%lld]", orientation);
    %orig;
}
%end
%end

%group TracePipelineAccelerometer
%hook SBTraitsEmbeddedDisplayPipelineManager
- (void)accelerometer:(id)accelerometer didChangeDeviceOrientation:(long long)orientation {
    CRTrace(@"-[SBTraitsEmbeddedDisplayPipelineManager accelerometer:didChangeDeviceOrientation:%lld]", orientation);
    %orig;
}
%end
%end

%group TraceLockManager
%hook SBOrientationLockManager
- (void)lock:(long long)orientation {
    CRTrace(@"-[SBOrientationLockManager lock:%lld]", orientation);
    %orig;
}
%end
%end

// Installs the rotation test hooks that fit this iOS version, and listens for Record Rotation Test
static void CRInstallTraceHooks(void) {
    NSMutableArray *installed = [NSMutableArray array];
    if (CRHasMethod(@"SpringBoard", @"_deviceOrientationChanged:", @"v@:q")) { %init(TraceDeviceOrientationChanged); [installed addObject:@"_deviceOrientationChanged:"]; }
    if (CRHasMethod(@"SpringBoard", @"_setDeviceOrientation:animated:logMessage:", @"v@:qB@")) { %init(TraceSetDeviceOrientation); [installed addObject:@"_setDeviceOrientation:"]; }
    if (CRHasMethod(@"SpringBoard", @"noteInterfaceOrientationChanged:duration:updateMirroredDisplays:force:logMessage:", @"v@:qdBB@")) { %init(TraceNoteInterfaceOrientation); [installed addObject:@"noteInterfaceOrientationChanged:"]; }
    if (CRHasMethod(@"SBDeviceOrientationUpdateManager", @"_enqueueOrientationUpdateToDeviceOrientation:", @"v@:q")) { %init(TraceEnqueue); [installed addObject:@"_enqueueOrientationUpdate"]; }
    if (CRHasMethod(@"SBDeviceOrientationUpdateManager", @"_legacy_enqueueOrientationUpdateToDeviceOrientation:source:", @"v@:q@")) { %init(TraceLegacyEnqueue); [installed addObject:@"_legacy_enqueueOrientationUpdate"]; }
    if (CRHasMethod(@"SBTraitsInputsOrientationLockValidator", @"setLockOrientation:", @"v@:q")) { %init(TraceLockValidator); [installed addObject:@"setLockOrientation:"]; }
    if (CRHasMethod(@"SBTraitsEmbeddedDisplayPipelineManager", @"accelerometer:didChangeDeviceOrientation:", @"v@:@q")) { %init(TracePipelineAccelerometer); [installed addObject:@"accelerometer:didChangeDeviceOrientation:"]; }
    if (CRHasMethod(@"SBOrientationLockManager", @"lock:", @"v@:q")) { %init(TraceLockManager); [installed addObject:@"lock:"]; }
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, CRRotationTestRequested,
                                    CFSTR(CR_ROTATION_TEST_NOTIFICATION), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    dispatch_async(dispatch_get_main_queue(), ^{ CRLogInfo(@"rotation test hooks available: %@", installed.count ? [installed componentsJoinedByString:@", "] : @"none"); });
}

%ctor {
#if TARGET_OS_SIMULATOR
    // The simulator test build is injected into every simulator process; only SpringBoard gets the tweak
    if (strcmp(getprogname(), "SpringBoard") != 0) return;
#endif
    // Only what is safe while SpringBoard is still loading: the crash guard (plain C file calls), the
    // self-check (runtime lookups) and the hooks. Logging, the status file, settings and observers wait
    // for the main queue, which runs once loading is done.
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, CRRespringRequested,
                                    CFSTR(CR_RESPRING_NOTIFICATION), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    void (^writeSurvey)(void) = ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ CRWriteRuntimeSurvey(); });
    };
    void (^logLoaded)(void) = ^{
        CRLoadPrefs();
        CRLogInfo(@"---- ConfirmRotate Reborn %s loaded: %@ iOS %@ (%@), %@ jailbreak", CR_VERSION, CRSysctlString("hw.machine"),
                  [UIDevice currentDevice].systemVersion, CRSysctlString("kern.osversion"), CRJailbreakType());
    };

    if (CRCrashGuardTripped()) {
        dispatch_async(dispatch_get_main_queue(), ^{
            logLoaded();
            CRLogInfo(@"crash guard: SpringBoard restarted %d times in a row shortly after start; tweak paused", gUnstableStarts);
            CRWriteStatus(@"paused", nil, nil);
        });
        return;
    }

    // Which method: iOS 17's traits pipeline, else the older path through -[SpringBoard _deviceOrientationChanged:]
    NSArray *common = CRMissing(@[@[@"SBOrientationLockManager", @"sharedInstance", @YES], @[@"SBOrientationLockManager", @"isUserLocked"],
                                  @[@"SpringBoard", @"activeInterfaceOrientation"]]);
    NSMutableArray *modern = [CRMissing(@[@[@"SBTraitsEmbeddedDisplayPipelineManager", @"inputs"], @[@"TRAArbitrationInputs", @"deviceOrientationInputs"],
                                          @[@"TRAArbitrationDeviceOrientationInputs", @"currentDeviceOrientation"]]) mutableCopy];
    if (![objc_getClass("SBTraitsEmbeddedDisplayPipelineManager") instancesRespondToSelector:@selector(_noteInputsNeedUpdateAnimated:reason:)] &&
        ![objc_getClass("TRAArbiter") instancesRespondToSelector:@selector(_setNeedsUpdateArbitrationWithReason:animated:)]) {
        [modern addObject:@"a way to re-run the traits pipeline"];
    }
    NSMutableArray *pipeline = [NSMutableArray array];
    if (!objc_getClass("SBTraitsEmbeddedDisplayPipelineManager")) [pipeline addObject:@"SBTraitsEmbeddedDisplayPipelineManager"];
    else if (!CRHasMethod(@"SBTraitsEmbeddedDisplayPipelineManager", @"accelerometer:didChangeDeviceOrientation:", @"v@:@q")) {
        [pipeline addObject:@"-SBTraitsEmbeddedDisplayPipelineManager accelerometer:didChangeDeviceOrientation:"];
    }
    NSArray *legacy = CRMissing(@[@[@"SpringBoard", @"_deviceOrientationChanged:"]]);
    // iOS 15 has no pipeline manager; iOS 16 has one, but without iOS 17's inputs
    NSString *method = nil;
    if (common.count == 0 && modern.count == 0) method = @"iOS 17";
    else if (common.count == 0 && pipeline.count == 0) method = @"iOS 16";
    else if (common.count == 0 && legacy.count == 0) method = @"iOS 15";
    NSString *(^result)(NSArray *) = ^NSString *(NSArray *missing) {
        return missing.count ? [@"missing " stringByAppendingString:[missing componentsJoinedByString:@", "]] : @"ok";
    };
    NSString *checks = [NSString stringWithFormat:@"self-check: common %@ | iOS 17 method %@ | iOS 16 method %@ | iOS 15 method %@",
                        common.count ? [common componentsJoinedByString:@", "] : @"ok", result(modern), result(pipeline), result(legacy)];

    if (!method) {
        NSMutableArray *missing = [common mutableCopy];
        [missing addObjectsFromArray:modern];
        [missing addObjectsFromArray:pipeline];
        [missing addObjectsFromArray:legacy];
        dispatch_async(dispatch_get_main_queue(), ^{
            logLoaded();
            CRLogInfo(@"%@", checks);
            CRLogInfo(@"inactive: this iOS version is not supported");
            CRWriteStatus(@"unsupported", nil, missing);
            CRMarkStable();
        });
        CRInstallTraceHooks();
        writeSurvey();
        return;
    }
    gLegacy = [method isEqualToString:@"iOS 15"];
    gPipelineEvents = [method isEqualToString:@"iOS 16"];

    NSMutableArray *optionalMissing = [NSMutableArray array];
    if ([objc_getClass("SBOrientationLockManager") instancesRespondToSelector:@selector(lock)] &&
        [objc_getClass("SBOrientationLockManager") instancesRespondToSelector:@selector(unlock)]) %init(Common);
    else [optionalMissing addObject:@"rotation lock hooks"];
    if (gLegacy) {
        %init(Legacy);
        if ([objc_getClass("SBLayoutStateTransitionCoordinator") instancesRespondToSelector:@selector(beginTransitionForWorkspaceTransaction:)]) %init(LegacyTransitions);
        else [optionalMissing addObject:@"app switch hook"];
    } else {
        if (gPipelineEvents) %init(PipelineEvents);
        else %init(Modern);
        if ([objc_getClass("SBTraitsEmbeddedDisplayPipelineManager") instancesRespondToSelector:@selector(layoutStateTransitionCoordinator:transitionDidBeginWithTransitionContext:)]) %init(ModernTransitions);
        else [optionalMissing addObject:@"app switch hook"];
    }

    CRInstallTraceHooks();
    writeSurvey();
    dispatch_async(dispatch_get_main_queue(), ^{
        logLoaded();
        CRLogInfo(@"%@", checks);
        if (optionalMissing.count) CRLogInfo(@"not available on this iOS: %@", [optionalMissing componentsJoinedByString:@", "]);
        CRWriteStatus(@"active", method, optionalMissing);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, CRPrefsChangedCallback,
                                        CFSTR(CR_PREFS_CHANGED), NULL, CFNotificationSuspensionBehaviorCoalesce);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[CRController shared] start];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(CR_STABLE_AFTER * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CRMarkStable(); });
    });
}
