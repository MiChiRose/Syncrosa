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

@property (nonatomic, strong, readonly) NSArray<IGUSBDrive *> *availableDrives;

- (void)startMonitoring;
- (void)stopMonitoring;
- (void)updateDrives;

@end
