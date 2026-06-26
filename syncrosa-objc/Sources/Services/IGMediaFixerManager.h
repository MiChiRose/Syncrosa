#import <Foundation/Foundation.h>

@interface IGMediaFixerManager : NSObject

+ (instancetype)sharedManager;

- (NSString *)normalizeText:(NSString *)text;
- (void)getMergeCandidatesWithCompletion:(void(^)(NSArray *candidates))completionBlock;
- (void)runMetadataFixWithProgress:(void(^)(NSInteger current, NSInteger total))progressBlock 
                        completion:(void(^)(void))completionBlock;
- (void)runMetadataFixWithOptions:(NSDictionary *)options
                         progress:(void(^)(NSInteger current, NSInteger total))progressBlock 
                       completion:(void(^)(void))completionBlock;

@end
