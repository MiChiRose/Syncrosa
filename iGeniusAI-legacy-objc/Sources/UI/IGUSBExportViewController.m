#import "IGUSBExportViewController.h"
#import "IGUSBService.h"
#import "IGiTunesService.h"
#import "IGNotificationView.h"
#import "IGLocalizationService.h"

typedef NS_ENUM(NSInteger, IGExportMode) {
    IGExportModeAll = 0,
    IGExportModeFit = 1
};

@interface IGUSBExportViewController ()

@property (nonatomic, strong) NSPopUpButton *drivePopup;
@property (nonatomic, strong) NSTextField *driveInfoLabel;
@property (nonatomic, strong) NSPopUpButton *playlistPopup;
@property (nonatomic, strong) NSTextField *playlistInfoLabel;
@property (nonatomic, strong) NSPopUpButton *modePopup;
@property (nonatomic, strong) NSButton *exportButton;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSTextField *statusLabel;

@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *instrLabel;
@property (nonatomic, strong) NSTextField *driveLabel;
@property (nonatomic, strong) NSTextField *playlistLabel;
@property (nonatomic, strong) NSTextField *modeLabel;
@property (nonatomic, strong) NSButton *refreshBtn;
@property (nonatomic, strong) NSTextField *footerLabel;

@property (nonatomic, strong) NSArray<IGUSBDrive *> *drives;
@property (nonatomic, strong) NSArray<NSDictionary *> *playlists;
@property (nonatomic, strong) NSArray<NSDictionary *> *currentPlaylistTracks;
@property (nonatomic, assign) BOOL isExporting;

@end

@implementation IGUSBExportViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 480)];
    [self setupUI];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Register for USB status changes
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(drivesUpdated:)
                                                 name:@"IGUSBDrivesUpdatedNotification"
                                               object:nil];
    
    // Register for language changes
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(localizationChanged:)
                                                 name:@"IGLanguageChangedNotification"
                                               object:nil];
    
    [[IGUSBService sharedService] startMonitoring];
    [self reloadDrives];
    [self reloadPlaylists];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[IGUSBService sharedService] stopMonitoring];
}

- (void)setupUI {
    // Title
    self.titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 430, 540, 30)];
    self.titleLabel.font = [NSFont boldSystemFontOfSize:18];
    self.titleLabel.editable = NO;
    self.titleLabel.bordered = NO;
    self.titleLabel.drawsBackground = NO;
    self.titleLabel.alignment = NSCenterTextAlignment;
    [self.view addSubview:self.titleLabel];
    
    // Subtitle instructions
    self.instrLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(40, 395, 500, 30)];
    self.instrLabel.font = [NSFont systemFontOfSize:11];
    self.instrLabel.textColor = [NSColor grayColor];
    self.instrLabel.editable = NO;
    self.instrLabel.bordered = NO;
    self.instrLabel.drawsBackground = NO;
    self.instrLabel.alignment = NSCenterTextAlignment;
    [self.view addSubview:self.instrLabel];
    
    // Drive Picker
    self.driveLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(40, 350, 150, 20)];
    self.driveLabel.font = [NSFont systemFontOfSize:13];
    self.driveLabel.editable = NO;
    self.driveLabel.bordered = NO;
    self.driveLabel.drawsBackground = NO;
    [self.view addSubview:self.driveLabel];
    
    self.drivePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(200, 348, 300, 26) pullsDown:NO];
    self.drivePopup.target = self;
    self.drivePopup.action = @selector(driveSelected:);
    [self.view addSubview:self.drivePopup];
    
    self.refreshBtn = [[NSButton alloc] initWithFrame:NSMakeRect(505, 346, 35, 28)];
    self.refreshBtn.bezelStyle = NSRecessedBezelStyle;
    self.refreshBtn.title = @"↻";
    self.refreshBtn.target = self;
    self.refreshBtn.action = @selector(refreshClicked:);
    [self.view addSubview:self.refreshBtn];
    
    self.driveInfoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(200, 322, 340, 18)];
    self.driveInfoLabel.font = [NSFont systemFontOfSize:11];
    self.driveInfoLabel.textColor = [NSColor grayColor];
    self.driveInfoLabel.editable = NO;
    self.driveInfoLabel.bordered = NO;
    self.driveInfoLabel.drawsBackground = NO;
    [self.view addSubview:self.driveInfoLabel];
    
    // Playlist Picker
    self.playlistLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(40, 280, 150, 20)];
    self.playlistLabel.font = [NSFont systemFontOfSize:13];
    self.playlistLabel.editable = NO;
    self.playlistLabel.bordered = NO;
    self.playlistLabel.drawsBackground = NO;
    [self.view addSubview:self.playlistLabel];
    
    self.playlistPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(200, 278, 340, 26) pullsDown:NO];
    self.playlistPopup.target = self;
    self.playlistPopup.action = @selector(playlistSelected:);
    [self.view addSubview:self.playlistPopup];
    
    self.playlistInfoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(200, 252, 340, 18)];
    self.playlistInfoLabel.font = [NSFont systemFontOfSize:11];
    self.playlistInfoLabel.textColor = [NSColor grayColor];
    self.playlistInfoLabel.editable = NO;
    self.playlistInfoLabel.bordered = NO;
    self.playlistInfoLabel.drawsBackground = NO;
    [self.view addSubview:self.playlistInfoLabel];
    
    // Mode Picker
    self.modeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(40, 210, 150, 20)];
    self.modeLabel.font = [NSFont systemFontOfSize:13];
    self.modeLabel.editable = NO;
    self.modeLabel.bordered = NO;
    self.modeLabel.drawsBackground = NO;
    [self.view addSubview:self.modeLabel];
    
    self.modePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(200, 208, 340, 26) pullsDown:NO];
    [self.view addSubview:self.modePopup];
    
    // Export Button
    self.exportButton = [[NSButton alloc] initWithFrame:NSMakeRect(190, 150, 200, 40)];
    self.exportButton.bezelStyle = NSTexturedRoundedBezelStyle;
    self.exportButton.target = self;
    self.exportButton.action = @selector(exportClicked:);
    self.exportButton.enabled = NO;
    [self.view addSubview:self.exportButton];
    
    // Progress bar
    self.progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(40, 110, 500, 20)];
    self.progressIndicator.style = NSProgressIndicatorBarStyle;
    self.progressIndicator.indeterminate = NO;
    self.progressIndicator.hidden = YES;
    [self.view addSubview:self.progressIndicator];
    
    // Status text
    self.statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(40, 80, 500, 20)];
    self.statusLabel.font = [NSFont systemFontOfSize:12];
    self.statusLabel.alignment = NSCenterTextAlignment;
    self.statusLabel.editable = NO;
    self.statusLabel.bordered = NO;
    self.statusLabel.drawsBackground = NO;
    [self.view addSubview:self.statusLabel];
    
    // Footer
    self.footerLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 20, 540, 40)];
    self.footerLabel.font = [NSFont systemFontOfSize:10];
    self.footerLabel.textColor = [NSColor grayColor];
    self.footerLabel.alignment = NSCenterTextAlignment;
    self.footerLabel.editable = NO;
    self.footerLabel.bordered = NO;
    self.footerLabel.drawsBackground = NO;
    [self.view addSubview:self.footerLabel];
    
    [self updateLocalization];
}

#pragma mark - Data Loading

- (void)reloadDrives {
    self.drives = [IGUSBService sharedService].availableDrives;
    [self.drivePopup removeAllItems];
    
    if (self.drives.count == 0) {
        [self.drivePopup addItemWithTitle:[[IGLocalizationService sharedService] t:@"no_drives"]];
        self.drivePopup.enabled = NO;
        self.driveInfoLabel.stringValue = @"";
    } else {
        self.drivePopup.enabled = YES;
        for (IGUSBDrive *drive in self.drives) {
            [self.drivePopup addItemWithTitle:drive.name];
        }
        [self driveSelected:self.drivePopup];
    }
    [self updateExportButtonState];
}

- (void)reloadPlaylists {
    [[IGiTunesService sharedService] fetchPlaylistsWithCompletion:^(NSArray<NSDictionary *> *playlists) {
        self.playlists = playlists;
        [self.playlistPopup removeAllItems];
        
        if (playlists.count == 0) {
            [self.playlistPopup addItemWithTitle:[[IGLocalizationService sharedService] t:@"no_playlists"]];
            self.playlistPopup.enabled = NO;
            self.playlistInfoLabel.stringValue = @"";
        } else {
            self.playlistPopup.enabled = YES;
            for (NSDictionary *pl in playlists) {
                [self.playlistPopup addItemWithTitle:pl[@"name"]];
            }
            [self playlistSelected:self.playlistPopup];
        }
        [self updateExportButtonState];
    }];
}

#pragma mark - Actions

- (void)driveSelected:(id)sender {
    NSInteger index = [self.drivePopup indexOfSelectedItem];
    if (index >= 0 && index < self.drives.count) {
        IGUSBDrive *drive = self.drives[index];
        NSString *freeStr = [NSByteCountFormatter stringFromByteCount:drive.freeSpace countStyle:NSByteCountFormatterCountStyleFile];
        NSString *totalStr = [NSByteCountFormatter stringFromByteCount:drive.totalSpace countStyle:NSByteCountFormatterCountStyleFile];
        
        self.driveInfoLabel.stringValue = [NSString stringWithFormat:@"Free: %@ / %@ | Format: %@", freeStr, totalStr, drive.filesystemLabel];
        
        // Warn if Android incompatible filesystem (NTFS, APFS, HFS+)
        if (!drive.isAndroidCompatible) {
            [IGNotificationView showInView:self.view 
                                   message:[NSString stringWithFormat:[[IGLocalizationService sharedService] t:@"incompatible_fs"], drive.filesystemLabel] 
                                   isError:YES];
        } else {
            [IGNotificationView dismissInView:self.view];
        }
    }
}

- (void)playlistSelected:(id)sender {
    NSInteger index = [self.playlistPopup indexOfSelectedItem];
    if (index >= 0 && index < self.playlists.count) {
        NSDictionary *playlist = self.playlists[index];
        NSString *playlistName = playlist[@"name"];
        
        self.playlistInfoLabel.stringValue = @"Loading track details...";
        
        [[IGiTunesService sharedService] fetchTracksForPlaylist:playlistName completion:^(NSArray *tracks) {
            self.currentPlaylistTracks = tracks;
            int64_t totalBytes = 0;
            for (NSDictionary *t in tracks) {
                totalBytes += [t[@"size"] longLongValue];
            }
            
            NSString *sizeStr = [NSByteCountFormatter stringFromByteCount:totalBytes countStyle:NSByteCountFormatterCountStyleFile];
            self.playlistInfoLabel.stringValue = [NSString stringWithFormat:@"Tracks: %ld | Total Size: %@", (long)tracks.count, sizeStr];
            [self updateExportButtonState];
        }];
    }
}

- (void)updateExportButtonState {
    BOOL hasDrive = (self.drives.count > 0);
    BOOL hasPlaylist = (self.currentPlaylistTracks.count > 0);
    self.exportButton.enabled = hasDrive && hasPlaylist && !self.isExporting;
}

- (void)updateLocalization {
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    
    self.titleLabel.stringValue = [lang t:@"usb_export"];
    self.instrLabel.stringValue = [lang.selectedLanguage isEqualToString:@"ru"] ? 
        @"Экспорт плейлистов iTunes прямо на внешний флеш-накопитель." : 
        @"Export your iTunes playlists directly to an external flash drive.";
        
    self.driveLabel.stringValue = [lang t:@"select_drive"];
    self.playlistLabel.stringValue = [lang t:@"select_playlist"];
    self.modeLabel.stringValue = [lang.selectedLanguage isEqualToString:@"ru"] ? @"Режим экспорта:" : @"Export Mode:";
    
    // Save selected mode index and restore after rebuilding options
    NSInteger selectedIdx = [self.modePopup indexOfSelectedItem];
    [self.modePopup removeAllItems];
    [self.modePopup addItemsWithTitles:@[
        [lang.selectedLanguage isEqualToString:@"ru"] ? @"Копировать все треки" : @"Copy all tracks",
        [lang.selectedLanguage isEqualToString:@"ru"] ? @"Заполнить доступное место (случайный выбор)" : @"Fit available space (random selection)"
    ]];
    if (selectedIdx >= 0 && selectedIdx < self.modePopup.numberOfItems) {
        [self.modePopup selectItemAtIndex:selectedIdx];
    }
    
    self.exportButton.title = [lang t:@"export_button"];
    [self.refreshBtn setToolTip:[lang.selectedLanguage isEqualToString:@"ru"] ? @"Обновить" : @"Refresh"];
    
    self.footerLabel.stringValue = [lang.selectedLanguage isEqualToString:@"ru"] ? 
        @"© 2026 iGeniusAI | Примечание: Защищенные DRM (.m4p) треки пропускаются.\nУбедитесь, что файловая система USB совпадает с целевой системой." : 
        @"© 2026 iGeniusAI | Note: DRM protected (.m4p) tracks are skipped.\nEnsure your USB drive filesystem matches your destination system.";
        
    [self reloadDrives];
    [self reloadPlaylists];
}

- (void)localizationChanged:(NSNotification *)notification {
    [self updateLocalization];
}

- (void)refreshClicked:(id)sender {
    [[IGUSBService sharedService] updateDrives];
    [self reloadPlaylists];
}

- (void)drivesUpdated:(NSNotification *)notification {
    [self reloadDrives];
}

- (void)exportClicked:(id)sender {
    if (self.isExporting) return;
    
    NSInteger driveIdx = [self.drivePopup indexOfSelectedItem];
    if (driveIdx < 0 || driveIdx >= self.drives.count) return;
    IGUSBDrive *drive = self.drives[driveIdx];
    
    // Calculate size
    int64_t totalBytes = 0;
    for (NSDictionary *t in self.currentPlaylistTracks) {
        totalBytes += [t[@"size"] longLongValue];
    }
    
    IGExportMode mode = (IGExportMode)[self.modePopup indexOfSelectedItem];
    
    // Check space
    if (drive.freeSpace < totalBytes && mode == IGExportModeAll) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = [[IGLocalizationService sharedService] t:@"disk_full_title"];
        
        NSString *sizeStr = [NSByteCountFormatter stringFromByteCount:totalBytes countStyle:NSByteCountFormatterCountStyleFile];
        NSString *freeStr = [NSByteCountFormatter stringFromByteCount:drive.freeSpace countStyle:NSByteCountFormatterCountStyleFile];
        
        alert.informativeText = [NSString stringWithFormat:[[IGLocalizationService sharedService] t:@"disk_full_msg"], 
                                 drive.name, (int)self.currentPlaylistTracks.count, sizeStr, freeStr];
        [alert addButtonWithTitle:[[IGLocalizationService sharedService] t:@"fit_available"]];
        [alert addButtonWithTitle:[[IGLocalizationService sharedService] t:@"cancel"]];
        
        if ([alert runModal] == NSAlertFirstButtonReturn) {
            [self.modePopup selectItemAtIndex:IGExportModeFit];
            mode = IGExportModeFit;
        } else {
            return;
        }
    }
    
    self.isExporting = YES;
    self.exportButton.enabled = NO;
    self.drivePopup.enabled = NO;
    self.playlistPopup.enabled = NO;
    self.modePopup.enabled = NO;
    self.progressIndicator.hidden = NO;
    self.progressIndicator.doubleValue = 0;
    
    [self runExportProcessToDrive:drive mode:mode];
}

- (void)runExportProcessToDrive:(IGUSBDrive *)drive mode:(IGExportMode)mode {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *tracksToCopy = self.currentPlaylistTracks;
        
        if (mode == IGExportModeFit) {
            // Shuffle
            NSMutableArray *shuffled = [self.currentPlaylistTracks mutableCopy];
            for (NSUInteger i = shuffled.count; i > 1; i--) {
                [shuffled exchangeObjectAtIndex:i - 1 withObjectAtIndex:arc4random_uniform((uint32_t)i)];
            }
            
            // Filter to fit available space
            NSMutableArray *filtered = [NSMutableArray array];
            int64_t accumulatedSize = 0;
            for (NSDictionary *t in shuffled) {
                int64_t fileSize = [t[@"size"] longLongValue];
                if (accumulatedSize + fileSize < drive.freeSpace) {
                    accumulatedSize += fileSize;
                    [filtered addObject:t];
                }
            }
            tracksToCopy = filtered;
        }
        
        NSInteger copiedCount = 0;
        NSInteger skippedDRM = 0;
        NSInteger totalTracks = tracksToCopy.count;
        int64_t totalBytesCopied = 0;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressIndicator.maxValue = totalTracks;
        });
        
        NSFileManager *fm = [NSFileManager defaultManager];
        
        for (NSInteger i = 0; i < totalTracks; i++) {
            // Check if drive is still mounted
            if (![fm fileExistsAtPath:drive.volumeURL.path]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self finishExportWithError:[[IGLocalizationService sharedService] t:@"drive_disconnected"]];
                });
                return;
            }
            
            NSDictionary *track = tracksToCopy[i];
            NSString *filePath = track[@"path"];
            int64_t fileSize = [track[@"size"] longLongValue];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                self.progressIndicator.doubleValue = i;
                self.statusLabel.stringValue = [NSString stringWithFormat:[[IGLocalizationService sharedService] t:@"exporting"], (int)(i + 1), (int)totalTracks];
            });
            
            // Check DRM (extension .m4p)
            if ([[filePath pathExtension].lowercaseString isEqualToString:@"m4p"]) {
                skippedDRM++;
                continue;
            }
            
            NSURL *sourceURL = [NSURL fileURLWithPath:filePath];
            
            // Build unique destination filename to prevent collision
            NSString *sanitizedArtist = [self sanitizeFilename:track[@"artist"]];
            NSString *sanitizedTitle = [self sanitizeFilename:track[@"name"]];
            NSString *ext = [filePath pathExtension];
            
            NSString *destName = [NSString stringWithFormat:@"%@ - %@.%@", sanitizedArtist, sanitizedTitle, ext];
            NSURL *destURL = [drive.volumeURL URLByAppendingPathComponent:destName];
            
            NSInteger suffix = 2;
            while ([fm fileExistsAtPath:destURL.path]) {
                destName = [NSString stringWithFormat:@"%@ - %@_%ld.%@", sanitizedArtist, sanitizedTitle, (long)suffix, ext];
                destURL = [drive.volumeURL URLByAppendingPathComponent:destName];
                suffix++;
            }
            
            NSError *copyError = nil;
            BOOL success = [self copyFileFrom:sourceURL to:destURL error:&copyError];
            if (success) {
                copiedCount++;
                totalBytesCopied += fileSize;
            } else {
                NSLog(@"Failed to copy %@: %@", destName, copyError.localizedDescription);
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishExportWithCopiedCount:copiedCount totalRequested:totalTracks skippedDRM:skippedDRM bytes:totalBytesCopied];
        });
    });
}

- (NSString *)sanitizeFilename:(NSString *)name {
    NSCharacterSet *invalidCharacters = [NSCharacterSet characterSetWithCharactersInString:@"/\\?%*|\"<>:"];
    NSArray *parts = [name componentsSeparatedByCharactersInSet:invalidCharacters];
    return [parts componentsJoinedByString:@"_"];
}

- (BOOL)copyFileFrom:(NSURL *)source to:(NSURL *)destination error:(NSError **)outError {
    NSFileHandle *srcHandle = [NSFileHandle fileHandleForReadingFromURL:source error:outError];
    if (!srcHandle) return NO;
    
    [[NSFileManager defaultManager] createFileAtPath:destination.path contents:nil attributes:nil];
    NSFileHandle *dstHandle = [NSFileHandle fileHandleForWritingToURL:destination error:outError];
    if (!dstHandle) {
        [srcHandle closeFile];
        return NO;
    }
    
    NSUInteger chunkSize = 1024 * 1024; // 1 MB chunks
    @try {
        while (YES) {
            NSData *data = [srcHandle readDataOfLength:chunkSize];
            if (data.length == 0) break;
            [dstHandle writeData:data];
        }
    } @catch (NSException *e) {
        [srcHandle closeFile];
        [dstHandle closeFile];
        if (outError) {
            *outError = [NSError errorWithDomain:@"IGCopyError" code:-1 
                                        userInfo:@{NSLocalizedDescriptionKey: e.reason ?: @"File writing crashed"}];
        }
        return NO;
    }
    
    [srcHandle closeFile];
    [dstHandle closeFile];
    return YES;
}

- (void)finishExportWithError:(NSString *)errorMsg {
    self.isExporting = NO;
    self.progressIndicator.hidden = YES;
    self.statusLabel.stringValue = errorMsg;
    
    [self.drivePopup setEnabled:YES];
    [self.playlistPopup setEnabled:YES];
    [self.modePopup setEnabled:YES];
    [self updateExportButtonState];
    
    [IGNotificationView showInView:self.view message:errorMsg isError:YES];
}

- (void)finishExportWithCopiedCount:(NSInteger)copied 
                      totalRequested:(NSInteger)total 
                          skippedDRM:(NSInteger)skippedDRM 
                               bytes:(int64_t)bytes {
    self.isExporting = NO;
    self.progressIndicator.hidden = YES;
    
    [self.drivePopup setEnabled:YES];
    [self.playlistPopup setEnabled:YES];
    [self.modePopup setEnabled:YES];
    [self updateExportButtonState];
    [self reloadDrives]; // Refresh free space info
    
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    NSString *sizeStr = [NSByteCountFormatter stringFromByteCount:bytes countStyle:NSByteCountFormatterCountStyleFile];
    NSString *message = @"";
    
    if (skippedDRM > 0) {
        message = [NSString stringWithFormat:[lang t:@"export_partial"], (int)copied, (int)total, (int)skippedDRM];
    } else {
        message = [NSString stringWithFormat:[lang t:@"export_success"], (int)copied];
    }
    
    self.statusLabel.stringValue = [NSString stringWithFormat:@"%@ (%@)", message, sizeStr];
    [IGNotificationView showInView:self.view message:message isError:NO];
}

@end
