#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString * const IGOperationActivityDidChangeNotification;
FOUNDATION_EXPORT NSString * const IGOperationRecoveryDidChangeNotification;
FOUNDATION_EXPORT NSString * const IGOperationActivityUSBExportIdentifier;
FOUNDATION_EXPORT NSString * const IGOperationActivityAIPlaylistIdentifier;
FOUNDATION_EXPORT NSString * const IGOperationActivityVideoMetadataIdentifier;

@interface IGOperationActivity : NSObject

+ (instancetype)sharedActivity;

@property (nonatomic, readonly, copy) NSString *activeIdentifier;
@property (nonatomic, readonly, assign) double progress;

- (id)initWithRecoveryDirectory:(NSString *)directory;
@property (nonatomic, readonly, copy) NSArray *recoveryMarkers;
@property (nonatomic, readonly, copy) NSArray *recoveryWarnings;
- (void)reloadRecoveryMarkers;
- (BOOL)saveRecoveryMarker:(NSDictionary *)marker error:(NSError **)error;
- (BOOL)finishRecoveryMarkerWithIdentifier:(NSString *)identifier error:(NSError **)error;
- (BOOL)clearRecoveryMarkerWithIdentifier:(NSString *)identifier error:(NSError **)error;

- (BOOL)beginOperationWithIdentifier:(NSString *)identifier;
- (void)updateProgress:(double)progress forIdentifier:(NSString *)identifier;
- (void)finishOperationWithIdentifier:(NSString *)identifier;
- (BOOL)isOperationActiveWithIdentifier:(NSString *)identifier;

@end
