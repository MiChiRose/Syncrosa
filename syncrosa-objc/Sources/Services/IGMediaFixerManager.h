#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSArray *IGMediaAppleVideoMatchesFromData(NSData *data,
                                                            BOOL television,
                                                            NSInteger requestedSeason,
                                                            NSInteger requestedEpisode);

/** Conservative catalog matching: ambiguous editions and different recording versions are rejected. */
FOUNDATION_EXPORT NSDictionary *IGMediaBestAppleMusicMatch(NSArray *results, NSString *artist, NSString *title, NSString *album);
/** Returns only selected fields which are missing in the snapshot; never replaces existing lyrics. */
FOUNDATION_EXPORT NSDictionary *IGMediaMissingMetadataProperties(NSDictionary *track, NSDictionary *metadata, NSString *lyrics, NSDictionary *options);

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
- (void)runMetadataFixWithOptions:(NSDictionary *)options
                         progress:(void(^)(NSInteger current, NSInteger total))progressBlock
                   reportCompletion:(void(^)(NSDictionary *report))completionBlock;

@end
