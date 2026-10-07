// Control Center toggle for ConfirmRotate Reborn (loaded by CCSupport): turns the tweak on and off.
// It runs inside SpringBoard, so it writes the Enabled setting directly and tells the tweak.

#import <ControlCenterUIKit/CCUIToggleModule.h>

#define CR_PREFS_DOMAIN CFSTR("com.goldenappleguy.confirmrotatereborn")
#define CR_PREFS_CHANGED CFSTR("com.goldenappleguy.confirmrotatereborn/changed")

@interface CRModule : CCUIToggleModule
@end

@implementation CRModule

// A phone with a rotate arrow, in teal when on: distinct from the system rotation lock toggle (a lock
// inside an arrow, white when on)
- (UIImage *)iconGlyph {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightSemibold];
    return [UIImage systemImageNamed:@"rectangle.portrait.rotate" withConfiguration:config]
        ?: [UIImage systemImageNamed:@"rotate.right" withConfiguration:config];
}

- (UIColor *)selectedColor {
    return [UIColor systemTealColor];
}

- (BOOL)isSelected {
    CFPreferencesAppSynchronize(CR_PREFS_DOMAIN);
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("Enabled"), CR_PREFS_DOMAIN);
    BOOL enabled = [(__bridge id)value respondsToSelector:@selector(boolValue)] ? [(__bridge id)value boolValue] : YES;
    if (value) CFRelease(value);
    return enabled;
}

- (void)setSelected:(BOOL)selected {
    CFPreferencesSetAppValue(CFSTR("Enabled"), selected ? kCFBooleanTrue : kCFBooleanFalse, CR_PREFS_DOMAIN);
    CFPreferencesAppSynchronize(CR_PREFS_DOMAIN);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CR_PREFS_CHANGED, NULL, NULL, YES);
    [super setSelected:selected];
    [self refreshState];
}

@end
