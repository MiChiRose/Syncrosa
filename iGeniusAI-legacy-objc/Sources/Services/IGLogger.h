#import <Foundation/AppKit.h>

@interface IGLogger : NSObject

+ (instancetype)sharedLogger;
- (void)log:(NSString *)message;
- (void)saveLogToDesktopWithRawResponse:(NSString *)rawResponse;
- (NSString *)currentLog;
- (void)clearLog;

@end
