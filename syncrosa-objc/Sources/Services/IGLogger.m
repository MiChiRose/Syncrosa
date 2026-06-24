#import "IGLogger.h"

@interface IGLogger ()
@property (nonatomic, strong) NSMutableArray *logLines;
@end

@implementation IGLogger

+ (instancetype)sharedLogger {
    static IGLogger *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
        sharedInstance.logLines = [NSMutableArray array];
    });
    return sharedInstance;
}

- (void)log:(NSString *)message {
    NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                         dateStyle:NSDateFormatterShortStyle
                                                         timeStyle:NSDateFormatterLongStyle];
    NSString *line = [NSString stringWithFormat:@"[%@] %@", timestamp, message];
    [self.logLines addObject:line];
    NSLog(@"%@", line);
}

- (NSString *)currentLog {
    return [self.logLines componentsJoinedByString:@"\n"];
}

- (void)clearLog {
    [self.logLines removeAllObjects];
}

- (void)saveLogToDesktopWithRawResponse:(NSString *)rawResponse {
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
