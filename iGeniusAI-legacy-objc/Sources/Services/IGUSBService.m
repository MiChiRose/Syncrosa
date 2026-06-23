#import "IGUSBService.h"
#import <AppKit/AppKit.h>
#import <sys/mount.h>

@implementation IGUSBDrive

- (BOOL)isAndroidCompatible {
    NSString *typeLower = [self.filesystemType lowercaseString];
    NSString *labelLower = [self.filesystemLabel lowercaseString];
    return [typeLower containsString:@"msdos"] ||
           [typeLower containsString:@"fat"] ||
           [typeLower containsString:@"exfat"] ||
           [labelLower containsString:@"fat32"] ||
           [labelLower containsString:@"exfat"];
}

@end

@interface IGUSBService ()
@property (nonatomic, strong, readwrite) NSArray<IGUSBDrive *> *availableDrives;
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
        _availableDrives = @[];
    }
    return self;
}

- (void)startMonitoring {
    NSNotificationCenter *wsCenter = [[NSWorkspace sharedWorkspace] notificationCenter];
    [wsCenter addObserver:self
                 selector:@selector(volumeMounted:)
                     name:NSWorkspaceDidMountNotification
                   object:nil];
    [wsCenter addObserver:self
                 selector:@selector(volumeUnmounted:)
                     name:NSWorkspaceDidUnmountNotification
                   object:nil];
    [self updateDrives];
}

- (void)stopMonitoring {
    NSNotificationCenter *wsCenter = [[NSWorkspace sharedWorkspace] notificationCenter];
    [wsCenter removeObserver:self];
}

- (void)volumeMounted:(NSNotification *)notification {
    [self updateDrives];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self updateDrives];
    });
}

- (void)volumeUnmounted:(NSNotification *)notification {
    [self updateDrives];
}

- (void)updateDrives {
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
        }
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.availableDrives = drives;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"IGUSBDrivesUpdatedNotification" object:nil];
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
