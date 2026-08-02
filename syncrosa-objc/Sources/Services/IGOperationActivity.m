#import "IGOperationActivity.h"

NSString * const IGOperationActivityDidChangeNotification = @"IGOperationActivityDidChangeNotification";
NSString * const IGOperationActivityUSBExportIdentifier = @"usb-export";
NSString * const IGOperationActivityAIPlaylistIdentifier = @"ai-playlist";
NSString * const IGOperationActivityVideoMetadataIdentifier = @"video-metadata";

@interface IGOperationActivity ()
@property (nonatomic, readwrite, copy) NSString *activeIdentifier;
@property (nonatomic, readwrite, assign) double progress;
@end

@implementation IGOperationActivity

+ (instancetype)sharedActivity {
    static IGOperationActivity *activity = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        activity = [[self alloc] init];
    });
    return activity;
}

- (BOOL)beginOperationWithIdentifier:(NSString *)identifier {
    if ([identifier length] == 0) return NO;
    if ([self.activeIdentifier length] > 0 && ![self.activeIdentifier isEqualToString:identifier]) return NO;
    self.activeIdentifier = identifier;
    self.progress = 0.0;
    [self postChange];
    return YES;
}

- (void)updateProgress:(double)progress forIdentifier:(NSString *)identifier {
    if (![self.activeIdentifier isEqualToString:identifier]) return;
    self.progress = MIN(1.0, MAX(0.0, progress));
    [self postChange];
}

- (void)finishOperationWithIdentifier:(NSString *)identifier {
    if (![self.activeIdentifier isEqualToString:identifier]) return;
    self.activeIdentifier = nil;
    self.progress = 0.0;
    [self postChange];
}

- (BOOL)isOperationActiveWithIdentifier:(NSString *)identifier {
    return [self.activeIdentifier isEqualToString:identifier];
}

- (void)postChange {
    void (^postBlock)(void) = ^{
        NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
                              self.activeIdentifier ?: @"", @"identifier",
                              [NSNumber numberWithDouble:self.progress], @"progress",
                              nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:IGOperationActivityDidChangeNotification
                                                            object:self
                                                          userInfo:info];
    };
    if ([NSThread isMainThread]) {
        postBlock();
    } else {
        dispatch_async(dispatch_get_main_queue(), postBlock);
    }
}

- (void)dealloc {
#if !__has_feature(objc_arc)
    [_activeIdentifier release];
    [super dealloc];
#endif
}

@end
