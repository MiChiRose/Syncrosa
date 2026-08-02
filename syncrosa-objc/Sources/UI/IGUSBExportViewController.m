#import "IGUSBExportViewController.h"
#import "IGUSBService.h"
#import "IGiTunesService.h"
#import "IGNotificationView.h"
#import "IGLocalizationService.h"
#import "IGTheme.h"
#import "IGIconProvider.h"
#import "IGHelpSheetPresenter.h"
#import "IGOperationActivity.h"

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
@property (nonatomic, strong) NSButton *m3uButton;
@property (nonatomic, strong) NSButton *m3u8Button;
@property (nonatomic, strong) NSButton *ipodSafeButton;
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

@property (nonatomic, strong) NSWindow *helpSheetWindow;

@property (nonatomic, strong) NSArray *drives;
@property (nonatomic, strong) NSArray *playlists;
@property (nonatomic, strong) NSArray *currentPlaylistTracks;
@property (nonatomic, assign) BOOL isExporting;
@property (nonatomic, assign) BOOL shouldCancelExport;

@end

@implementation IGUSBExportViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 480)];
    [self setupUI];

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

    // Set initial placeholder state for playlists without calling AppleScript
    [self.playlistPopup removeAllItems];
    [self.playlistPopup addItemWithTitle:[[IGLocalizationService sharedService] t:@"no_playlists"]];
    self.playlistPopup.enabled = NO;
    self.playlistInfoLabel.stringValue = @"";
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[IGUSBService sharedService] stopMonitoring];
#if !__has_feature(objc_arc)
    [super dealloc];
#endif
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

    NSButton *helpButton = [[NSButton alloc] initWithFrame:NSMakeRect(520, 430, 25, 25)];
    helpButton.bezelStyle = NSHelpButtonBezelStyle;
    helpButton.title = @"";
    helpButton.target = self;
    helpButton.action = @selector(helpClicked:);
    [self.view addSubview:helpButton];

    // Subtitle instructions
    self.instrLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(40, 395, 500, 30)];
    self.instrLabel.font = [NSFont systemFontOfSize:11];
    self.instrLabel.textColor = IGThemeMutedTextColor();
    self.instrLabel.editable = NO;
    self.instrLabel.bordered = NO;
    self.instrLabel.drawsBackground = NO;
    self.instrLabel.alignment = NSCenterTextAlignment;
    [self.view addSubview:self.instrLabel];

    // Drive Picker
    self.driveLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(40, 350, 150, 20)];
    self.driveLabel.font = [NSFont systemFontOfSize:13];
    self.driveLabel.alignment = NSRightTextAlignment;
    self.driveLabel.editable = NO;
    self.driveLabel.bordered = NO;
    self.driveLabel.drawsBackground = NO;
    [self.view addSubview:self.driveLabel];

    self.drivePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(200, 348, 292, 26) pullsDown:NO];
    self.drivePopup.target = self;
    self.drivePopup.action = @selector(driveSelected:);
    [self.view addSubview:self.drivePopup];

    self.refreshBtn = [[NSButton alloc] initWithFrame:NSMakeRect(504, 346, 36, 28)];
    self.refreshBtn.bezelStyle = NSRoundedBezelStyle;
    self.refreshBtn.title = @"";
    self.refreshBtn.target = self;
    self.refreshBtn.action = @selector(refreshClicked:);
    IGConfigureIconButton(self.refreshBtn, @"refresh", @"Refresh connected drives", YES);
    IGApplyThemeToButton(self.refreshBtn, IGThemeButtonRoleSecondary);
    [self.view addSubview:self.refreshBtn];

    self.driveInfoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(200, 322, 340, 18)];
    self.driveInfoLabel.font = [NSFont systemFontOfSize:11];
    self.driveInfoLabel.textColor = IGThemeMutedTextColor();
    self.driveInfoLabel.editable = NO;
    self.driveInfoLabel.bordered = NO;
    self.driveInfoLabel.drawsBackground = NO;
    [self.view addSubview:self.driveInfoLabel];

    // Playlist Picker
    self.playlistLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(40, 280, 150, 20)];
    self.playlistLabel.font = [NSFont systemFontOfSize:13];
    self.playlistLabel.alignment = NSRightTextAlignment;
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
    self.playlistInfoLabel.textColor = IGThemeMutedTextColor();
    self.playlistInfoLabel.editable = NO;
    self.playlistInfoLabel.bordered = NO;
    self.playlistInfoLabel.drawsBackground = NO;
    [self.view addSubview:self.playlistInfoLabel];

    // Mode Picker
    self.modeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(40, 210, 150, 20)];
    self.modeLabel.font = [NSFont systemFontOfSize:13];
    self.modeLabel.alignment = NSRightTextAlignment;
    self.modeLabel.editable = NO;
    self.modeLabel.bordered = NO;
    self.modeLabel.drawsBackground = NO;
    [self.view addSubview:self.modeLabel];

    self.modePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(200, 208, 340, 26) pullsDown:NO];
    [self.view addSubview:self.modePopup];

    self.m3uButton = [[NSButton alloc] initWithFrame:NSMakeRect(195, 176, 90, 20)];
    [self.m3uButton setButtonType:NSSwitchButton];
    self.m3uButton.title = @".m3u";
    self.m3uButton.enabled = NO;
    [self.view addSubview:self.m3uButton];

    self.m3u8Button = [[NSButton alloc] initWithFrame:NSMakeRect(305, 176, 95, 20)];
    [self.m3u8Button setButtonType:NSSwitchButton];
    self.m3u8Button.title = @".m3u8";
    self.m3u8Button.state = NSOnState;
    self.m3u8Button.enabled = NO;
    [self.view addSubview:self.m3u8Button];

    self.ipodSafeButton = [[NSButton alloc] initWithFrame:NSMakeRect(415, 176, 125, 20)];
    [self.ipodSafeButton setButtonType:NSSwitchButton];
    self.ipodSafeButton.title = @"iPod-safe names";
    [self.ipodSafeButton setToolTip:@"Shortens and cleans filenames for older iPods, car stereos, and FAT/exFAT drives."];
    self.ipodSafeButton.enabled = NO;
    [self.view addSubview:self.ipodSafeButton];

    // Export Button
    self.exportButton = [[NSButton alloc] initWithFrame:NSMakeRect(190, 128, 200, 40)];
    self.exportButton.bezelStyle = NSTexturedRoundedBezelStyle;
    self.exportButton.target = self;
    self.exportButton.action = @selector(exportClicked:);
    self.exportButton.enabled = NO;
    [self.view addSubview:self.exportButton];

    // Progress bar
    self.progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(40, 98, 500, 20)];
    self.progressIndicator.style = NSProgressIndicatorBarStyle;
    self.progressIndicator.indeterminate = NO;
    self.progressIndicator.hidden = YES;
    [self.view addSubview:self.progressIndicator];

    // Status text
    self.statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(40, 70, 500, 20)];
    self.statusLabel.font = [NSFont systemFontOfSize:12];
    self.statusLabel.alignment = NSCenterTextAlignment;
    self.statusLabel.editable = NO;
    self.statusLabel.bordered = NO;
    self.statusLabel.drawsBackground = NO;
    [self.view addSubview:self.statusLabel];

    // Footer
    self.footerLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 20, 540, 40)];
    self.footerLabel.font = [NSFont systemFontOfSize:10];
    self.footerLabel.textColor = IGThemeMutedTextColor();
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

    BOOL isSearching = [IGUSBService sharedService].isSearching;

    if (isSearching) {
        NSString *searchStr = [[IGLocalizationService sharedService].selectedLanguage isEqualToString:@"ru"] ?
            @"Поиск накопителей..." : @"Searching for drives...";
        [self.drivePopup addItemWithTitle:searchStr];
        self.drivePopup.enabled = NO;
        self.driveInfoLabel.stringValue = @"";
        self.refreshBtn.enabled = NO;
    } else if (self.drives.count == 0) {
        [self.drivePopup addItemWithTitle:[[IGLocalizationService sharedService] t:@"no_drives"]];
        self.drivePopup.enabled = NO;
        self.driveInfoLabel.stringValue = @"";
        self.refreshBtn.enabled = YES;
    } else {
        self.drivePopup.enabled = YES;
        self.refreshBtn.enabled = YES;
        for (IGUSBDrive *drive in self.drives) {
            [self.drivePopup addItemWithTitle:drive.name];
        }
        [self driveSelected:self.drivePopup];
    }
    [self updateExportButtonState];
}

- (void)reloadPlaylists {
    self.currentPlaylistTracks = @[];
    self.statusLabel.stringValue = [[IGLocalizationService sharedService].selectedLanguage isEqualToString:@"ru"] ?
        @"Загрузка плейлистов iTunes..." :
        @"Loading iTunes playlists...";

    [[IGiTunesService sharedService] fetchPlaylistsWithCompletion:^(NSArray *playlists) {
        self.playlists = playlists ?: @[];
        [self.playlistPopup removeAllItems];

        if (self.playlists.count == 0) {
            [self.playlistPopup addItemWithTitle:[[IGLocalizationService sharedService] t:@"no_playlists"]];
            self.playlistPopup.enabled = NO;
            self.playlistInfoLabel.stringValue = @"";
            [[IGiTunesService sharedService] fetchLibraryTrackCountWithCompletion:^(NSInteger trackCount, NSString *errorMessage) {
                NSString *message = @"";
                if (trackCount < 0) {
                    message = [[IGLocalizationService sharedService].selectedLanguage isEqualToString:@"ru"] ?
                        @"Не удалось прочитать медиатеку iTunes." :
                        @"Could not read the iTunes library.";
                    if (errorMessage.length > 0) {
                        message = [message stringByAppendingFormat:@" %@", errorMessage];
                    }
                    [IGNotificationView showInView:self.view message:message isError:YES];
                } else if (trackCount == 0) {
                    message = [[IGLocalizationService sharedService].selectedLanguage isEqualToString:@"ru"] ?
                        @"В iTunes нет треков. Экспортировать пока нечего." :
                        @"iTunes has no tracks. There is nothing to export yet.";
                } else {
                    message = [[IGLocalizationService sharedService].selectedLanguage isEqualToString:@"ru"] ?
                        @"В iTunes есть треки, но нет плейлистов для экспорта." :
                        @"iTunes has tracks, but no playlists are available for export.";
                }
                self.statusLabel.stringValue = message;
                [self updateExportButtonState];
            }];
        } else {
            self.playlistPopup.enabled = YES;
            self.statusLabel.stringValue = @"";
            for (NSDictionary *pl in self.playlists) {
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
        self.currentPlaylistTracks = @[];
        [self updateExportButtonState];

        [[IGiTunesService sharedService] fetchTracksForPlaylist:playlistName completion:^(NSArray *tracks) {
            self.currentPlaylistTracks = tracks ?: @[];
            int64_t totalBytes = 0;
            for (NSDictionary *t in self.currentPlaylistTracks) {
                totalBytes += [t[@"size"] longLongValue];
            }

            NSString *sizeStr = [NSByteCountFormatter stringFromByteCount:totalBytes countStyle:NSByteCountFormatterCountStyleFile];
            self.playlistInfoLabel.stringValue = [NSString stringWithFormat:@"Tracks: %ld | Total Size: %@", (long)self.currentPlaylistTracks.count, sizeStr];
            if (self.currentPlaylistTracks.count == 0) {
                self.statusLabel.stringValue = [[IGLocalizationService sharedService].selectedLanguage isEqualToString:@"ru"] ?
                    @"В выбранном плейлисте нет локальных файлов для экспорта." :
                    @"The selected playlist has no local files to export.";
            } else {
                self.statusLabel.stringValue = @"";
            }
            [self updateExportButtonState];
        }];
    }
}

- (void)updateExportButtonState {
    BOOL hasDrive = (self.drives.count > 0);
    BOOL hasPlaylist = (self.currentPlaylistTracks.count > 0);
    self.exportButton.enabled = self.isExporting || (hasDrive && hasPlaylist);
    BOOL optionsEnabled = (!self.isExporting && hasDrive && hasPlaylist);
    self.m3uButton.enabled = optionsEnabled;
    self.m3u8Button.enabled = optionsEnabled;
    self.ipodSafeButton.enabled = optionsEnabled;
    IGApplyThemeToButton(self.m3uButton, IGThemeButtonRoleSecondary);
    IGApplyThemeToButton(self.m3u8Button, IGThemeButtonRoleSecondary);
    IGApplyThemeToButton(self.ipodSafeButton, IGThemeButtonRoleSecondary);
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

    self.exportButton.title = self.isExporting ?
        ([lang.selectedLanguage isEqualToString:@"ru"] ? @"Остановить" : @"Stop") :
        [lang t:@"export_button"];
    [self.refreshBtn setToolTip:[lang.selectedLanguage isEqualToString:@"ru"] ? @"Обновить" : @"Refresh"];

    self.footerLabel.stringValue = [lang.selectedLanguage isEqualToString:@"ru"] ?
        @"© 2026 Syncrosa | Примечание: Защищенные DRM (.m4p) треки пропускаются.\nУбедитесь, что файловая система USB совпадает с целевой системой." :
        @"© 2026 Syncrosa | Note: DRM protected (.m4p) tracks are skipped.\nEnsure your USB drive filesystem matches your destination system.";

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
    if (self.isExporting) {
        self.shouldCancelExport = YES;
        self.exportButton.enabled = NO;
        self.statusLabel.stringValue = [[IGLocalizationService sharedService].selectedLanguage isEqualToString:@"ru"] ?
            @"Остановка после текущего файла..." :
            @"Stopping after the current file...";
        return;
    }

    NSInteger driveIdx = [self.drivePopup indexOfSelectedItem];
    if (driveIdx < 0 || driveIdx >= self.drives.count) return;
    IGUSBDrive *drive = self.drives[driveIdx];

    if (self.currentPlaylistTracks.count == 0) {
        NSString *message = [[IGLocalizationService sharedService].selectedLanguage isEqualToString:@"ru"] ?
            @"В выбранном плейлисте нет локальных треков для экспорта." :
            @"The selected playlist has no local tracks to export.";
        self.statusLabel.stringValue = message;
        [IGNotificationView showInView:self.view message:message isError:YES];
        return;
    }

    IGOperationActivity *activity = [IGOperationActivity sharedActivity];
    if (![activity beginOperationWithIdentifier:IGOperationActivityUSBExportIdentifier]) {
        NSString *message = [[IGLocalizationService sharedService].selectedLanguage isEqualToString:@"ru"] ?
            @"Сначала завершите текущую фоновую операцию." :
            @"Finish the current background operation before starting USB Export.";
        self.statusLabel.stringValue = message;
        [IGNotificationView showInView:self.view message:message isError:YES];
        return;
    }

    // Calculate size
    int64_t totalBytes = 0;
    for (NSDictionary *t in self.currentPlaylistTracks) {
        totalBytes += [t[@"size"] longLongValue];
    }

    IGExportMode mode = (IGExportMode)[self.modePopup indexOfSelectedItem];

    // Check space
    int64_t safetyMargin = MAX((int64_t)(64 * 1024 * 1024), drive.freeSpace / 100);
    if (drive.freeSpace < totalBytes + safetyMargin && mode == IGExportModeAll) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:[[IGLocalizationService sharedService] t:@"disk_full_title"]];

        NSString *sizeStr = [NSByteCountFormatter stringFromByteCount:totalBytes countStyle:NSByteCountFormatterCountStyleFile];
        NSString *freeStr = [NSByteCountFormatter stringFromByteCount:drive.freeSpace countStyle:NSByteCountFormatterCountStyleFile];

        [alert setInformativeText:[NSString stringWithFormat:[[IGLocalizationService sharedService] t:@"disk_full_msg"],
                                 drive.name, (int)self.currentPlaylistTracks.count, sizeStr, freeStr]];
        [alert addButtonWithTitle:[[IGLocalizationService sharedService] t:@"fit_available"]];
        [alert addButtonWithTitle:[[IGLocalizationService sharedService] t:@"cancel"]];

        if ([alert runModal] == NSAlertFirstButtonReturn) {
            [self.modePopup selectItemAtIndex:IGExportModeFit];
            mode = IGExportModeFit;
        } else {
            [[IGOperationActivity sharedActivity] finishOperationWithIdentifier:IGOperationActivityUSBExportIdentifier];
            return;
        }
    }

    self.isExporting = YES;
    self.shouldCancelExport = NO;
    self.exportButton.enabled = YES;
    self.exportButton.title = [[IGLocalizationService sharedService].selectedLanguage isEqualToString:@"ru"] ? @"Остановить" : @"Stop";
    self.drivePopup.enabled = NO;
    self.playlistPopup.enabled = NO;
    self.modePopup.enabled = NO;
    self.m3uButton.enabled = NO;
    self.m3u8Button.enabled = NO;
    self.ipodSafeButton.enabled = NO;
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
            int64_t safetyMargin = MAX((int64_t)(64 * 1024 * 1024), drive.freeSpace / 100);
            int64_t usableSpace = MAX((int64_t)0, drive.freeSpace - safetyMargin);
            for (NSDictionary *t in shuffled) {
                int64_t fileSize = [t[@"size"] longLongValue];
                if (accumulatedSize + fileSize < usableSpace) {
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
        NSMutableArray *copiedEntries = [NSMutableArray array];

        if (totalTracks == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *message = [[IGLocalizationService sharedService].selectedLanguage isEqualToString:@"ru"] ?
                    @"Нет треков, которые помещаются на выбранный накопитель." :
                    @"No tracks fit on the selected drive.";
                [self finishExportWithError:message];
            });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressIndicator.maxValue = totalTracks;
            [[IGOperationActivity sharedActivity] updateProgress:0.0 forIdentifier:IGOperationActivityUSBExportIdentifier];
        });

        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *playlistName = @"Syncrosa Playlist";
        NSInteger playlistIndex = [self.playlistPopup indexOfSelectedItem];
        if (playlistIndex >= 0 && playlistIndex < self.playlists.count) {
            NSString *candidate = [[self.playlists objectAtIndex:playlistIndex] objectForKey:@"name"];
            if (candidate.length > 0) playlistName = candidate;
        }
        NSURL *exportFolder = [drive.volumeURL URLByAppendingPathComponent:[self sanitizedFolderName:playlistName]];
        NSError *folderError = nil;
        if (![fm createDirectoryAtURL:exportFolder withIntermediateDirectories:YES attributes:nil error:&folderError]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self finishExportWithError:[NSString stringWithFormat:@"Could not create playlist folder: %@", folderError.localizedDescription ?: @""]];
            });
            return;
        }

        for (NSInteger i = 0; i < totalTracks; i++) {
            if (self.shouldCancelExport) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self finishExportCanceledWithCopiedCount:copiedCount totalRequested:totalTracks skippedDRM:skippedDRM bytes:totalBytesCopied];
                });
                return;
            }

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
                [[IGOperationActivity sharedActivity] updateProgress:(double)i / (double)MAX((NSInteger)1, totalTracks)
                                                       forIdentifier:IGOperationActivityUSBExportIdentifier];
            });

            // Check DRM (extension .m4p)
            if ([[filePath pathExtension].lowercaseString isEqualToString:@"m4p"]) {
                skippedDRM++;
                continue;
            }

            NSURL *sourceURL = [NSURL fileURLWithPath:filePath];

            // Build unique destination filename to prevent collision
            NSString *sanitizedArtist = (self.ipodSafeButton.state == NSOnState) ? [self iPodSafeFilename:track[@"artist"]] : [self sanitizeFilename:track[@"artist"]];
            NSString *sanitizedTitle = (self.ipodSafeButton.state == NSOnState) ? [self iPodSafeFilename:track[@"name"]] : [self sanitizeFilename:track[@"name"]];
            NSString *ext = [filePath pathExtension];

            NSString *destName = [NSString stringWithFormat:@"%@ - %@.%@", sanitizedArtist, sanitizedTitle, ext];
            NSURL *destURL = [exportFolder URLByAppendingPathComponent:destName];

            NSInteger suffix = 2;
            while ([fm fileExistsAtPath:destURL.path]) {
                destName = [NSString stringWithFormat:@"%@ - %@_%ld.%@", sanitizedArtist, sanitizedTitle, (long)suffix, ext];
                destURL = [exportFolder URLByAppendingPathComponent:destName];
                suffix++;
            }

            NSError *copyError = nil;
            __block int64_t currentFileBytes = 0;
            BOOL success = [self copyFileFrom:sourceURL
                                           to:destURL
                                  cancelBlock:^BOOL{
                                      return self.shouldCancelExport;
                                  }
                                progressBlock:^(int64_t copiedBytes) {
                                    currentFileBytes = copiedBytes;
                                    double fraction = fileSize > 0 ? MIN(0.99, (double)copiedBytes / (double)fileSize) : 0;
                                    NSString *copiedStr = [NSByteCountFormatter stringFromByteCount:copiedBytes countStyle:NSByteCountFormatterCountStyleFile];
                                    NSString *fileStr = [NSByteCountFormatter stringFromByteCount:fileSize countStyle:NSByteCountFormatterCountStyleFile];
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        self.progressIndicator.doubleValue = (double)i + fraction;
                                        [[IGOperationActivity sharedActivity] updateProgress:((double)i + fraction) / (double)MAX((NSInteger)1, totalTracks)
                                                                               forIdentifier:IGOperationActivityUSBExportIdentifier];
                                        self.statusLabel.stringValue = [NSString stringWithFormat:@"Copying %ld/%ld: %@ / %@",
                                                                        (long)(i + 1),
                                                                        (long)totalTracks,
                                                                        copiedStr,
                                                                        fileStr];
                                    });
                                }
                                        error:&copyError];
            if (success) {
                copiedCount++;
                totalBytesCopied += fileSize;
                [copiedEntries addObject:destURL.lastPathComponent ?: destName];
            } else {
                if (currentFileBytes > 0 && [fm fileExistsAtPath:destURL.path]) {
                    [fm removeItemAtURL:destURL error:nil];
                }
                if (self.shouldCancelExport) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self finishExportCanceledWithCopiedCount:copiedCount totalRequested:totalTracks skippedDRM:skippedDRM bytes:totalBytesCopied];
                    });
                    return;
                }
                NSLog(@"Failed to copy %@: %@", destName, copyError.localizedDescription);
            }
        }

        if (copiedEntries.count > 0 && (self.m3uButton.state == NSOnState || self.m3u8Button.state == NSOnState)) {
            [self writePlaylistFiles:copiedEntries playlistName:playlistName folderURL:exportFolder];
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

- (NSString *)sanitizedFolderName:(NSString *)name {
    NSString *clean = [[self sanitizeFilename:name ?: @""] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return clean.length > 0 ? clean : @"Syncrosa Playlist";
}

- (NSString *)iPodSafeFilename:(NSString *)name {
    NSMutableString *value = [[name ?: @"Track" mutableCopy] autorelease];
    CFStringTransform((CFMutableStringRef)value, NULL, kCFStringTransformStripCombiningMarks, NO);
    NSCharacterSet *allowed = [[NSCharacterSet alphanumericCharacterSet] mutableCopy];
    [(NSMutableCharacterSet *)allowed addCharactersInString:@" ._-"];
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = 0; i < value.length; i++) {
        unichar ch = [value characterAtIndex:i];
        if ([allowed characterIsMember:ch]) {
            [out appendFormat:@"%C", ch];
        } else {
            [out appendString:@"_"];
        }
    }
#if !__has_feature(objc_arc)
    [allowed release];
#endif
    while ([out rangeOfString:@"__"].location != NSNotFound) {
        [out replaceOccurrencesOfString:@"__" withString:@"_" options:0 range:NSMakeRange(0, out.length)];
    }
    NSString *trimmed = [out stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" ._-\n\r\t"]];
    if (trimmed.length == 0) trimmed = @"Track";
    if (trimmed.length > 80) trimmed = [trimmed substringToIndex:80];
    return [self sanitizeFilename:trimmed];
}

- (void)writePlaylistFiles:(NSArray *)entries playlistName:(NSString *)playlistName folderURL:(NSURL *)folderURL {
    if (entries.count == 0) return;
    NSString *base = [self sanitizedFolderName:playlistName];
    NSString *body = [NSString stringWithFormat:@"#EXTM3U\n%@\n", [entries componentsJoinedByString:@"\n"]];
    if (self.m3u8Button.state == NSOnState) {
        [body writeToURL:[folderURL URLByAppendingPathComponent:[base stringByAppendingPathExtension:@"m3u8"]]
              atomically:YES
                encoding:NSUTF8StringEncoding
                   error:nil];
    }
    if (self.m3uButton.state == NSOnState) {
        [body writeToURL:[folderURL URLByAppendingPathComponent:[base stringByAppendingPathExtension:@"m3u"]]
              atomically:YES
                encoding:NSUTF8StringEncoding
                   error:nil];
    }
}

- (BOOL)copyFileFrom:(NSURL *)source
                  to:(NSURL *)destination
         cancelBlock:(BOOL(^)(void))cancelBlock
       progressBlock:(void(^)(int64_t copiedBytes))progressBlock
               error:(NSError **)outError {
    NSFileHandle *srcHandle = [NSFileHandle fileHandleForReadingFromURL:source error:outError];
    if (!srcHandle) return NO;

    if (![[NSFileManager defaultManager] createFileAtPath:destination.path contents:nil attributes:nil]) {
        [srcHandle closeFile];
        if (outError) {
            *outError = [NSError errorWithDomain:@"IGCopyError" code:-3
                                        userInfo:@{NSLocalizedDescriptionKey: @"Could not create destination file"}];
        }
        return NO;
    }
    NSFileHandle *dstHandle = [NSFileHandle fileHandleForWritingToURL:destination error:outError];
    if (!dstHandle) {
        [srcHandle closeFile];
        [[NSFileManager defaultManager] removeItemAtURL:destination error:nil];
        return NO;
    }

    NSUInteger chunkSize = 512 * 1024; // Gentle chunks for old HDD/USB media
    int64_t copiedBytes = 0;
    @try {
        while (YES) {
            if (cancelBlock && cancelBlock()) {
                if (outError) {
                    *outError = [NSError errorWithDomain:@"IGCopyError" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Copy canceled"}];
                }
                [srcHandle closeFile];
                [dstHandle closeFile];
                [[NSFileManager defaultManager] removeItemAtURL:destination error:nil];
                return NO;
            }
            NSData *data = [srcHandle readDataOfLength:chunkSize];
            if (data.length == 0) break;
            [dstHandle writeData:data];
            copiedBytes += data.length;
            if (progressBlock) {
                progressBlock(copiedBytes);
            }
            if ([[NSUserDefaults standardUserDefaults] boolForKey:@"hdd_safe_mode"] &&
                copiedBytes > 0 &&
                copiedBytes % (16 * 1024 * 1024) == 0) {
                [NSThread sleepForTimeInterval:0.005];
            }
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
    [[IGOperationActivity sharedActivity] finishOperationWithIdentifier:IGOperationActivityUSBExportIdentifier];
    self.isExporting = NO;
    self.shouldCancelExport = NO;
    self.progressIndicator.hidden = YES;
    self.statusLabel.stringValue = errorMsg;

    [self.drivePopup setEnabled:YES];
    [self.playlistPopup setEnabled:YES];
    [self.modePopup setEnabled:YES];
    [self.m3uButton setEnabled:YES];
    [self.m3u8Button setEnabled:YES];
    [self.ipodSafeButton setEnabled:YES];
    self.exportButton.title = [[IGLocalizationService sharedService] t:@"export_button"];
    [self updateExportButtonState];

    [IGNotificationView showInView:self.view message:errorMsg isError:YES];
}

- (void)finishExportCanceledWithCopiedCount:(NSInteger)copied
                             totalRequested:(NSInteger)total
                                 skippedDRM:(NSInteger)skippedDRM
                                      bytes:(int64_t)bytes {
    [[IGOperationActivity sharedActivity] finishOperationWithIdentifier:IGOperationActivityUSBExportIdentifier];
    self.isExporting = NO;
    self.shouldCancelExport = NO;
    self.progressIndicator.hidden = YES;

    [self.drivePopup setEnabled:YES];
    [self.playlistPopup setEnabled:YES];
    [self.modePopup setEnabled:YES];
    [self.m3uButton setEnabled:YES];
    [self.m3u8Button setEnabled:YES];
    [self.ipodSafeButton setEnabled:YES];
    self.exportButton.title = [[IGLocalizationService sharedService] t:@"export_button"];
    [self updateExportButtonState];
    [self reloadDrives];

    NSString *sizeStr = [NSByteCountFormatter stringFromByteCount:bytes countStyle:NSByteCountFormatterCountStyleFile];
    NSString *message = [NSString stringWithFormat:@"Export canceled. Copied %ld of %ld tracks (%@). Skipped DRM: %ld.",
                         (long)copied,
                         (long)total,
                         sizeStr,
                         (long)skippedDRM];
    self.statusLabel.stringValue = message;
    [IGNotificationView showInView:self.view message:@"Export canceled." isError:NO];
}

- (void)finishExportWithCopiedCount:(NSInteger)copied
                      totalRequested:(NSInteger)total
                          skippedDRM:(NSInteger)skippedDRM
                               bytes:(int64_t)bytes {
    [[IGOperationActivity sharedActivity] finishOperationWithIdentifier:IGOperationActivityUSBExportIdentifier];
    self.isExporting = NO;
    self.shouldCancelExport = NO;
    self.progressIndicator.hidden = YES;

    [self.drivePopup setEnabled:YES];
    [self.playlistPopup setEnabled:YES];
    [self.modePopup setEnabled:YES];
    [self.m3uButton setEnabled:YES];
    [self.m3u8Button setEnabled:YES];
    [self.ipodSafeButton setEnabled:YES];
    self.exportButton.title = [[IGLocalizationService sharedService] t:@"export_button"];
    [self updateExportButtonState];
    [self reloadDrives]; // Refresh free space info

    IGLocalizationService *lang = [IGLocalizationService sharedService];
    NSString *sizeStr = [NSByteCountFormatter stringFromByteCount:bytes countStyle:NSByteCountFormatterCountStyleFile];
    BOOL russian = [lang.selectedLanguage isEqualToString:@"ru"];
    NSString *message = nil;
    if (skippedDRM > 0 || copied < total) {
        message = russian ?
            [NSString stringWithFormat:@"Экспорт завершён частично: скопировано %ld из %ld, пропущено DRM: %ld, записано %@.",
             (long)copied, (long)total, (long)skippedDRM, sizeStr] :
            [NSString stringWithFormat:@"Export completed with skipped files: %ld of %ld tracks copied, %ld DRM-protected skipped, %@ written.",
             (long)copied, (long)total, (long)skippedDRM, sizeStr];
    } else {
        message = russian ?
            [NSString stringWithFormat:@"Экспорт завершён: скопировано %ld треков, записано %@.", (long)copied, sizeStr] :
            [NSString stringWithFormat:@"Export completed: %ld tracks copied, %@ written.", (long)copied, sizeStr];
    }

    self.statusLabel.stringValue = message;
    [IGNotificationView showInView:self.view message:message isError:NO];
}

- (void)helpClicked:(id)sender {
    (void)sender;
    if (self.helpSheetWindow) return;
    NSArray *sections = @[
        IGHelpSectionMake(@"Choose the destination", @"Select a connected drive and an iTunes playlist. Syncrosa creates a folder named after that playlist and copies tracks inside it."),
        IGHelpSectionMake(@"Choose a space policy", @"Copy All requires enough free space. Fit Available Space copies complete files until the safe capacity limit is reached. Optional M3U or M3U8 files preserve playback order."),
        IGHelpSectionMake(@"Older-device compatibility", @"iPod-safe names shorten and clean filenames for older iPods, car stereos, and FAT or exFAT drives. DRM-protected or unavailable local files are skipped and reported.")
    ];
    self.helpSheetWindow = [IGHelpSheetPresenter sheetWithTitle:@"USB Export"
                                                        summary:@"Copy a playlist into its own organized folder on a removable drive."
                                                       sections:sections
                                                     closeTitle:@"Close"
                                                         target:self
                                                         action:@selector(closeHelpSheet:)];
    [IGHelpSheetPresenter presentSheet:self.helpSheetWindow forWindow:self.view.window];
}

- (void)closeHelpSheet:(id)sender {
    if (self.helpSheetWindow) {
        if ([self.view.window respondsToSelector:@selector(endSheet:)]) {
            [self.view.window endSheet:self.helpSheetWindow];
        } else {
            [NSApp endSheet:self.helpSheetWindow];
        }
        [self.helpSheetWindow orderOut:nil];
        self.helpSheetWindow = nil;
    }
}

@end
