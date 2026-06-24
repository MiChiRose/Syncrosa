#import <AppKit/AppKit.h>

@interface IGNotificationView : NSView

+ (void)showInView:(NSView *)parentView message:(NSString *)message isError:(BOOL)isError;
+ (void)dismissInView:(NSView *)parentView;

@end
