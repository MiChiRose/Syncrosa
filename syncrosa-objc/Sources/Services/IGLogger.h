#import <Cocoa/Cocoa.h>

@interface IGLogger : NSObject

+ (instancetype)sharedLogger;
+ (BOOL)desktopDiagnosticsEnabled;
- (NSString *)diagnosticLogPath;
- (void)startDiagnosticSession;
- (void)log:(NSString *)message;
- (void)logAppleScriptWithName:(NSString *)name
                         source:(NSString *)source
                         stdout:(NSString *)stdoutText
                         stderr:(NSString *)stderrText
                 terminationStatus:(int)terminationStatus
                       elapsedTime:(NSTimeInterval)elapsedTime
                          timedOut:(BOOL)timedOut;
- (void)saveLogToDesktopWithRawResponse:(NSString *)rawResponse;
- (NSString *)currentLog;
- (void)clearLog;

@end
