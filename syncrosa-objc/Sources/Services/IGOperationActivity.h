#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString * const IGOperationActivityDidChangeNotification;
FOUNDATION_EXPORT NSString * const IGOperationActivityUSBExportIdentifier;
FOUNDATION_EXPORT NSString * const IGOperationActivityAIPlaylistIdentifier;
FOUNDATION_EXPORT NSString * const IGOperationActivityVideoMetadataIdentifier;

@interface IGOperationActivity : NSObject

+ (instancetype)sharedActivity;

@property (nonatomic, readonly, copy) NSString *activeIdentifier;
@property (nonatomic, readonly, assign) double progress;

- (BOOL)beginOperationWithIdentifier:(NSString *)identifier;
- (void)updateProgress:(double)progress forIdentifier:(NSString *)identifier;
- (void)finishOperationWithIdentifier:(NSString *)identifier;
- (BOOL)isOperationActiveWithIdentifier:(NSString *)identifier;

@end
