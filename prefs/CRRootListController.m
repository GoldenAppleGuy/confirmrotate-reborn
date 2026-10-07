// Settings page for ConfirmRotate Reborn. Exists as a bundle (rather than a plist-only entry) so AltList's
// app picker, used by Always Show In, is loaded into the settings app before that row is opened.

#import <Preferences/PSListController.h>
#import <dlfcn.h>
#import <rootless.h>

@interface CRRootListController : PSListController
@end

@implementation CRRootListController

+ (void)initialize {
    if (self == [CRRootListController class]) {
        dlopen(ROOT_PATH("/Library/Frameworks/AltList.framework/AltList"), RTLD_NOW);
    }
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

@end

// Slider row whose value reads as a whole number (plus an optional "valueSuffix" from the specifier)
// at all times, and can be typed in with a long press. The stock value label prints decimals and
// redraws them on every change, so it is kept for layout but hidden, and a label styled like it sits
// in its place.
#import <Preferences/PSSliderTableCell.h>
#import <Preferences/PSSpecifier.h>

@interface CRIntegerSliderCell : PSSliderTableCell
@end

@implementation CRIntegerSliderCell {
    UILabel *_valueLabel;
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

- (void)updateValueLabel {
    _valueLabel.text = [self textForValue:[self slider].value];
}

// The stock value label: a label in the row showing a number, other than ours
- (UILabel *)stockValueLabelIn:(UIView *)view {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[UILabel class]] && subview != _valueLabel) {
            NSScanner *scanner = [NSScanner scannerWithString:((UILabel *)subview).text ?: @""];
            double number;
            if ([scanner scanDouble:&number]) return (UILabel *)subview;
        }
        UILabel *found = [self stockValueLabelIn:subview];
        if (found) return found;
    }
    return nil;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    UISlider *slider = [self slider];
    if (!_valueLabel && slider) {
        _valueLabel = [UILabel new];
        _valueLabel.userInteractionEnabled = YES;
        [_valueLabel addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(valueLabelLongPressed:)]];
        // Dragging moves the value continuously, but this slider only reports a change on release
        [slider addTarget:self action:@selector(sliderMoved) forControlEvents:UIControlEventValueChanged | UIControlEventTouchDragInside | UIControlEventTouchDragOutside | UIControlEventTouchDown];
    }
    [self updateValueLabel];
    [self setNeedsLayout];
}

- (void)sliderMoved {
    [self updateValueLabel];
    [self setNeedsLayout]; // the stock label may have been redrawn (and shown) again
}

- (void)layoutSubviews {
    [super layoutSubviews];
    UILabel *stock = [self stockValueLabelIn:self];
    if (!stock || !_valueLabel) return;
    if (_valueLabel.superview != stock.superview) [stock.superview addSubview:_valueLabel];
    _valueLabel.font = stock.font;
    _valueLabel.textColor = stock.textColor;
    _valueLabel.textAlignment = NSTextAlignmentRight;
    stock.alpha = 0;

    // Same place as the stock label, widened to the left for the widest value with its suffix (the
    // stock label is sized for the bare number); the slider gives up the extra space.
    CGFloat needed = 0;
    for (NSString *key in @[@"min", @"max"]) {
        NSString *text = [self textForValue:[[self.specifier propertyForKey:key] floatValue]];
        needed = MAX(needed, ceil([text sizeWithAttributes:@{NSFontAttributeName: stock.font}].width) + 4);
    }
    CGRect frame = stock.frame;
    CGFloat extra = MAX(0, needed - frame.size.width);
    frame.origin.x -= extra;
    frame.size.width += extra;
    _valueLabel.frame = frame;

    UISlider *slider = [self slider];
    CGRect labelInSlider = [_valueLabel.superview convertRect:frame toView:slider.superview];
    CGRect sliderFrame = slider.frame;
    CGFloat overlap = CGRectGetMaxX(sliderFrame) + 14 - CGRectGetMinX(labelInSlider); // the knob draws past the frame
    if (overlap > 0) {
        sliderFrame.size.width -= overlap;
        slider.frame = sliderFrame;
    }
    [self updateValueLabel];
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
        [weakSelf updateValueLabel];
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

@end
