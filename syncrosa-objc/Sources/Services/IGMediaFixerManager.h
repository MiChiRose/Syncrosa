#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSArray *IGMediaAppleVideoMatchesFromData(NSData *data,
                                                            BOOL television,
                                                            NSInteger requestedSeason,
                                                            NSInteger requestedEpisode);

@interface IGMediaFixerManager : NSObject

+ (instancetype)sharedManager;

- (NSString *)normalizeText:(NSString *)text;
- (void)searchVideoMetadataForTitle:(NSString *)title
                          videoKind:(NSString *)videoKind
                          completion:(void(^)(NSArray *results, NSString *errorMessage))completionBlock;
- (void)searchVideoMetadataForTitle:(NSString *)title
                          videoKind:(NSString *)videoKind
                           showName:(NSString *)showName
                       seasonNumber:(NSInteger)seasonNumber
                      episodeNumber:(NSInteger)episodeNumber
                         completion:(void(^)(NSArray *results, NSString *errorMessage))completionBlock;
- (void)downloadVideoArtworkAtURLString:(NSString *)urlString
                              completion:(void(^)(NSURL *fileURL, NSString *errorMessage))completionBlock;
- (void)getMergeCandidatesWithCompletion:(void(^)(NSArray *candidates))completionBlock;
- (void)runMetadataFixWithProgress:(void(^)(NSInteger current, NSInteger total))progressBlock 
                        completion:(void(^)(void))completionBlock;
- (void)runMetadataFixWithOptions:(NSDictionary *)options
                         progress:(void(^)(NSInteger current, NSInteger total))progressBlock 
                       completion:(void(^)(void))completionBlock;

@end
