#import <Foundation/Foundation.h>

@interface IGVideoFileMetadataService : NSObject

+ (instancetype)sharedService;
+ (NSArray *)supportedVideoExtensions;
+ (NSArray *)videoFileURLsInDirectory:(NSURL *)directoryURL;
+ (NSDictionary *)filenameHintsForName:(NSString *)name;
+ (NSDictionary *)filenameHintsForURL:(NSURL *)fileURL;
+ (NSDictionary *)televisionHintsForMetadataComment:(NSString *)comment;
+ (NSString *)episodeDisplayTitleForTitle:(NSString *)title
                             seasonNumber:(NSInteger)seasonNumber
                            episodeNumber:(NSInteger)episodeNumber;

- (void)readMetadataAtURL:(NSURL *)fileURL
               completion:(void(^)(NSDictionary *metadata, NSString *errorMessage))completionBlock;

- (void)writeMetadata:(NSDictionary *)metadata
           artworkURL:(NSURL *)artworkURL
             toFileURL:(NSURL *)fileURL
            completion:(void(^)(BOOL success, NSURL *backupURL, NSString *errorMessage))completionBlock;

@end
