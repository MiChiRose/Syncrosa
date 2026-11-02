#import <Foundation/Foundation.h>

@interface IGLyricsService : NSObject

+ (instancetype)sharedService;

- (void)fetchLyricsForArtist:(NSString *)artist 
                       title:(NSString *)title 
                  completion:(void(^)(NSString *lyrics))completionBlock;
- (void)fetchLyricsForArtist:(NSString *)artist
                       title:(NSString *)title
             errorCompletion:(void(^)(NSString *lyrics, NSString *errorMessage))completionBlock;
/** Background-thread variant used by sequential legacy repair jobs. */
- (NSString *)lyricsForArtist:(NSString *)artist title:(NSString *)title errorMessage:(NSString **)errorMessage;

@end
