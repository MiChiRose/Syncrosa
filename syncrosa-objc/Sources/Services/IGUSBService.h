#import <Foundation/Foundation.h>

@interface IGUSBDrive : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSURL *volumeURL;
@property (nonatomic, assign) int64_t totalSpace;
@property (nonatomic, assign) int64_t freeSpace;
@property (nonatomic, copy) NSString *filesystemType;
@property (nonatomic, copy) NSString *filesystemLabel;
@property (nonatomic, readonly) BOOL isAndroidCompatible;

@end

@interface IGUSBService : NSObject

+ (instancetype)sharedService;

@property (nonatomic, strong, readonly) NSArray *availableDrives;
@property (nonatomic, assign, readonly) BOOL isSearching;

- (void)startMonitoring;
- (void)stopMonitoring;
- (void)updateDrives;

@end

FOUNDATION_EXPORT NSString * const IGUSBExportJobsDidChangeNotification;

/* Progress and result dictionaries are delivered on the main thread. */
@interface IGUSBExportService : NSObject
+ (instancetype)sharedService;
- (instancetype)initWithJournalDirectory:(NSURL *)directory;
- (NSArray *)pendingJobsWithWarnings:(NSArray **)warnings;
- (BOOL)discardJobWithIdentifier:(NSString *)identifier error:(NSError **)error;
- (void)exportTracks:(NSArray *)tracks destination:(NSURL *)destination playlistName:(NSString *)playlistName options:(NSDictionary *)options progress:(void(^)(NSDictionary *progress))progress completion:(void(^)(NSDictionary *result))completion;
- (void)resumeJobWithIdentifier:(NSString *)identifier destination:(NSURL *)destination progress:(void(^)(NSDictionary *progress))progress completion:(void(^)(NSDictionary *result))completion;
- (void)cancel;
/* Synchronous entry points permit offline filesystem regression tests. */
- (NSDictionary *)performExportTracks:(NSArray *)tracks destination:(NSURL *)destination playlistName:(NSString *)playlistName options:(NSDictionary *)options progress:(void(^)(NSDictionary *progress))progress cancel:(BOOL(^)(void))cancel;
- (NSDictionary *)performResumeJobWithIdentifier:(NSString *)identifier destination:(NSURL *)destination progress:(void(^)(NSDictionary *progress))progress cancel:(BOOL(^)(void))cancel;
- (int64_t)availableBytesAtURL:(NSURL *)url;
@end
