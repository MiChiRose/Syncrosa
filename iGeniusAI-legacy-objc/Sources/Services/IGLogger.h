#import <Cocoa/Cocoa.h>

@interface IGLogger : NSObject

+ (instancetype)sharedLogger;
- (void)log:(NSString *)message;
- (void)saveLogToDesktopWithRawResponse:(NSString *)rawResponse;
- (NSString *)currentLog;
- (void)clearLog;

@end
