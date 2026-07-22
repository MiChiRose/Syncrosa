#import "IGRecoveryCenterViewController.h"
#import "IGLocalizationService.h"
#import "IGTheme.h"
#import "IGIconProvider.h"
#import "IGHelpSheetPresenter.h"

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
    [super dealloc];
#endif
}

- (void)setupUI
{
    self.titleLabel = IGRecoveryLabel(@"Recovery Center", NSMakeRect(20, 426, 540, 30), [NSFont boldSystemFontOfSize:18.0]);
    self.titleLabel.alignment = NSCenterTextAlignment;
    [self.view addSubview:self.titleLabel];

    self.helpButton = [[[NSButton alloc] initWithFrame:NSMakeRect(520, 428, 25, 25)] autorelease];
    self.helpButton.bezelStyle = NSHelpButtonBezelStyle;
    self.helpButton.title = @"";
    self.helpButton.target = self;
    self.helpButton.action = @selector(helpClicked:);
    [self.view addSubview:self.helpButton];

    self.activeBox = [[[NSBox alloc] initWithFrame:NSMakeRect(30, 326, 520, 88)] autorelease];
    self.activeBox.title = @"Interrupted Operation";
    self.activeBox.boxType = NSBoxPrimary;
    [self.view addSubview:self.activeBox];

    self.activeLabel = IGRecoveryLabel(@"No interrupted operation marker found.", NSMakeRect(16, 14, 488, 48), [NSFont systemFontOfSize:11.0]);
    [self.activeBox addSubview:self.activeLabel];

    self.refreshButton = [self actionButtonWithTitle:@"Refresh" icon:@"refresh" frame:NSMakeRect(30, 286, 250, 30) action:@selector(refreshClicked:)];
    self.showBackupsButton = [self actionButtonWithTitle:@"Show Backups" icon:@"folder" frame:NSMakeRect(300, 286, 250, 30) action:@selector(showBackupsClicked:)];
    self.clearMarkerButton = [self actionButtonWithTitle:@"Clear Marker" icon:@"restore" frame:NSMakeRect(30, 248, 250, 30) action:@selector(clearMarkerClicked:)];
    self.clearHistoryButton = [self actionButtonWithTitle:@"Clear History" icon:@"history" frame:NSMakeRect(300, 248, 250, 30) action:@selector(clearHistoryClicked:)];

    self.filterLabel = IGRecoveryLabel(@"Tool:", NSMakeRect(30, 211, 55, 22), [NSFont systemFontOfSize:11.0]);
    [self.view addSubview:self.filterLabel];

    self.toolPopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(82, 208, 210, 26) pullsDown:NO] autorelease];
    self.toolPopup.target = self;
    self.toolPopup.action = @selector(filterChanged:);
    [self.view addSubview:self.toolPopup];

    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(30, 56, 520, 140)] autorelease];
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.autohidesScrollers = YES;
    scroll.borderType = NSBezelBorder;

    self.historyTable = [[[NSTableView alloc] initWithFrame:scroll.bounds] autorelease];
    self.historyTable.dataSource = self;
    self.historyTable.rowHeight = 24.0;
    self.historyTable.usesAlternatingRowBackgroundColors = YES;
    self.historyTable.allowsMultipleSelection = NO;

    [self addColumn:@"date" title:@"Date" width:100.0];
    [self addColumn:@"tool" title:@"Tool" width:105.0];
    [self addColumn:@"status" title:@"Status" width:65.0];
    [self addColumn:@"message" title:@"Details" width:220.0];

    scroll.documentView = self.historyTable;
    [self.view addSubview:scroll];

    self.summaryLabel = IGRecoveryLabel(@"No history entries yet.", NSMakeRect(30, 26, 520, 20), [NSFont systemFontOfSize:10.0]);
    self.summaryLabel.textColor = IGThemeMutedTextColor();
    self.summaryLabel.alignment = NSCenterTextAlignment;
    [self.view addSubview:self.summaryLabel];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(localizationChanged:) name:@"IGLanguageChangedNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:IGThemeDidChangeNotification object:nil];
    [self updateLocalization];
    [self themeChanged:nil];
    [self reloadRecoveryData];
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
    [self.view addSubview:button];
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
    self.clearMarkerButton.title = russian ? @"Сбросить маркер" : @"Clear Marker";
    self.clearHistoryButton.title = russian ? @"Очистить историю" : @"Clear History";
    self.filterLabel.stringValue = russian ? @"Раздел:" : @"Tool:";
    self.activeBox.title = russian ? @"Прерванная операция" : @"Interrupted Operation";

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

- (NSDictionary *)loadActiveMarker
{
    NSString *support = IGRecoverySupportDirectory();
    NSString *plistPath = [support stringByAppendingPathComponent:@"active-operation.plist"];
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    if ([plist isKindOfClass:[NSDictionary class]] && [plist count] > 0) {
        return plist;
    }

    NSString *jsonPath = [support stringByAppendingPathComponent:@"active-operation.json"];
    NSData *data = [NSData dataWithContentsOfFile:jsonPath];
    if ([data length] > 0) {
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([json isKindOfClass:[NSDictionary class]]) {
            return json;
        }
    }
    return nil;
}

- (void)reloadRecoveryData
{
    self.historyEntries = [self loadHistoryEntries];
    self.activeMarker = [self loadActiveMarker];
    [self rebuildToolFilter];
    [self applyHistoryFilter];

    BOOL russian = [[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];
    if (self.activeMarker) {
        NSString *title = IGRecoveryStringValue([self.activeMarker objectForKey:@"title"]);
        NSString *tool = IGRecoveryStringValue([self.activeMarker objectForKey:@"tool"]);
        NSString *message = IGRecoveryStringValue([self.activeMarker objectForKey:@"message"]);
        self.activeLabel.stringValue = [NSString stringWithFormat:@"%@\n%@: %@%@%@",
                                        title,
                                        russian ? @"Инструмент" : @"Tool",
                                        tool,
                                        [message length] > 0 ? @" - " : @"",
                                        message];
    } else {
        self.activeLabel.stringValue = russian ? @"Прерванных операций не найдено." : @"No interrupted operation marker found.";
    }

    NSString *backupPath = [IGRecoverySupportDirectory() stringByAppendingPathComponent:@"Backups"];
    self.showBackupsButton.enabled = [[NSFileManager defaultManager] fileExistsAtPath:backupPath];
    self.clearMarkerButton.enabled = self.activeMarker != nil;
    self.clearHistoryButton.enabled = [self.historyEntries count] > 0;
    self.summaryLabel.stringValue = [NSString stringWithFormat:russian ? @"Записей: %lu. Показано: %lu." : @"Entries: %lu. Showing: %lu.",
                                     (unsigned long)[self.historyEntries count],
                                     (unsigned long)[self.filteredEntries count]];
    [self.historyTable reloadData];
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
    NSString *path = [IGRecoverySupportDirectory() stringByAppendingPathComponent:@"Backups"];
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
    if (![self confirmActionWithTitle:@"Clear Interrupted Operation?" message:@"This removes only the recovery marker. Music files and backups are not deleted."]) {
        return;
    }
    NSString *support = IGRecoverySupportDirectory();
    [[NSFileManager defaultManager] removeItemAtPath:[support stringByAppendingPathComponent:@"active-operation.plist"] error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:[support stringByAppendingPathComponent:@"active-operation.json"] error:nil];
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
        IGHelpSectionMake(@"Backup и история", @"Показать backup открывает папку восстановления. Фильтр помогает найти записи конкретного инструмента."),
        IGHelpSectionMake(@"Безопасная очистка", @"Сброс маркера не удаляет музыку или backup. Очистка истории удаляет только список записей.")
    ] : @[
        IGHelpSectionMake(@"Interrupted operation", @"The top panel shows a saved marker for a task that did not finish normally. Read its details and inspect the operation result first."),
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
