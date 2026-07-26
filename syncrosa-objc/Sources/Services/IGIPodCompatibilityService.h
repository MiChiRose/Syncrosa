#import <Foundation/Foundation.h>

typedef void (^IGIPodConversionProgressBlock)(NSInteger completed,
                                               NSInteger total,
                                               NSString *filename,
                                               double fileProgress);
typedef void (^IGIPodConversionCompletionBlock)(NSArray *convertedFiles, NSArray *failures, BOOL cancelled);

typedef NSInteger IGIPodConversionMode;
enum {
    IGIPodConversionModeCreateCopy = 0,
    IGIPodConversionModeReplaceITunesTrack = 1
};

@interface IGIPodCompatibilityService : NSObject

+ (instancetype)sharedService;
+ (BOOL)isSupportedFileURL:(NSURL *)fileURL;
+ (NSArray *)compatibilityIssuesForFileURL:(NSURL *)fileURL deepScan:(BOOL)deepScan;
+ (NSURL *)destinationURLForSourceURL:(NSURL *)sourceURL
                          directoryURL:(NSURL *)directoryURL
                           fileManager:(NSFileManager *)fileManager;

- (void)convertFiles:(NSArray *)fileURLs
         toDirectory:(NSURL *)directoryURL
            progress:(IGIPodConversionProgressBlock)progressBlock
          completion:(IGIPodConversionCompletionBlock)completionBlock;
- (void)convertFiles:(NSArray *)fileURLs
         toDirectory:(NSURL *)directoryURL
                mode:(IGIPodConversionMode)mode
            progress:(IGIPodConversionProgressBlock)progressBlock
          completion:(IGIPodConversionCompletionBlock)completionBlock;
- (void)cancelConversion;

@end
