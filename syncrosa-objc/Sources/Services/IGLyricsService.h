#import <Foundation/Foundation.h>

@interface IGLyricsService : NSObject

+ (instancetype)sharedService;

- (void)fetchLyricsForArtist:(NSString *)artist 
                       title:(NSString *)title 
                  completion:(void(^)(NSString *lyrics))completionBlock;

@end
