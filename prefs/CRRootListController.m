// Settings page for ConfirmRotate Reborn. Exists as a bundle (rather than a plist-only entry) so AltList's
// app picker, used by Always Show In, is loaded into the settings app before that row is opened.

#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <rootless.h>

@interface CRRootListController : PSListController
- (void)refreshCounts;
@end

// Text set in code, translated from the same table (Root.strings) that translates Root.plist
static NSString *CRLocalized(NSString *key) {
    return [[NSBundle bundleForClass:[CRRootListController class]] localizedStringForKey:key value:key table:@"Root"];
}

@interface PSListController ()
- (BOOL)containsSpecifier:(PSSpecifier *)specifier;
@end

// Rows with "dependsOn" = AutoRotate are shown only while that switch is on, and rows with "hiddenBy" =
// AutoRotate only while it is off
@implementation CRRootListController {
    NSArray<PSSpecifier *> *_autoRotateOptions; // shown while Auto-Rotate is on ("dependsOn")
    NSArray<PSSpecifier *> *_autoRotateHides;   // shown while it is off ("hiddenBy")
}

// AltList's multi-selection list, shown as a checklist: tapping an app ticks it, and the ticked apps sit
// in a "Selected" section at the top, moving there (and back) with an animation as they are toggled.
// AltList is loaded at runtime, so this subclass is made at runtime too.
#define kCRSelectedTitle CRLocalized(@"Selected")

static NSString *CRAppID(PSSpecifier *specifier) {
    if (specifier.cellType == PSGroupCell) return nil;
    return [specifier propertyForKey:@"applicationIdentifier"] ?: specifier.identifier;
}

static NSSet *CRSelectedApps(PSListController *controller) {
    id selection = nil;
    @try { selection = [controller valueForKey:@"_selectedApplications"]; } @catch (NSException *e) {}
    if ([selection isKindOfClass:[NSSet class]]) return selection;
    id saved = [controller readPreferenceValue:controller.specifier];
    return [saved isKindOfClass:[NSArray class]] ? [NSSet setWithArray:saved] : [NSSet set];
}

// The cell's own checked state: unlike setting the checkmark directly, it survives the cell being
// redrawn (AltList redraws rows as their icons load)
static void CRSetChecked(UITableViewCell *cell, BOOL checked) {
    if ([cell respondsToSelector:@selector(setChecked:)]) [(PSTableCell *)cell setChecked:checked];
    else cell.accessoryType = checked ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
}

static BOOL CRIsSelectedGroup(PSSpecifier *specifier) {
    return specifier.cellType == PSGroupCell && [specifier.name isEqualToString:kCRSelectedTitle];
}

// Letter section an app belongs to (as AltList groups them)
static NSString *CRLetterFor(PSSpecifier *specifier) {
    NSString *name = specifier.name.length ? [[specifier.name substringToIndex:1] uppercaseString] : @"#";
    unichar c = [name characterAtIndex:0];
    return (c >= 'A' && c <= 'Z') ? name : @"#";
}

static NSArray *CRSelectedFirst(PSListController *controller, NSArray<PSSpecifier *> *specifiers) {
    NSSet *selectedIDs = CRSelectedApps(controller);
    if (selectedIDs.count == 0) return specifiers;
    NSMutableArray *selected = [NSMutableArray array], *rest = [NSMutableArray array];
    for (PSSpecifier *specifier in specifiers) {
        NSString *app = CRAppID(specifier);
        if (app && [selectedIDs containsObject:app]) [selected addObject:specifier];
        else [rest addObject:specifier];
    }
    if (selected.count == 0) return specifiers;
    NSMutableArray *result = [NSMutableArray arrayWithObject:[PSSpecifier groupSpecifierWithName:kCRSelectedTitle]];
    [result addObjectsFromArray:[selected sortedArrayUsingComparator:^NSComparisonResult(PSSpecifier *a, PSSpecifier *b) {
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }]];
    for (NSUInteger i = 0; i < rest.count; i++) { // drop letter groups left empty
        PSSpecifier *specifier = rest[i];
        BOOL emptyGroup = specifier.cellType == PSGroupCell && (i + 1 == rest.count || ((PSSpecifier *)rest[i + 1]).cellType == PSGroupCell);
        if (!emptyGroup) [result addObject:specifier];
    }
    return result;
}

// Inserts an app in its section (creating the section if needed), sorted by name. Positions are always
// taken from the current list: each insert or remove can replace PSListController's array.
static void CRInsertSorted(PSListController *controller, PSSpecifier *app, BOOL intoSelected) {
    NSMutableArray<PSSpecifier *> *all = [controller valueForKey:@"_specifiers"];
    NSString *title = intoSelected ? kCRSelectedTitle : CRLetterFor(app);
    NSUInteger groupIndex = NSNotFound;
    for (NSUInteger i = 0; i < all.count; i++) {
        if (all[i].cellType == PSGroupCell && [all[i].name isEqualToString:title]) { groupIndex = i; break; }
    }
    if (groupIndex == NSNotFound) { // new section: Selected first, letters in order after it
        NSUInteger at = all.count;
        if (intoSelected) at = 0;
        else for (NSUInteger i = 0; i < all.count; i++) {
            if (all[i].cellType == PSGroupCell && !CRIsSelectedGroup(all[i]) && [all[i].name compare:title] == NSOrderedDescending) { at = i; break; }
        }
        PSSpecifier *newGroup = [PSSpecifier groupSpecifierWithName:title];
        [controller insertSpecifier:newGroup atIndex:at animated:YES];
        all = [controller valueForKey:@"_specifiers"]; // inserting can replace the array: read it again
        groupIndex = [all indexOfObject:newGroup];
        if (groupIndex == NSNotFound) return;
    }
    NSUInteger at = groupIndex + 1;
    while (at < all.count && all[at].cellType != PSGroupCell && [all[at].name localizedCaseInsensitiveCompare:app.name] == NSOrderedAscending) at++;
    [controller insertSpecifier:app atIndex:at animated:YES];
}

static void CRToggleApp(PSListController *controller, PSSpecifier *app, Class base) {
    NSString *appID = CRAppID(app);
    BOOL select = ![CRSelectedApps(controller) containsObject:appID];
    struct objc_super sup = {controller, base};
    ((void (*)(struct objc_super *, SEL, NSNumber *, PSSpecifier *))objc_msgSendSuper)(&sup, @selector(setApplicationEnabled:specifier:), @(select), app);

    UITableView *table = controller.table;
    UISearchController *search = nil;
    @try { search = [controller valueForKey:@"_searchController"]; } @catch (NSException *e) {}
    if (search.isActive) { // searching: just the checkmark, results stay where they are
        NSIndexPath *path = [controller indexPathForSpecifier:app];
        if (path) CRSetChecked([table cellForRowAtIndexPath:path], select);
        return;
    }

    // Move: out of its section (dropping the section if left empty), into the other, in one animation
    NSMutableArray<PSSpecifier *> *all = [controller valueForKey:@"_specifiers"];
    NSUInteger index = [all indexOfObject:app];
    if (index == NSNotFound) return;
    [table beginUpdates];
    PSSpecifier *group = nil;
    for (NSInteger i = index - 1; i >= 0; i--) if (all[i].cellType == PSGroupCell) { group = all[i]; break; }
    BOOL alone = group && (index + 1 == all.count || all[index + 1].cellType == PSGroupCell) && all[index - 1] == group;
    [controller removeSpecifier:app animated:YES];
    if (alone) [controller removeSpecifier:group animated:YES];
    CRInsertSorted(controller, app, select);
    [table endUpdates];
}

static void CRRegisterSelectedFirstListController(void) {
    Class base = NSClassFromString(@"ATLApplicationListMultiSelectionController");
    if (!base || NSClassFromString(@"CRSelectedFirstListController")) return;
    Class cls = objc_allocateClassPair(base, "CRSelectedFirstListController", 0);
    if (!cls) return;

    // The list as AltList builds it, with the selected apps moved to the top
    SEL sel = @selector(specifiers);
    IMP imp = imp_implementationWithBlock(^NSArray *(PSListController *controller) {
        struct objc_super sup = {controller, base};
        NSArray *specifiers = ((NSArray *(*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, sel);
        if (specifiers.count && objc_getAssociatedObject(controller, @selector(specifiers)) != specifiers) {
            NSArray *ordered = CRSelectedFirst(controller, specifiers);
            if (ordered != specifiers) {
                [controller setValue:[ordered mutableCopy] forKey:@"_specifiers"];
                specifiers = [controller valueForKey:@"_specifiers"];
            }
            objc_setAssociatedObject(controller, @selector(specifiers), specifiers, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return specifiers;
    });
    class_addMethod(cls, sel, imp, method_getTypeEncoding(class_getInstanceMethod(base, sel)));

    // Plain rows instead of switches
    SEL cellType = @selector(cellTypeForApplicationCells);
    if (class_getInstanceMethod(base, cellType)) {
        class_addMethod(cls, cellType, imp_implementationWithBlock(^NSInteger(id controller) { return PSListItemCell; }),
                        method_getTypeEncoding(class_getInstanceMethod(base, cellType)));
    }

    // Checkmark on selected apps
    SEL cellForRow = @selector(tableView:cellForRowAtIndexPath:);
    class_addMethod(cls, cellForRow, imp_implementationWithBlock(^UITableViewCell *(PSListController *controller, UITableView *table, NSIndexPath *path) {
        struct objc_super sup = {controller, base};
        UITableViewCell *cell = ((UITableViewCell *(*)(struct objc_super *, SEL, UITableView *, NSIndexPath *))objc_msgSendSuper)(&sup, cellForRow, table, path);
        NSString *app = CRAppID([controller specifierAtIndexPath:path]);
        if (app) CRSetChecked(cell, [CRSelectedApps(controller) containsObject:app]);
        return cell;
    }), method_getTypeEncoding(class_getInstanceMethod(base, cellForRow)));

    // Tapping an app toggles it
    SEL didSelect = @selector(tableView:didSelectRowAtIndexPath:);
    class_addMethod(cls, didSelect, imp_implementationWithBlock(^(PSListController *controller, UITableView *table, NSIndexPath *path) {
        PSSpecifier *specifier = [controller specifierAtIndexPath:path];
        if (!CRAppID(specifier)) {
            struct objc_super sup = {controller, base};
            ((void (*)(struct objc_super *, SEL, UITableView *, NSIndexPath *))objc_msgSendSuper)(&sup, didSelect, table, path);
            return;
        }
        [table deselectRowAtIndexPath:path animated:YES];
        CRToggleApp(controller, specifier, base);
    }), method_getTypeEncoding(class_getInstanceMethod(base, didSelect)));

    objc_registerClassPair(cls);
}

+ (void)initialize {
    if (self == [CRRootListController class]) {
        dlopen(ROOT_PATH("/Library/Frameworks/AltList.framework/AltList"), RTLD_NOW);
        CRRegisterSelectedFirstListController();
    }
}

// The app list counts are refreshed when coming back from a list, when the settings app comes back to
// the front, and when the tweak changes a setting itself (long press to blacklist). Reloading the
// specifiers does not redraw these cells, so they are refreshed directly.
- (void)refreshCounts {
    for (UITableViewCell *cell in self.table.visibleCells) {
        if ([cell isKindOfClass:NSClassFromString(@"CRCountLinkCell")]) [(PSTableCell *)cell refreshCellContentsWithSpecifier:((PSTableCell *)cell).specifier];
    }
}

static void CRSettingsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef info) {
    CRRootListController *controller = (__bridge CRRootListController *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{ [controller refreshCounts]; });
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshCounts) name:UIApplicationDidBecomeActiveNotification object:nil];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self, CRSettingsChanged,
                                    CFSTR("com.goldenappleguy.confirmrotatereborn/changed"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshCounts];
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
    NSString *suffix = CRLocalized([self.specifier propertyForKey:@"valueSuffix"] ?: @"");
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
    if (inlineText.length) inlineText = CRLocalized(inlineText);
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
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:CRLocalized(@"Enter Value")
        message:[NSString stringWithFormat:CRLocalized(@"From %1$@ to %2$@."), [NSString stringWithFormat:@"%.0f", min], [self textForValue:max]]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.keyboardType = UIKeyboardTypeNumberPad;
        field.text = [NSString stringWithFormat:@"%.0f", round(slider.value)];
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:CRLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:CRLocalized(@"Set") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *text = alert.textFields.firstObject.text;
        if (text.length == 0) return;
        float value = MAX(min, MIN(max, (float)round(text.doubleValue)));
        [slider setValue:value animated:YES];
        [weakSelf controlChanged:slider]; // saves through the specifier, as dragging does
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

@end

// App list row that shows how many apps the list holds, at the trailing end beside the chevron (a stray
// whitelisted app is easy to miss otherwise). The row's own getter must stay as it is, since AltList
// reads the list through it.
@interface CRCountLinkCell : PSTableCell
@end

@implementation CRCountLinkCell {
    UILabel *_countLabel;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    if (!_countLabel) {
        _countLabel = [UILabel new];
        _countLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        _countLabel.textColor = [UIColor secondaryLabelColor];
        _countLabel.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:_countLabel];
    }
    // From the shared settings store, which also sees changes made from SpringBoard; the page's own read
    // as a fallback
    NSString *key = [specifier propertyForKey:@"key"], *domain = [specifier propertyForKey:@"defaults"];
    id apps = nil;
    if (key && domain) {
        CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
        apps = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)domain));
    }
    if (!apps && [specifier.target respondsToSelector:@selector(readPreferenceValue:)]) apps = [specifier.target readPreferenceValue:specifier];
    NSUInteger count = [apps isKindOfClass:[NSArray class]] ? [apps count] : 0;
    _countLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)count];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.contentView.bounds;
    CGFloat width = ceil([_countLabel sizeThatFits:bounds.size].width);
    _countLabel.frame = CGRectMake(bounds.size.width - self.contentView.layoutMargins.right - width, 0, width, bounds.size.height);
}

@end
