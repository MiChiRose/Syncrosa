#import "IGUSBService.h"
#import <AppKit/AppKit.h>
#import <sys/mount.h>

@implementation IGUSBDrive

- (void)dealloc {
#if !__has_feature(objc_arc)
    [_name release];
    [_volumeURL release];
    [_filesystemType release];
    [_filesystemLabel release];
    [super dealloc];
#endif
}

- (BOOL)isAndroidCompatible {
    NSString *typeLower = [self.filesystemType lowercaseString];
    NSString *labelLower = [self.filesystemLabel lowercaseString];
    return [typeLower rangeOfString:@"msdos"].location != NSNotFound ||
           [typeLower rangeOfString:@"fat"].location != NSNotFound ||
           [typeLower rangeOfString:@"exfat"].location != NSNotFound ||
           [labelLower rangeOfString:@"fat32"].location != NSNotFound ||
           [labelLower rangeOfString:@"exfat"].location != NSNotFound;
}

@end

@interface IGUSBService ()
@property (nonatomic, strong, readwrite) NSArray *availableDrives;
@property (nonatomic, assign, readwrite) BOOL isSearching;
@end

@implementation IGUSBService

+ (instancetype)sharedService {
    static IGUSBService *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.availableDrives = @[];
    }
    return self;
}

- (void)dealloc {
#if !__has_feature(objc_arc)
    [_availableDrives release];
    [super dealloc];
#endif
}

- (void)startMonitoring {
    // Manual updates only
}

- (void)stopMonitoring {
    // Manual updates only
}

- (void)volumeMounted:(NSNotification *)notification {
    // Manual updates only
}

- (void)volumeUnmounted:(NSNotification *)notification {
    // Manual updates only
}

- (void)updateDrives {
    if ([NSThread isMainThread]) {
        self.isSearching = YES;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"IGUSBDrivesUpdatedNotification" object:nil];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.isSearching = YES;
            [[NSNotificationCenter defaultCenter] postNotificationName:@"IGUSBDrivesUpdatedNotification" object:nil];
        });
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *keys = @[
            NSURLVolumeNameKey,
            NSURLVolumeIsRemovableKey,
            NSURLVolumeIsEjectableKey,
            NSURLVolumeTotalCapacityKey,
            NSURLVolumeAvailableCapacityKey,
            NSURLVolumeLocalizedFormatDescriptionKey
        ];
        
        NSArray *urls = [[NSFileManager defaultManager] mountedVolumeURLsIncludingResourceValuesForKeys:keys options:0];
        NSMutableArray *drives = [NSMutableArray array];
        
        for (NSURL *url in urls) {
            NSDictionary *values = [url resourceValuesForKeys:keys error:nil];
            if (!values) continue;
            
            BOOL isRemovable = [values[NSURLVolumeIsRemovableKey] boolValue];
            BOOL isEjectable = [values[NSURLVolumeIsEjectableKey] boolValue];
            
            if ((isRemovable || isEjectable) && [url.path hasPrefix:@"/Volumes/"]) {
                IGUSBDrive *drive = [[IGUSBDrive alloc] init];
                drive.name = values[NSURLVolumeNameKey] ?: [url lastPathComponent];
                drive.volumeURL = url;
                drive.totalSpace = [values[NSURLVolumeTotalCapacityKey] longLongValue];
                drive.freeSpace = [values[NSURLVolumeAvailableCapacityKey] longLongValue];
                drive.filesystemLabel = values[NSURLVolumeLocalizedFormatDescriptionKey] ?: @"Unknown";
                drive.filesystemType = [self getRawFilesystemType:url];
                
                // Deduplicate
                BOOL exists = NO;
                for (IGUSBDrive *d in drives) {
                    if ([d.volumeURL isEqual:drive.volumeURL]) {
                        exists = YES;
                        break;
                    }
                }
                if (!exists) {
                    [drives addObject:drive];
                }
#if !__has_feature(objc_arc)
                [drive release];
#endif
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.availableDrives = drives;
            self.isSearching = NO;
            [[NSNotificationCenter defaultCenter] postNotificationName:@"IGUSBDrivesUpdatedNotification" object:nil];
        });
    });
}

- (NSString *)getRawFilesystemType:(NSURL *)url {
    struct statfs stats;
    if (statfs([url.path fileSystemRepresentation], &stats) == 0) {
        return [NSString stringWithUTF8String:stats.f_fstypename];
    }
    return @"unknown";
}

@end
