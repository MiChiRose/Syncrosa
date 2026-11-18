#import "IGFolderTitleEditor.h"
#import "IGLocalizationService.h"
#import "IGOperationActivity.h"
#import "IGTheme.h"
#import "../../../shared/TrackTitles/SRTrackTitles.h"

static NSString * const IGTitleEditOperation = @"folder-title-edit";

@interface IGFolderTitleEditor () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, retain) NSURL *folder;
@property (nonatomic, retain) NSURL *backupFolder;
@property (nonatomic, retain) NSTableView *table;
@property (nonatomic, retain) NSTextField *status;
@property (nonatomic, retain) NSButton *applyButton;
@property (nonatomic, retain) NSButton *suggestButton;
@property (nonatomic, retain) NSButton *backupButton;
@property (nonatomic, retain) NSButton *closeButton;
@property (nonatomic, retain) NSMutableArray *rows;
@property (nonatomic, assign) BOOL russian;
@property (nonatomic, assign) BOOL busy;
@end

@implementation IGFolderTitleEditor

- (instancetype)initWithFolder:(NSURL *)folder {
    NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 740, 440)
                                                   styleMask:NSTitledWindowMask
                                                     backing:NSBackingStoreBuffered defer:NO] autorelease];
    self = [super initWithWindow:window];
    if (self) {
        self.folder = folder;
        self.russian = [[IGLocalizationService sharedService].selectedLanguage isEqualToString:@"ru"];
        [self setup];
        [self scan];
    }
    return self;
}

- (void)dealloc {
    _table.delegate = nil;
    _table.dataSource = nil;
    [_folder release];
    [_backupFolder release];
    [_rows release];
    [_table release];
    [_status release];
    [_applyButton release];
    [_suggestButton release];
    [_backupButton release];
    [_closeButton release];
    [super dealloc];
}

- (NSString *)ru:(NSString *)russian en:(NSString *)english {
    return self.russian ? russian : english;
}

- (NSTextField *)label:(NSString *)text frame:(NSRect)frame {
    NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    label.stringValue = text;
    label.bezeled = NO;
    label.editable = NO;
    label.drawsBackground = NO;
    label.textColor = IGThemeTextColor();
    [self.window.contentView addSubview:label];
    return label;
}

- (NSButton *)button:(NSString *)title frame:(NSRect)frame action:(SEL)action {
    NSButton *button = [[[NSButton alloc] initWithFrame:frame] autorelease];
    button.title = title;
    button.bezelStyle = NSRoundedBezelStyle;
    button.target = self;
    button.action = action;
    [self.window.contentView addSubview:button];
    return button;
}

- (void)setup {
    NSView *content = self.window.contentView;
    IGInstallThemedContentBackground(content);
    self.window.title = [self ru:@"Исправить названия треков" en:@"Correct Track Titles"];
    NSTextField *title = [self label:self.window.title frame:NSMakeRect(18, 402, 704, 25)];
    title.font = [NSFont boldSystemFontOfSize:17];
    NSTextField *path = [self label:self.folder.path frame:NSMakeRect(18, 377, 704, 21)];
    path.selectable = YES;
    path.toolTip = self.folder.path;
    [path.cell setLineBreakMode:NSLineBreakByTruncatingMiddle];

    NSTextField *help = [self label:[self ru:@"Двойной щелчок по новому названию позволяет его изменить. Имена файлов сохраняются."
                                         en:@"Double-click a new title to edit it. This updates the audio tag and keeps the file name."]
                                 frame:NSMakeRect(18, 349, 704, 22)];
    help.font = [NSFont systemFontOfSize:12];

    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(18, 82, 704, 260)] autorelease];
    scroll.borderType = NSBezelBorder;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    self.table = [[[NSTableView alloc] initWithFrame:scroll.contentView.bounds] autorelease];
    self.table.usesAlternatingRowBackgroundColors = YES;
    self.table.rowHeight = 23;
    self.table.allowsColumnReordering = NO;
    self.table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    NSArray *columns = @[@[@"file", [self ru:@"Файл" en:@"File"], @211],
                         @[@"old", [self ru:@"Текущее название" en:@"Current title"], @194],
                         @[@"new", [self ru:@"Новое название" en:@"New title"], @250]];
    for (NSArray *spec in columns) {
        NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:spec[0]] autorelease];
        [[column headerCell] setStringValue:spec[1]];
        column.width = [spec[2] doubleValue];
        column.minWidth = 130;
        column.editable = [spec[0] isEqual:@"new"];
        [self.table addTableColumn:column];
    }
    self.table.dataSource = self;
    self.table.delegate = self;
    scroll.documentView = self.table;
    [content addSubview:scroll];

    self.status = [self label:[self ru:@"Читаем названия…" en:@"Reading track titles…"] frame:NSMakeRect(18, 52, 704, 20)];
    self.status.font = [NSFont systemFontOfSize:12];
    [self.status.cell setLineBreakMode:NSLineBreakByTruncatingTail];
    self.suggestButton = [self button:[self ru:@"Взять из имён файлов" en:@"Use File Names"]
                                frame:NSMakeRect(12, 14, 185, 30) action:@selector(suggestClicked:)];
    self.suggestButton.toolTip = [self ru:@"Берёт часть после «Исполнитель - » для строк, которые вы ещё не правили."
                                        en:@"Uses the text after “Artist - ” for rows you have not edited."];
    self.backupButton = [self button:[self ru:@"Показать оригиналы" en:@"Show Originals"]
                               frame:NSMakeRect(198, 14, 165, 30) action:@selector(backupsClicked:)];
    self.backupButton.hidden = YES;
    self.closeButton = [self button:[self ru:@"Закрыть" en:@"Close"] frame:NSMakeRect(461, 14, 110, 30) action:@selector(closeClicked:)];
    self.closeButton.keyEquivalent = @"\e";
    self.applyButton = [self button:[self ru:@"Применить изменения" en:@"Apply Changes"]
                             frame:NSMakeRect(570, 14, 157, 30) action:@selector(applyClicked:)];
    IGApplyThemeToButton(self.applyButton, IGThemeButtonRolePrimary);
    IGApplyThemeToButton(self.closeButton, IGThemeButtonRoleSecondary);
    IGApplyThemeToButton(self.suggestButton, IGThemeButtonRoleSecondary);
    IGApplyThemeToButton(self.backupButton, IGThemeButtonRoleSecondary);
    [self updateButtons];
}

- (void)scan {
    self.busy = YES;
    [self updateButtons];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            NSArray *items = SRScanTrackTitles(self.folder, NULL);
            NSMutableArray *result = [NSMutableArray array];
            for (NSDictionary *item in items) {
                NSMutableDictionary *row = [[item mutableCopy] autorelease];
                row[@"title"] = row[@"snapshot"][@"title"] ?: @"";
                [result addObject:row];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                self.rows = result;
                self.busy = NO;
                [self.table reloadData];
                [self updateButtons];
                if (!items) self.status.stringValue = [self ru:@"Не удалось прочитать папку." en:@"Could not read the folder."];
                else if (result.count == 0) self.status.stringValue = [self ru:@"В папке нет аудиофайлов." en:@"No audio files found."];
                else self.status.stringValue = [self ru:@"Измените нужные строки и проверьте итог перед применением."
                                                      en:@"Edit the rows you need, then review the new titles and apply."];
            });
        }
    });
}

- (BOOL)rowIsEditable:(NSDictionary *)row {
    return row[@"snapshot"] != nil && row[@"result"] == nil;
}

- (void)updateButtons {
    BOOL editable = NO, suggest = NO;
    for (NSDictionary *row in self.rows) {
        if (![self rowIsEditable:row]) continue;
        editable = YES;
        if ([row[@"title"] isEqual:row[@"snapshot"][@"title"]] &&
            [row[@"suggestion"] length] > 0 && ![row[@"suggestion"] isEqual:row[@"title"]]) suggest = YES;
    }
    self.suggestButton.enabled = !self.busy && suggest;
    self.applyButton.enabled = !self.busy && editable;
    self.closeButton.enabled = !self.busy;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.rows.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)index {
    NSDictionary *row = self.rows[index];
    if ([column.identifier isEqual:@"file"]) {
        NSURL *file = row[@"file"];
        NSString *base = [self.folder.path hasSuffix:@"/"] ? self.folder.path : [self.folder.path stringByAppendingString:@"/"];
        return [file.path hasPrefix:base] ? [file.path substringFromIndex:base.length] : file.lastPathComponent;
    }
    if ([column.identifier isEqual:@"old"]) {
        NSString *title = row[@"snapshot"][@"title"];
        return title.length ? title : @"—";
    }
    return row[@"result"] ?: (row[@"snapshot"] ? row[@"title"] : [self ru:@"Редактирование недоступно" en:@"Editing unavailable"]);
}

- (NSString *)tableView:(NSTableView *)tableView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect
             tableColumn:(NSTableColumn *)column row:(NSInteger)index mouseLocation:(NSPoint)point {
    return [column.identifier isEqual:@"file"] ? [self.rows[index][@"file"] path]
        : [self tableView:tableView objectValueForTableColumn:column row:index];
}

- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)column row:(NSInteger)index {
    return !self.busy && [column.identifier isEqual:@"new"] && [self rowIsEditable:self.rows[index]];
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(NSInteger)index {
    if (![value isKindOfClass:[NSString class]] || ![self tableView:tableView shouldEditTableColumn:column row:index]) return;
    self.rows[index][@"title"] = value;
    [self updateButtons];
}

- (void)suggestClicked:(id)sender {
    if (![self.window makeFirstResponder:self.table]) return;
    for (NSMutableDictionary *row in self.rows) {
        if ([self rowIsEditable:row] && [row[@"title"] isEqual:row[@"snapshot"][@"title"]] && [row[@"suggestion"] length]) {
            row[@"title"] = row[@"suggestion"];
        }
    }
    [self.table reloadData];
    self.status.stringValue = [self ru:@"Проверьте предложенные названия перед применением."
                                     en:@"Review the suggested titles before applying."];
    [self updateButtons];
}

- (void)closeClicked:(id)sender {
    if (!self.busy) [self.window.sheetParent endSheet:self.window];
}

- (void)backupsClicked:(id)sender {
    if (self.backupFolder) [[NSWorkspace sharedWorkspace] openURL:self.backupFolder];
}

- (void)applyClicked:(id)sender {
    if (self.busy || ![self.window makeFirstResponder:self.table]) return;
    NSMutableArray *edits = [NSMutableArray array];
    for (NSDictionary *row in self.rows) {
        if (![self rowIsEditable:row] || [row[@"title"] isEqual:row[@"snapshot"][@"title"]]) continue;
        if (!SRIsValidTrackTitle(row[@"title"])) {
            self.status.stringValue = [self ru:@"Введите непустое название для каждой изменённой строки."
                                              en:@"Enter a nonempty title for every edited row."];
            return;
        }
        [edits addObject:[[row copy] autorelease]];
    }
    if (edits.count == 0) {
        self.status.stringValue = [self ru:@"Введите новое название в нужной строке."
                                         en:@"Enter a new title in the row you want to change."];
        return;
    }
    IGOperationActivity *activity = [IGOperationActivity sharedActivity];
    if (![activity beginOperationWithIdentifier:IGTitleEditOperation]) {
        self.status.stringValue = [self ru:@"Сначала завершите текущую фоновую операцию."
                                         en:@"Finish the current background operation first."];
        return;
    }

    self.busy = YES;
    [self updateButtons];
    self.status.stringValue = [self ru:@"Сохраняем оригиналы и записываем названия…" en:@"Backing up originals and writing titles…"];
    NSURL *support = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                           inDomains:NSUserDomainMask] firstObject];
    NSURL *backups = [[support URLByAppendingPathComponent:@"Syncrosa/Backups/Track Titles" isDirectory:YES]
                      URLByAppendingPathComponent:[[NSUUID UUID] UUIDString] isDirectory:YES];
    NSString *identifier = [[NSUUID UUID] UUIDString];
    [activity saveRecoveryMarker:@{@"id": identifier, @"tool": @"Folder Fixer", @"title": @"Correct Track Titles",
                                    @"message": @"Title editing stopped before all files were processed.",
                                    @"startedAt": @([[NSDate date] timeIntervalSince1970]),
                                    @"affectedCount": @(edits.count), @"backupPath": backups.path}
                              error:NULL];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            NSMutableDictionary *results = [NSMutableDictionary dictionary];
            NSUInteger updated = 0, processed = 0;
            for (NSDictionary *item in edits) {
                @autoreleasepool {
                    NSError *error = nil;
                    NSURL *file = item[@"file"];
                    if (SRReplaceTrackTitle(file, item[@"snapshot"], item[@"title"], backups, &error)) {
                        updated++;
                        results[file] = item[@"title"];
                    } else {
                        results[file] = [error code] == 3
                            ? [self ru:@"Файл изменился после просмотра" en:@"File changed after preview"]
                            : [self ru:@"Не удалось записать тег" en:@"Could not write title"];
                    }
                }
                processed++;
                [activity updateProgress:(double)processed / (double)edits.count forIdentifier:IGTitleEditOperation];
                NSUInteger completed = processed;
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.status.stringValue = [NSString stringWithFormat:[self ru:@"Обработано %lu из %lu" en:@"Processed %lu of %lu"],
                                               (unsigned long)completed, (unsigned long)edits.count];
                });
            }
            NSUInteger failed = edits.count - updated;
            [activity finishRecoveryMarkerWithIdentifier:identifier error:NULL];
            [activity finishOperationWithIdentifier:IGTitleEditOperation];
            BOOL hasBackups = [[NSFileManager defaultManager] fileExistsAtPath:backups.path];
            dispatch_async(dispatch_get_main_queue(), ^{
                for (NSMutableDictionary *row in self.rows) {
                    NSString *result = results[row[@"file"]];
                    if (result) row[@"result"] = result;
                }
                self.backupFolder = hasBackups ? backups : nil;
                self.backupButton.hidden = !hasBackups;
                self.busy = NO;
                self.status.stringValue = [NSString stringWithFormat:[self ru:@"Изменено: %lu. Ошибок: %lu." en:@"Updated: %lu. Failed: %lu."],
                                           (unsigned long)updated, (unsigned long)failed];
                [self.table reloadData];
                [self updateButtons];
            });
        }
    });
}

@end
