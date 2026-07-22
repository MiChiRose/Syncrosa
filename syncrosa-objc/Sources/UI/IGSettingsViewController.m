#import "IGSettingsViewController.h"
#import "IGAIService.h"
#import "IGMainWindowController.h"
#import "IGKeychainHelper.h"
#import "IGLocalizationService.h"
#import "IGNotificationView.h"
#import "IGiTunesService.h"
#import "IGLogger.h"
#import "IGUpdateSupport.h"
#import "IGTheme.h"
#import "IGHelpSheetPresenter.h"

static NSString *IGSettingsCanonicalProvider(NSString *provider) {
    if ([provider caseInsensitiveCompare:@"Groq"] == NSOrderedSame) {
        return @"Groq";
    }
    if ([provider caseInsensitiveCompare:@"OpenRouter"] == NSOrderedSame) {
        return @"OpenRouter";
    }
    return @"Gemini";
}

static NSString *IGSettingsPlainTextFromMarkdown(NSString *markdown) {
    if (![markdown isKindOfClass:[NSString class]] || [markdown length] == 0) {
        return @"";
    }

    NSMutableArray *cleanLines = [NSMutableArray array];
    NSArray *lines = [markdown componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    BOOL insideFence = NO;
    for (NSString *line in lines) {
        NSString *clean = line ?: @"";
        NSString *trimmed = [clean stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed hasPrefix:@"```"]) {
            insideFence = !insideFence;
            continue;
        }
        if (insideFence) {
            [cleanLines addObject:clean];
            continue;
        }
        while ([clean hasPrefix:@"#"]) {
            clean = [clean substringFromIndex:1];
        }
        clean = [clean stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        clean = [clean stringByReplacingOccurrencesOfString:@"**" withString:@""];
        clean = [clean stringByReplacingOccurrencesOfString:@"`" withString:@""];
        [cleanLines addObject:clean];
    }
    return [cleanLines componentsJoinedByString:@"\n"];
}

@interface IGSettingsViewController () <NSComboBoxDelegate>

@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *langLabel;
@property (nonatomic, strong) NSPopUpButton *langPopup;
@property (nonatomic, strong) NSTextField *themeLabel;
@property (nonatomic, strong) NSPopUpButton *themePopup;
@property (nonatomic, strong) NSTextField *appearanceLabel;
@property (nonatomic, strong) NSPopUpButton *appearancePopup;
@property (nonatomic, strong) NSTextField *providerLabel;
@property (nonatomic, strong) NSComboBox *providerCombo;
@property (nonatomic, strong) NSTextField *modelLabel;
@property (nonatomic, strong) NSComboBox *modelCombo;
@property (nonatomic, strong) NSButton *syncModelsBtn;
@property (nonatomic, strong) NSTextField *apiKeyLabel;
@property (nonatomic, strong) NSSecureTextField *apiKeyField;
@property (nonatomic, strong) NSButton *enableLoggingCheckbox;
@property (nonatomic, strong) NSButton *onlyLocalCheckbox;
@property (nonatomic, strong) NSButton *hddSafeCheckbox;
@property (nonatomic, strong) NSButton *showFooterCheckbox;
@property (nonatomic, strong) NSButton *historyButton;
@property (nonatomic, strong) NSButton *recoveryButton;
@property (nonatomic, strong) NSButton *syncLibButton;
@property (nonatomic, strong) NSTextField *syncLibStatusLabel;
@property (nonatomic, strong) NSButton *updateCheckButton;
@property (nonatomic, strong) NSButton *updateOpenButton;
@property (nonatomic, strong) NSButton *releaseNotesButton;
@property (nonatomic, strong) NSTextField *updateStatusLabel;
@property (nonatomic, strong) NSString *latestUpdateURL;
@property (nonatomic, strong) NSString *latestReleaseTitle;
@property (nonatomic, strong) NSString *latestReleaseNotes;
@property (nonatomic, strong) NSButton *saveButton;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextField *footerLabel;
@property (nonatomic, strong) NSButton *helpBtn;
@property (nonatomic, strong) NSWindow *helpSheetWindow;

@end

@implementation IGSettingsViewController

- (void)loadView {
    self.view = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 500)] autorelease];
    [self setupUI];
    [self loadSettings];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(localizationChanged:)
                                                 name:@"IGLanguageChangedNotification"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeChanged:)
                                                 name:IGThemeDidChangeNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
#if !__has_feature(objc_arc)
    [_titleLabel release];
    [_langLabel release];
    [_langPopup release];
    [_themeLabel release];
    [_themePopup release];
    [_appearanceLabel release];
    [_appearancePopup release];
    [_providerLabel release];
    [_providerCombo release];
    [_modelLabel release];
    [_modelCombo release];
    [_syncModelsBtn release];
    [_apiKeyLabel release];
    [_apiKeyField release];
    [_enableLoggingCheckbox release];
    [_onlyLocalCheckbox release];
    [_hddSafeCheckbox release];
    [_showFooterCheckbox release];
    [_historyButton release];
    [_recoveryButton release];
    [_syncLibButton release];
    [_syncLibStatusLabel release];
    [_updateCheckButton release];
    [_updateOpenButton release];
    [_releaseNotesButton release];
    [_updateStatusLabel release];
    [_latestUpdateURL release];
    [_latestReleaseTitle release];
    [_latestReleaseNotes release];
    [_saveButton release];
    [_statusLabel release];
    [_footerLabel release];
    [_helpBtn release];
    [_helpSheetWindow release];
    [super dealloc];
#endif
}

- (void)setupUI {
    CGFloat y = 465;
    CGFloat rowGap = 42.0;
    CGFloat compactRowGap = 32.0;
    CGFloat buttonHeight = 26.0;
    self.latestUpdateURL = @"https://github.com/MiChiRose/Syncrosa/releases/latest";
    self.latestReleaseTitle = @"";
    self.latestReleaseNotes = IGUpdateBundledReleaseNotes();
    
    // Title
    self.titleLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 30)] autorelease];
    self.titleLabel.font = [NSFont boldSystemFontOfSize:18];
    self.titleLabel.editable = NO;
    self.titleLabel.bordered = NO;
    self.titleLabel.drawsBackground = NO;
    self.titleLabel.alignment = NSCenterTextAlignment;
    [self.view addSubview:self.titleLabel];
    
    y -= rowGap;
    // Language Section
    self.langLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 120, 20)] autorelease];
    self.langLabel.font = [NSFont systemFontOfSize:13];
    self.langLabel.editable = NO;
    self.langLabel.bordered = NO;
    self.langLabel.drawsBackground = NO;
    [self.view addSubview:self.langLabel];
    
    self.langPopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(150, y-2, 200, 26) pullsDown:NO] autorelease];
    [self.langPopup addItemsWithTitles:@[@"English", @"Русский", @"Беларуская", @"한국어", @"日本語", @"中文", @"Deutsch", @"Polski", @"Eesti", @"Español"]];
    self.langPopup.target = self;
    self.langPopup.action = @selector(languagePopupChanged:);
    [self.view addSubview:self.langPopup];

    self.themeLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(370, y, 60, 20)] autorelease];
    self.themeLabel.font = [NSFont systemFontOfSize:13];
    self.themeLabel.editable = NO;
    self.themeLabel.bordered = NO;
    self.themeLabel.drawsBackground = NO;
    [self.view addSubview:self.themeLabel];

    self.themePopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(430, y-2, 130, 26) pullsDown:NO] autorelease];
    NSArray *themeIDs = IGThemeIdentifiers();
    for (NSString *identifier in themeIDs) {
        [self.themePopup addItemWithTitle:IGThemeDisplayNameForIdentifier(identifier)];
    }
    self.themePopup.target = self;
    self.themePopup.action = @selector(themePopupChanged:);
    [self.view addSubview:self.themePopup];

    y -= 32.0;
    self.appearanceLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 140, 20)] autorelease];
    self.appearanceLabel.font = [NSFont systemFontOfSize:13];
    self.appearanceLabel.editable = NO;
    self.appearanceLabel.bordered = NO;
    self.appearanceLabel.drawsBackground = NO;
    [self.view addSubview:self.appearanceLabel];

    self.appearancePopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(150, y-2, 200, 26) pullsDown:NO] autorelease];
    NSArray *appearanceIDs = IGAppearanceModeIdentifiers();
    for (NSString *identifier in appearanceIDs) {
        [self.appearancePopup addItemWithTitle:IGAppearanceModeDisplayNameForIdentifier(identifier)];
    }
    self.appearancePopup.target = self;
    self.appearancePopup.action = @selector(appearancePopupChanged:);
    self.appearancePopup.toolTip = @"System follows macOS appearance where supported. On OS X 10.9 it safely uses light Classic Graphite.";
    [self.view addSubview:self.appearancePopup];
    
    y -= rowGap - 10.0;
    // AI Provider Section
    self.providerLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 120, 20)] autorelease];
    self.providerLabel.font = [NSFont systemFontOfSize:13];
    self.providerLabel.editable = NO;
    self.providerLabel.bordered = NO;
    self.providerLabel.drawsBackground = NO;
    [self.view addSubview:self.providerLabel];
    
    self.providerCombo = [[[NSComboBox alloc] initWithFrame:NSMakeRect(150, y-2, 200, 26)] autorelease];
    [self.providerCombo addItemsWithObjectValues:@[@"Gemini", @"OpenRouter", @"Groq"]];
    self.providerCombo.editable = NO;
    self.providerCombo.delegate = self;
    [self.view addSubview:self.providerCombo];
    
    y -= rowGap;
    // Model Section
    self.modelLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 120, 20)] autorelease];
    self.modelLabel.font = [NSFont systemFontOfSize:13];
    self.modelLabel.editable = NO;
    self.modelLabel.bordered = NO;
    self.modelLabel.drawsBackground = NO;
    [self.view addSubview:self.modelLabel];
    
    self.modelCombo = [[[NSComboBox alloc] initWithFrame:NSMakeRect(150, y-2, 270, 26)] autorelease];
    [self.view addSubview:self.modelCombo];
    
    self.syncModelsBtn = [[[NSButton alloc] initWithFrame:NSMakeRect(430, y-2, 130, 30)] autorelease];
    self.syncModelsBtn.bezelStyle = NSRoundedBezelStyle;
    self.syncModelsBtn.target = self;
    self.syncModelsBtn.action = @selector(syncClicked:);
    [self.view addSubview:self.syncModelsBtn];
    
    y -= rowGap;
    // API Key Section
    self.apiKeyLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 120, 20)] autorelease];
    self.apiKeyLabel.font = [NSFont systemFontOfSize:13];
    self.apiKeyLabel.editable = NO;
    self.apiKeyLabel.bordered = NO;
    self.apiKeyLabel.drawsBackground = NO;
    [self.view addSubview:self.apiKeyLabel];
    
    self.apiKeyField = [[[NSSecureTextField alloc] initWithFrame:NSMakeRect(150, y-2, 410, 24)] autorelease];
    [self.view addSubview:self.apiKeyField];

    y -= 34;
    self.saveButton = [[[NSButton alloc] initWithFrame:NSMakeRect(150, y, 200, buttonHeight)] autorelease];
    self.saveButton.bezelStyle = NSTexturedRoundedBezelStyle;
    self.saveButton.target = self;
    self.saveButton.action = @selector(saveClicked:);
    [self.view addSubview:self.saveButton];

    self.statusLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(360, y + 3, 200, 20)] autorelease];
    self.statusLabel.stringValue = @"";
    self.statusLabel.font = [NSFont systemFontOfSize:11];
    self.statusLabel.editable = NO;
    self.statusLabel.bordered = NO;
    self.statusLabel.drawsBackground = NO;
    self.statusLabel.alignment = NSLeftTextAlignment;
    [self.view addSubview:self.statusLabel];
    
    y -= compactRowGap;
    // Logging Checkbox
    self.enableLoggingCheckbox = [[[NSButton alloc] initWithFrame:NSMakeRect(20, y, 540, 20)] autorelease];
    self.enableLoggingCheckbox.buttonType = NSSwitchButton;
    self.enableLoggingCheckbox.hidden = ![IGLogger desktopDiagnosticsEnabled];
    self.enableLoggingCheckbox.enabled = [IGLogger desktopDiagnosticsEnabled];
    [self.view addSubview:self.enableLoggingCheckbox];

    y -= compactRowGap;
    self.onlyLocalCheckbox = [[[NSButton alloc] initWithFrame:NSMakeRect(20, y, 260, 20)] autorelease];
    self.onlyLocalCheckbox.buttonType = NSSwitchButton;
    self.onlyLocalCheckbox.title = @"Only Local Mode";
    [self.view addSubview:self.onlyLocalCheckbox];

    self.historyButton = [[[NSButton alloc] initWithFrame:NSMakeRect(300, y - 3, 180, buttonHeight)] autorelease];
    self.historyButton.bezelStyle = NSRoundedBezelStyle;
    self.historyButton.title = @"Operation History";
    self.historyButton.target = self;
    self.historyButton.action = @selector(historyClicked:);
    [self.view addSubview:self.historyButton];

    y -= compactRowGap;
    self.hddSafeCheckbox = [[[NSButton alloc] initWithFrame:NSMakeRect(20, y, 260, 20)] autorelease];
    self.hddSafeCheckbox.buttonType = NSSwitchButton;
    self.hddSafeCheckbox.title = @"HDD Safe Mode";
    [self.view addSubview:self.hddSafeCheckbox];

    self.recoveryButton = [[[NSButton alloc] initWithFrame:NSMakeRect(300, y - 3, 180, buttonHeight)] autorelease];
    self.recoveryButton.bezelStyle = NSRoundedBezelStyle;
    self.recoveryButton.title = @"Recovery Center";
    self.recoveryButton.target = self;
    self.recoveryButton.action = @selector(recoveryClicked:);
    [self.view addSubview:self.recoveryButton];

    y -= compactRowGap;
    self.showFooterCheckbox = [[[NSButton alloc] initWithFrame:NSMakeRect(20, y, 260, 20)] autorelease];
    self.showFooterCheckbox.buttonType = NSSwitchButton;
    self.showFooterCheckbox.target = self;
    self.showFooterCheckbox.action = @selector(showFooterChanged:);
    [self.view addSubview:self.showFooterCheckbox];

    y -= compactRowGap + 4.0;
    // Library Sync Section
    self.syncLibButton = [[[NSButton alloc] initWithFrame:NSMakeRect(20, y, 200, buttonHeight)] autorelease];
    self.syncLibButton.bezelStyle = NSRoundedBezelStyle;
    self.syncLibButton.target = self;
    self.syncLibButton.action = @selector(syncLibClicked:);
    [self.view addSubview:self.syncLibButton];
    
    self.syncLibStatusLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(230, y + 3, 330, 20)] autorelease];
    self.syncLibStatusLabel.font = [NSFont systemFontOfSize:11];
    self.syncLibStatusLabel.textColor = IGThemeMutedTextColor();
    self.syncLibStatusLabel.editable = NO;
    self.syncLibStatusLabel.bordered = NO;
    self.syncLibStatusLabel.drawsBackground = NO;
    [self.view addSubview:self.syncLibStatusLabel];

    y -= rowGap;
    // Updates Section
    self.updateCheckButton = [[[NSButton alloc] initWithFrame:NSMakeRect(20, y, 160, buttonHeight)] autorelease];
    self.updateCheckButton.bezelStyle = NSRoundedBezelStyle;
    self.updateCheckButton.target = self;
    self.updateCheckButton.action = @selector(checkUpdatesClicked:);
    [self.view addSubview:self.updateCheckButton];

    self.updateOpenButton = [[[NSButton alloc] initWithFrame:NSMakeRect(190, y, 120, buttonHeight)] autorelease];
    self.updateOpenButton.bezelStyle = NSRoundedBezelStyle;
    self.updateOpenButton.target = self;
    self.updateOpenButton.action = @selector(openUpdateClicked:);
    self.updateOpenButton.enabled = NO;
    [self.view addSubview:self.updateOpenButton];

    self.releaseNotesButton = [[[NSButton alloc] initWithFrame:NSMakeRect(320, y, 140, buttonHeight)] autorelease];
    self.releaseNotesButton.bezelStyle = NSRoundedBezelStyle;
    self.releaseNotesButton.target = self;
    self.releaseNotesButton.action = @selector(releaseNotesClicked:);
    self.releaseNotesButton.enabled = YES;
    [self.view addSubview:self.releaseNotesButton];

    self.updateStatusLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, y - 24, 540, 20)] autorelease];
    self.updateStatusLabel.font = [NSFont systemFontOfSize:11];
    self.updateStatusLabel.textColor = IGThemeMutedTextColor();
    self.updateStatusLabel.editable = NO;
    self.updateStatusLabel.bordered = NO;
    self.updateStatusLabel.drawsBackground = NO;
    self.updateStatusLabel.stringValue = [NSString stringWithFormat:@"Current version: %@", IGCurrentApplicationVersionString()];
    [self.view addSubview:self.updateStatusLabel];
    
    // Help Button
    self.helpBtn = [[[NSButton alloc] initWithFrame:NSMakeRect(520, 467, 25, 25)] autorelease];
    self.helpBtn.bezelStyle = NSHelpButtonBezelStyle;
    self.helpBtn.title = @"";
    self.helpBtn.target = self;
    self.helpBtn.action = @selector(helpClicked:);
    [self.view addSubview:self.helpBtn];
    
    // Footer
    self.footerLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, 4, 500, 30)] autorelease];
    self.footerLabel.font = [NSFont systemFontOfSize:10];
    self.footerLabel.textColor = IGThemeMutedTextColor();
    self.footerLabel.alignment = NSCenterTextAlignment;
    self.footerLabel.editable = NO;
    self.footerLabel.bordered = NO;
    self.footerLabel.drawsBackground = NO;
    [self.view addSubview:self.footerLabel];
    
    [self updateLocalization];

}

- (void)updateLocalization {
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    
    self.titleLabel.stringValue = [lang t:@"settings"];
    self.langLabel.stringValue = [NSString stringWithFormat:@"%@:", [lang t:@"lang_section"]];
    self.themeLabel.stringValue = [lang.selectedLanguage isEqualToString:@"ru"] ? @"Тема:" : @"Theme:";
    self.appearanceLabel.stringValue = [lang.selectedLanguage isEqualToString:@"ru"] ? @"Режим оформления:" : @"Appearance mode:";
    NSArray *appearanceTitles = [lang.selectedLanguage isEqualToString:@"ru"] ?
        @[@"Как в системе", @"Светлая", @"Тёмная"] :
        @[@"System", @"Light", @"Dark"];
    for (NSInteger i = 0; i < (NSInteger)[appearanceTitles count] && i < [self.appearancePopup numberOfItems]; i++) {
        [[self.appearancePopup itemAtIndex:i] setTitle:[appearanceTitles objectAtIndex:i]];
    }
    self.providerLabel.stringValue = [lang t:@"select_provider"];
    self.modelLabel.stringValue = [lang t:@"select_model"];
    self.syncModelsBtn.title = [lang t:@"sync_models"];
    self.apiKeyLabel.stringValue = [lang t:@"enter_key"];
    self.syncLibButton.title = [lang t:@"sync_library"];
    self.saveButton.title = [lang t:@"validate_save"];
    self.footerLabel.stringValue = [lang t:@"footer"];
    
    self.enableLoggingCheckbox.title = [lang.selectedLanguage isEqualToString:@"ru"] ? 
        @"Запрашивать сохранение логов при генерации и ошибках" : 
        @"Prompt to save text logs for errors and successful generation";
    self.onlyLocalCheckbox.title = [lang.selectedLanguage isEqualToString:@"ru"] ? @"Only Local Mode (без сетевых метаданных)" : @"Only Local Mode (skip online metadata)";
    self.hddSafeCheckbox.title = [lang.selectedLanguage isEqualToString:@"ru"] ? @"HDD Safe Mode (мягче для диска)" : @"HDD Safe Mode (gentler disk work)";
    self.showFooterCheckbox.title = [lang.selectedLanguage isEqualToString:@"ru"] ? @"Показывать нижнюю подсказку" : @"Show footer note";
    self.showFooterCheckbox.toolTip = [lang.selectedLanguage isEqualToString:@"ru"] ? @"Показывает постоянную нижнюю строку Syncrosa на всех вкладках." : @"Keep the Syncrosa footer note visible on every tab.";
    self.historyButton.title = [lang.selectedLanguage isEqualToString:@"ru"] ? @"История операций" : @"Operation History";
    self.recoveryButton.title = [lang.selectedLanguage isEqualToString:@"ru"] ? @"Recovery Center" : @"Recovery Center";
    self.updateCheckButton.title = [lang.selectedLanguage isEqualToString:@"ru"] ? @"Проверить обновления" : @"Check Updates";
    self.updateOpenButton.title = [lang.selectedLanguage isEqualToString:@"ru"] ? @"Update App" : @"Update App";
    self.releaseNotesButton.title = [lang.selectedLanguage isEqualToString:@"ru"] ? @"Что нового" : @"Release Notes";
    
    if (self.syncLibStatusLabel.stringValue.length == 0 || 
        [self.syncLibStatusLabel.stringValue isEqualToString:@"Refresh your local music database cache."] ||
        [self.syncLibStatusLabel.stringValue isEqualToString:@"Обновите локальный кэш музыкальной базы."]) {
        self.syncLibStatusLabel.stringValue = [lang t:@"refresh_cache"];
    }
    if (self.updateStatusLabel.stringValue.length == 0) {
        self.updateStatusLabel.stringValue = [NSString stringWithFormat:@"Current version: %@", IGCurrentApplicationVersionString()];
    }
    [self applyThemeColors];
}

- (void)localizationChanged:(NSNotification *)notification {
    [self updateLocalization];
    
    // Update language popup selection to match service
    NSString *langCode = [IGLocalizationService sharedService].selectedLanguage;
    NSArray *codes = @[@"en", @"ru", @"be", @"ko", @"ja", @"zh", @"de", @"pl", @"et", @"es"];
    NSInteger index = [codes indexOfObject:langCode];
    if (index != NSNotFound) {
        [self.langPopup selectItemAtIndex:index];
    }
}

- (void)themePopupChanged:(id)sender {
    NSArray *themeIDs = IGThemeIdentifiers();
    NSInteger index = [self.themePopup indexOfSelectedItem];
    if (index >= 0 && index < (NSInteger)[themeIDs count]) {
        /*
         System appearance on Mavericks deliberately falls back to the light
         Classic palette.  Keep the palette chooser useful by moving to an
         explicit Light appearance as soon as the user chooses a palette.
         */
        if ([IGActiveAppearanceModeIdentifier() isEqualToString:@"system"] &&
            !IGSystemAppearanceDetectionAvailable()) {
            IGSetActiveAppearanceModeIdentifier(@"light");
        }
        IGSetActiveThemeIdentifier([themeIDs objectAtIndex:index]);
    }
}

- (void)appearancePopupChanged:(id)sender {
    NSArray *modeIDs = IGAppearanceModeIdentifiers();
    NSInteger index = [self.appearancePopup indexOfSelectedItem];
    if (index >= 0 && index < (NSInteger)[modeIDs count]) {
        IGSetActiveAppearanceModeIdentifier([modeIDs objectAtIndex:index]);
    }
}

- (void)themeChanged:(NSNotification *)notification {
    (void)notification;
    [self applyThemeColors];
}

- (void)applyThemeColors {
    NSArray *themeIDs = IGThemeIdentifiers();
    NSInteger themeIndex = [themeIDs indexOfObject:IGActiveThemeIdentifier()];
    if (themeIndex != NSNotFound && themeIndex < [self.themePopup numberOfItems]) {
        [self.themePopup selectItemAtIndex:themeIndex];
    }
    NSArray *modeIDs = IGAppearanceModeIdentifiers();
    NSInteger appearanceIndex = [modeIDs indexOfObject:IGActiveAppearanceModeIdentifier()];
    if (appearanceIndex != NSNotFound && appearanceIndex < [self.appearancePopup numberOfItems]) {
        [self.appearancePopup selectItemAtIndex:appearanceIndex];
    }
    BOOL usesMavericksSystemFallback = [IGActiveAppearanceModeIdentifier() isEqualToString:@"system"] && !IGSystemAppearanceDetectionAvailable();
    self.themePopup.enabled = YES;
    self.themePopup.toolTip = usesMavericksSystemFallback ? @"System uses light Classic Graphite on this version of OS X. Choosing another palette switches Appearance to Light." : @"Choose the color palette used throughout Syncrosa.";
    if (usesMavericksSystemFallback) {
        [self.themePopup selectItemAtIndex:0];
    }
    self.titleLabel.textColor = IGThemeTextColor();
    self.langLabel.textColor = IGThemeTextColor();
    self.themeLabel.textColor = IGThemeTextColor();
    self.appearanceLabel.textColor = IGThemeTextColor();
    self.providerLabel.textColor = IGThemeTextColor();
    self.modelLabel.textColor = IGThemeTextColor();
    self.apiKeyLabel.textColor = IGThemeTextColor();
    self.syncLibStatusLabel.textColor = IGThemeMutedTextColor();
    self.updateStatusLabel.textColor = IGThemeMutedTextColor();
    self.statusLabel.textColor = IGThemeMutedTextColor();
    self.footerLabel.textColor = IGThemeMutedTextColor();
    IGInstallThemedContentBackground(self.view);
    IGApplyThemeToViewHierarchy(self.view);
    IGApplyThemeToButton(self.saveButton, IGThemeButtonRolePrimary);
    IGApplyThemeToButton(self.syncModelsBtn, IGThemeButtonRoleSecondary);
    IGApplyThemeToButton(self.historyButton, IGThemeButtonRoleSecondary);
    IGApplyThemeToButton(self.recoveryButton, IGThemeButtonRoleSecondary);
    IGApplyThemeToButton(self.syncLibButton, IGThemeButtonRoleSecondary);
    IGApplyThemeToButton(self.updateCheckButton, IGThemeButtonRolePrimary);
    IGApplyThemeToButton(self.updateOpenButton, IGThemeButtonRolePrimary);
    IGApplyThemeToButton(self.releaseNotesButton, IGThemeButtonRoleSecondary);
}

- (void)languagePopupChanged:(id)sender {
    NSArray *codes = @[@"en", @"ru", @"be", @"ko", @"ja", @"zh", @"de", @"pl", @"et", @"es"];
    NSInteger index = [self.langPopup indexOfSelectedItem];
    if (index >= 0 && index < codes.count) {
        [IGLocalizationService sharedService].selectedLanguage = codes[index];
    }
}

- (void)helpClicked:(id)sender {
    (void)sender;
    if (self.helpSheetWindow) return;
    NSArray *sections = @[
        IGHelpSectionMake(@"AI is optional", @"An API key is needed only for AI Playlist features. Library repair, folder tools, USB Export, diagnostics, and offline playlists work without one."),
        IGHelpSectionMake(@"Choose a provider", @"OpenRouter keys usually start with sk-or, Gemini keys with AIza, and Groq keys with gsk_. Create the key on the provider's official website."),
        IGHelpSectionMake(@"Validate safely", @"Paste the key without leading or trailing spaces, then choose Validate & Save. Syncrosa tests it and stores it in the macOS Keychain. Use Sync Models if a saved model is no longer available.")
    ];
    self.helpSheetWindow = [IGHelpSheetPresenter sheetWithTitle:@"Settings and API Key"
                                                        summary:@"Configure appearance, updates, performance safeguards, and optional AI access."
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

- (NSString *)operationHistoryPath {
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *base = dirs.count > 0 ? [dirs objectAtIndex:0] : NSHomeDirectory();
    return [[base stringByAppendingPathComponent:@"Syncrosa"] stringByAppendingPathComponent:@"operation-history.json"];
}

- (void)historyClicked:(id)sender {
    NSString *path = [self operationHistoryPath];
    NSData *data = [NSData dataWithContentsOfFile:path];
    id json = [data length] > 0 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSMutableString *formatted = [NSMutableString string];
    if ([json isKindOfClass:[NSArray class]]) {
        NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
        dateFormatter.dateStyle = NSDateFormatterMediumStyle;
        dateFormatter.timeStyle = NSDateFormatterShortStyle;
        for (NSDictionary *entry in (NSArray *)json) {
            if (![entry isKindOfClass:[NSDictionary class]]) continue;
            id createdAt = [entry objectForKey:@"createdAt"];
            NSString *dateText = @"Unknown date";
            if ([createdAt isKindOfClass:[NSNumber class]]) {
                dateText = [dateFormatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:[createdAt doubleValue]]] ?: dateText;
            } else if ([createdAt isKindOfClass:[NSString class]] && [createdAt length] > 0) {
                dateText = createdAt;
            }
            NSString *tool = [entry objectForKey:@"tool"] ?: @"Syncrosa";
            NSString *status = [entry objectForKey:@"status"] ?: @"";
            NSString *title = [entry objectForKey:@"title"] ?: @"Operation";
            NSString *message = [entry objectForKey:@"message"] ?: @"";
            NSNumber *affected = [entry objectForKey:@"affectedCount"];
            [formatted appendFormat:@"%@  |  %@  |  %@\n%@\n", dateText, tool, status, title];
            if ([message length] > 0) {
                [formatted appendFormat:@"%@\n", message];
            }
            if ([affected respondsToSelector:@selector(integerValue)] && [affected integerValue] > 0) {
                [formatted appendFormat:@"Affected items: %@\n", affected];
            }
            [formatted appendString:@"\n----------------------------------------\n\n"];
        }
    }
    NSString *text = [formatted length] > 0 ? formatted : [NSString stringWithFormat:@"No operation history yet.\n\nHistory will appear after Syncrosa finishes supported tasks.\n\nStorage path:\n%@", path];

    NSWindow *sheet = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 520, 360)
                                                   styleMask:NSTitledWindowMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES] autorelease];
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(20, 60, 480, 280)] autorelease];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    NSTextView *textView = [[[NSTextView alloc] initWithFrame:scroll.bounds] autorelease];
    textView.editable = NO;
    textView.string = text;
    textView.font = [NSFont fontWithName:@"Monaco" size:10] ?: [NSFont systemFontOfSize:10];
    scroll.documentView = textView;
    [sheet.contentView addSubview:scroll];

    NSButton *closeButton = [[[NSButton alloc] initWithFrame:NSMakeRect(210, 15, 100, 30)] autorelease];
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    closeButton.title = [lang.selectedLanguage isEqualToString:@"ru"] ? @"Закрыть" : @"Close";
    closeButton.bezelStyle = NSRoundedBezelStyle;
    closeButton.target = self;
    closeButton.action = @selector(closeHelpSheet:);
    [sheet.contentView addSubview:closeButton];

    IGApplyThemeToWindow(sheet);
    self.helpSheetWindow = sheet;
    if ([self.view.window respondsToSelector:@selector(beginSheet:completionHandler:)]) {
        [self.view.window beginSheet:sheet completionHandler:nil];
    } else {
        [NSApp beginSheet:sheet modalForWindow:self.view.window modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
    }
}

- (NSString *)applicationSupportSyncrosaPath {
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *base = dirs.count > 0 ? [dirs objectAtIndex:0] : NSHomeDirectory();
    return [base stringByAppendingPathComponent:@"Syncrosa"];
}

- (void)recoveryClicked:(id)sender {
    NSString *support = [self applicationSupportSyncrosaPath];
    NSString *backups = [support stringByAppendingPathComponent:@"Backups"];
    NSString *history = [self operationHistoryPath];
    NSString *activePath = [support stringByAppendingPathComponent:@"active-operation.plist"];
    NSDictionary *active = [NSDictionary dictionaryWithContentsOfFile:activePath];
    NSString *activeText = @"No interrupted operation marker found.";
    if ([active isKindOfClass:[NSDictionary class]] && [active objectForKey:@"title"]) {
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:[[active objectForKey:@"startedAt"] doubleValue]];
        activeText = [NSString stringWithFormat:@"%@\nTool: %@\nStarted: %@\nAffected: %@\nBackup: %@",
                      [active objectForKey:@"title"] ?: @"",
                      [active objectForKey:@"tool"] ?: @"",
                      date ?: [NSDate date],
                      [active objectForKey:@"affectedCount"] ?: @0,
                      [active objectForKey:@"backupPath"] ?: @""];
    }
    NSString *text = [NSString stringWithFormat:
                      @"Interrupted operations:\n"
                      "%@\n\n"
                      "Backups:\n%@\n\n"
                      "Operation History:\n%@\n\n"
                      "Info Eraser local backups are also stored next to the selected music folder as SyncrosaInfoEraserBackup.",
                      activeText,
                      backups,
                      history];
    [self showTextSheetWithTitle:@"Recovery Center" text:text monospace:NO];
}

- (void)releaseNotesClicked:(id)sender {
    NSString *title = self.latestReleaseTitle.length > 0 ? self.latestReleaseTitle : @"Syncrosa Release Notes";
    NSString *text = self.latestReleaseNotes.length > 0 ? self.latestReleaseNotes : IGUpdateBundledReleaseNotes();
    [self showTextSheetWithTitle:title text:IGSettingsPlainTextFromMarkdown(text) monospace:NO];
}

- (void)showTextSheetWithTitle:(NSString *)title text:(NSString *)text monospace:(BOOL)monospace {
    NSWindow *sheet = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 540, 380)
                                                   styleMask:NSTitledWindowMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES] autorelease];
    NSTextField *titleLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(24, 338, 492, 24)] autorelease];
    titleLabel.stringValue = title ?: @"";
    titleLabel.font = [NSFont boldSystemFontOfSize:15];
    titleLabel.editable = NO;
    titleLabel.bordered = NO;
    titleLabel.drawsBackground = NO;
    [sheet.contentView addSubview:titleLabel];

    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(24, 62, 492, 258)] autorelease];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    NSTextView *textView = [[[NSTextView alloc] initWithFrame:scroll.bounds] autorelease];
    textView.editable = NO;
    textView.string = text ?: @"";
    textView.font = monospace ? ([NSFont fontWithName:@"Monaco" size:10] ?: [NSFont systemFontOfSize:10]) : [NSFont systemFontOfSize:12];
    scroll.documentView = textView;
    [sheet.contentView addSubview:scroll];

    NSButton *closeButton = [[[NSButton alloc] initWithFrame:NSMakeRect(220, 16, 100, 30)] autorelease];
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    closeButton.title = [lang.selectedLanguage isEqualToString:@"ru"] ? @"Закрыть" : @"Close";
    closeButton.bezelStyle = NSRoundedBezelStyle;
    closeButton.target = self;
    closeButton.action = @selector(closeHelpSheet:);
    [sheet.contentView addSubview:closeButton];

    IGApplyThemeToWindow(sheet);
    self.helpSheetWindow = sheet;
    if ([self.view.window respondsToSelector:@selector(beginSheet:completionHandler:)]) {
        [self.view.window beginSheet:sheet completionHandler:nil];
    } else {
        [NSApp beginSheet:sheet modalForWindow:self.view.window modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
    }
}

- (void)comboBoxSelectionDidChange:(NSNotification *)notification {
    if (notification.object == self.providerCombo) {
        NSInteger index = [self.providerCombo indexOfSelectedItem];
        if (index >= 0 && index < self.providerCombo.numberOfItems) {
            NSString *selected = [self.providerCombo itemObjectValueAtIndex:index];
            [self updateModelAndKeyForProvider:selected];
        }
    }
}

- (void)updateModelAndKeyForProvider:(NSString *)provider {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    provider = IGSettingsCanonicalProvider(provider);
    [self.modelCombo removeAllItems];
    
    // Load Key
    NSString *savedKey = [[IGKeychainHelper sharedHelper] readStringForAccount:[provider lowercaseString]];
    self.apiKeyField.stringValue = savedKey ?: @"";
    
    // Load Models
    if ([provider isEqualToString:@"Gemini"]) {
        [self.modelCombo addItemsWithObjectValues:@[@"google/gemini-2.0-flash-exp:free", @"google/gemini-1.5-pro"]];
        NSString *savedModel = [defaults stringForKey:@"model_gemini"];
        self.modelCombo.stringValue = savedModel ?: @"google/gemini-2.0-flash-exp:free";
    } else if ([provider isEqualToString:@"Groq"]) {
        [self.modelCombo addItemsWithObjectValues:@[@"llama3-8b-8192", @"mixtral-8x7b-32768"]];
        NSString *savedModel = [defaults stringForKey:@"model_groq"];
        self.modelCombo.stringValue = savedModel ?: @"llama3-8b-8192";
    } else if ([provider isEqualToString:@"OpenRouter"]) {
        NSArray *cached = [defaults stringArrayForKey:@"cachedOpenRouterModels"];
        if (cached && cached.count > 0) {
            [self.modelCombo addItemsWithObjectValues:cached];
        } else {
            [self.modelCombo addItemsWithObjectValues:@[@"google/gemini-2.0-flash-exp:free"]];
        }
        NSString *savedModel = [defaults stringForKey:@"model_openrouter"];
        self.modelCombo.stringValue = savedModel ?: @"google/gemini-2.0-flash-exp:free";
    }
}

- (void)loadSettings {
    [self migrateLegacyUserDefaultsAPIKey];
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // 1. Language
    NSString *langCode = [IGLocalizationService sharedService].selectedLanguage;
    NSArray *codes = @[@"en", @"ru", @"be", @"ko", @"ja", @"zh", @"de", @"pl", @"et", @"es"];
    NSInteger langIndex = [codes indexOfObject:langCode];
    if (langIndex != NSNotFound) {
        [self.langPopup selectItemAtIndex:langIndex];
    }
    
    // 2. Provider
    NSString *storedProvider = [defaults stringForKey:@"provider"];
    NSString *provider = IGSettingsCanonicalProvider(storedProvider);
    if (![storedProvider isEqualToString:provider]) {
        [defaults setObject:provider forKey:@"provider"];
        [defaults synchronize];
    }
    self.providerCombo.stringValue = provider;
    
    // 3. Key & Model
    [self updateModelAndKeyForProvider:provider];
    
    // 4. Logging
    self.enableLoggingCheckbox.state = ([IGLogger desktopDiagnosticsEnabled] && [defaults boolForKey:@"enable_logging"]) ? NSOnState : NSOffState;
    self.onlyLocalCheckbox.state = [defaults boolForKey:@"only_local_mode"] ? NSOnState : NSOffState;
    self.hddSafeCheckbox.state = [defaults boolForKey:@"hdd_safe_mode"] ? NSOnState : NSOffState;
    self.showFooterCheckbox.state = [IGMainWindowController globalFooterVisible] ? NSOnState : NSOffState;
    
    // Sync AIService state
    [IGAIService sharedService].provider = provider;
    [IGAIService sharedService].model = self.modelCombo.stringValue;
    [IGAIService sharedService].apiKey = self.apiKeyField.stringValue;
}

- (void)showFooterChanged:(NSButton *)sender {
    [IGMainWindowController setGlobalFooterVisible:(sender.state == NSOnState)];
}

- (void)migrateLegacyUserDefaultsAPIKey {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *legacyKey = [defaults stringForKey:@"api_key"];
    
    if (legacyKey && legacyKey.length > 0) {
        NSString *provider = [IGSettingsCanonicalProvider([defaults stringForKey:@"provider"]) lowercaseString];
        BOOL success = [[IGKeychainHelper sharedHelper] saveString:legacyKey forAccount:provider];
        if (success) {
            [defaults removeObjectForKey:@"api_key"];
            [defaults synchronize];
            NSLog(@"Migrated legacy API key for provider '%@' to secure keychain.", provider);
        }
    }
}

- (void)syncClicked:(id)sender {
    self.statusLabel.stringValue = [[IGLocalizationService sharedService] t:@"checking"];
    [IGAIService sharedService].apiKey = self.apiKeyField.stringValue;
    
    [[IGAIService sharedService] fetchOpenRouterModelsWithDetailedCompletion:^(NSArray *models, NSError *error) {
        if (models.count > 0) {
            [self.modelCombo removeAllItems];
            [self.modelCombo addItemsWithObjectValues:models];
            
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            [defaults setObject:models forKey:@"cachedOpenRouterModels"];
            [defaults synchronize];
            
            self.statusLabel.stringValue = [[IGLocalizationService sharedService] t:@"sync_success"];
            
            NSAlert *alert = [[[NSAlert alloc] init] autorelease];
            [alert setMessageText:@"Success"];
            [alert setInformativeText:[NSString stringWithFormat:@"Synced %ld models from OpenRouter.", (long)models.count]];
            [alert runModal];
        } else {
            NSString *message = IGAIUserFacingNetworkErrorMessage(error);
            self.statusLabel.stringValue = message;
            NSAlert *alert = [[[NSAlert alloc] init] autorelease];
            [alert setMessageText:@"Network Error"];
            [alert setInformativeText:message];
            [alert runModal];
        }
    }];
}

- (void)showWaitSheetWithMessage:(NSString *)message {
    if (self.helpSheetWindow) {
        [self closeHelpSheet:nil];
    }

    NSWindow *sheet = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 140)
                                                   styleMask:NSTitledWindowMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES] autorelease];
    sheet.title = @"Syncrosa";

    NSProgressIndicator *spinner = [[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(32, 78, 32, 32)] autorelease];
    spinner.style = NSProgressIndicatorSpinningStyle;
    spinner.indeterminate = YES;
    [spinner startAnimation:nil];
    [sheet.contentView addSubview:spinner];

    NSTextField *label = [[[NSTextField alloc] initWithFrame:NSMakeRect(78, 58, 310, 54)] autorelease];
    label.stringValue = message ?: @"Please wait...";
    label.font = [NSFont systemFontOfSize:12];
    label.editable = NO;
    label.selectable = NO;
    label.bordered = NO;
    label.drawsBackground = NO;
    [[label cell] setWraps:YES];
    [sheet.contentView addSubview:label];

    IGApplyThemeToWindow(sheet);
    self.helpSheetWindow = sheet;
    [NSApp beginSheet:self.helpSheetWindow
       modalForWindow:self.view.window
        modalDelegate:nil
       didEndSelector:NULL
          contextInfo:NULL];
    [self.view.window display];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

- (void)syncLibClicked:(id)sender {
    if (![[IGiTunesService sharedService] iTunesIsRunning]) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:@"Open iTunes?"];
        [alert setInformativeText:@"Syncrosa needs iTunes to refresh the local library cache. It will not open iTunes unless you allow it."];
        [alert addButtonWithTitle:@"Open iTunes"];
        [alert addButtonWithTitle:@"Cancel"];
        NSInteger result = [alert runModal];
        if (result != NSAlertFirstButtonReturn) {
            self.syncLibStatusLabel.stringValue = @"Library sync cancelled.";
            return;
        }
        self.syncLibStatusLabel.stringValue = @"Opening iTunes...";
        [self showWaitSheetWithMessage:@"Opening iTunes. Please wait while Syncrosa prepares the library sync..."];
        if (![[IGiTunesService sharedService] launchITunesForUserActionWithOperation:@"settings library sync"]) {
            [self closeHelpSheet:nil];
            self.syncLibStatusLabel.stringValue = @"Could not open iTunes.";
            [IGNotificationView showInView:self.view message:@"Open iTunes manually, then click Sync Library again." isError:YES];
            return;
        }
        [self closeHelpSheet:nil];
    }

    self.syncLibStatusLabel.stringValue = @"Syncing iTunes tracks...";
    self.syncLibButton.enabled = NO;

    [[IGiTunesService sharedService] fetchLibraryTrackCountWithCompletion:^(NSInteger trackCount, NSString *errorMessage) {
        if (trackCount < 0) {
            self.syncLibStatusLabel.stringValue = errorMessage ?: @"Could not read iTunes library.";
            self.syncLibButton.enabled = YES;
            [IGNotificationView showInView:self.view message:self.syncLibStatusLabel.stringValue isError:YES];
            return;
        }
        if (trackCount == 0) {
            self.syncLibStatusLabel.stringValue = @"iTunes library is readable, but it has no tracks.";
            self.syncLibButton.enabled = YES;
            [IGNotificationView showInView:self.view message:self.syncLibStatusLabel.stringValue isError:YES];
            return;
        }

        [[IGiTunesService sharedService] fetchAllTracksWithProgress:^(NSInteger current, NSInteger total) {
            self.syncLibStatusLabel.stringValue = [NSString stringWithFormat:@"Synced %ld / %ld tracks...", (long)current, (long)total];
        } completion:^(NSArray *tracks) {
            if (tracks.count == 0) {
                self.syncLibStatusLabel.stringValue = @"No readable iTunes tracks were returned.";
                self.syncLibButton.enabled = YES;
                [IGNotificationView showInView:self.view message:self.syncLibStatusLabel.stringValue isError:YES];
                return;
            }

            self.syncLibStatusLabel.stringValue = [[IGLocalizationService sharedService] t:@"msg_lib_synced"];
            self.syncLibButton.enabled = YES;

            [IGNotificationView showInView:self.view message:[[IGLocalizationService sharedService] t:@"msg_lib_synced"] isError:NO];
        }];
    }];
}

- (void)checkUpdatesClicked:(id)sender {
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    self.updateCheckButton.enabled = NO;
    self.updateOpenButton.enabled = NO;
    self.latestUpdateURL = @"";
    self.latestReleaseTitle = @"";
    self.latestReleaseNotes = IGUpdateBundledReleaseNotes();
    self.releaseNotesButton.enabled = YES;
    self.updateStatusLabel.stringValue = [lang.selectedLanguage isEqualToString:@"ru"] ? @"Проверяю обновления..." : @"Checking for updates...";

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSError *updateError = nil;
        NSDictionary *info = [IGLatestUpdateInfoWithError(&updateError) retain];
        NSString *message = nil;
        NSString *targetURL = nil;
        NSString *title = nil;
        NSString *notes = nil;
        BOOL isError = NO;
        BOOL updateAvailable = NO;

        if (!info) {
            message = IGUpdateShortErrorMessage(updateError);
            title = @"Update Check Details";
            notes = IGUpdateDetailedErrorMessage(updateError);
            isError = YES;
        } else {
            NSString *latest = [info objectForKey:@"version"];
            NSString *current = IGCurrentApplicationVersionString();
            title = IGUpdateReleaseTitleFromInfo(info);
            notes = IGUpdateReleaseNotesFromInfo(info);
            targetURL = IGUpdateDownloadURLStringFromInfo(info);
            if ([targetURL length] == 0) {
                targetURL = IGUpdateReleaseURLStringFromInfo(info);
            }

            if ([latest length] == 0) {
                message = IGUpdateShortErrorMessage(nil);
                title = @"Update Check Details";
                notes = @"The update source did not include a readable Syncrosa version.";
                isError = YES;
            } else if (IGVersionStringIsNewer(latest, current)) {
                message = [NSString stringWithFormat:@"Syncrosa %@ is available.", latest];
                updateAvailable = YES;
            } else {
                message = [NSString stringWithFormat:@"Syncrosa %@ is installed.", current];
            }
        }

        [message retain];
        [targetURL retain];
        [title retain];
        [notes retain];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.latestUpdateURL = updateAvailable ? targetURL : @"";
            self.updateStatusLabel.stringValue = message ?: @"Update check finished.";
            self.updateCheckButton.enabled = YES;
            self.updateOpenButton.enabled = updateAvailable;
            self.latestReleaseTitle = title ?: @"Syncrosa Release Notes";
            self.latestReleaseNotes = notes ?: IGUpdateBundledReleaseNotes();
            self.releaseNotesButton.enabled = YES;
            [IGNotificationView showInView:self.view message:self.updateStatusLabel.stringValue isError:isError];
            [info release];
            [message release];
            [targetURL release];
            [title release];
            [notes release];
        });
        [pool drain];
    });
}

- (void)openUpdateClicked:(id)sender {
    if (![self.updateOpenButton isEnabled] || self.latestUpdateURL.length == 0) {
        return;
    }
    NSString *urlString = self.latestUpdateURL;
    if (!IGUpdateURLStringIsTrusted(urlString)) {
        self.updateStatusLabel.stringValue = @"Update link is not trusted.";
        [IGNotificationView showInView:self.view message:self.updateStatusLabel.stringValue isError:YES];
        return;
    }
    NSURL *url = [NSURL URLWithString:urlString];
    if (url) {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

- (void)saveClicked:(id)sender {
    self.statusLabel.stringValue = [[IGLocalizationService sharedService] t:@"checking"];
    self.saveButton.enabled = NO;
    
    NSString *currentProvider = IGSettingsCanonicalProvider(self.providerCombo.stringValue);
    NSString *currentModel = self.modelCombo.stringValue;
    NSString *currentKey = self.apiKeyField.stringValue;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:(self.onlyLocalCheckbox.state == NSOnState) forKey:@"only_local_mode"];
    [defaults setBool:(self.hddSafeCheckbox.state == NSOnState) forKey:@"hdd_safe_mode"];
    [defaults synchronize];
    
    [IGAIService sharedService].provider = currentProvider;
    [IGAIService sharedService].model = currentModel;
    [IGAIService sharedService].apiKey = currentKey;
    
    [[IGAIService sharedService] validateAPIKeyWithCompletion:^(BOOL success, NSString *errorMsg) {
        if (success) {
            self.statusLabel.stringValue = @"Settings saved successfully!";
            
            [defaults setObject:currentProvider forKey:@"provider"];
            [defaults setObject:currentModel forKey:@"model"];
            
            // Save model per-provider
            NSString *providerKey = [NSString stringWithFormat:@"model_%@", [currentProvider lowercaseString]];
            [defaults setObject:currentModel forKey:providerKey];
            
            [defaults setBool:([IGLogger desktopDiagnosticsEnabled] && self.enableLoggingCheckbox.state == NSOnState) forKey:@"enable_logging"];
            [defaults setBool:(self.onlyLocalCheckbox.state == NSOnState) forKey:@"only_local_mode"];
            [defaults setBool:(self.hddSafeCheckbox.state == NSOnState) forKey:@"hdd_safe_mode"];
            [defaults synchronize];
            
            // Securely save API Key to Keychain
            [[IGKeychainHelper sharedHelper] saveString:currentKey forAccount:[currentProvider lowercaseString]];
            
            // Notify UI to update buttons
            id controller = self.view.window.windowController;
            if ([controller isKindOfClass:[IGMainWindowController class]]) {
                [(IGMainWindowController *)controller updateButtonStates];
            }
            
            NSAlert *alert = [[[NSAlert alloc] init] autorelease];
            [alert setMessageText:@"Settings Saved"];
            [alert setInformativeText:@"AI Provider configuration has been validated and saved securely in the Keychain."];
            [alert runModal];
        } else {
            self.statusLabel.stringValue = [NSString stringWithFormat:@"Validation failed: %@", errorMsg];
            NSAlert *alert = [[[NSAlert alloc] init] autorelease];
            [alert setMessageText:@"Validation Error"];
            [alert setInformativeText:errorMsg];
            [alert runModal];
        }
        self.saveButton.enabled = YES;
    }];
}

@end
