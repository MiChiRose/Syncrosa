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
@property (nonatomic, strong) NSTextField *emptyStateLabel;
@property (nonatomic, strong) NSBox *setupBox;

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
    self.playlistInfoLabel.stringValue = [self playlistPlaceholderText];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[IGUSBService sharedService] stopMonitoring];
#if !__has_feature(objc_arc)
    [_emptyStateLabel release];
    [_setupBox release];
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

    self.setupBox = [[[NSBox alloc] initWithFrame:NSMakeRect(35, 120, 510, 262)] autorelease];
    self.setupBox.boxType = NSBoxPrimary;
    [self.view addSubview:self.setupBox];

    // Drive Picker
    self.driveLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(48, 330, 142, 20)];
    self.driveLabel.font = [NSFont systemFontOfSize:13];
    self.driveLabel.alignment = NSLeftTextAlignment;
    self.driveLabel.editable = NO;
    self.driveLabel.bordered = NO;
    self.driveLabel.drawsBackground = NO;
    [self.view addSubview:self.driveLabel];

    self.drivePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(200, 328, 284, 26) pullsDown:NO];
    self.drivePopup.target = self;
    self.drivePopup.action = @selector(driveSelected:);
    [self.view addSubview:self.drivePopup];

    self.refreshBtn = [[NSButton alloc] initWithFrame:NSMakeRect(496, 326, 36, 28)];
    self.refreshBtn.bezelStyle = NSRoundedBezelStyle;
    self.refreshBtn.title = @"";
    self.refreshBtn.target = self;
    self.refreshBtn.action = @selector(refreshClicked:);
    IGConfigureIconButton(self.refreshBtn, @"refresh", @"Refresh connected drives", YES);
    IGApplyThemeToButton(self.refreshBtn, IGThemeButtonRoleSecondary);
    [self.view addSubview:self.refreshBtn];

    self.driveInfoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(200, 302, 332, 18)];
    self.driveInfoLabel.font = [NSFont systemFontOfSize:11];
    self.driveInfoLabel.textColor = IGThemeMutedTextColor();
    self.driveInfoLabel.editable = NO;
    self.driveInfoLabel.bordered = NO;
    self.driveInfoLabel.drawsBackground = NO;
    [self.view addSubview:self.driveInfoLabel];

    // Playlist Picker
    self.playlistLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(48, 266, 142, 20)];
    self.playlistLabel.font = [NSFont systemFontOfSize:13];
    self.playlistLabel.alignment = NSLeftTextAlignment;
    self.playlistLabel.editable = NO;
    self.playlistLabel.bordered = NO;
    self.playlistLabel.drawsBackground = NO;
    [self.view addSubview:self.playlistLabel];

    self.playlistPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(200, 264, 332, 26) pullsDown:NO];
    self.playlistPopup.target = self;
    self.playlistPopup.action = @selector(playlistSelected:);
    [self.view addSubview:self.playlistPopup];

    self.playlistInfoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(200, 238, 332, 18)];
    self.playlistInfoLabel.font = [NSFont systemFontOfSize:11];
    self.playlistInfoLabel.textColor = IGThemeMutedTextColor();
    self.playlistInfoLabel.editable = NO;
    self.playlistInfoLabel.bordered = NO;
    self.playlistInfoLabel.drawsBackground = NO;
    [self.view addSubview:self.playlistInfoLabel];

    // Mode Picker
    self.modeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(48, 204, 142, 20)];
    self.modeLabel.font = [NSFont systemFontOfSize:13];
    self.modeLabel.alignment = NSLeftTextAlignment;
    self.modeLabel.editable = NO;
    self.modeLabel.bordered = NO;
    self.modeLabel.drawsBackground = NO;
    [self.view addSubview:self.modeLabel];

    self.modePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(200, 202, 332, 26) pullsDown:NO];
    [self.view addSubview:self.modePopup];

    self.m3uButton = [[NSButton alloc] initWithFrame:NSMakeRect(200, 174, 85, 20)];
    [self.m3uButton setButtonType:NSSwitchButton];
    self.m3uButton.title = @".m3u";
    self.m3uButton.enabled = NO;
    [self.view addSubview:self.m3uButton];

    self.m3u8Button = [[NSButton alloc] initWithFrame:NSMakeRect(305, 174, 90, 20)];
    [self.m3u8Button setButtonType:NSSwitchButton];
    self.m3u8Button.title = @".m3u8";
    self.m3u8Button.state = NSOnState;
    self.m3u8Button.enabled = NO;
    [self.view addSubview:self.m3u8Button];

    self.ipodSafeButton = [[NSButton alloc] initWithFrame:NSMakeRect(410, 174, 122, 20)];
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

    self.emptyStateLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(72, 66, 436, 48)] autorelease];
    self.emptyStateLabel.font = [NSFont systemFontOfSize:11];
    self.emptyStateLabel.textColor = IGThemeMutedTextColor();
    self.emptyStateLabel.alignment = NSCenterTextAlignment;
    self.emptyStateLabel.editable = NO;
    self.emptyStateLabel.bordered = NO;
    self.emptyStateLabel.drawsBackground = NO;
    [[self.emptyStateLabel cell] setLineBreakMode:NSLineBreakByWordWrapping];
    [[self.emptyStateLabel cell] setUsesSingleLineMode:NO];
    [self.view addSubview:self.emptyStateLabel];

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

- (NSString *)drivePlaceholderText {
    BOOL russian = [[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];
    return russian ? @"После подключения здесь появятся свободное место и формат."
                   : @"Free space and format will appear after connection.";
}

- (NSString *)playlistPlaceholderText {
    BOOL russian = [[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];
    return russian ? @"После выбора здесь появятся количество треков и размер."
                   : @"Track count and size will appear after selection.";
}

- (void)reloadDrives {
    self.drives = [IGUSBService sharedService].availableDrives;
    [self.drivePopup removeAllItems];

    BOOL isSearching = [IGUSBService sharedService].isSearching;

    if (isSearching) {
        NSString *searchStr = [[IGLocalizationService sharedService].selectedLanguage isEqualToString:@"ru"] ?
            @"Поиск накопителей..." : @"Searching for drives...";
        [self.drivePopup addItemWithTitle:searchStr];
        self.drivePopup.enabled = NO;
        self.driveInfoLabel.stringValue = [self drivePlaceholderText];
        self.refreshBtn.enabled = NO;
    } else if (self.drives.count == 0) {
        [self.drivePopup addItemWithTitle:[[IGLocalizationService sharedService] t:@"no_drives"]];
        self.drivePopup.enabled = NO;
        self.driveInfoLabel.stringValue = [self drivePlaceholderText];
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
            self.playlistInfoLabel.stringValue = [self playlistPlaceholderText];
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
            if (totalBytes == 0) sizeStr = @"0 KB";
            BOOL russian = [[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];
            self.playlistInfoLabel.stringValue = russian ?
                [NSString stringWithFormat:@"Треков: %ld · %@", (long)self.currentPlaylistTracks.count, sizeStr] :
                [NSString stringWithFormat:@"%ld tracks · %@", (long)self.currentPlaylistTracks.count, sizeStr];
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
    self.emptyStateLabel.hidden = hasDrive || self.isExporting;
    self.statusLabel.hidden = !hasDrive && !self.isExporting;
    BOOL russian = [[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];
    self.emptyStateLabel.stringValue = russian ? @"USB-накопитель не подключён.\nПодключите его и нажмите кнопку обновления."
                                               : @"No USB drive is connected.\nConnect one, then use the refresh button.";
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
    self.setupBox.title = [lang.selectedLanguage isEqualToString:@"ru"] ? @"Настройка экспорта" : @"Export Setup";
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
        [[IGUSBExportService sharedService] cancel];
        self.exportButton.enabled = NO;
        self.statusLabel.stringValue = [[IGLocalizationService sharedService].selectedLanguage isEqualToString:@"ru"] ?
            @"Остановка с сохранением прогресса..." :
            @"Stopping and saving progress...";
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

    IGExportMode mode = (IGExportMode)[self.modePopup indexOfSelectedItem];

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
    NSInteger index=[self.playlistPopup indexOfSelectedItem];
    NSString *playlistName=(index>=0&&index<(NSInteger)[self.playlists count])?self.playlists[index][@"name"]:@"Syncrosa Playlist";
    NSDictionary *options=@{@"fitAvailable":@(mode==IGExportModeFit),@"m3u":@(self.m3uButton.state==NSOnState),@"m3u8":@(self.m3u8Button.state==NSOnState),@"ipodSafeNames":@(self.ipodSafeButton.state==NSOnState)};
    [[IGUSBExportService sharedService] exportTracks:self.currentPlaylistTracks destination:drive.volumeURL playlistName:playlistName options:options progress:^(NSDictionary *progress) {
        NSInteger total=MAX((NSInteger)1,[progress[@"totalCount"] integerValue]);
        NSInteger completed=[progress[@"completedCount"] integerValue];
        BOOL russian=[[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];
        BOOL checking=[progress[@"phase"] isEqualToString:@"checking"];
        self.progressIndicator.maxValue=total;
        self.progressIndicator.doubleValue=completed;
        [[IGOperationActivity sharedActivity] updateProgress:(double)completed/(double)total forIdentifier:IGOperationActivityUSBExportIdentifier];
        self.statusLabel.stringValue=[NSString stringWithFormat:russian?(checking?@"Проверка %ld/%ld: %@":@"Копирование: %ld/%ld · %@"):(checking?@"Checking %ld/%ld: %@":@"Copying: %ld/%ld · %@"),(long)(checking?[progress[@"currentTrack"] integerValue]:completed),(long)total,progress[@"currentTrackName"]?:@""];
    } completion:^(NSDictionary *result) {
        [[IGOperationActivity sharedActivity] finishOperationWithIdentifier:IGOperationActivityUSBExportIdentifier];
        self.isExporting=NO;self.shouldCancelExport=NO;self.progressIndicator.hidden=YES;
        self.drivePopup.enabled=YES;self.playlistPopup.enabled=YES;self.modePopup.enabled=YES;
        self.exportButton.title=[[IGLocalizationService sharedService] t:@"export_button"];
        [self updateExportButtonState];[self reloadDrives];
        BOOL russian=[[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];
        NSString *bytes=[NSByteCountFormatter stringFromByteCount:[result[@"totalBytesCopied"] longLongValue] countStyle:NSByteCountFormatterCountStyleFile];
        NSString *summary=[NSString stringWithFormat:russian?@"Новых копий: %@ · Уже перенесено: %@ · Недоступно: %@ · DRM: %@ · Не вместилось: %@ · Записано %@":@"New copies: %@ · Already exported: %@ · Unavailable: %@ · DRM: %@ · Did not fit: %@ · Written %@",result[@"copiedCount"],result[@"existingCount"],result[@"skippedMissing"],result[@"skippedDRM"],result[@"skippedSpace"],bytes];
        if(![result[@"status"] isEqualToString:@"completed"])summary=[summary stringByAppendingString:russian?@". Продолжите через Центр восстановления.":@". Continue from Recovery Center."];
        self.statusLabel.stringValue=summary;
        self.statusLabel.toolTip=[result[@"errors"] componentsJoinedByString:@"\n"];
        [IGNotificationView showInView:self.view message:summary isError:[result[@"errors"] count]>0];
    }];
}

- (void)helpClicked:(id)sender {
    (void)sender;
    if (self.helpSheetWindow) return;
    NSArray *sections = @[
        IGHelpSectionMake(@"Choose the destination", @"Select a connected drive and an iTunes playlist. Syncrosa creates a folder named after that playlist and copies tracks inside it."),
        IGHelpSectionMake(@"Repeat or continue an export", @"Existing files are checked by content and reused. Only missing or changed tracks are copied; unrelated files and older copies are preserved. Recovery Center can continue a stopped export after you reconnect the same drive."),
        IGHelpSectionMake(@"Choose a space policy", @"Only files still needing transfer count against free space. Fit Available Space saves one stable selection. Optional M3U or M3U8 files preserve playlist order, including completed tracks after cancellation."),
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
