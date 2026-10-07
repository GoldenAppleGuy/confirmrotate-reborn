// Settings page for ConfirmRotate Reborn. Exists as a bundle (rather than a plist-only entry) so AltList's
// app picker, used by Always Show In, is loaded into the settings app before that row is opened.

#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <dlfcn.h>
#import <rootless.h>

@interface CRRootListController : PSListController
@end

@interface PSListController ()
- (BOOL)containsSpecifier:(PSSpecifier *)specifier;
@end

// Rows with "dependsOn" = AutoRotate are shown only while that switch is on, and rows with "hiddenBy" =
// AutoRotate only while it is off
@implementation CRRootListController {
    NSArray<PSSpecifier *> *_autoRotateOptions; // shown while Auto-Rotate is on ("dependsOn")
    NSArray<PSSpecifier *> *_autoRotateHides;   // shown while it is off ("hiddenBy")
}

+ (void)initialize {
    if (self == [CRRootListController class]) {
        dlopen(ROOT_PATH("/Library/Frameworks/AltList.framework/AltList"), RTLD_NOW);
    }
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specifiers = [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];
        NSArray *(^matching)(NSString *, NSString *) = ^NSArray *(NSString *property, NSString *value) {
            return [specifiers filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(PSSpecifier *specifier, NSDictionary *bindings) {
                return [[specifier propertyForKey:property] isEqualToString:value];
            }]];
        };
        _autoRotateOptions = matching(@"dependsOn", @"AutoRotate");
        _autoRotateHides = matching(@"hiddenBy", @"AutoRotate");
        PSSpecifier *autoRotate = matching(@"key", @"AutoRotate").firstObject;
        BOOL on = autoRotate && [[self readPreferenceValue:autoRotate] boolValue];
        [specifiers removeObjectsInArray:on ? _autoRotateHides : _autoRotateOptions];
        _specifiers = specifiers;
    }
    return _specifiers;
}

// Rows follow the Auto-Rotate switch, right after it: its options (Tap to Cancel, Delay) while it is on,
// and Hide After while it is off (with auto-rotate, the delay decides when the button goes)
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    if (![[specifier propertyForKey:@"key"] isEqualToString:@"AutoRotate"]) return;
    NSArray *show = [value boolValue] ? _autoRotateOptions : _autoRotateHides;
    NSArray *hide = [value boolValue] ? _autoRotateHides : _autoRotateOptions;
    if (hide.count && [self containsSpecifier:hide.firstObject]) [self removeContiguousSpecifiers:hide animated:YES];
    if (show.count && ![self containsSpecifier:show.firstObject]) [self insertContiguousSpecifiers:show afterSpecifier:specifier animated:YES];
}

@end

// Slider row whose value reads as a whole number (plus an optional "valueSuffix", or "zeroText" for 0,
// from the specifier) at all times, and can be typed in with a long press. The slider's own value label
// sits inside the slider and is sized and laid out by it, so instead of covering it, that label's class
// is swapped for one that formats whatever text the slider sets (it prints decimals, on every change).
#import <Preferences/PSSliderTableCell.h>
#import <Preferences/PSSpecifier.h>
#import <objc/runtime.h>
#import <objc/message.h>

static char kCRFormatKey;   // label: block formatting a value
static char kCRWidthKey;    // label: width reserved for the value (widest text, larger font)
static char kCRReserveKey;  // slider: space kept free of the track (and knob) at the trailing end
static char kCRLeadingKey;  // slider: space kept free at the leading end, for an inline label
#define CR_VALUE_FONT_SIZE 16.0

@interface CRValueLabel : UILabel // no ivars: installed on an existing label with object_setClass
@end

@implementation CRValueLabel
// Wherever the slider puts this label, it goes at the trailing end in the space kept free of the track,
// sized for the widest value and centered vertically
- (void)setFrame:(CGRect)frame {
    NSNumber *width = objc_getAssociatedObject(self, &kCRWidthKey);
    if (width && self.superview) {
        CGFloat w = width.doubleValue, h = ceil(self.font.lineHeight) + 2, H = self.superview.bounds.size.height;
        frame = CGRectMake(self.superview.bounds.size.width - w, round((H - h) / 2), w, h);
    }
    [super setFrame:frame];
}

- (void)setText:(NSString *)text {
    NSString *(^format)(double) = objc_getAssociatedObject(self, &kCRFormatKey);
    NSScanner *scanner = [NSScanner scannerWithString:text ?: @""];
    double value;
    if (format && [scanner scanDouble:&value]) text = format(value);
    [super setText:text];
}
@end

// A subclass of the slider's own class, made at runtime, whose track (and so the knob) stops short of the
// trailing end by the reserved amount, and starts after the leading reserve (if any)
static Class CRPaddedSliderClass(Class base) {
    NSString *name = [@"CRPadded_" stringByAppendingString:NSStringFromClass(base)];
    Class cls = NSClassFromString(name);
    if (cls) return cls;
    cls = objc_allocateClassPair(base, name.UTF8String, 0);
    if (!cls) return base;
    SEL sel = @selector(trackRectForBounds:);
    IMP imp = imp_implementationWithBlock(^CGRect(UISlider *slider, CGRect bounds) {
        struct objc_super sup = {slider, base};
        CGRect rect = ((CGRect (*)(struct objc_super *, SEL, CGRect))objc_msgSendSuper)(&sup, sel, bounds);
        NSNumber *reserve = objc_getAssociatedObject(slider, &kCRReserveKey);
        if (reserve) {
            CGFloat maxX = bounds.size.width - reserve.doubleValue;
            if (CGRectGetMaxX(rect) > maxX) rect.size.width = MAX(0, maxX - rect.origin.x);
        }
        NSNumber *leading = objc_getAssociatedObject(slider, &kCRLeadingKey);
        if (leading && rect.origin.x < leading.doubleValue) {
            CGFloat maxX = CGRectGetMaxX(rect);
            rect.origin.x = leading.doubleValue;
            rect.size.width = MAX(0, maxX - rect.origin.x);
        }
        return rect;
    });
    class_addMethod(cls, sel, imp, method_getTypeEncoding(class_getInstanceMethod(base, sel)));
    objc_registerClassPair(cls);
    return cls;
}

@interface CRIntegerSliderCell : PSSliderTableCell
@end

// An "inlineLabel" property puts a title at the leading end of the row (e.g. "Delay"), for a slider that
// sits in a group with other rows rather than under its own header.
@implementation CRIntegerSliderCell {
    UILabel *_inlineLabel;
}

- (UISlider *)slider {
    return [self.control isKindOfClass:[UISlider class]] ? (UISlider *)self.control : nil;
}

- (NSString *)textForValue:(float)value {
    NSString *zeroText = [self.specifier propertyForKey:@"zeroText"]; // e.g. "Off" for a setting where 0 disables it
    if (zeroText && round(value) == 0) return zeroText;
    NSString *suffix = [self.specifier propertyForKey:@"valueSuffix"] ?: @"";
    return [NSString stringWithFormat:@"%.0f%@", round(value), suffix];
}

// The slider's value label: a label inside the slider showing a number
- (UILabel *)valueLabelIn:(UIView *)view {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[UILabel class]]) {
            NSScanner *scanner = [NSScanner scannerWithString:((UILabel *)subview).text ?: @""];
            double number;
            if ([subview isKindOfClass:[CRValueLabel class]] || [scanner scanDouble:&number]) return (UILabel *)subview;
        }
        UILabel *found = [self valueLabelIn:subview];
        if (found) return found;
    }
    return nil;
}

- (void)installValueFormatting {
    UILabel *label = [self valueLabelIn:[self slider]];
    if (!label) return;
    __weak typeof(self) weakSelf = self;
    objc_setAssociatedObject(label, &kCRFormatKey, ^NSString *(double value) {
        return [weakSelf textForValue:value] ?: [NSString stringWithFormat:@"%.0f", value];
    }, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (![label isKindOfClass:[CRValueLabel class]]) {
        object_setClass(label, [CRValueLabel class]);
        label.userInteractionEnabled = YES;
        [label addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(valueLabelLongPressed:)]];
    }
    // Larger than the slider's own size; room for the widest value is taken from the end of the track
    UISlider *slider = [self slider];
    label.font = [label.font fontWithSize:CR_VALUE_FONT_SIZE];
    label.textAlignment = NSTextAlignmentRight;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.8;
    CGFloat width = 0;
    for (NSString *key in @[@"min", @"max"]) {
        NSString *text = [self textForValue:[[self.specifier propertyForKey:key] floatValue]];
        width = MAX(width, ceil([text sizeWithAttributes:@{NSFontAttributeName: label.font}].width) + 2);
    }
    objc_setAssociatedObject(label, &kCRWidthKey, @(width), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGFloat knobOverhang = 8, gap = 8; // the knob reaches past the end of the track
    NSNumber *reserve = @(width + gap + knobOverhang);
    if (![objc_getAssociatedObject(slider, &kCRReserveKey) isEqual:reserve]) {
        objc_setAssociatedObject(slider, &kCRReserveKey, reserve, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (![NSStringFromClass([slider class]) hasPrefix:@"CRPadded_"]) object_setClass(slider, CRPaddedSliderClass([slider class]));
        [label.superview setNeedsLayout];
        [slider setNeedsLayout];
    }
    NSString *inlineText = [self.specifier propertyForKey:@"inlineLabel"];
    if (inlineText.length) {
        if (!_inlineLabel) {
            _inlineLabel = [UILabel new];
            _inlineLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
            _inlineLabel.textColor = [UIColor labelColor];
            _inlineLabel.userInteractionEnabled = NO;
            [slider addSubview:_inlineLabel];
        }
        _inlineLabel.text = inlineText;
        [_inlineLabel sizeToFit];
        CGFloat h = _inlineLabel.bounds.size.height;
        _inlineLabel.frame = CGRectMake(0, round((slider.bounds.size.height - h) / 2), _inlineLabel.bounds.size.width, h);
        NSNumber *leading = @(_inlineLabel.bounds.size.width + gap + knobOverhang);
        if (![objc_getAssociatedObject(slider, &kCRLeadingKey) isEqual:leading]) {
            objc_setAssociatedObject(slider, &kCRLeadingKey, leading, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [label.superview setNeedsLayout];
            [slider setNeedsLayout];
        }
    }
    label.frame = label.frame; // place it in the reserved space
    label.text = label.text;   // reformat what is showing now
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    [self installValueFormatting];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self installValueFormatting]; // the slider may create its label lazily
}

- (void)valueLabelLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    UISlider *slider = [self slider];
    UIViewController *presenter = nil;
    for (UIResponder *r = self; r; r = r.nextResponder) {
        if ([r isKindOfClass:[UIViewController class]]) { presenter = (UIViewController *)r; break; }
    }
    if (!slider || !presenter) return;

    float min = [[self.specifier propertyForKey:@"min"] floatValue], max = [[self.specifier propertyForKey:@"max"] floatValue];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Enter Value"
        message:[NSString stringWithFormat:@"From %.0f to %@.", min, [self textForValue:max]]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.keyboardType = UIKeyboardTypeNumberPad;
        field.text = [NSString stringWithFormat:@"%.0f", round(slider.value)];
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Set" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *text = alert.textFields.firstObject.text;
        if (text.length == 0) return;
        float value = MAX(min, MIN(max, (float)round(text.doubleValue)));
        [slider setValue:value animated:YES];
        [weakSelf controlChanged:slider]; // saves through the specifier, as dragging does
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

@end
