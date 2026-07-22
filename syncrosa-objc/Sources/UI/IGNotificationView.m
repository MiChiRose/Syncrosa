#import "IGNotificationView.h"
#import "IGLogger.h"
#import "IGTheme.h"
#import <QuartzCore/QuartzCore.h>

@interface IGNotificationView ()
@property (nonatomic, strong) NSTextField *label;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, assign) BOOL isError;
- (void)applyTheme;
@end

@implementation IGNotificationView

+ (void)showInView:(NSView *)parentView message:(NSString *)message isError:(BOOL)isError {
    [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"Notification show isError=%@ message=%@", isError ? @"YES" : @"NO", message ?: @""]];
    [self dismissInView:parentView];
    
    CGFloat width = 450;
    CGFloat height = 36;
    NSRect parentBounds = parentView.bounds;
    NSRect frame = NSMakeRect((parentBounds.size.width - width) / 2.0, parentBounds.size.height - height - 15, width, height);
    
    IGNotificationView *hud = [[IGNotificationView alloc] initWithFrame:frame];
    hud.isError = isError;
    hud.label.stringValue = message;
    [hud applyTheme];
    
    // Add to parent view with zero alpha for fade in
    hud.alphaValue = 0.0;
    hud.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin;
    [parentView addSubview:hud];
#if !__has_feature(objc_arc)
    [hud release];
#endif
    
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.3;
        hud.animator.alphaValue = 1.0;
    } completionHandler:nil];
    
    // Auto dismiss after 3 seconds if not a loading/progress indicator (i.e. doesn't contain "...")
    if ([message rangeOfString:@"..."].location == NSNotFound) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (hud.superview) {
                [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                    context.duration = 0.3;
                    hud.animator.alphaValue = 0.0;
                } completionHandler:^{
                    [hud removeFromSuperview];
                }];
            }
        });
    }
}

+ (void)dismissInView:(NSView *)parentView {
    NSArray *subviews = [parentView.subviews copy];
    for (NSView *subview in subviews) {
        if ([subview isKindOfClass:[IGNotificationView class]]) {
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                context.duration = 0.2;
                subview.animator.alphaValue = 0.0;
            } completionHandler:^{
                [subview removeFromSuperview];
            }];
        }
    }
#if !__has_feature(objc_arc)
    [subviews release];
#endif
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 8.0;
        
        // Text Label
        _label = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 8, frame.size.width - 45, 20)];
        _label.editable = NO;
        _label.bordered = NO;
        _label.drawsBackground = NO;
        _label.alignment = NSCenterTextAlignment;
        _label.font = [NSFont systemFontOfSize:11];
        [self addSubview:_label];
        
        // Close Button
        _closeButton = [[NSButton alloc] initWithFrame:NSMakeRect(frame.size.width - 30, 8, 20, 20)];
        _closeButton.title = @"✕";
        _closeButton.bordered = NO;
        _closeButton.font = [NSFont systemFontOfSize:11];
        if ([_closeButton respondsToSelector:@selector(setAttributedTitle:)]) {
            NSDictionary *attrs = @{
                NSForegroundColorAttributeName: [NSColor whiteColor],
                NSFontAttributeName: [NSFont systemFontOfSize:11]
            };
            NSAttributedString *title = [[NSAttributedString alloc] initWithString:_closeButton.title attributes:attrs];
            [_closeButton setAttributedTitle:title];
#if !__has_feature(objc_arc)
            [title release];
#endif
        }
        _closeButton.target = self;
        _closeButton.action = @selector(closeClicked:);
        [self addSubview:_closeButton];
    }
    return self;
}

- (void)applyTheme {
    NSColor *background = self.isError ? IGThemeDangerColor() : IGThemeAccentColor();
    self.layer.backgroundColor = [[background colorWithAlphaComponent:0.94] CGColor];
    self.label.textColor = [NSColor whiteColor];
    NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
                           [NSColor whiteColor], NSForegroundColorAttributeName,
                           [NSFont systemFontOfSize:11], NSFontAttributeName,
                           nil];
    NSAttributedString *title = [[NSAttributedString alloc] initWithString:self.closeButton.title ?: @"" attributes:attrs];
    [self.closeButton setAttributedTitle:title];
#if !__has_feature(objc_arc)
    [title release];
#endif
}

- (void)dealloc {
#if !__has_feature(objc_arc)
    [_label release];
    [_closeButton release];
    [super dealloc];
#endif
}

- (void)drawRect:(NSRect)dirtyRect {
    // Round corner background is handled by CALayer cornerRadius
    [super drawRect:dirtyRect];
}

- (void)closeClicked:(id)sender {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.2;
        self.animator.alphaValue = 0.0;
    } completionHandler:^{
        [self removeFromSuperview];
    }];
}

@end
