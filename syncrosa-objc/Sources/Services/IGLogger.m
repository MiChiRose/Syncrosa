#import "IGLogger.h"

@interface IGLogger ()
@property (nonatomic, strong) NSMutableArray *logLines;
@end

@implementation IGLogger

static NSString *IGLoggerTrimForFile(NSString *value, NSUInteger maxLength) {
    if (!value) return @"";
    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length <= maxLength) {
        return trimmed;
    }
    return [NSString stringWithFormat:@"%@\n... <truncated, %lu total chars>",
            [trimmed substringToIndex:maxLength],
            (unsigned long)trimmed.length];
}

static NSString *IGLoggerThreadLabel(void) {
    return [NSThread isMainThread] ? @"main" : @"background";
}

static BOOL IGLoggerFlagValueEnabled(NSString *value) {
    if (!value) return NO;
    NSString *normalized = [[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    return [normalized isEqualToString:@"1"] ||
           [normalized isEqualToString:@"yes"] ||
           [normalized isEqualToString:@"true"] ||
           [normalized isEqualToString:@"on"] ||
           [normalized isEqualToString:@"debug"];
}

+ (instancetype)sharedLogger {
    static IGLogger *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
        sharedInstance.logLines = [NSMutableArray array];
    });
    return sharedInstance;
}

+ (BOOL)desktopDiagnosticsEnabled {
    NSDictionary *environment = [[NSProcessInfo processInfo] environment];
    NSString *envFlag = [environment objectForKey:@"SYNCROSA_DESKTOP_DEBUG"];
    if (!envFlag) {
        envFlag = [environment objectForKey:@"SYNCROSA_DEV_LOGS"];
    }
    if (envFlag.length > 0) {
        return IGLoggerFlagValueEnabled(envFlag);
    }

    return [[NSUserDefaults standardUserDefaults] boolForKey:@"SyncrosaDesktopDebugEnabled"];
}

- (NSString *)diagnosticLogPath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES);
    NSString *desktopPath = paths.count > 0 ? [paths objectAtIndex:0] : [NSHomeDirectory() stringByAppendingPathComponent:@"Desktop"];
    return [desktopPath stringByAppendingPathComponent:@"Syncrosa-Debug.log"];
}

- (void)appendDiagnosticLine:(NSString *)line {
    if (!line) return;
    if (![IGLogger desktopDiagnosticsEnabled]) return;

    @synchronized (self) {
        NSString *path = [self diagnosticLogPath];
        NSString *parent = [path stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:parent
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];

        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!handle) {
            [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
            handle = [NSFileHandle fileHandleForWritingAtPath:path];
        }

        if (handle) {
            [handle seekToEndOfFile];
            NSData *data = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
            [handle writeData:data];
            [handle closeFile];
        }
    }
}

- (void)startDiagnosticSession {
    if (![IGLogger desktopDiagnosticsEnabled]) return;

    NSString *bundleVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] ?: @"unknown";
    NSString *build = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"] ?: @"unknown";
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath] ?: @"unknown";
    NSString *osString = [[NSProcessInfo processInfo] operatingSystemVersionString] ?: @"unknown";

    [self appendDiagnosticLine:@""];
    [self appendDiagnosticLine:@"==================== Syncrosa Diagnostic Session ===================="];
    [self log:[NSString stringWithFormat:@"Diagnostic log path: %@", [self diagnosticLogPath]]];
    [self log:[NSString stringWithFormat:@"App version: %@ (%@)", bundleVersion, build]];
    [self log:[NSString stringWithFormat:@"Bundle path: %@", bundlePath]];
    [self log:[NSString stringWithFormat:@"OS: %@", osString]];
    [self log:[NSString stringWithFormat:@"Home: %@", NSHomeDirectory() ?: @"unknown"]];
    [self log:[NSString stringWithFormat:@"Temp: %@", NSTemporaryDirectory() ?: @"unknown"]];
    [self log:[NSString stringWithFormat:@"Process: %@ pid=%d", [[NSProcessInfo processInfo] processName], [[NSProcessInfo processInfo] processIdentifier]]];
}

- (void)log:(NSString *)message {
    NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                         dateStyle:NSDateFormatterShortStyle
                                                         timeStyle:NSDateFormatterLongStyle];
    NSString *line = [NSString stringWithFormat:@"[%@][%@] %@", timestamp, IGLoggerThreadLabel(), message ?: @""];
    @synchronized (self) {
        [self.logLines addObject:line];
    }
    NSLog(@"%@", line);
    if ([IGLogger desktopDiagnosticsEnabled]) {
        [self appendDiagnosticLine:line];
    }
}

- (void)logAppleScriptWithName:(NSString *)name
                         source:(NSString *)source
                         stdout:(NSString *)stdoutText
                         stderr:(NSString *)stderrText
               terminationStatus:(int)terminationStatus
                     elapsedTime:(NSTimeInterval)elapsedTime
                        timedOut:(BOOL)timedOut {
    NSString *label = name.length > 0 ? name : @"AppleScript";
    [self log:[NSString stringWithFormat:@"AppleScript '%@' finished status=%d timeout=%@ elapsed=%.2fs sourceLength=%lu",
               label,
               terminationStatus,
               timedOut ? @"YES" : @"NO",
               elapsedTime,
               (unsigned long)source.length]];
    if (![IGLogger desktopDiagnosticsEnabled]) return;

    [self appendDiagnosticLine:[NSString stringWithFormat:@"--- AppleScript %@ SOURCE ---", label]];
    [self appendDiagnosticLine:IGLoggerTrimForFile(source, 4000)];
    [self appendDiagnosticLine:[NSString stringWithFormat:@"--- AppleScript %@ STDOUT ---", label]];
    [self appendDiagnosticLine:IGLoggerTrimForFile(stdoutText, 12000)];
    [self appendDiagnosticLine:[NSString stringWithFormat:@"--- AppleScript %@ STDERR ---", label]];
    [self appendDiagnosticLine:IGLoggerTrimForFile(stderrText, 12000)];
    [self appendDiagnosticLine:[NSString stringWithFormat:@"--- AppleScript %@ END ---", label]];
}

- (NSString *)currentLog {
    @synchronized (self) {
        return [self.logLines componentsJoinedByString:@"\n"];
    }
}

- (void)clearLog {
    @synchronized (self) {
        [self.logLines removeAllObjects];
    }
}

- (void)saveLogToDesktopWithRawResponse:(NSString *)rawResponse {
    if (![IGLogger desktopDiagnosticsEnabled]) return;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:@"enable_logging"]) return;

    NSMutableString *fullLog = [NSMutableString stringWithString:[self currentLog]];
    if (rawResponse) {
        [fullLog appendFormat:@"\n\n--- RAW AI RESPONSE ---\n%@\n", rawResponse];
    }
    
    NSString *fileName = [NSString stringWithFormat:@"Syncrosa_Log_%ld.txt", (long)[[NSDate date] timeIntervalSince1970]];
    NSString *desktopPath = [NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES) firstObject];
    NSString *filePath = [desktopPath stringByAppendingPathComponent:fileName];
    
    NSError *error = nil;
    [fullLog writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    
    if (!error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Log Saved"];
            [alert setInformativeText:[NSString stringWithFormat:@"A detailed log has been saved to your Desktop as %@", fileName]];
            [alert runModal];
        });
    }
}

@end
