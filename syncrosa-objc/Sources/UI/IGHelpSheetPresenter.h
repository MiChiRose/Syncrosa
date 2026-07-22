#import <Cocoa/Cocoa.h>

NSDictionary *IGHelpSectionMake(NSString *title, NSString *body);

@interface IGHelpSheetPresenter : NSObject

+ (NSWindow *)sheetWithTitle:(NSString *)title
                     summary:(NSString *)summary
                    sections:(NSArray *)sections
                  closeTitle:(NSString *)closeTitle
                      target:(id)target
                      action:(SEL)action;

+ (void)presentSheet:(NSWindow *)sheet forWindow:(NSWindow *)parentWindow;
+ (void)dismissSheet:(NSWindow *)sheet fromWindow:(NSWindow *)parentWindow;

@end
