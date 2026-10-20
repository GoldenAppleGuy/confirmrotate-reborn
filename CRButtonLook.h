// The button's look, shared by the tweak (the real button) and the settings page (its preview), so the
// two always match. Settings: IconColor ("Default", a preset name, or "Custom" with IconCustomColor) and
// Background ("Blur", or "Custom" with BackgroundColor); custom colors are stored as "#RRGGBB" or
// "#RRGGBBAA".
#import <UIKit/UIKit.h>

static inline NSArray<NSString *> *CRPresetColorNames(void) {
    return @[@"Blue", @"Green", @"Orange", @"Pink", @"Purple", @"Red", @"Teal", @"Yellow"];
}

static inline UIColor *CRPresetColor(NSString *name) {
    NSDictionary<NSString *, UIColor *> *colors = @{
        @"Blue": [UIColor systemBlueColor], @"Green": [UIColor systemGreenColor], @"Orange": [UIColor systemOrangeColor],
        @"Pink": [UIColor systemPinkColor], @"Purple": [UIColor systemPurpleColor], @"Red": [UIColor systemRedColor],
        @"Teal": [UIColor systemTealColor], @"Yellow": [UIColor systemYellowColor],
    };
    return name ? colors[name] : nil;
}

static inline UIColor *CRColorFromHex(NSString *hex) {
    if (![hex isKindOfClass:[NSString class]]) return nil;
    NSString *digits = [hex stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"# "]];
    if (digits.length != 6 && digits.length != 8) return nil;
    unsigned int value = 0;
    if (![[NSScanner scannerWithString:digits] scanHexInt:&value]) return nil;
    if (digits.length == 6) value = (value << 8) | 0xFF;
    return [UIColor colorWithRed:((value >> 24) & 0xFF) / 255.0 green:((value >> 16) & 0xFF) / 255.0
                            blue:((value >> 8) & 0xFF) / 255.0 alpha:(value & 0xFF) / 255.0];
}

static inline NSString *CRHexFromColor(UIColor *color, BOOL withAlpha) {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) return nil;
    int (^byte)(CGFloat) = ^int(CGFloat v) { return (int)lround(MAX(0, MIN(1, v)) * 255); };
    return withAlpha ? [NSString stringWithFormat:@"#%02X%02X%02X%02X", byte(r), byte(g), byte(b), byte(a)]
                     : [NSString stringWithFormat:@"#%02X%02X%02X", byte(r), byte(g), byte(b)];
}

// Icon and caption color: a preset, the custom color, or the label color (follows light / dark mode)
static inline UIColor *CRIconColorFor(NSString *setting, NSString *customHex) {
    if ([setting isEqualToString:@"Custom"]) return CRColorFromHex(customHex) ?: [UIColor labelColor];
    return CRPresetColor(setting) ?: [UIColor labelColor];
}

// Background color, or nil for the system blur material
static inline UIColor *CRBackgroundColorFor(NSString *setting, NSString *customHex) {
    return [setting isEqualToString:@"Custom"] ? CRColorFromHex(customHex) : nil;
}

// Fills an empty square view of the given size with the button's look: shape, background (blur material
// or a color), the rotation lock symbol and the caption, all scaled with the size. Light / dark follows
// the view's overrideUserInterfaceStyle, which the caller sets.
static inline void CRBuildButtonLook(UIView *button, CGFloat size, BOOL roundedSquare, UIColor *accent, UIColor *background, NSString *caption) {
    button.bounds = CGRectMake(0, 0, size, size);
    button.layer.cornerRadius = roundedSquare ? size * 0.25 : size / 2;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.layer.masksToBounds = YES;

    if (background) {
        button.backgroundColor = background;
    } else {
        UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterial]];
        blur.frame = button.bounds;
        blur.userInteractionEnabled = NO;
        [button addSubview:blur];
    }

    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:round(size * 0.34) weight:UIImageSymbolWeightSemibold];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lock.rotation" withConfiguration:config]];
    icon.tintColor = accent;
    [icon sizeToFit];

    UILabel *label = [UILabel new];
    label.text = caption;
    label.font = [UIFont systemFontOfSize:MAX(9.0, round(size * 0.16)) weight:UIFontWeightSemibold];
    label.textColor = accent;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.7;
    label.textAlignment = NSTextAlignmentCenter;
    [label sizeToFit];
    CGFloat captionWidth = MIN(label.bounds.size.width, size * (roundedSquare ? 0.86 : 0.74));
    CGFloat spacing = round(size * 0.03);
    CGFloat contentHeight = icon.bounds.size.height + spacing + label.bounds.size.height;
    CGFloat top = (size - contentHeight) / 2;
    icon.center = CGPointMake(size / 2, top + icon.bounds.size.height / 2);
    label.frame = CGRectMake((size - captionWidth) / 2, top + icon.bounds.size.height + spacing, captionWidth, label.bounds.size.height);
    icon.userInteractionEnabled = NO;
    label.userInteractionEnabled = NO;
    [button addSubview:icon];
    [button addSubview:label];
}
