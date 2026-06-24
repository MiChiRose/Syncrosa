#import "IGNotificationView.h"

@interface IGNotificationView ()
@property (nonatomic, strong) NSTextField *label;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, assign) BOOL isError;
@end

@implementation IGNotificationView

+ (void)showInView:(NSView *)parentView message:(NSString *)message isError:(BOOL)isError {
    [self dismissInView:parentView];
    
    CGFloat width = 450;
    CGFloat height = 36;
    NSRect parentBounds = parentView.bounds;
    NSRect frame = NSMakeRect((parentBounds.size.width - width) / 2.0, parentBounds.size.height - height - 15, width, height);
    
    IGNotificationView *hud = [[IGNotificationView alloc] initWithFrame:frame];
    hud.isError = isError;
    hud.label.stringValue = message;
    
    // Setup text color and background color
    if (isError) {
        hud.label.textColor = [NSColor whiteColor];
    } else {
        hud.label.textColor = [NSColor whiteColor];
    }
    
    // Add to parent view with zero alpha for fade in
    hud.alphaValue = 0.0;
    hud.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin;
    [parentView addSubview:hud];
    
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
        context.duration = 0.3;
        hud.animator.alphaValue = 1.0;
    } completionHandler:nil];
    
    // Auto dismiss after 3 seconds if not a loading/progress indicator (i.e. doesn't contain "...")
    if (![message containsString:@"..."]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (hud.superview) {
                [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
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
    for (NSView *subview in [parentView.subviews copy]) {
        if ([subview isKindOfClass:[IGNotificationView class]]) {
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
                context.duration = 0.2;
                subview.animator.alphaValue = 0.0;
            } completionHandler:^{
                [subview removeFromSuperview];
            }];
        }
    }
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 8.0;
        
        // Semi-transparent black background
        self.layer.backgroundColor = [[NSColor colorWithCalibratedWhite:0.1 alpha:0.9] CGColor];
        
        // Text Label
        _label = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 8, frame.size.width - 45, 20)];
        _label.editable = NO;
        _label.bordered = NO;
        _label.drawsBackground = NO;
        _label.alignment = NSCenterTextAlignment;
        if ([NSFont respondsToSelector:@selector(systemFontOfSize:weight:)]) {
            _label.font = [NSFont systemFontOfSize:11 weight:0.0]; // Regular weight
        } else {
            _label.font = [NSFont systemFontOfSize:11];
        }
        [self addSubview:_label];
        
        // Close Button
        _closeButton = [[NSButton alloc] initWithFrame:NSMakeRect(frame.size.width - 30, 8, 20, 20)];
        _closeButton.title = @"✕";
        _closeButton.bordered = NO;
        _closeButton.font = [NSFont systemFontOfSize:11];
        [_closeButton.cell setTextColor:[NSColor grayColor]];
        _closeButton.target = self;
        _closeButton.action = @selector(closeClicked:);
        [self addSubview:_closeButton];
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    // Round corner background is handled by CALayer cornerRadius
    [super drawRect:dirtyRect];
}

- (void)closeClicked:(id)sender {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
        context.duration = 0.2;
        self.animator.alphaValue = 0.0;
    } completionHandler:^{
        [self removeFromSuperview];
    }];
}

@end
