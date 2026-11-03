#import "IGRecoveryCenterViewController.h"
#import "IGLocalizationService.h"
#import "IGTheme.h"
#import "IGIconProvider.h"
#import "IGHelpSheetPresenter.h"
#import "IGOperationActivity.h"
#import "IGUSBService.h"

static NSString *IGRecoverySupportDirectory(void)
{
    NSArray *directories = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *base = [directories count] > 0 ? [directories objectAtIndex:0] : NSHomeDirectory();
    return [base stringByAppendingPathComponent:@"Syncrosa"];
}

static NSString *IGRecoveryStringValue(id value)
{
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

NSArray *IGRecoverySanitizedHistoryEntries(id value)
{
    if (![value isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray *entries = [NSMutableArray array];
    for (id entry in (NSArray *)value) {
        if ([entry isKindOfClass:[NSDictionary class]]) {
            [entries addObject:entry];
        }
    }
    return entries;
}

static NSTextField *IGRecoveryLabel(NSString *text, NSRect frame, NSFont *font)
{
    NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    label.stringValue = text ?: @"";
    label.font = font ?: [NSFont systemFontOfSize:12.0];
    label.editable = NO;
    label.selectable = NO;
    label.bordered = NO;
    label.drawsBackground = NO;
    NSCell *cell = [label cell];
    if ([cell respondsToSelector:@selector(setLineBreakMode:)]) {
        [cell setLineBreakMode:NSLineBreakByWordWrapping];
    }
    return label;
}

@interface IGRecoveryCenterViewController ()
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *activeLabel;
@property (nonatomic, strong) NSTextField *summaryLabel;
@property (nonatomic, strong) NSTextField *filterLabel;
@property (nonatomic, strong) NSBox *activeBox;
@property (nonatomic, strong) NSButton *refreshButton;
@property (nonatomic, strong) NSButton *showBackupsButton;
@property (nonatomic, strong) NSButton *clearMarkerButton;
@property (nonatomic, strong) NSButton *clearHistoryButton;
@property (nonatomic, strong) NSButton *helpButton;
@property (nonatomic, strong) NSPopUpButton *toolPopup;
@property (nonatomic, strong) NSTableView *historyTable;
@property (nonatomic, strong) NSArray *historyEntries;
@property (nonatomic, strong) NSArray *filteredEntries;
@property (nonatomic, strong) NSDictionary *activeMarker;
@property (nonatomic, strong) NSWindow *helpSheetWindow;
@property (nonatomic, strong) NSView *contentView;
@property (nonatomic, strong) NSPopUpButton *markerPopup;
@property (nonatomic, strong) NSArray *recoveryMarkers;
@property (nonatomic, strong) NSBox *usbBox;
@property (nonatomic, strong) NSPopUpButton *usbJobsPopup;
@property (nonatomic, strong) NSTextField *usbDetailsLabel;
@property (nonatomic, strong) NSButton *resumeUSBButton;
@property (nonatomic, strong) NSButton *discardUSBButton;
@property (nonatomic, strong) NSArray *usbJobs;
@property (nonatomic, strong) NSArray *usbWarnings;
@property (nonatomic, assign) BOOL isResumingUSB;
@end

@implementation IGRecoveryCenterViewController

- (void)loadView
{
    self.view = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 480)] autorelease];
    [self setupUI];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
#if !__has_feature(objc_arc)
    [_titleLabel release];
    [_activeLabel release];
    [_summaryLabel release];
    [_filterLabel release];
    [_activeBox release];
    [_refreshButton release];
    [_showBackupsButton release];
    [_clearMarkerButton release];
    [_clearHistoryButton release];
    [_helpButton release];
    [_toolPopup release];
    [_historyTable release];
    [_historyEntries release];
    [_filteredEntries release];
    [_activeMarker release];
    [_helpSheetWindow release];
    [_contentView release]; [_markerPopup release]; [_recoveryMarkers release];
    [_usbBox release]; [_usbJobsPopup release]; [_usbDetailsLabel release];
    [_resumeUSBButton release]; [_discardUSBButton release]; [_usbJobs release]; [_usbWarnings release];
    [super dealloc];
#endif
}

- (void)setupUI
{
    NSScrollView *pageScroll = [[[NSScrollView alloc] initWithFrame:self.view.bounds] autorelease];
    pageScroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    pageScroll.hasVerticalScroller = YES;
    pageScroll.autohidesScrollers = YES;
    pageScroll.borderType = NSNoBorder;
    self.contentView = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 900)] autorelease];
    pageScroll.documentView = self.contentView;
    [self.view addSubview:pageScroll];
    self.titleLabel = IGRecoveryLabel(@"Recovery Center", NSMakeRect(20, 850, 540, 30), [NSFont boldSystemFontOfSize:18]);
    self.titleLabel.alignment = NSCenterTextAlignment;
    [self.contentView addSubview:self.titleLabel];
    self.helpButton = [[[NSButton alloc] initWithFrame:NSMakeRect(520, 852, 25, 25)] autorelease];
    self.helpButton.bezelStyle = NSHelpButtonBezelStyle;
    self.helpButton.title = @""; self.helpButton.target = self; self.helpButton.action = @selector(helpClicked:);
    [self.contentView addSubview:self.helpButton];

    self.activeBox = [[[NSBox alloc] initWithFrame:NSMakeRect(30, 635, 520, 205)] autorelease];
    self.activeBox.boxType = NSBoxPrimary;
    [self.contentView addSubview:self.activeBox];
    self.markerPopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(16, 144, 488, 26) pullsDown:NO] autorelease];
    self.markerPopup.target = self; self.markerPopup.action = @selector(markerChanged:);
    [self.activeBox addSubview:self.markerPopup];
    self.activeLabel = IGRecoveryLabel(@"", NSMakeRect(16, 28, 488, 104), [NSFont systemFontOfSize:11]);
    [self.activeBox addSubview:self.activeLabel];
    self.refreshButton = [self actionButtonWithTitle:@"Refresh" icon:@"refresh" frame:NSMakeRect(30, 595, 250, 30) action:@selector(refreshClicked:)];
    self.showBackupsButton = [self actionButtonWithTitle:@"Show Backups" icon:@"folder" frame:NSMakeRect(300, 595, 250, 30) action:@selector(showBackupsClicked:)];
    self.clearMarkerButton = [self actionButtonWithTitle:@"Remove Record" icon:@"restore" frame:NSMakeRect(30, 557, 250, 30) action:@selector(clearMarkerClicked:)];
    self.clearHistoryButton = [self actionButtonWithTitle:@"Clear History" icon:@"history" frame:NSMakeRect(300, 557, 250, 30) action:@selector(clearHistoryClicked:)];

    self.usbBox = [[[NSBox alloc] initWithFrame:NSMakeRect(30, 285, 520, 260)] autorelease];
    self.usbBox.boxType = NSBoxPrimary;
    [self.contentView addSubview:self.usbBox];
    self.usbJobsPopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(16, 188, 488, 26) pullsDown:NO] autorelease];
    self.usbJobsPopup.target = self; self.usbJobsPopup.action = @selector(usbJobChanged:);
    [self.usbBox addSubview:self.usbJobsPopup];
    self.usbDetailsLabel = IGRecoveryLabel(@"", NSMakeRect(16, 84, 488, 96), [NSFont systemFontOfSize:11]);
    [self.usbBox addSubview:self.usbDetailsLabel];
    self.resumeUSBButton = [self actionButtonWithTitle:@"Resume…" icon:@"usb" frame:NSMakeRect(46, 313, 230, 32) action:@selector(resumeUSBClicked:)];
    self.discardUSBButton = [self actionButtonWithTitle:@"Remove Record" icon:@"restore" frame:NSMakeRect(300, 313, 230, 32) action:@selector(discardUSBClicked:)];
    self.filterLabel = IGRecoveryLabel(@"Tool:", NSMakeRect(30, 245, 55, 22), [NSFont systemFontOfSize:11]);
    [self.contentView addSubview:self.filterLabel];
    self.toolPopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(82, 242, 210, 26) pullsDown:NO] autorelease];
    self.toolPopup.target = self; self.toolPopup.action = @selector(filterChanged:);
    [self.contentView addSubview:self.toolPopup];
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(30, 56, 520, 174)] autorelease];
    scroll.hasVerticalScroller = YES; scroll.autohidesScrollers = YES; scroll.borderType = NSBezelBorder;
    self.historyTable = [[[NSTableView alloc] initWithFrame:scroll.bounds] autorelease];
    self.historyTable.dataSource = self; self.historyTable.rowHeight = 24;
    self.historyTable.usesAlternatingRowBackgroundColors = YES; self.historyTable.allowsMultipleSelection = NO;
    [self addColumn:@"date" title:@"Date" width:100]; [self addColumn:@"tool" title:@"Tool" width:105];
    [self addColumn:@"status" title:@"Status" width:65]; [self addColumn:@"message" title:@"Details" width:220];
    scroll.documentView = self.historyTable; [self.contentView addSubview:scroll];
    self.summaryLabel = IGRecoveryLabel(@"", NSMakeRect(30, 26, 520, 20), [NSFont systemFontOfSize:10]);
    self.summaryLabel.alignment = NSCenterTextAlignment; [self.contentView addSubview:self.summaryLabel];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(localizationChanged:) name:@"IGLanguageChangedNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:IGThemeDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshClicked:) name:IGUSBExportJobsDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshClicked:) name:IGOperationRecoveryDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(activityChanged:) name:IGOperationActivityDidChangeNotification object:nil];
    [self updateLocalization]; [self themeChanged:nil]; [self reloadRecoveryData];
    [[pageScroll contentView] scrollToPoint:NSMakePoint(0, 900 - NSHeight(pageScroll.contentView.bounds))];
    [pageScroll reflectScrolledClipView:pageScroll.contentView];
}

- (NSButton *)actionButtonWithTitle:(NSString *)title icon:(NSString *)iconName frame:(NSRect)frame action:(SEL)action
{
    NSButton *button = [[[NSButton alloc] initWithFrame:frame] autorelease];
    button.title = title;
    button.bezelStyle = NSTexturedRoundedBezelStyle;
    button.target = self;
    button.action = action;
    IGConfigureIconButton(button, iconName, title, NO);
    IGApplyThemeToButton(button, IGThemeButtonRoleSecondary);
    [self.contentView addSubview:button];
    return button;
}

- (void)addColumn:(NSString *)identifier title:(NSString *)title width:(CGFloat)width
{
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:identifier] autorelease];
    column.width = width;
    column.minWidth = 50.0;
    [[column headerCell] setStringValue:title];
    [self.historyTable addTableColumn:column];
}

- (void)updateLocalization
{
    BOOL russian = [[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];
    self.titleLabel.stringValue = russian ? @"Центр восстановления" : @"Recovery Center";
    self.refreshButton.title = russian ? @"Обновить" : @"Refresh";
    self.showBackupsButton.title = russian ? @"Показать backup" : @"Show Backups";
    self.clearMarkerButton.title = russian ? @"Убрать запись" : @"Remove Record";
    self.clearHistoryButton.title = russian ? @"Очистить историю" : @"Clear History";
    self.filterLabel.stringValue = russian ? @"Раздел:" : @"Tool:";
    self.activeBox.title = russian ? @"Прерванные операции" : @"Interrupted Operations";
    self.usbBox.title = russian ? @"Продолжить USB-экспорт" : @"Resume USB Export";
    self.discardUSBButton.title = russian ? @"Убрать запись" : @"Remove Record";

    NSArray *columns = [self.historyTable tableColumns];
    if ([columns count] == 4) {
        [[[columns objectAtIndex:0] headerCell] setStringValue:russian ? @"Дата" : @"Date"];
        [[[columns objectAtIndex:1] headerCell] setStringValue:russian ? @"Инструмент" : @"Tool"];
        [[[columns objectAtIndex:2] headerCell] setStringValue:russian ? @"Статус" : @"Status"];
        [[[columns objectAtIndex:3] headerCell] setStringValue:russian ? @"Подробности" : @"Details"];
    }
    [self reloadRecoveryData];
}

- (void)localizationChanged:(NSNotification *)notification
{
    (void)notification;
    [self updateLocalization];
}

- (void)themeChanged:(NSNotification *)notification
{
    (void)notification;
    self.summaryLabel.textColor = IGThemeMutedTextColor();
    IGApplyThemeToButton(self.refreshButton, IGThemeButtonRoleSecondary);
    IGApplyThemeToButton(self.showBackupsButton, IGThemeButtonRoleSecondary);
    IGApplyThemeToButton(self.clearMarkerButton, IGThemeButtonRoleSecondary);
    IGApplyThemeToButton(self.clearHistoryButton, IGThemeButtonRoleDanger);
    IGApplyThemeToViewHierarchy(self.view);
    [self.view setNeedsDisplay:YES];
}

- (NSString *)historyPath
{
    return [IGRecoverySupportDirectory() stringByAppendingPathComponent:@"operation-history.json"];
}

- (NSArray *)loadHistoryEntries
{
    NSData *data = [NSData dataWithContentsOfFile:[self historyPath]];
    if ([data length] == 0) {
        return @[];
    }
    id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return IGRecoverySanitizedHistoryEntries(value);
}

- (void)reloadRecoveryData
{
    NSString *previousMarker = [self.activeMarker objectForKey:@"id"];
    NSString *previousJob = [[self selectedUSBJob] objectForKey:@"id"];
    IGOperationActivity *activity = [IGOperationActivity sharedActivity];
    [activity reloadRecoveryMarkers];
    self.recoveryMarkers = [activity recoveryMarkers];
    [self.markerPopup removeAllItems];
    NSInteger markerSelection = 0;
    for (NSDictionary *marker in self.recoveryMarkers) {
        [self.markerPopup addItemWithTitle:[NSString stringWithFormat:@"%lu. %@ · %@", (unsigned long)[self.markerPopup numberOfItems] + 1, IGRecoveryStringValue(marker[@"title"]), [self displayDate:marker[@"startedAt"]]]];
        if ([marker[@"id"] isEqual:previousMarker]) markerSelection = [self.markerPopup numberOfItems] - 1;
    }
    if ([self.markerPopup numberOfItems] > 0) [self.markerPopup selectItemAtIndex:markerSelection];
    [self markerChanged:nil];
    NSArray *warnings = nil;
    self.usbJobs = [[IGUSBExportService sharedService] pendingJobsWithWarnings:&warnings];
    self.usbWarnings = warnings ?: @[];
    [self.usbJobsPopup removeAllItems];
    NSInteger jobSelection = 0;
    for (NSDictionary *job in self.usbJobs) {
        [self.usbJobsPopup addItemWithTitle:[NSString stringWithFormat:@"%lu. %@ · %@/%@", (unsigned long)[self.usbJobsPopup numberOfItems] + 1, IGRecoveryStringValue(job[@"playlistName"]), job[@"completedCount"] ?: @0, job[@"totalCount"] ?: @0]];
        if ([job[@"id"] isEqual:previousJob]) jobSelection = [self.usbJobsPopup numberOfItems] - 1;
    }
    if ([self.usbJobsPopup numberOfItems] > 0) [self.usbJobsPopup selectItemAtIndex:jobSelection];
    [self usbJobChanged:nil];
    self.historyEntries = [self loadHistoryEntries];
    [self rebuildToolFilter]; [self applyHistoryFilter];
    self.clearHistoryButton.enabled = [self.historyEntries count] > 0;
    BOOL russian = [[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];
    self.summaryLabel.stringValue = [NSString stringWithFormat:russian ? @"Записей: %lu. Показано: %lu." : @"Entries: %lu. Showing: %lu.", (unsigned long)[self.historyEntries count], (unsigned long)[self.filteredEntries count]];
    [self.historyTable reloadData];
    [self activityChanged:nil];
}

- (void)markerChanged:(id)sender
{
    (void)sender;
    NSInteger index = [self.markerPopup indexOfSelectedItem];
    self.activeMarker = index >= 0 && index < (NSInteger)[self.recoveryMarkers count] ? self.recoveryMarkers[index] : nil;
    BOOL russian = [[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];
    NSMutableArray *lines = [NSMutableArray array];
    if (self.activeMarker) {
        [lines addObject:[NSString stringWithFormat:@"%@ · %@", IGRecoveryStringValue(self.activeMarker[@"tool"]), [self displayDate:self.activeMarker[@"startedAt"]]]];
        [lines addObject:IGRecoveryStringValue(self.activeMarker[@"message"])];
    } else [lines addObject:russian ? @"Прерванных операций нет." : @"No interrupted operations."];
    for (NSString *warning in [[IGOperationActivity sharedActivity] recoveryWarnings]) if ([lines count] < 5) [lines addObject:warning];
    self.activeLabel.stringValue = [lines componentsJoinedByString:@"\n"];
    self.markerPopup.enabled = [self.recoveryMarkers count] > 0;
    self.clearMarkerButton.enabled = self.activeMarker != nil;
    NSString *backup = IGRecoveryStringValue(self.activeMarker[@"backupPath"]);
    if ([backup length] == 0) backup = [IGRecoverySupportDirectory() stringByAppendingPathComponent:@"Backups"];
    self.showBackupsButton.enabled = [[NSFileManager defaultManager] fileExistsAtPath:backup];
}

- (NSDictionary *)selectedUSBJob
{
    NSInteger index = [self.usbJobsPopup indexOfSelectedItem];
    return index >= 0 && index < (NSInteger)[self.usbJobs count] ? self.usbJobs[index] : nil;
}

- (void)usbJobChanged:(id)sender
{
    (void)sender;
    if (self.isResumingUSB) return;
    BOOL russian = [[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];
    NSDictionary *job = [self selectedUSBJob];
    NSMutableArray *lines = [NSMutableArray array];
    if (job) {
        [lines addObject:[NSString stringWithFormat:@"%@ · %@/%@", IGRecoveryStringValue(job[@"destinationName"]), job[@"completedCount"], job[@"totalCount"]]];
        [lines addObject:russian ? @"Подключите тот же накопитель и выберите его заново. Готовые файлы проверяются по содержимому; копируются оставшиеся." : @"Reconnect the same drive and select it again. Completed files are checked by content; remaining tracks are copied."];
    } else [lines addObject:russian ? @"Незавершённых USB-задач нет." : @"No unfinished USB exports."];
    for (NSString *warning in self.usbWarnings) if ([lines count] < 4) [lines addObject:warning];
    self.usbDetailsLabel.stringValue = [lines componentsJoinedByString:@"\n"];
    [self activityChanged:nil];
}

- (void)activityChanged:(id)sender
{
    (void)sender;
    BOOL russian = [[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];
    BOOL busy = [[[IGOperationActivity sharedActivity] activeIdentifier] length] > 0;
    self.resumeUSBButton.title = self.isResumingUSB ? (russian ? @"Остановить" : @"Stop") : (russian ? @"Продолжить…" : @"Resume…");
    self.resumeUSBButton.enabled = self.isResumingUSB || ([self selectedUSBJob] != nil && !busy);
    self.discardUSBButton.enabled = [self selectedUSBJob] != nil && !busy && !self.isResumingUSB;
    self.usbJobsPopup.enabled = [self.usbJobs count] > 0 && !self.isResumingUSB;
}

- (void)resumeUSBClicked:(id)sender
{
    (void)sender;
    if (self.isResumingUSB) { [[IGUSBExportService sharedService] cancel]; return; }
    NSDictionary *job = [self selectedUSBJob];
    IGOperationActivity *activity = [IGOperationActivity sharedActivity];
    if (!job || [[activity activeIdentifier] length] > 0) return;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES; panel.canChooseFiles = NO; panel.allowsMultipleSelection = NO;
    BOOL russian = [[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];
    panel.title = russian ? @"Выберите тот же USB-накопитель" : @"Select the same USB drive";
    if ([panel runModal] != NSOKButton || ![panel URL]) return;
    if (![activity beginOperationWithIdentifier:IGOperationActivityUSBExportIdentifier]) return;
    self.isResumingUSB = YES; [self activityChanged:nil];
    self.usbDetailsLabel.stringValue = russian ? @"Проверка сохранённых файлов…" : @"Checking saved files…";
    [[IGUSBExportService sharedService] resumeJobWithIdentifier:job[@"id"] destination:[panel URL] progress:^(NSDictionary *progress) {
        self.usbDetailsLabel.stringValue = [NSString stringWithFormat:@"%@/%@ · %@", progress[@"currentTrack"] ?: @0, progress[@"totalTracks"] ?: @0, IGRecoveryStringValue(progress[@"currentTrackName"])];
    } completion:^(NSDictionary *result) {
        self.isResumingUSB = NO;
        [[IGOperationActivity sharedActivity] finishOperationWithIdentifier:IGOperationActivityUSBExportIdentifier];
        [self reloadRecoveryData];
        NSString *message = [NSString stringWithFormat:russian ? @"Скопировано: %@. Уже перенесено: %@. Ошибок: %lu." : @"Copied: %@. Already present: %@. Errors: %lu.", result[@"copiedCount"] ?: @0, result[@"existingCount"] ?: @0, (unsigned long)[result[@"errors"] count]];
        if (![result[@"status"] isEqualToString:@"completed"]) message = [message stringByAppendingString:russian ? @" Задача сохранена для продолжения." : @" The task remains available to resume."];
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        alert.messageText = russian ? @"USB-экспорт" : @"USB Export";
        alert.informativeText = message;
        [alert addButtonWithTitle:russian ? @"Закрыть" : @"Close"];
        [alert runModal];
    }];
}

- (void)discardUSBClicked:(id)sender
{
    (void)sender;
    NSDictionary *job = [self selectedUSBJob];
    if (!job || self.isResumingUSB) return;
    BOOL russian = [[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];
    if (![self confirmActionWithTitle:(russian ? @"Убрать запись USB-задачи?" : @"Remove USB Recovery Record?") message:(russian ? @"Удалится только выбранная запись. Готовые файлы на USB и исходная музыка сохранятся." : @"Only the selected recovery record is removed. Completed USB files and source music are kept.")]) return;
    NSError *error = nil;
    if (![[IGUSBExportService sharedService] discardJobWithIdentifier:job[@"id"] error:&error]) {
        NSAlert *alert = [NSAlert alertWithError:error ?: [NSError errorWithDomain:@"Syncrosa.Recovery" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Could not remove the recovery record."}]];
        [alert runModal];
    }
    [self reloadRecoveryData];
}

- (void)rebuildToolFilter
{
    NSString *previous = [self.toolPopup titleOfSelectedItem];
    NSMutableSet *tools = [NSMutableSet set];
    for (NSDictionary *entry in self.historyEntries) {
        NSString *tool = [entry objectForKey:@"tool"];
        if ([tool isKindOfClass:[NSString class]] && [tool length] > 0) {
            [tools addObject:tool];
        }
    }

    BOOL russian = [[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];
    [self.toolPopup removeAllItems];
    [self.toolPopup addItemWithTitle:russian ? @"Все инструменты" : @"All Tools"];
    NSArray *sorted = [[tools allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    [self.toolPopup addItemsWithTitles:sorted];
    if ([previous length] > 0 && [[self.toolPopup itemTitles] containsObject:previous]) {
        [self.toolPopup selectItemWithTitle:previous];
    }
}

- (void)applyHistoryFilter
{
    if ([self.toolPopup indexOfSelectedItem] <= 0) {
        self.filteredEntries = self.historyEntries ?: @[];
        return;
    }
    NSString *tool = [self.toolPopup titleOfSelectedItem];
    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *entry, NSDictionary *bindings) {
        (void)bindings;
        return [IGRecoveryStringValue([entry objectForKey:@"tool"]) isEqualToString:tool];
    }];
    self.filteredEntries = [self.historyEntries filteredArrayUsingPredicate:predicate];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    (void)tableView;
    return (NSInteger)[self.filteredEntries count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    (void)tableView;
    if (row < 0 || row >= (NSInteger)[self.filteredEntries count]) {
        return @"";
    }
    NSDictionary *entry = [self.filteredEntries objectAtIndex:(NSUInteger)row];
    NSString *identifier = [tableColumn identifier];
    if ([identifier isEqualToString:@"date"]) {
        return [self displayDate:[entry objectForKey:@"createdAt"]];
    }
    if ([identifier isEqualToString:@"message"]) {
        NSString *message = IGRecoveryStringValue([entry objectForKey:@"message"]);
        NSString *title = IGRecoveryStringValue([entry objectForKey:@"title"]);
        return [message length] > 0 ? message : title;
    }
    id value = [entry objectForKey:identifier];
    return [value respondsToSelector:@selector(description)] ? [value description] : @"";
}

- (NSString *)displayDate:(id)value
{
    if ([value isKindOfClass:[NSNumber class]]) {
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:[value doubleValue]];
        NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
        formatter.dateStyle = NSDateFormatterShortStyle;
        formatter.timeStyle = NSDateFormatterShortStyle;
        return [formatter stringFromDate:date] ?: @"";
    }
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

- (void)refreshClicked:(id)sender
{
    (void)sender;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self reloadRecoveryData]; });
        return;
    }
    [self reloadRecoveryData];
}

- (void)filterChanged:(id)sender
{
    (void)sender;
    [self applyHistoryFilter];
    [self.historyTable reloadData];
    BOOL russian = [[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];
    self.summaryLabel.stringValue = [NSString stringWithFormat:russian ? @"Записей: %lu. Показано: %lu." : @"Entries: %lu. Showing: %lu.",
                                     (unsigned long)[self.historyEntries count],
                                     (unsigned long)[self.filteredEntries count]];
}

- (void)showBackupsClicked:(id)sender
{
    (void)sender;
    NSString *path = IGRecoveryStringValue(self.activeMarker[@"backupPath"]);
    if ([path length] == 0) path = [IGRecoverySupportDirectory() stringByAppendingPathComponent:@"Backups"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSWorkspace sharedWorkspace] selectFile:nil inFileViewerRootedAtPath:path];
    }
}

- (BOOL)confirmActionWithTitle:(NSString *)title message:(NSString *)message
{
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:title ?: @"Syncrosa"];
    [alert setInformativeText:message ?: @""];
    [alert addButtonWithTitle:@"Continue"];
    [alert addButtonWithTitle:@"Cancel"];
    return [alert runModal] == NSAlertFirstButtonReturn;
}

- (void)clearMarkerClicked:(id)sender
{
    (void)sender;
    if (!self.activeMarker) return;
    BOOL russian = [[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];
    if (![self confirmActionWithTitle:(russian ? @"Убрать запись восстановления?" : @"Remove Recovery Record?") message:(russian ? @"Удалится только выбранная запись. Музыка и резервные копии сохранятся." : @"Only the selected record is removed. Music and backups are kept.")]) return;
    NSError *error = nil;
    if (![[IGOperationActivity sharedActivity] clearRecoveryMarkerWithIdentifier:self.activeMarker[@"id"] error:&error] && error) [[NSAlert alertWithError:error] runModal];
    [self reloadRecoveryData];
}

- (void)clearHistoryClicked:(id)sender
{
    (void)sender;
    if (![self confirmActionWithTitle:@"Clear Operation History?" message:@"This removes the history list. Backup files are not deleted."]) {
        return;
    }
    [[NSFileManager defaultManager] removeItemAtPath:[self historyPath] error:nil];
    [self reloadRecoveryData];
}

- (void)helpClicked:(id)sender
{
    (void)sender;
    if (self.helpSheetWindow) {
        return;
    }
    BOOL russian = [[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];
    NSArray *sections = russian ? @[
        IGHelpSectionMake(@"Незавершённая операция", @"Верхний блок показывает сохранённый маркер задачи, которая не завершилась штатно. Сначала прочитайте его описание и проверьте результат операции."),
        IGHelpSectionMake(@"Продолжить USB-экспорт", @"Подключите тот же накопитель, выберите незавершённую USB-задачу и нажмите «Продолжить». Готовые файлы проверяются и не копируются повторно."),
        IGHelpSectionMake(@"Backup и история", @"Показать backup открывает папку восстановления. Фильтр помогает найти записи конкретного инструмента."),
        IGHelpSectionMake(@"Безопасная очистка", @"Сброс маркера не удаляет музыку или backup. Очистка истории удаляет только список записей.")
    ] : @[
        IGHelpSectionMake(@"Interrupted operation", @"The top panel shows a saved marker for a task that did not finish normally. Read its details and inspect the operation result first."),
        IGHelpSectionMake(@"Resume USB Export", @"Reconnect the same drive, select an unfinished USB task and choose Resume. Completed files are verified and are not copied again."),
        IGHelpSectionMake(@"Backups and history", @"Show Backups opens the recovery folder. Use the filter to find records created by a specific tool."),
        IGHelpSectionMake(@"Safe cleanup", @"Clear Marker never deletes music or backups. Clear History removes only the list of records.")
    ];
    self.helpSheetWindow = [IGHelpSheetPresenter sheetWithTitle:(russian ? @"Центр восстановления" : @"Recovery Center")
                                                        summary:(russian ? @"Проверьте прерванные задачи, backup и историю операций." : @"Review interrupted tasks, backups, and operation history.")
                                                       sections:sections
                                                     closeTitle:(russian ? @"Закрыть" : @"Close")
                                                         target:self
                                                         action:@selector(closeHelpSheet:)];
    [IGHelpSheetPresenter presentSheet:self.helpSheetWindow forWindow:self.view.window];
}

- (void)closeHelpSheet:(id)sender
{
    (void)sender;
    if (!self.helpSheetWindow) {
        return;
    }
    [NSApp endSheet:self.helpSheetWindow];
    [self.helpSheetWindow orderOut:nil];
    self.helpSheetWindow = nil;
}

@end
