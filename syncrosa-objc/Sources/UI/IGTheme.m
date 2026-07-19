#import "IGTheme.h"
#import <math.h>

NSString * const IGThemeDefaultsKey = @"SyncrosaLegacyThemeIdentifier";
NSString * const IGThemeDidChangeNotification = @"IGThemeDidChangeNotification";

static NSString * const IGThemeIdentifierClassic = @"classic-graphite";
static NSString * const IGThemeIdentifierAqua = @"aqua-blue";
static NSString * const IGThemeIdentifierSage = @"sage-graphite";
static NSString * const IGThemeIdentifierPlum = @"soft-plum";
static NSString * const IGThemeIdentifierRuby = @"ruby-graphite";
static NSString * const IGThemeIdentifierOcean = @"ocean-mist";

typedef struct {
    CGFloat red;
    CGFloat green;
    CGFloat blue;
} IGRGBColor;

typedef struct {
    IGRGBColor window;
    IGRGBColor sidebar;
    IGRGBColor content;
    IGRGBColor panel;
    IGRGBColor panelInset;
    IGRGBColor control;
    IGRGBColor controlBorder;
    IGRGBColor divider;
    IGRGBColor text;
    IGRGBColor mutedText;
    IGRGBColor accent;
    IGRGBColor danger;
} IGThemePalette;

static IGThemePalette IGThemePaletteForIdentifier(NSString *identifier);

@interface IGThemedBackgroundView : NSView
@property (nonatomic, assign) IGThemeBackgroundRole themeRole;
@end

@interface IGThemedButtonCell : NSButtonCell
@property (nonatomic, assign) IGThemeButtonRole themeRole;
@end

static IGRGBColor IGRGBMake(NSUInteger hex) {
    IGRGBColor color;
    color.red = (CGFloat)((hex >> 16) & 0xff) / 255.0;
    color.green = (CGFloat)((hex >> 8) & 0xff) / 255.0;
    color.blue = (CGFloat)(hex & 0xff) / 255.0;
    return color;
}

static NSColor *IGColorFromRGB(IGRGBColor color) {
    return [NSColor colorWithCalibratedRed:color.red green:color.green blue:color.blue alpha:1.0];
}

static IGThemePalette IGThemePaletteMake(NSUInteger window,
                                         NSUInteger sidebar,
                                         NSUInteger content,
                                         NSUInteger panel,
                                         NSUInteger panelInset,
                                         NSUInteger control,
                                         NSUInteger controlBorder,
                                         NSUInteger divider,
                                         NSUInteger text,
                                         NSUInteger mutedText,
                                         NSUInteger accent,
                                         NSUInteger danger) {
    IGThemePalette palette;
    palette.window = IGRGBMake(window);
    palette.sidebar = IGRGBMake(sidebar);
    palette.content = IGRGBMake(content);
    palette.panel = IGRGBMake(panel);
    palette.panelInset = IGRGBMake(panelInset);
    palette.control = IGRGBMake(control);
    palette.controlBorder = IGRGBMake(controlBorder);
    palette.divider = IGRGBMake(divider);
    palette.text = IGRGBMake(text);
    palette.mutedText = IGRGBMake(mutedText);
    palette.accent = IGRGBMake(accent);
    palette.danger = IGRGBMake(danger);
    return palette;
}

static BOOL IGGetRGBComponents(NSColor *color, CGFloat *red, CGFloat *green, CGFloat *blue) {
    if (!color) {
        return NO;
    }

    NSColor *rgbColor = nil;
    @try {
        rgbColor = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
        if (!rgbColor) {
            rgbColor = [color colorUsingColorSpaceName:NSDeviceRGBColorSpace];
        }
        if (!rgbColor) {
            return NO;
        }
        if (red) *red = [rgbColor redComponent];
        if (green) *green = [rgbColor greenComponent];
        if (blue) *blue = [rgbColor blueComponent];
        return YES;
    } @catch (NSException *exception) {
        (void)exception;
        return NO;
    }
}

static NSColor *IGSafeCalibratedColor(NSColor *color, NSColor *fallback) {
    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    if (!IGGetRGBComponents(color, &red, &green, &blue)) {
        if (!IGGetRGBComponents(fallback, &red, &green, &blue)) {
            red = green = blue = 0.0;
        }
    }
    return [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:1.0];
}

static NSColor *IGColorWithAlpha(NSColor *color, CGFloat alpha) {
    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    if (!IGGetRGBComponents(color, &red, &green, &blue)) {
        red = green = blue = 0.0;
    }
    return [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:alpha];
}

static NSColor *IGColorBlend(NSColor *left, NSColor *right, CGFloat amount) {
    left = IGSafeCalibratedColor(left, [NSColor blackColor]);
    right = IGSafeCalibratedColor(right, [NSColor whiteColor]);
    CGFloat inverse = 1.0 - amount;
    return [NSColor colorWithCalibratedRed:([left redComponent] * inverse) + ([right redComponent] * amount)
                                     green:([left greenComponent] * inverse) + ([right greenComponent] * amount)
                                      blue:([left blueComponent] * inverse) + ([right blueComponent] * amount)
                                     alpha:1.0];
}

static BOOL IGColorIsCloseToRGB(NSColor *color, IGRGBColor rgb) {
    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    if (!IGGetRGBComponents(color, &red, &green, &blue)) {
        return NO;
    }
    CGFloat tolerance = 0.025;
    return fabs(red - rgb.red) < tolerance &&
           fabs(green - rgb.green) < tolerance &&
           fabs(blue - rgb.blue) < tolerance;
}

static BOOL IGColorIsNeutral(NSColor *color) {
    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    if (!IGGetRGBComponents(color, &red, &green, &blue)) {
        return YES;
    }
    CGFloat maxValue = MAX(red, MAX(green, blue));
    CGFloat minValue = MIN(red, MIN(green, blue));
    return (maxValue - minValue) < 0.08;
}

static BOOL IGColorIsThemeTextColor(NSColor *color) {
    if (!color) {
        return YES;
    }
    NSArray *identifiers = IGThemeIdentifiers();
    for (NSString *identifier in identifiers) {
        IGThemePalette palette = IGThemePaletteForIdentifier(identifier);
        if (IGColorIsCloseToRGB(color, palette.text) || IGColorIsCloseToRGB(color, palette.mutedText)) {
            return YES;
        }
    }
    return NO;
}

NSArray *IGThemeIdentifiers(void) {
    return [NSArray arrayWithObjects:
            IGThemeIdentifierClassic,
            IGThemeIdentifierAqua,
            IGThemeIdentifierSage,
            IGThemeIdentifierPlum,
            IGThemeIdentifierRuby,
            IGThemeIdentifierOcean,
            nil];
}

static BOOL IGThemeIdentifierIsValid(NSString *identifier) {
    return identifier && [IGThemeIdentifiers() containsObject:identifier];
}

NSString *IGThemeDisplayNameForIdentifier(NSString *identifier) {
    if ([identifier isEqualToString:IGThemeIdentifierAqua]) return @"Aqua Blue";
    if ([identifier isEqualToString:IGThemeIdentifierSage]) return @"Sage Graphite";
    if ([identifier isEqualToString:IGThemeIdentifierPlum]) return @"Soft Plum";
    if ([identifier isEqualToString:IGThemeIdentifierRuby]) return @"Ruby Graphite";
    if ([identifier isEqualToString:IGThemeIdentifierOcean]) return @"Ocean Mist";
    return @"Classic Graphite";
}

NSString *IGActiveThemeIdentifier(void) {
    NSString *identifier = [[NSUserDefaults standardUserDefaults] stringForKey:IGThemeDefaultsKey];
    return IGThemeIdentifierIsValid(identifier) ? identifier : IGThemeIdentifierClassic;
}

void IGSetActiveThemeIdentifier(NSString *identifier) {
    if (!IGThemeIdentifierIsValid(identifier)) {
        identifier = IGThemeIdentifierClassic;
    }
    [[NSUserDefaults standardUserDefaults] setObject:identifier forKey:IGThemeDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:IGThemeDidChangeNotification object:nil];
}

static IGThemePalette IGThemePaletteForIdentifier(NSString *identifier) {
    if ([identifier isEqualToString:IGThemeIdentifierAqua]) {
        return IGThemePaletteMake(0xd9ecfb, 0xb9d7f0, 0xf2f9ff, 0xffffff, 0xdff0fb, 0xecf7fe, 0x86b2d4, 0x91b8d1, 0x0d2237, 0x345f7c, 0x0f73bd, 0xb44747);
    }
    if ([identifier isEqualToString:IGThemeIdentifierSage]) {
        return IGThemePaletteMake(0xecf2ed, 0xd9e5dc, 0xf8fbf8, 0xffffff, 0xeaf2eb, 0xf3f8f4, 0xbacdbc, 0xb8cab9, 0x17241b, 0x526557, 0x3f7a51, 0xa84545);
    }
    if ([identifier isEqualToString:IGThemeIdentifierPlum]) {
        return IGThemePaletteMake(0xf1ecf4, 0xe4d8e9, 0xfcf8fd, 0xffffff, 0xf2eaf5, 0xf8f2fa, 0xcfb9d8, 0xcbb7d2, 0x281b2f, 0x6b5872, 0x7d4d91, 0xb04a59);
    }
    if ([identifier isEqualToString:IGThemeIdentifierRuby]) {
        return IGThemePaletteMake(0xf2eeee, 0xe5dddd, 0xfcfbfb, 0xffffff, 0xf6eeee, 0xf9f4f4, 0xd4bcbc, 0xcdbcbc, 0x261d1d, 0x6a5a5a, 0x9a3e52, 0xb13d3d);
    }
    if ([identifier isEqualToString:IGThemeIdentifierOcean]) {
        return IGThemePaletteMake(0xeaf1f0, 0xd7e6e4, 0xf8fbfb, 0xffffff, 0xecf5f4, 0xf4faf9, 0xb7cecb, 0xb7cbc8, 0x162726, 0x526866, 0x277d7a, 0xa94444);
    }
    return IGThemePaletteMake(0xededed, 0xdbdedf, 0xf8f8f8, 0xffffff, 0xeeeeee, 0xf6f6f6, 0xbebebe, 0xc8c8c8, 0x222222, 0x666666, 0x5e768b, 0xaa4949);
}

static IGThemePalette IGActiveThemePalette(void) {
    return IGThemePaletteForIdentifier(IGActiveThemeIdentifier());
}

NSColor *IGThemeWindowColor(void) {
    return IGColorFromRGB(IGActiveThemePalette().window);
}

NSColor *IGThemeSidebarColor(void) {
    return IGColorFromRGB(IGActiveThemePalette().sidebar);
}

NSColor *IGThemeContentColor(void) {
    return IGColorFromRGB(IGActiveThemePalette().content);
}

NSColor *IGThemePanelColor(void) {
    return IGColorFromRGB(IGActiveThemePalette().panel);
}

NSColor *IGThemePanelInsetColor(void) {
    return IGColorFromRGB(IGActiveThemePalette().panelInset);
}

NSColor *IGThemeControlColor(void) {
    return IGColorFromRGB(IGActiveThemePalette().control);
}

NSColor *IGThemeControlBorderColor(void) {
    return IGColorFromRGB(IGActiveThemePalette().controlBorder);
}

NSColor *IGThemeDividerColor(void) {
    return IGColorFromRGB(IGActiveThemePalette().divider);
}

NSColor *IGThemeTextColor(void) {
    return IGColorFromRGB(IGActiveThemePalette().text);
}

NSColor *IGThemeMutedTextColor(void) {
    return IGColorFromRGB(IGActiveThemePalette().mutedText);
}

NSColor *IGThemeAccentColor(void) {
    return IGColorFromRGB(IGActiveThemePalette().accent);
}

NSColor *IGThemeDangerColor(void) {
    return IGColorFromRGB(IGActiveThemePalette().danger);
}

@implementation IGThemedBackgroundView
@synthesize themeRole = _themeRole;

- (BOOL)isOpaque {
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect bounds = [self bounds];

    if (self.themeRole == IGThemeBackgroundRoleSidebar) {
        NSGradient *gradient = [[[NSGradient alloc] initWithStartingColor:IGColorBlend(IGThemeSidebarColor(), [NSColor whiteColor], 0.20)
                                                               endingColor:IGColorBlend(IGThemeSidebarColor(), IGThemeWindowColor(), 0.35)] autorelease];
        [gradient drawInRect:bounds angle:-90.0];
        [[IGColorWithAlpha([NSColor whiteColor], 0.42) colorUsingColorSpaceName:NSCalibratedRGBColorSpace] set];
        NSRectFill(NSMakeRect(NSMinX(bounds), NSMaxY(bounds) - 1.0, NSWidth(bounds), 1.0));
        [IGThemeDividerColor() set];
        NSRectFill(NSMakeRect(NSMaxX(bounds) - 1.0, NSMinY(bounds), 1.0, NSHeight(bounds)));
        return;
    }

    NSColor *base = self.themeRole == IGThemeBackgroundRoleWindow ? IGThemeWindowColor() : IGThemeContentColor();
    [base set];
    NSRectFill(bounds);

    NSGradient *topGlow = [[[NSGradient alloc] initWithStartingColor:IGColorWithAlpha([NSColor whiteColor], 0.34)
                                                         endingColor:IGColorWithAlpha(base, 0.0)] autorelease];
    [topGlow drawInRect:NSMakeRect(NSMinX(bounds), NSMaxY(bounds) - 130.0, NSWidth(bounds), 130.0) angle:-90.0];

    /*
     Keep content backgrounds unframed. The individual legacy AppKit screens
     use fixed coordinates; a global rounded panel makes controls and footers
     look like they are colliding with an unrelated outer border.
     */
}

@end

@implementation IGThemedButtonCell
@synthesize themeRole = _themeRole;

- (id)copyWithZone:(NSZone *)zone {
    IGThemedButtonCell *copy = [super copyWithZone:zone];
    copy.themeRole = self.themeRole;
    return copy;
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    BOOL enabled = [self isEnabled];
    BOOL selected = ([self state] == NSOnState);
    BOOL highlighted = [self isHighlighted];
    BOOL primary = (self.themeRole == IGThemeButtonRolePrimary);
    BOOL danger = (self.themeRole == IGThemeButtonRoleDanger);
    BOOL sidebar = (self.themeRole == IGThemeButtonRoleSidebar);
    BOOL tab = (self.themeRole == IGThemeButtonRoleTab);
    CGFloat radius = sidebar ? 5.0 : 6.0;

    NSRect rect = NSInsetRect(cellFrame, 0.5, 0.5);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius];

    NSColor *accent = danger ? IGThemeDangerColor() : IGThemeAccentColor();
    NSColor *fillTop = IGThemeControlColor();
    NSColor *fillBottom = IGColorBlend(IGThemeControlColor(), IGThemeDividerColor(), 0.16);
    NSColor *border = IGThemeControlBorderColor();
    NSColor *text = IGThemeTextColor();

    if (sidebar && selected) {
        fillTop = IGColorBlend(accent, [NSColor whiteColor], 0.12);
        fillBottom = IGColorBlend(accent, [NSColor blackColor], 0.04);
        border = IGColorBlend(accent, [NSColor blackColor], 0.12);
        text = [NSColor whiteColor];
    } else if (primary || danger) {
        fillTop = IGColorBlend(accent, [NSColor whiteColor], highlighted ? 0.02 : 0.18);
        fillBottom = IGColorBlend(accent, [NSColor blackColor], highlighted ? 0.14 : 0.04);
        border = IGColorBlend(accent, [NSColor blackColor], 0.18);
        text = [NSColor whiteColor];
    } else if (tab && selected) {
        fillTop = IGColorBlend(accent, [NSColor whiteColor], 0.76);
        fillBottom = IGColorBlend(accent, [NSColor whiteColor], 0.64);
        border = IGColorBlend(accent, IGThemeControlBorderColor(), 0.26);
        text = IGColorBlend(accent, [NSColor blackColor], 0.28);
    } else if (sidebar) {
        fillTop = IGColorWithAlpha(IGThemePanelColor(), 0.76);
        fillBottom = IGColorWithAlpha(IGThemeControlColor(), 0.58);
        border = IGColorWithAlpha(IGThemeControlBorderColor(), 0.70);
        text = IGThemeTextColor();
    }

    if (highlighted && enabled && !(primary || danger || (sidebar && selected))) {
        fillTop = IGColorBlend(fillTop, [NSColor whiteColor], 0.18);
        fillBottom = IGColorBlend(fillBottom, IGThemeAccentColor(), 0.08);
        border = IGColorBlend(border, IGThemeAccentColor(), 0.25);
    }

    if (!enabled) {
        fillTop = IGColorBlend(IGThemeControlColor(), IGThemeContentColor(), 0.56);
        fillBottom = IGColorBlend(IGThemeControlColor(), IGThemeContentColor(), 0.68);
        border = IGColorWithAlpha(IGThemeControlBorderColor(), 0.45);
        text = IGColorWithAlpha(IGThemeMutedTextColor(), 0.58);
    }

    NSGradient *gradient = [[[NSGradient alloc] initWithStartingColor:fillTop endingColor:fillBottom] autorelease];
    [gradient drawInBezierPath:path angle:-90.0];
    [border set];
    [path stroke];

    if (enabled) {
        NSBezierPath *highlightPath = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(rect, 1.0, 1.0) xRadius:MAX(radius - 1.0, 1.0) yRadius:MAX(radius - 1.0, 1.0)];
        [IGColorWithAlpha([NSColor whiteColor], (primary || danger || (sidebar && selected)) ? 0.22 : 0.48) set];
        [highlightPath stroke];
    }

    NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [style setAlignment:NSCenterTextAlignment];
    [style setLineBreakMode:NSLineBreakByTruncatingTail];

    NSFont *font = [self font] ?: [NSFont systemFontOfSize:12.0];
    NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
                           font, NSFontAttributeName,
                           text, NSForegroundColorAttributeName,
                           style, NSParagraphStyleAttributeName,
                           nil];
    NSString *title = [self title] ?: @"";
    NSSize size = [title sizeWithAttributes:attrs];
    CGFloat textY = NSMinY(rect) + floor((NSHeight(rect) - size.height) / 2.0) + 1.0;
    NSRect textRect = NSMakeRect(NSMinX(rect) + 8.0, textY, NSWidth(rect) - 16.0, size.height + 2.0);
    [title drawInRect:textRect withAttributes:attrs];
}

@end

NSView *IGCreateThemedBackgroundView(NSRect frame, IGThemeBackgroundRole role) {
    IGThemedBackgroundView *view = [[[IGThemedBackgroundView alloc] initWithFrame:frame] autorelease];
    view.themeRole = role;
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    return view;
}

static BOOL IGButtonIsChoiceControl(NSButton *button) {
    NSButtonCell *cell = [button cell];
    if (![cell isKindOfClass:[NSButtonCell class]]) {
        return NO;
    }
    if ([cell isKindOfClass:[IGThemedButtonCell class]]) {
        return NO;
    }
    return ![button isBordered];
}

void IGApplyThemeToButton(NSButton *button, IGThemeButtonRole role) {
    if (![button isKindOfClass:[NSButton class]] || [button isKindOfClass:[NSPopUpButton class]]) {
        return;
    }
    if (button.bezelStyle == NSHelpButtonBezelStyle || IGButtonIsChoiceControl(button)) {
        return;
    }

    IGThemedButtonCell *cell = nil;
    if ([[button cell] isKindOfClass:[IGThemedButtonCell class]]) {
        cell = (IGThemedButtonCell *)[button cell];
    } else {
        NSButtonCell *oldCell = [button cell];
        id target = [button target];
        SEL action = [button action];
        NSInteger tag = [button tag];
        NSInteger state = [button state];
        BOOL enabled = [button isEnabled];
        NSInteger highlightsBy = [oldCell highlightsBy];
        NSInteger showsStateBy = [oldCell showsStateBy];
        NSString *keyEquivalent = [[button keyEquivalent] copy];
        NSUInteger keyEquivalentMask = [button keyEquivalentModifierMask];
        NSImage *image = [[button image] retain];
        NSImage *alternateImage = [[button alternateImage] retain];
        NSCellImagePosition imagePosition = [oldCell imagePosition];
        NSImageScaling imageScaling = [oldCell imageScaling];
        NSFont *font = [oldCell font] ?: [NSFont systemFontOfSize:12.0];
        cell = [[[IGThemedButtonCell alloc] initTextCell:[button title] ?: @""] autorelease];
        [cell setButtonType:(role == IGThemeButtonRoleTab ? NSPushOnPushOffButton : NSMomentaryPushInButton)];
        [cell setHighlightsBy:highlightsBy];
        [cell setShowsStateBy:showsStateBy];
        [cell setBezelStyle:NSRoundedBezelStyle];
        [cell setFont:font];
        [cell setAlignment:NSCenterTextAlignment];
        [cell setLineBreakMode:NSLineBreakByTruncatingTail];
        [cell setImage:image];
        [cell setAlternateImage:alternateImage];
        [cell setImagePosition:imagePosition];
        [cell setImageScaling:imageScaling];
        [button setCell:cell];
        [button setTarget:target];
        [button setAction:action];
        [button setTag:tag];
        [button setState:state];
        [button setEnabled:enabled];
        [button setKeyEquivalent:keyEquivalent ?: @""];
        [button setKeyEquivalentModifierMask:keyEquivalentMask];
        [button setBordered:NO];
#if !__has_feature(objc_arc)
        [keyEquivalent release];
        [image release];
        [alternateImage release];
#endif
    }
    cell.themeRole = role;
    [cell setTitle:[button title] ?: @""];
    [button setNeedsDisplay:YES];
}

static IGThemeButtonRole IGThemeButtonRoleForTitle(NSString *title) {
    NSString *lower = [title lowercaseString] ?: @"";
    if ([lower rangeOfString:@"delete"].location != NSNotFound ||
        [lower rangeOfString:@"erase"].location != NSNotFound ||
        [lower rangeOfString:@"clear"].location != NSNotFound ||
        [lower rangeOfString:@"очист"].location != NSNotFound ||
        [lower rangeOfString:@"удал"].location != NSNotFound) {
        return IGThemeButtonRoleDanger;
    }
    if ([lower rangeOfString:@"run"].location != NSNotFound ||
        [lower rangeOfString:@"fix"].location != NSNotFound ||
        [lower rangeOfString:@"export"].location != NSNotFound ||
        [lower rangeOfString:@"import"].location != NSNotFound ||
        [lower rangeOfString:@"generate"].location != NSNotFound ||
        [lower rangeOfString:@"analyze"].location != NSNotFound ||
        [lower rangeOfString:@"scan"].location != NSNotFound ||
        [lower rangeOfString:@"show"].location != NSNotFound ||
        [lower rangeOfString:@"refresh"].location != NSNotFound ||
        [lower rangeOfString:@"optimize"].location != NSNotFound ||
        [lower rangeOfString:@"backup"].location != NSNotFound ||
        [lower rangeOfString:@"restore"].location != NSNotFound ||
        [lower rangeOfString:@"update"].location != NSNotFound ||
        [lower rangeOfString:@"save"].location != NSNotFound ||
        [lower rangeOfString:@"create"].location != NSNotFound ||
        [lower rangeOfString:@"open"].location != NSNotFound ||
        [lower rangeOfString:@"обнов"].location != NSNotFound ||
        [lower rangeOfString:@"сохран"].location != NSNotFound ||
        [lower rangeOfString:@"созд"].location != NSNotFound) {
        return IGThemeButtonRolePrimary;
    }
    return IGThemeButtonRoleSecondary;
}

void IGInstallThemedContentBackground(NSView *view) {
    if (!view) {
        return;
    }
    for (NSView *subview in [view subviews]) {
        if ([subview isKindOfClass:[IGThemedBackgroundView class]]) {
            [(IGThemedBackgroundView *)subview setThemeRole:IGThemeBackgroundRoleContent];
            [subview setFrame:[view bounds]];
            [subview setNeedsDisplay:YES];
            return;
        }
    }
    NSView *background = IGCreateThemedBackgroundView([view bounds], IGThemeBackgroundRoleContent);
    [view addSubview:background positioned:NSWindowBelow relativeTo:nil];
}

void IGApplyThemeToViewHierarchy(NSView *view) {
    if (!view) {
        return;
    }
    if ([view isKindOfClass:[IGThemedBackgroundView class]]) {
        [view setNeedsDisplay:YES];
        return;
    }

    if ([view isKindOfClass:[NSButton class]]) {
        NSButton *button = (NSButton *)view;
        if ([[button cell] isKindOfClass:[IGThemedButtonCell class]]) {
            [button setNeedsDisplay:YES];
        } else {
            IGApplyThemeToButton(button, IGThemeButtonRoleForTitle([button title]));
        }
    } else if ([view isKindOfClass:[NSTextField class]]) {
        NSTextField *field = (NSTextField *)view;
        if (![field isEditable] && ![field isBordered]) {
            CGFloat size = [[field font] pointSize];
            NSColor *existingColor = [field textColor];
            if (IGColorIsNeutral(existingColor) || IGColorIsThemeTextColor(existingColor)) {
                field.textColor = size <= 11.0 ? IGThemeMutedTextColor() : IGThemeTextColor();
                field.drawsBackground = NO;
            }
        }
    } else if ([view isKindOfClass:[NSBox class]]) {
        NSBox *box = (NSBox *)view;
        if ([box boxType] == NSBoxCustom) {
            box.fillColor = IGThemePanelColor();
        }
    }

    NSArray *children = [[view subviews] copy];
    for (NSView *child in children) {
        IGApplyThemeToViewHierarchy(child);
    }
#if !__has_feature(objc_arc)
    [children release];
#endif
}

void IGRefreshThemedViews(NSView *view) {
    if (!view) {
        return;
    }
    [view setNeedsDisplay:YES];
    NSArray *children = [[view subviews] copy];
    for (NSView *child in children) {
        IGRefreshThemedViews(child);
    }
#if !__has_feature(objc_arc)
    [children release];
#endif
}
