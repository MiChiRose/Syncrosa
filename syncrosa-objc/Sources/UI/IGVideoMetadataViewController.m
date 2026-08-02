#import "IGVideoMetadataViewController.h"
#import "IGiTunesService.h"
#import "IGNotificationView.h"
#import "IGOperationActivity.h"
#import "IGTheme.h"
#import "IGMediaFixerManager.h"
#import "IGLocalizationService.h"
#import "IGIconProvider.h"
#import "IGVideoFileMetadataService.h"

@interface IGVideoMetadataViewController () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSArray *tracks;
@property (nonatomic, strong) NSButton *refreshButton;
@property (nonatomic, strong) NSPopUpButton *sourcePopup;
@property (nonatomic, strong) NSTextField *subtitleLabel;
@property (nonatomic, strong) NSPopUpButton *kindPopup;
@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSTextField *showField;
@property (nonatomic, strong) NSTextField *seasonField;
@property (nonatomic, strong) NSTextField *episodeField;
@property (nonatomic, strong) NSTextField *genreField;
@property (nonatomic, strong) NSTextField *yearField;
@property (nonatomic, strong) NSTextField *descriptionField;
@property (nonatomic, strong) NSTextField *directorField;
@property (nonatomic, strong) NSTextField *artworkLabel;
@property (nonatomic, strong) NSButton *artworkButton;
@property (nonatomic, strong) NSButton *searchButton;
@property (nonatomic, strong) NSButton *applyButton;
@property (nonatomic, strong) NSPopUpButton *titleLanguagePopup;
@property (nonatomic, strong) NSProgressIndicator *spinner;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSURL *selectedArtworkURL;
@property (nonatomic, strong) NSURL *selectedFolderURL;
@property (nonatomic, strong) NSDictionary *selectedCatalogCandidate;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, assign) BOOL selectedArtworkTemporary;
- (void)applyCatalogCandidate:(NSDictionary *)candidate;
- (void)removeTemporaryArtworkIfNeeded;
- (void)updateTitleFromLanguageChoice;
- (BOOL)isFolderMode;
- (void)sourceChanged:(id)sender;
- (void)loadFolderAtURL:(NSURL *)folderURL;
- (void)readFolderFiles:(NSArray *)fileURLs index:(NSInteger)index results:(NSMutableArray *)results;
@end

static NSTextField *IGVideoLabel(NSString *title, NSRect frame) {
    NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    label.stringValue = title ?: @"";
    label.font = [NSFont systemFontOfSize:11.0];
    label.textColor = IGThemeMutedTextColor();
    label.editable = NO;
    label.selectable = NO;
    label.bordered = NO;
    label.drawsBackground = NO;
    return label;
}

static NSTextField *IGVideoField(NSRect frame) {
    NSTextField *field = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    field.bezelStyle = NSTextFieldRoundedBezel;
    return field;
}

static NSBox *IGVideoPanel(NSRect frame) {
    NSBox *panel = [[[NSBox alloc] initWithFrame:frame] autorelease];
    panel.boxType = NSBoxCustom;
    panel.titlePosition = NSNoTitle;
    panel.borderType = NSLineBorder;
    panel.borderWidth = 1.0;
    panel.cornerRadius = 9.0;
    panel.fillColor = IGThemePanelColor();
    panel.borderColor = IGThemeControlBorderColor();
    panel.transparent = NO;
    return panel;
}

@interface IGVideoMetadataChoiceController : NSObject
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSArray *results;
@property (nonatomic, strong) NSMutableArray *matchButtons;
@property (nonatomic, strong) NSMutableArray *titleButtons;
@property (nonatomic, strong) NSMutableArray *artworkButtons;
@property (nonatomic, strong) NSBox *titleBox;
@property (nonatomic, strong) NSBox *artworkBox;
@property (nonatomic, strong) NSButton *useButton;
@property (nonatomic, strong) NSDictionary *choice;
@property (nonatomic, assign) NSInteger selectedResultIndex;
@property (nonatomic, assign) NSInteger selectedLanguage;
@property (nonatomic, assign) NSInteger selectedArtwork;
@property (nonatomic, assign) BOOL hasCurrentArtwork;
+ (NSDictionary *)runWithResults:(NSArray *)results hasCurrentArtwork:(BOOL)hasCurrentArtwork;
@end

@implementation IGVideoMetadataChoiceController

- (NSBox *)cardWithFrame:(NSRect)frame {
    NSBox *card = [[[NSBox alloc] initWithFrame:frame] autorelease];
    card.boxType = NSBoxCustom;
    card.titlePosition = NSNoTitle;
    card.borderType = NSLineBorder;
    card.borderWidth = 1.0;
    card.cornerRadius = 8.0;
    card.fillColor = IGThemePanelColor();
    card.borderColor = IGThemeControlBorderColor();
    card.transparent = NO;
    return card;
}

- (NSTextField *)stepLabel:(NSString *)text frame:(NSRect)frame {
    NSTextField *label = IGVideoLabel(text, frame);
    label.font = [NSFont boldSystemFontOfSize:10.0];
    label.textColor = IGThemeAccentColor();
    return label;
}

+ (NSDictionary *)runWithResults:(NSArray *)results hasCurrentArtwork:(BOOL)hasCurrentArtwork {
    IGVideoMetadataChoiceController *controller = [[self alloc] init];
    controller.results = results;
    controller.hasCurrentArtwork = hasCurrentArtwork;
    controller.selectedResultIndex = -1;
    controller.selectedLanguage = -1;
    controller.selectedArtwork = -1;
    [controller buildWindow];
    [controller.window center];
    [controller.window makeKeyAndOrderFront:nil];
    [NSApp runModalForWindow:controller.window];
    [controller.window orderOut:nil];
    NSDictionary *choice = [[controller.choice retain] autorelease];
    [controller release];
    return choice;
}

- (NSButton *)radioButtonWithTitle:(NSString *)title frame:(NSRect)frame action:(SEL)action tag:(NSInteger)tag {
    NSButton *button = [[[NSButton alloc] initWithFrame:frame] autorelease];
    button.buttonType = NSRadioButton;
    button.title = title ?: @"";
    button.target = self;
    button.action = action;
    button.tag = tag;
    button.font = [NSFont systemFontOfSize:11.0];
    return button;
}

- (void)buildWindow {
    BOOL russian = [[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];
    NSInteger visibleResultCount = 0;
    for (NSDictionary *result in self.results) {
        if ([[result objectForKey:@"displayTitle"] length] > 0) visibleResultCount++;
    }
    CGFloat matchHeight = MIN(166.0, MAX(80.0, visibleResultCount * 30.0 + 40.0));
    CGFloat windowHeight = 360.0 + matchHeight;
    self.window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, windowHeight)
                                                styleMask:NSTitledWindowMask
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO] autorelease];
    self.window.title = russian ? @"Выбор метаданных фильма" : @"Choose Video Metadata";
    self.window.backgroundColor = IGThemeWindowColor();
    NSView *content = self.window.contentView;
    NSTextField *title = IGVideoLabel(russian ? @"Выберите метаданные фильма" : @"Choose video metadata", NSMakeRect(28, windowHeight - 48, 584, 26));
    title.font = [NSFont boldSystemFontOfSize:18.0];
    title.textColor = IGThemeTextColor();
    [content addSubview:title];
    NSTextField *subtitle = IGVideoLabel(russian ? @"Проверьте фильм, название и обложку до внесения изменений в iTunes."
                                                  : @"Review the movie, title, and artwork before anything changes in iTunes.",
                                         NSMakeRect(28, windowHeight - 70, 584, 20));
    [content addSubview:subtitle];

    [content addSubview:[self stepLabel:(russian ? @"1   НАЙДЕННЫЙ ФИЛЬМ" : @"1   MOVIE MATCH") frame:NSMakeRect(28, windowHeight - 101, 584, 18)]];
    NSBox *matchBox = [self cardWithFrame:NSMakeRect(24, 256, 592, matchHeight)];
    [content addSubview:matchBox];
    NSTextField *matchHelp = IGVideoLabel(russian ? @"Выберите, какому фильму соответствует название из iTunes."
                                                  : @"Choose which movie the title found in iTunes refers to.",
                                             NSMakeRect(14, matchHeight - 30, 560, 18));
    [[matchBox contentView] addSubview:matchHelp];
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(10, 7, 572, matchHeight - 38)] autorelease];
    scroll.hasVerticalScroller = visibleResultCount * 30.0 + 8.0 > matchHeight - 38.0;
    scroll.borderType = NSNoBorder;
    scroll.drawsBackground = NO;
    scroll.verticalScrollElasticity = NSScrollElasticityNone;
    scroll.horizontalScrollElasticity = NSScrollElasticityNone;
    CGFloat documentHeight = MAX(matchHeight - 38.0, visibleResultCount * 30.0 + 8.0);
    NSView *document = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 552, documentHeight)] autorelease];
    self.matchButtons = [NSMutableArray array];
    NSInteger index = 0;
    NSInteger sourceIndex = 0;
    for (NSDictionary *result in self.results) {
        NSString *display = [result objectForKey:@"displayTitle"];
        if ([display length] == 0) {
            sourceIndex++;
            continue;
        }
        CGFloat y = documentHeight - 32.0 - index * 30.0;
        NSButton *button = [self radioButtonWithTitle:display frame:NSMakeRect(8, y, 530, 24)
                                               action:@selector(matchChanged:) tag:sourceIndex];
        [document addSubview:button];
        [self.matchButtons addObject:button];
        index++;
        sourceIndex++;
    }
    scroll.documentView = document;
    [matchBox addSubview:scroll];

    [content addSubview:[self stepLabel:(russian ? @"2   НАЗВАНИЕ" : @"2   TITLE") frame:NSMakeRect(28, 226, 584, 18)]];
    self.titleBox = [self cardWithFrame:NSMakeRect(24, 144, 592, 76)];
    [content addSubview:self.titleBox];
    [content addSubview:[self stepLabel:(russian ? @"3   ОБЛОЖКА" : @"3   ARTWORK") frame:NSMakeRect(28, 114, 584, 18)]];
    self.artworkBox = [self cardWithFrame:NSMakeRect(24, 58, 592, 50)];
    [content addSubview:self.artworkBox];

    NSBox *separator = [[[NSBox alloc] initWithFrame:NSMakeRect(24, 47, 592, 1)] autorelease];
    separator.boxType = NSBoxSeparator;
    [content addSubview:separator];
    NSButton *cancel = [[[NSButton alloc] initWithFrame:NSMakeRect(410, 10, 96, 30)] autorelease];
    cancel.title = russian ? @"Отмена" : @"Cancel";
    cancel.bezelStyle = NSRoundedBezelStyle;
    cancel.target = self;
    cancel.action = @selector(cancelClicked:);
    IGApplyThemeToButton(cancel, IGThemeButtonRoleSecondary);
    [content addSubview:cancel];
    self.useButton = [[[NSButton alloc] initWithFrame:NSMakeRect(516, 10, 100, 30)] autorelease];
    self.useButton.title = russian ? @"Продолжить" : @"Continue";
    self.useButton.bezelStyle = NSRoundedBezelStyle;
    self.useButton.target = self;
    self.useButton.action = @selector(useClicked:);
    self.useButton.enabled = NO;
    IGApplyThemeToButton(self.useButton, IGThemeButtonRolePrimary);
    [content addSubview:self.useButton];

    if ([self.matchButtons count] == 1) {
        NSButton *only = [self.matchButtons objectAtIndex:0];
        only.state = NSOnState;
        [self selectResultAtIndex:only.tag];
    } else {
        [self showInstruction:(russian ? @"Сначала выберите найденный фильм выше." : @"Choose one real catalog match above.") inBox:self.titleBox];
        [self showInstruction:(russian ? @"Варианты обложки появятся после выбора фильма." : @"Artwork choices appear after a match is selected.") inBox:self.artworkBox];
    }
    IGApplyThemeToWindow(self.window);
}

- (void)removeChoiceViewsFromBox:(NSBox *)box {
    NSArray *views = [[[[box contentView] subviews] copy] autorelease];
    for (NSView *view in views) {
        [view removeFromSuperview];
    }
}

- (void)showInstruction:(NSString *)text inBox:(NSBox *)box {
    [self removeChoiceViewsFromBox:box];
    NSTextField *label = IGVideoLabel(text, NSMakeRect(12, 8, NSWidth(box.bounds) - 24, 20));
    [[box contentView] addSubview:label];
}

- (void)setExclusiveSelection:(NSButton *)sender buttons:(NSArray *)buttons {
    for (NSButton *button in buttons) button.state = button == sender ? NSOnState : NSOffState;
}

- (void)matchChanged:(NSButton *)sender {
    [self setExclusiveSelection:sender buttons:self.matchButtons];
    [self selectResultAtIndex:sender.tag];
}

- (void)selectResultAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)[self.results count]) return;
    self.selectedResultIndex = index;
    self.selectedLanguage = -1;
    self.selectedArtwork = -1;
    NSDictionary *candidate = [self.results objectAtIndex:index];
    BOOL russian = [[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];

    [self removeChoiceViewsFromBox:self.titleBox];
    self.titleButtons = [NSMutableArray array];
    NSString *localized = [candidate objectForKey:@"localizedName"];
    NSString *original = [candidate objectForKey:@"originalName"];
    NSMutableArray *titleOptions = [NSMutableArray array];
    if ([localized length] > 0) [titleOptions addObject:@{ @"title": [(russian ? @"Русский: " : @"Russian: ") stringByAppendingString:localized], @"tag": @0 }];
    if ([original length] > 0 && ![original isEqualToString:localized]) [titleOptions addObject:@{ @"title": [(russian ? @"Оригинальное: " : @"Original: ") stringByAppendingString:original], @"tag": @1 }];
    NSInteger row = 0;
    for (NSDictionary *option in titleOptions) {
        NSButton *button = [self radioButtonWithTitle:[option objectForKey:@"title"]
                                               frame:NSMakeRect(12, 34 - row * 27, 560, 24)
                                              action:@selector(titleChanged:)
                                                 tag:[[option objectForKey:@"tag"] integerValue]];
        [[self.titleBox contentView] addSubview:button];
        [self.titleButtons addObject:button];
        row++;
    }
    if ([self.titleButtons count] == 1) {
        NSButton *only = [self.titleButtons objectAtIndex:0];
        only.state = NSOnState;
        self.selectedLanguage = only.tag;
    }

    [self removeChoiceViewsFromBox:self.artworkBox];
    self.artworkButtons = [NSMutableArray array];
    NSString *artworkURL = [candidate objectForKey:@"artworkURL"];
    NSMutableArray *artOptions = [NSMutableArray array];
    if ([artworkURL length] > 0) {
        NSInteger width = [[candidate objectForKey:@"artworkWidth"] integerValue];
        NSInteger height = [[candidate objectForKey:@"artworkHeight"] integerValue];
        NSString *size = width > 0 && height > 0 ? [NSString stringWithFormat:@" (%ldx%ld)", (long)width, (long)height] : @"";
        [artOptions addObject:@{ @"title": [(russian ? @"Каноническая основная обложка IMDb" : @"Canonical IMDb primary poster") stringByAppendingString:size], @"tag": @1 }];
    }
    if (self.hasCurrentArtwork) [artOptions addObject:@{ @"title": russian ? @"Сохранить текущую обложку iTunes" : @"Keep current iTunes artwork", @"tag": @0 }];
    row = 0;
    for (NSDictionary *option in artOptions) {
        NSButton *button = [self radioButtonWithTitle:[option objectForKey:@"title"]
                                               frame:NSMakeRect(12 + row * 292, 8, 286, 24)
                                              action:@selector(artworkChanged:)
                                                 tag:[[option objectForKey:@"tag"] integerValue]];
        [[self.artworkBox contentView] addSubview:button];
        [self.artworkButtons addObject:button];
        row++;
    }
    if ([self.artworkButtons count] == 1) {
        NSButton *only = [self.artworkButtons objectAtIndex:0];
        only.state = NSOnState;
        self.selectedArtwork = only.tag;
    } else if ([self.artworkButtons count] == 0) {
        self.selectedArtwork = -2;
        [self showInstruction:(russian ? @"Обложки нет, но остальные метаданные можно применить."
                                       : @"No catalog or current artwork is available; metadata can still be applied.") inBox:self.artworkBox];
    }
    [self updateUseButton];
}

- (void)titleChanged:(NSButton *)sender {
    [self setExclusiveSelection:sender buttons:self.titleButtons];
    self.selectedLanguage = sender.tag;
    [self updateUseButton];
}

- (void)artworkChanged:(NSButton *)sender {
    [self setExclusiveSelection:sender buttons:self.artworkButtons];
    self.selectedArtwork = sender.tag;
    [self updateUseButton];
}

- (void)updateUseButton {
    self.useButton.enabled = self.selectedResultIndex >= 0 && self.selectedLanguage >= 0 && self.selectedArtwork != -1;
}

- (void)useClicked:(id)sender {
    (void)sender;
    if (![self.useButton isEnabled]) return;
    NSMutableDictionary *choice = [[[self.results objectAtIndex:self.selectedResultIndex] mutableCopy] autorelease];
    [choice setObject:(self.selectedLanguage == 0 ? @"Russian" : @"Original") forKey:@"chosenTitleLanguage"];
    [choice setObject:[NSNumber numberWithBool:self.selectedArtwork == 1] forKey:@"useCatalogArtwork"];
    self.choice = choice;
    [NSApp stopModal];
}

- (void)cancelClicked:(id)sender {
    (void)sender;
    self.choice = nil;
    [NSApp abortModal];
}

- (void)dealloc {
#if !__has_feature(objc_arc)
    [_window release];
    [_results release];
    [_matchButtons release];
    [_titleButtons release];
    [_artworkButtons release];
    [_titleBox release];
    [_artworkBox release];
    [_useButton release];
    [_choice release];
    [super dealloc];
#endif
}

@end

@implementation IGVideoMetadataViewController

- (void)loadView {
    self.view = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 480)] autorelease];
    IGInstallThemedContentBackground(self.view);
    BOOL russian = [[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];

    [self.view addSubview:IGVideoPanel(NSMakeRect(16, 292, 548, 116))];
    [self.view addSubview:IGVideoPanel(NSMakeRect(16, 36, 548, 206))];

    NSTextField *title = IGVideoLabel(russian ? @"Метаданные видео" : @"Video Metadata", NSMakeRect(20, 438, 540, 28));
    title.font = [NSFont boldSystemFontOfSize:18.0];
    title.textColor = IGThemeTextColor();
    [self.view addSubview:title];

    self.subtitleLabel = IGVideoLabel(russian ? @"Найдите точные данные фильма, проверьте их и только затем сохраните в iTunes."
                                                    : @"Find accurate movie details, review them, then save them to iTunes.", NSMakeRect(20, 416, 540, 18));
    [self.view addSubview:self.subtitleLabel];

    NSTextField *libraryHeading = IGVideoLabel(russian ? @"Фильмы и сериалы" : @"Movies & TV Shows", NSMakeRect(28, 384, 320, 18));
    libraryHeading.font = [NSFont boldSystemFontOfSize:12.0];
    libraryHeading.textColor = IGThemeTextColor();
    [self.view addSubview:libraryHeading];
    [self.view addSubview:IGVideoLabel(russian ? @"Источник" : @"Source", NSMakeRect(376, 385, 52, 18))];
    self.sourcePopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(426, 378, 126, 26) pullsDown:NO] autorelease];
    [self.sourcePopup addItemsWithTitles:russian ? @[@"iTunes", @"Папка / Диск"] : @[@"iTunes", @"Folder / Drive"]];
    self.sourcePopup.target = self;
    self.sourcePopup.action = @selector(sourceChanged:);
    [self.view addSubview:self.sourcePopup];
    NSTextField *detailsHeading = IGVideoLabel(russian ? @"Данные выбранного видео" : @"Selected Video Details", NSMakeRect(28, 216, 510, 18));
    detailsHeading.font = [NSFont boldSystemFontOfSize:12.0];
    detailsHeading.textColor = IGThemeTextColor();
    [self.view addSubview:detailsHeading];

    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(28, 300, 524, 82)] autorelease];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSNoBorder;
    scroll.drawsBackground = YES;
    scroll.verticalScrollElasticity = NSScrollElasticityNone;
    scroll.horizontalScrollElasticity = NSScrollElasticityNone;
    scroll.backgroundColor = IGThemePanelInsetColor();
    self.tableView = [[[NSTableView alloc] initWithFrame:scroll.bounds] autorelease];
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"video"] autorelease];
    column.width = 504.0;
    [[column headerCell] setStringValue:russian ? @"Видео" : @"Video"];
    [self.tableView addTableColumn:column];
    self.tableView.headerView = nil;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 28.0;
    self.tableView.backgroundColor = IGThemePanelInsetColor();
    self.tableView.usesAlternatingRowBackgroundColors = YES;
    scroll.documentView = self.tableView;
    [self.view addSubview:scroll];

    self.refreshButton = [[[NSButton alloc] initWithFrame:NSMakeRect(20, 252, 174, 30)] autorelease];
    self.refreshButton.title = russian ? @"Обновить фильмы и сериалы" : @"Refresh Movies & TV Shows";
    self.refreshButton.bezelStyle = NSRoundedBezelStyle;
    self.refreshButton.target = self;
    self.refreshButton.action = @selector(refreshClicked:);
    [self.view addSubview:self.refreshButton];
    IGApplyThemeToButton(self.refreshButton, IGThemeButtonRoleSecondary);
    IGConfigureIconButton(self.refreshButton, @"refresh", self.refreshButton.title, NO);

    self.searchButton = [[[NSButton alloc] initWithFrame:NSMakeRect(203, 252, 174, 30)] autorelease];
    self.searchButton.title = russian ? @"Найти метаданные" : @"Find Metadata";
    self.searchButton.bezelStyle = NSRoundedBezelStyle;
    self.searchButton.target = self;
    self.searchButton.action = @selector(searchMetadataClicked:);
    [self.view addSubview:self.searchButton];
    IGApplyThemeToButton(self.searchButton, IGThemeButtonRoleSecondary);
    IGConfigureIconButton(self.searchButton, @"search", self.searchButton.title, NO);

    self.artworkButton = [[[NSButton alloc] initWithFrame:NSMakeRect(386, 252, 174, 30)] autorelease];
    self.artworkButton.title = russian ? @"Выбрать изображение" : @"Choose Image";
    self.artworkButton.bezelStyle = NSRoundedBezelStyle;
    self.artworkButton.target = self;
    self.artworkButton.action = @selector(chooseArtworkClicked:);
    [self.view addSubview:self.artworkButton];
    IGApplyThemeToButton(self.artworkButton, IGThemeButtonRoleSecondary);
    IGConfigureIconButton(self.artworkButton, @"artwork", self.artworkButton.title, NO);

    [self.view addSubview:IGVideoLabel(russian ? @"Тип" : @"Type", NSMakeRect(28, 188, 40, 18))];
    self.kindPopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(68, 183, 122, 26) pullsDown:NO] autorelease];
    [self.kindPopup addItemsWithTitles:russian ? @[@"Фильм", @"Сериал"] : @[@"Movie", @"TV Show"]];
    self.kindPopup.target = self;
    self.kindPopup.action = @selector(kindChanged:);
    [self.view addSubview:self.kindPopup];

    [self.view addSubview:IGVideoLabel(russian ? @"Название" : @"Title", NSMakeRect(204, 188, 64, 18))];
    self.nameField = IGVideoField(NSMakeRect(268, 184, 280, 25));
    [self.view addSubview:self.nameField];

    [self.view addSubview:IGVideoLabel(russian ? @"Сериал" : @"Show", NSMakeRect(28, 154, 40, 18))];
    self.showField = IGVideoField(NSMakeRect(68, 150, 176, 25));
    [self.view addSubview:self.showField];

    [self.view addSubview:IGVideoLabel(russian ? @"Сезон" : @"Season", NSMakeRect(258, 154, 48, 18))];
    self.seasonField = IGVideoField(NSMakeRect(306, 150, 54, 25));
    [self.view addSubview:self.seasonField];
    [self.view addSubview:IGVideoLabel(russian ? @"Эпизод" : @"Episode", NSMakeRect(374, 154, 54, 18))];
    self.episodeField = IGVideoField(NSMakeRect(430, 150, 118, 25));
    [self.view addSubview:self.episodeField];

    [self.view addSubview:IGVideoLabel(russian ? @"Жанр" : @"Genre", NSMakeRect(28, 120, 40, 18))];
    self.genreField = IGVideoField(NSMakeRect(68, 116, 156, 25));
    [self.view addSubview:self.genreField];
    [self.view addSubview:IGVideoLabel(russian ? @"Год" : @"Year", NSMakeRect(238, 120, 34, 18))];
    self.yearField = IGVideoField(NSMakeRect(272, 116, 66, 25));
    [self.view addSubview:self.yearField];

    [self.view addSubview:IGVideoLabel(russian ? @"Режиссёр" : @"Director", NSMakeRect(352, 120, 58, 18))];
    self.directorField = IGVideoField(NSMakeRect(412, 116, 136, 25));
    [self.view addSubview:self.directorField];

    [self.view addSubview:IGVideoLabel(russian ? @"Описание" : @"Description", NSMakeRect(28, 86, 68, 18))];
    self.descriptionField = IGVideoField(NSMakeRect(98, 69, 450, 38));
    [[self.descriptionField cell] setLineBreakMode:NSLineBreakByWordWrapping];
    [self.view addSubview:self.descriptionField];

    [self.view addSubview:IGVideoLabel(russian ? @"Язык названия" : @"Title language", NSMakeRect(28, 48, 86, 18))];
    self.titleLanguagePopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(114, 43, 152, 26) pullsDown:NO] autorelease];
    [self.titleLanguagePopup addItemsWithTitles:russian ? @[@"Русский", @"Оригинальный"] : @[@"Russian", @"Original"]];
    self.titleLanguagePopup.target = self;
    self.titleLanguagePopup.action = @selector(titleLanguageChanged:);
    [self.view addSubview:self.titleLanguagePopup];

    self.artworkLabel = IGVideoLabel(russian ? @"Новая обложка не выбрана" : @"No new artwork", NSMakeRect(282, 48, 266, 18));
    [[self.artworkLabel cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [self.view addSubview:self.artworkLabel];

    self.applyButton = [[[NSButton alloc] initWithFrame:NSMakeRect(392, 3, 168, 30)] autorelease];
    self.applyButton.title = russian ? @"Сохранить в iTunes" : @"Apply to iTunes";
    self.applyButton.bezelStyle = NSTexturedRoundedBezelStyle;
    self.applyButton.target = self;
    self.applyButton.action = @selector(applyClicked:);
    [self.view addSubview:self.applyButton];
    IGApplyThemeToButton(self.applyButton, IGThemeButtonRolePrimary);

    self.spinner = [[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(366, 9, 18, 18)] autorelease];
    self.spinner.style = NSProgressIndicatorSpinningStyle;
    self.spinner.hidden = YES;
    [self.view addSubview:self.spinner];

    self.statusLabel = IGVideoLabel(russian ? @"Обновите список, чтобы прочитать видео из iTunes."
                                            : @"Refresh to read video tracks from iTunes.", NSMakeRect(20, 8, 338, 22));
    [[self.statusLabel cell] setLineBreakMode:NSLineBreakByTruncatingTail];
    [[self.statusLabel cell] setUsesSingleLineMode:YES];
    [self.view addSubview:self.statusLabel];

    self.tracks = [NSArray array];
    [self updateControls];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return (NSInteger)[self.tracks count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    (void)tableView;
    (void)tableColumn;
    if (row < 0 || row >= (NSInteger)[self.tracks count]) return @"";
    NSDictionary *track = [self.tracks objectAtIndex:row];
    NSString *name = [track objectForKey:@"name"] ?: @"Untitled";
    NSString *kind = [track objectForKey:@"videoKind"] ?: @"Video";
    return [NSString stringWithFormat:@"%@  —  %@", name, kind];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    (void)notification;
    [self populateSelectedTrack];
}

- (NSDictionary *)selectedTrack {
    NSInteger row = [self.tableView selectedRow];
    return row >= 0 && row < (NSInteger)[self.tracks count] ? [self.tracks objectAtIndex:row] : nil;
}

- (BOOL)isFolderMode {
    return [self.sourcePopup indexOfSelectedItem] == 1;
}

- (void)sourceChanged:(id)sender {
    (void)sender;
    [self removeTemporaryArtworkIfNeeded];
    self.selectedArtworkURL = nil;
    self.selectedCatalogCandidate = nil;
    self.tracks = [NSArray array];
    [self.tableView reloadData];
    self.selectedFolderURL = nil;
    BOOL russian = [[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];
    self.refreshButton.title = [self isFolderMode] ? (russian ? @"Выбрать папку или диск" : @"Choose Folder or Drive")
                                                   : (russian ? @"Обновить фильмы и сериалы" : @"Refresh Movies & TV Shows");
    IGConfigureIconButton(self.refreshButton, [self isFolderMode] ? @"folder" : @"refresh", self.refreshButton.title, NO);
    self.applyButton.title = [self isFolderMode] ? (russian ? @"Сохранить в файл" : @"Save to Video File")
                                                 : (russian ? @"Сохранить в iTunes" : @"Apply to iTunes");
    self.subtitleLabel.stringValue = [self isFolderMode] ? (russian ? @"Исправляйте видео в папках и на внешних дисках с сохранением исходника."
                                                                     : @"Fix videos in folders and on external drives while preserving the original.")
                                                         : (russian ? @"Найдите точные данные фильма, проверьте их и только затем сохраните в iTunes."
                                                                     : @"Find accurate movie details, review them, then save them to iTunes.");
    self.statusLabel.stringValue = [self isFolderMode] ? (russian ? @"Выберите папку или внешний диск с файлами MP4/M4V."
                                                                   : @"Choose a folder or external drive containing MP4/M4V files.")
                                                       : (russian ? @"Обновите список, чтобы прочитать видео из iTunes."
                                                                   : @"Refresh to read video tracks from iTunes.");
    [self populateSelectedTrack];
}

- (void)populateSelectedTrack {
    NSDictionary *track = [self selectedTrack];
    [self removeTemporaryArtworkIfNeeded];
    self.selectedArtworkURL = nil;
    self.selectedCatalogCandidate = nil;
    self.artworkLabel.stringValue = [[track objectForKey:@"hasArtwork"] boolValue] ? @"Current artwork present" : @"No current artwork";
    self.nameField.stringValue = [track objectForKey:@"name"] ?: @"";
    self.showField.stringValue = [track objectForKey:@"show"] ?: @"";
    self.seasonField.stringValue = track ? [[track objectForKey:@"seasonNumber"] stringValue] : @"";
    self.episodeField.stringValue = track ? [[track objectForKey:@"episodeNumber"] stringValue] : @"";
    self.genreField.stringValue = [track objectForKey:@"genre"] ?: @"";
    self.yearField.stringValue = track ? [[track objectForKey:@"year"] stringValue] : @"";
    self.directorField.stringValue = [track objectForKey:@"director"] ?: @"";
    NSString *longDescription = [track objectForKey:@"longDescription"];
    self.descriptionField.stringValue = [longDescription length] > 0 ? longDescription : ([track objectForKey:@"description"] ?: @"");
    [self.kindPopup selectItemAtIndex:[[track objectForKey:@"videoKind"] isEqualToString:@"TV Show"] ? 1 : 0];
    [self.titleLanguagePopup selectItemAtIndex:1];
    [self updateControls];
}

- (void)titleLanguageChanged:(id)sender {
    (void)sender;
    [self updateTitleFromLanguageChoice];
}

- (void)updateTitleFromLanguageChoice {
    NSString *localizedName = [self.selectedCatalogCandidate objectForKey:@"localizedName"];
    NSString *originalName = [self.selectedCatalogCandidate objectForKey:@"originalName"];
    BOOL wantsRussian = [self.titleLanguagePopup indexOfSelectedItem] == 0;
    NSString *chosenName = wantsRussian && [localizedName length] > 0 ? localizedName : originalName;
    if ([chosenName length] > 0) {
        if ([[self.selectedCatalogCandidate objectForKey:@"videoKind"] isEqualToString:@"TV Show"]) {
            self.showField.stringValue = chosenName;
        } else {
            self.nameField.stringValue = chosenName;
        }
    }
    NSString *genre = wantsRussian ? [self.selectedCatalogCandidate objectForKey:@"localizedGenre"] : [self.selectedCatalogCandidate objectForKey:@"originalGenre"];
    NSString *description = wantsRussian ? [self.selectedCatalogCandidate objectForKey:@"localizedDescription"] : [self.selectedCatalogCandidate objectForKey:@"originalDescription"];
    NSString *director = wantsRussian ? [self.selectedCatalogCandidate objectForKey:@"localizedDirector"] : [self.selectedCatalogCandidate objectForKey:@"originalDirector"];
    if ([genre length] == 0) genre = [self.selectedCatalogCandidate objectForKey:@"genre"];
    if ([description length] == 0) description = [self.selectedCatalogCandidate objectForKey:@"description"];
    if ([director length] == 0) director = [self.selectedCatalogCandidate objectForKey:@"director"];
    self.genreField.stringValue = genre ?: @"";
    self.descriptionField.stringValue = description ?: @"";
    self.directorField.stringValue = director ?: @"";
}

- (void)kindChanged:(id)sender {
    (void)sender;
    [self updateControls];
}

- (void)updateControls {
    BOOL selected = [self selectedTrack] != nil;
    BOOL television = [self.kindPopup indexOfSelectedItem] == 1;
    self.refreshButton.enabled = !self.busy;
    self.sourcePopup.enabled = !self.busy;
    self.kindPopup.enabled = selected && !self.busy;
    self.nameField.enabled = selected && !self.busy;
    self.showField.enabled = selected && television && !self.busy;
    self.seasonField.enabled = selected && television && !self.busy;
    self.episodeField.enabled = selected && television && !self.busy;
    self.genreField.enabled = selected && !self.busy;
    self.yearField.enabled = selected && !self.busy;
    self.directorField.enabled = selected && !self.busy;
    self.descriptionField.enabled = selected && !self.busy;
    self.artworkButton.enabled = selected && !self.busy;
    self.searchButton.enabled = selected && !self.busy && [self.nameField.stringValue length] > 0;
    self.applyButton.enabled = selected && !self.busy && [self.nameField.stringValue length] > 0;
    self.titleLanguagePopup.enabled = selected && !self.busy && self.selectedCatalogCandidate != nil;
}

- (BOOL)beginActivity {
    if (![[IGOperationActivity sharedActivity] beginOperationWithIdentifier:IGOperationActivityVideoMetadataIdentifier]) {
        [IGNotificationView showInView:self.view message:@"Finish the current background operation first." isError:YES];
        return NO;
    }
    self.busy = YES;
    self.spinner.hidden = NO;
    [self.spinner startAnimation:nil];
    [self updateControls];
    return YES;
}

- (void)finishActivity {
    [[IGOperationActivity sharedActivity] finishOperationWithIdentifier:IGOperationActivityVideoMetadataIdentifier];
    self.busy = NO;
    [self.spinner stopAnimation:nil];
    self.spinner.hidden = YES;
    [self updateControls];
}

- (void)refreshClicked:(id)sender {
    (void)sender;
    if ([self isFolderMode]) {
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        panel.canChooseFiles = NO;
        panel.canChooseDirectories = YES;
        panel.allowsMultipleSelection = NO;
        if ([panel runModal] == NSOKButton) {
            self.selectedFolderURL = [[panel URLs] firstObject];
            [self loadFolderAtURL:self.selectedFolderURL];
        }
        return;
    }
    if (![self beginActivity]) return;
    self.statusLabel.stringValue = @"Reading movies and TV shows from iTunes...";
    [[IGiTunesService sharedService] fetchVideoTracksWithCompletion:^(NSArray *tracks, NSString *errorMessage) {
        self.tracks = tracks ?: [NSArray array];
        [self.tableView reloadData];
        if ([self.tracks count] > 0) [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        self.statusLabel.stringValue = errorMessage ?: [NSString stringWithFormat:@"Loaded %ld video tracks.", (long)[self.tracks count]];
        [self finishActivity];
        if (errorMessage) [IGNotificationView showInView:self.view message:errorMessage isError:YES];
    }];
}

- (void)loadFolderAtURL:(NSURL *)folderURL {
    if (![folderURL isFileURL] || ![self beginActivity]) return;
    BOOL russian = [[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];
    self.statusLabel.stringValue = russian ? @"Ищу видео MP4/M4V в папке…" : @"Scanning folder for MP4/M4V videos...";
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *fileURLs = [IGVideoFileMetadataService videoFileURLsInDirectory:folderURL];
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([fileURLs count] == 0) {
                self.tracks = [NSArray array];
                [self.tableView reloadData];
                self.statusLabel.stringValue = russian ? @"В этой папке не найдено видео MP4 или M4V."
                                                       : @"No MP4 or M4V videos were found in this folder.";
                [self finishActivity];
                return;
            }
            self.statusLabel.stringValue = russian ? [NSString stringWithFormat:@"Читаю метаданные: %ld видео…", (long)[fileURLs count]]
                                                   : [NSString stringWithFormat:@"Reading metadata from %ld videos...", (long)[fileURLs count]];
            [self readFolderFiles:fileURLs index:0 results:[NSMutableArray arrayWithCapacity:[fileURLs count]]];
        });
    });
}

- (void)readFolderFiles:(NSArray *)fileURLs index:(NSInteger)index results:(NSMutableArray *)results {
    if (index >= (NSInteger)[fileURLs count]) {
        BOOL russian = [[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];
        self.tracks = [NSArray arrayWithArray:results];
        [self.tableView reloadData];
        if ([self.tracks count] > 0) {
            [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        }
        self.statusLabel.stringValue = russian ? [NSString stringWithFormat:@"Загружено видео: %ld — %@.", (long)[self.tracks count], [self.selectedFolderURL lastPathComponent] ?: @"папка"]
                                               : [NSString stringWithFormat:@"Loaded %ld videos from %@.", (long)[self.tracks count], [self.selectedFolderURL lastPathComponent] ?: @"folder"];
        [self finishActivity];
        return;
    }
    NSURL *fileURL = [fileURLs objectAtIndex:index];
    [[IGVideoFileMetadataService sharedService] readMetadataAtURL:fileURL completion:^(NSDictionary *metadata, NSString *errorMessage) {
        BOOL russian = [[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];
        if (metadata) [results addObject:metadata];
        self.statusLabel.stringValue = russian ? [NSString stringWithFormat:@"Читаю видео %ld из %ld%@",
                                                   (long)(index + 1), (long)[fileURLs count], errorMessage ? @" (один файл пропущен)" : @"…"]
                                                 : [NSString stringWithFormat:@"Reading video %ld of %ld%@",
                                                    (long)(index + 1), (long)[fileURLs count], errorMessage ? @" (one file skipped)" : @"..."];
        [[IGOperationActivity sharedActivity] updateProgress:(double)(index + 1) / (double)[fileURLs count]
                                              forIdentifier:IGOperationActivityVideoMetadataIdentifier];
        [self readFolderFiles:fileURLs index:index + 1 results:results];
    }];
}

- (void)chooseArtworkClicked:(id)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    [panel setAllowedFileTypes:@[@"jpg", @"jpeg", @"png", @"tif", @"tiff"]];
    if ([panel runModal] == NSFileHandlingPanelOKButton) {
        [self removeTemporaryArtworkIfNeeded];
        self.selectedArtworkURL = [panel URL];
        self.selectedArtworkTemporary = NO;
        self.artworkLabel.stringValue = [[self.selectedArtworkURL path] lastPathComponent] ?: @"Artwork selected";
    }
}

- (void)searchMetadataClicked:(id)sender {
    (void)sender;
    NSDictionary *selected = [self selectedTrack];
    if (!selected || ![self beginActivity]) return;
    BOOL television = [self.kindPopup indexOfSelectedItem] == 1;
    NSString *query = television && [self.showField.stringValue length] > 0 ? self.showField.stringValue : self.nameField.stringValue;
    self.statusLabel.stringValue = @"Searching movie and TV catalogs...";
    [[IGMediaFixerManager sharedManager] searchVideoMetadataForTitle:query
                                                          videoKind:(television ? @"TV Show" : @"Movie")
                                                          completion:^(NSArray *results, NSString *errorMessage) {
        [self finishActivity];
        if (errorMessage || [results count] == 0) {
            NSString *message = errorMessage ?: @"No matching movies or TV shows were found.";
            self.statusLabel.stringValue = message;
            [IGNotificationView showInView:self.view message:message isError:YES];
            return;
        }

        NSDictionary *choice = [IGVideoMetadataChoiceController runWithResults:results
                                                             hasCurrentArtwork:[[selected objectForKey:@"hasArtwork"] boolValue]];
        if (!choice) {
            self.statusLabel.stringValue = @"Catalog search cancelled. No iTunes data was changed.";
            return;
        }
        [self applyCatalogCandidate:choice];
    }];
}

- (void)applyCatalogCandidate:(NSDictionary *)candidate {
    self.selectedCatalogCandidate = candidate;
    BOOL television = [[candidate objectForKey:@"videoKind"] isEqualToString:@"TV Show"];
    [self.kindPopup selectItemAtIndex:television ? 1 : 0];
    NSString *localizedName = [candidate objectForKey:@"localizedName"];
    BOOL hasRussianName = [localizedName length] > 0;
    [[self.titleLanguagePopup itemAtIndex:0] setEnabled:hasRussianName];
    BOOL choseRussian = [[candidate objectForKey:@"chosenTitleLanguage"] isEqualToString:@"Russian"] && hasRussianName;
    [self.titleLanguagePopup selectItemAtIndex:choseRussian ? 0 : 1];
    self.showField.stringValue = [candidate objectForKey:@"show"] ?: @"";
    self.seasonField.stringValue = [[candidate objectForKey:@"seasonNumber"] stringValue] ?: @"0";
    self.genreField.stringValue = [candidate objectForKey:@"genre"] ?: @"";
    self.yearField.stringValue = [[candidate objectForKey:@"year"] stringValue] ?: @"0";
    self.descriptionField.stringValue = [candidate objectForKey:@"description"] ?: @"";
    self.directorField.stringValue = [candidate objectForKey:@"director"] ?: @"";
    [self updateTitleFromLanguageChoice];
    [self updateControls];

    NSString *artworkURL = [candidate objectForKey:@"artworkURL"];
    BOOL useCatalogArtwork = [[candidate objectForKey:@"useCatalogArtwork"] boolValue];
    if (!useCatalogArtwork || [artworkURL length] == 0) {
        self.statusLabel.stringValue = useCatalogArtwork ? @"Catalog metadata filled in. No poster was available."
                                                         : @"Catalog metadata filled in. Current iTunes artwork will be kept.";
        return;
    }
    if (![self beginActivity]) return;
    self.statusLabel.stringValue = @"Downloading the selected catalog artwork...";
    [[IGMediaFixerManager sharedManager] downloadVideoArtworkAtURLString:artworkURL completion:^(NSURL *fileURL, NSString *errorMessage) {
        [self finishActivity];
        if (fileURL) {
            [self removeTemporaryArtworkIfNeeded];
            self.selectedArtworkURL = fileURL;
            self.selectedArtworkTemporary = YES;
            self.artworkLabel.stringValue = @"Catalog artwork selected";
            self.statusLabel.stringValue = @"Catalog metadata and artwork filled in. Review them, then apply to iTunes.";
        } else {
            self.statusLabel.stringValue = errorMessage ?: @"Metadata filled in, but artwork could not be downloaded.";
        }
    }];
}

- (void)removeTemporaryArtworkIfNeeded {
    if (self.selectedArtworkTemporary && [self.selectedArtworkURL isFileURL]) {
        [[NSFileManager defaultManager] removeItemAtURL:self.selectedArtworkURL error:nil];
    }
    self.selectedArtworkTemporary = NO;
}

- (void)applyClicked:(id)sender {
    (void)sender;
    NSDictionary *selected = [self selectedTrack];
    if (!selected || ![self beginActivity]) return;
    NSDictionary *metadata = [NSDictionary dictionaryWithObjectsAndKeys:
                              self.nameField.stringValue ?: @"", @"name",
                              [self.kindPopup indexOfSelectedItem] == 1 ? @"TV Show" : @"Movie", @"videoKind",
                              self.showField.stringValue ?: @"", @"show",
                              [NSNumber numberWithInteger:MAX((NSInteger)0, [self.seasonField integerValue])], @"seasonNumber",
                              [NSNumber numberWithInteger:MAX((NSInteger)0, [self.episodeField integerValue])], @"episodeNumber",
                              self.genreField.stringValue ?: @"", @"genre",
                              [NSNumber numberWithInteger:MAX((NSInteger)0, [self.yearField integerValue])], @"year",
                              self.directorField.stringValue ?: @"", @"director",
                              self.descriptionField.stringValue ?: @"", @"description",
                              nil];
    if ([self isFolderMode]) {
        BOOL russian = [[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];
        NSURL *fileURL = [selected objectForKey:@"fileURL"];
        if (![fileURL isFileURL]) {
            [self finishActivity];
            [IGNotificationView showInView:self.view message:@"The selected video file is no longer available." isError:YES];
            return;
        }
        [self finishActivity];
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:russian ? @"Сохранить метаданные в этот видеофайл?" : @"Save metadata to this video file?"];
        [alert setInformativeText:[NSString stringWithFormat:
            russian ? @"Syncrosa создаст проверенную копию рядом с исходником. Исходный файл останется как .syncrosa-backup.\n\n%@"
                    : @"Syncrosa will create a verified replacement beside the original. The original will be kept as a .syncrosa-backup file.\n\n%@",
            [fileURL path]]];
        [alert addButtonWithTitle:russian ? @"Сохранить с резервной копией" : @"Save with Backup"];
        [alert addButtonWithTitle:russian ? @"Отмена" : @"Cancel"];
        if ([alert runModal] != NSAlertFirstButtonReturn) return;
        if (![self beginActivity]) return;
        self.statusLabel.stringValue = russian ? @"Записываю проверенный файл без перекодирования…"
                                               : @"Writing a verified video file without re-encoding...";
        [[IGVideoFileMetadataService sharedService] writeMetadata:metadata
                                                       artworkURL:self.selectedArtworkURL
                                                        toFileURL:fileURL
                                                       completion:^(BOOL success, NSURL *backupURL, NSString *errorMessage) {
            [self finishActivity];
            if (success) {
                self.statusLabel.stringValue = [NSString stringWithFormat:@"Video metadata saved. Backup: %@",
                                                [backupURL lastPathComponent] ?: @"created"];
                [IGNotificationView showInView:self.view message:@"Video metadata saved; the original backup was preserved." isError:NO];
                [self loadFolderAtURL:self.selectedFolderURL];
            } else {
                self.statusLabel.stringValue = errorMessage ?: @"Could not update the video file.";
                [IGNotificationView showInView:self.view message:self.statusLabel.stringValue isError:YES];
            }
        }];
        return;
    }
    self.statusLabel.stringValue = @"Updating iTunes video metadata...";
    [[IGiTunesService sharedService] updateVideoTrackWithPersistentID:[selected objectForKey:@"persistentID"]
                                                             metadata:metadata
                                                           artworkURL:self.selectedArtworkURL
                                                           completion:^(BOOL success, NSString *errorMessage) {
        [self finishActivity];
        if (success) {
            self.statusLabel.stringValue = @"Video metadata updated in iTunes.";
            [IGNotificationView showInView:self.view message:self.statusLabel.stringValue isError:NO];
            [self refreshClicked:nil];
        } else {
            self.statusLabel.stringValue = errorMessage ?: @"Could not update the video metadata.";
            [IGNotificationView showInView:self.view message:self.statusLabel.stringValue isError:YES];
        }
    }];
}

- (void)dealloc {
    [self removeTemporaryArtworkIfNeeded];
#if !__has_feature(objc_arc)
    [_tableView release];
    [_tracks release];
    [_refreshButton release];
    [_sourcePopup release];
    [_subtitleLabel release];
    [_kindPopup release];
    [_nameField release];
    [_showField release];
    [_seasonField release];
    [_episodeField release];
    [_genreField release];
    [_yearField release];
    [_directorField release];
    [_descriptionField release];
    [_artworkLabel release];
    [_artworkButton release];
    [_searchButton release];
    [_applyButton release];
    [_titleLanguagePopup release];
    [_spinner release];
    [_statusLabel release];
    [_selectedArtworkURL release];
    [_selectedFolderURL release];
    [_selectedCatalogCandidate release];
    [super dealloc];
#endif
}

@end
