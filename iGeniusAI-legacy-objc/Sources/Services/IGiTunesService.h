#import <Foundation/Foundation.h>
#import "IGTrack.h"

@interface IGiTunesService : NSObject

+ (instancetype)sharedService;

/**
 * Fetches all tracks from iTunes library playlist 1.
 * @param progressBlock A block called with (currentCount, totalCount).
 * @param completionBlock A block called with the array of IGTrack objects.
 */
- (void)fetchAllTracksWithProgress:(void(^)(NSInteger current, NSInteger total))progressBlock 
                        completion:(void(^)(NSArray *tracks))completionBlock;

/**
 * Creates a playlist in iTunes and adds tracks by their persistent IDs.
 */
- (void)createPlaylistWithName:(NSString *)name 
                 persistentIDs:(NSArray *)pids 
                    completion:(void(^)(NSInteger addedCount))completionBlock;

// Metadata fixing methods (to be implemented)
- (void)getMergeCandidatesWithCompletion:(void(^)(NSArray *candidates))completionBlock;
- (void)runMetadataFixWithProgress:(void(^)(NSInteger current, NSInteger total))progressBlock 
                        completion:(void(^)(void))completionBlock;

@end
