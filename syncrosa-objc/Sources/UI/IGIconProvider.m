#import "IGIconProvider.h"
#import "IGTheme.h"

static NSImage *IGTintIconImage(NSImage *source, NSColor *color)
{
    if (!source) {
        return nil;
    }
    NSSize size = [source size];
    if (size.width <= 0.0 || size.height <= 0.0) {
        return source;
    }

    NSImage *result = [[[NSImage alloc] initWithSize:size] autorelease];
    [result lockFocus];
    [source drawInRect:NSMakeRect(0.0, 0.0, size.width, size.height)
              fromRect:NSZeroRect
             operation:NSCompositeSourceOver
              fraction:1.0
        respectFlipped:NO
                 hints:nil];
    [color set];
    NSRectFillUsingOperation(NSMakeRect(0.0, 0.0, size.width, size.height), NSCompositeSourceAtop);
    [result unlockFocus];
    return result;
}

NSImage *IGIconImageNamed(NSString *name)
{
    if (![name length]) {
        return nil;
    }
    NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"png"];
    if (![path length]) {
        return nil;
    }
    return [[[NSImage alloc] initWithContentsOfFile:path] autorelease];
}

NSImage *IGIconImageNamedFlipped(NSString *name, BOOL flippedHorizontally)
{
    NSImage *source = IGIconImageNamed(name);
    if (!source || !flippedHorizontally) {
        return source;
    }

    NSSize size = [source size];
    NSImage *result = [[[NSImage alloc] initWithSize:size] autorelease];
    [result lockFocus];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:size.width yBy:0.0];
    [transform scaleXBy:-1.0 yBy:1.0];
    [transform concat];
    [source drawInRect:NSMakeRect(0.0, 0.0, size.width, size.height)
              fromRect:NSZeroRect
             operation:NSCompositeSourceOver
              fraction:1.0
        respectFlipped:NO
                 hints:nil];
    [result unlockFocus];
    return result;
}

NSImage *IGIconImageNamedRotated(NSString *name, CGFloat degrees)
{
    NSImage *source = IGIconImageNamed(name);
    if (!source || degrees == 0.0) {
        return source;
    }

    NSSize size = [source size];
    NSImage *result = [[[NSImage alloc] initWithSize:size] autorelease];
    [result lockFocus];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:size.width / 2.0 yBy:size.height / 2.0];
    [transform rotateByDegrees:degrees];
    [transform translateXBy:-size.width / 2.0 yBy:-size.height / 2.0];
    [transform concat];
    [source drawInRect:NSMakeRect(0.0, 0.0, size.width, size.height)
              fromRect:NSZeroRect
             operation:NSCompositeSourceOver
              fraction:1.0
        respectFlipped:NO
                 hints:nil];
    [result unlockFocus];
    return result;
}

void IGConfigureIconButton(NSButton *button, NSString *name, NSString *toolTip, BOOL imageOnly)
{
    if (!button) {
        return;
    }
    NSImage *image = IGIconImageNamed(name);
    [image setSize:NSMakeSize(imageOnly ? 15.0 : 16.0, imageOnly ? 15.0 : 16.0)];
    button.image = image;
    [[button cell] setImagePosition:imageOnly ? NSImageOnly : NSImageLeft];
    [[button cell] setImageScaling:NSImageScaleProportionallyDown];
    if ([toolTip length]) {
        button.toolTip = toolTip;
    }
}

@interface IGThemedIconView : NSView
@property (nonatomic, copy) NSString *iconName;
@property (nonatomic, assign) IGThemeIconRole iconRole;
@end

@implementation IGThemedIconView
@synthesize iconName = _iconName;
@synthesize iconRole = _iconRole;

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(themeChanged:)
                                                     name:IGThemeDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
#if !__has_feature(objc_arc)
    [_iconName release];
    [super dealloc];
#endif
}

- (BOOL)isOpaque
{
    return NO;
}

- (void)themeChanged:(NSNotification *)notification
{
    (void)notification;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    NSColor *color = IGThemeAccentColor();
    if (self.iconRole == IGThemeIconRoleText) {
        color = IGThemeTextColor();
    } else if (self.iconRole == IGThemeIconRoleMuted) {
        color = IGThemeMutedTextColor();
    }
    NSImage *image = IGTintIconImage(IGIconImageNamed(self.iconName), color);
    if (!image) {
        return;
    }
    [image drawInRect:NSInsetRect(self.bounds, 1.0, 1.0)
             fromRect:NSZeroRect
            operation:NSCompositeSourceOver
             fraction:1.0
       respectFlipped:YES
                hints:nil];
}

@end

NSView *IGCreateThemedIconView(NSString *name, NSRect frame, IGThemeIconRole role)
{
    IGThemedIconView *view = [[[IGThemedIconView alloc] initWithFrame:frame] autorelease];
    view.iconName = name;
    view.iconRole = role;
    return view;
}
