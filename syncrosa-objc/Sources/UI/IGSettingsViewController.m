#import "IGSettingsViewController.h"
#import "IGAIService.h"
#import "IGMainWindowController.h"
#import "IGKeychainHelper.h"
#import "IGLocalizationService.h"
#import "IGNotificationView.h"
#import "IGiTunesService.h"
#import "IGLogger.h"

static NSString *IGSettingsCanonicalProvider(NSString *provider) {
    if ([provider caseInsensitiveCompare:@"Groq"] == NSOrderedSame) {
        return @"Groq";
    }
    if ([provider caseInsensitiveCompare:@"OpenRouter"] == NSOrderedSame) {
        return @"OpenRouter";
    }
    return @"Gemini";
}

static NSString *IGSettingsCurrentVersion(void) {
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (version.length == 0) {
        version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
    }
    return version.length > 0 ? version : @"Development";
}

static NSString *IGSettingsTempPath(NSString *extension) {
    NSString *baseName = [NSString stringWithFormat:@"syncrosa-update-%@", [[NSProcessInfo processInfo] globallyUniqueString]];
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[baseName stringByAppendingPathExtension:extension]];
}

static BOOL IGSettingsCreatePrivateFile(NSString *path) {
    NSDictionary *attrs = @{NSFilePosixPermissions: [NSNumber numberWithUnsignedLong:0600]};
    return [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:attrs];
}

static NSString *IGSettingsDecodeUTF8(NSData *data) {
    if (data.length == 0) {
        return @"";
    }
    NSString *text = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if (!text) {
        text = [[[NSString alloc] initWithData:data encoding:NSMacOSRomanStringEncoding] autorelease];
    }
    return text ?: @"";
}

static NSString *IGSettingsBundledReleaseNotes(void) {
    return @"Syncrosa Legacy Update Notes\n\n"
           "This build includes the latest bundled release notes available inside the app.\n\n"
           "What's improved:\n"
           "- Safer update buttons and release notes fallback for older OS X systems.\n"
           "- Recovery Center layout fixes for the legacy Cocoa interface.\n"
           "- Library Doctor now uses simple native tab buttons instead of fragile Mavericks segmented controls.\n"
           "- Duplicate Finder progress bar now uses the same native style as the other legacy tools.\n\n"
           "If this Mac cannot reach GitHub because of old system certificates, open the Syncrosa releases page manually from a newer browser:\n"
           "https://github.com/MiChiRose/Syncrosa/releases";
}

static NSString *IGSettingsFriendlyUpdateError(NSString *technicalError) {
    NSString *details = technicalError.length > 0 ? technicalError : @"Unknown network error.";
    return [NSString stringWithFormat:
            @"Syncrosa could not reach GitHub Releases from this Mac.\n\n"
            "Older OS X systems can reject modern TLS certificate chains even when the app ships a fresh CA bundle. Syncrosa did not disable certificate checks.\n\n"
            "Technical details:\n%@\n\n"
            "Manual releases page:\nhttps://github.com/MiChiRose/Syncrosa/releases\n\n%@",
            details,
            IGSettingsBundledReleaseNotes()];
}

static NSString *IGSettingsUpdateErrorSummary(void) {
    return @"Network update error. Open Release Notes for details.";
}

static void IGSettingsFetchURLWithCurl(NSURL *url, NSDictionary *headers, void(^completionBlock)(NSData *data, NSError *error)) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *stdoutPath = IGSettingsTempPath(@"stdout");
        NSString *stderrPath = IGSettingsTempPath(@"stderr");
        IGSettingsCreatePrivateFile(stdoutPath);
        IGSettingsCreatePrivateFile(stderrPath);

        NSFileHandle *stdoutHandle = [NSFileHandle fileHandleForWritingAtPath:stdoutPath];
        NSFileHandle *stderrHandle = [NSFileHandle fileHandleForWritingAtPath:stderrPath];
        if (!stdoutHandle || !stderrHandle) {
            NSError *fileError = [NSError errorWithDomain:@"IGSettingsCurlError"
                                                     code:-2
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Could not create temporary curl output files."}];
            completionBlock(nil, fileError);
            return;
        }

        NSMutableArray *args = [NSMutableArray arrayWithObjects:
                                @"-q",
                                @"--silent",
                                @"--show-error",
                                @"--location",
                                @"--max-time", @"60",
                                nil];
        NSString *caPath = [[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"];
        if (caPath.length > 0) {
            [args addObjectsFromArray:@[@"--cacert", caPath]];
        }

        [args addObjectsFromArray:@[@"--header", @"User-Agent: Syncrosa-Legacy/1.0"]];
        for (NSString *key in headers) {
            NSString *value = [headers objectForKey:key];
            if (key.length > 0 && value.length > 0) {
                [args addObjectsFromArray:@[@"--header", [NSString stringWithFormat:@"%@: %@", key, value]]];
            }
        }
        [args addObject:url.absoluteString ?: @""];

        NSTask *task = [[[NSTask alloc] init] autorelease];
        [task setLaunchPath:@"/usr/bin/curl"];
        [task setArguments:args];
        if (caPath.length > 0) {
            NSMutableDictionary *environment = [NSMutableDictionary dictionaryWithDictionary:[[NSProcessInfo processInfo] environment]];
            [environment setObject:caPath forKey:@"SSL_CERT_FILE"];
            [environment setObject:caPath forKey:@"CURL_CA_BUNDLE"];
            [task setEnvironment:environment];
        }
        [task setStandardOutput:stdoutHandle];
        [task setStandardError:stderrHandle];

        @try {
            [task launch];
            [task waitUntilExit];
        } @catch (NSException *exception) {
            [stdoutHandle closeFile];
            [stderrHandle closeFile];
            [[NSFileManager defaultManager] removeItemAtPath:stdoutPath error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:stderrPath error:nil];
            NSString *reason = exception.reason ?: @"Could not launch curl.";
            NSError *launchError = [NSError errorWithDomain:@"IGSettingsCurlException"
                                                       code:-1
                                                   userInfo:@{NSLocalizedDescriptionKey: reason}];
            completionBlock(nil, launchError);
            return;
        }

        [stdoutHandle closeFile];
        [stderrHandle closeFile];

        NSData *curlData = [NSData dataWithContentsOfFile:stdoutPath];
        NSData *stderrData = [NSData dataWithContentsOfFile:stderrPath];
        NSString *stderrText = IGSettingsDecodeUTF8(stderrData);

        [[NSFileManager defaultManager] removeItemAtPath:stdoutPath error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:stderrPath error:nil];

        if ([task terminationStatus] == 0 && curlData.length > 0) {
            completionBlock(curlData, nil);
            return;
        }

        NSString *message = stderrText.length > 0 ?
            [NSString stringWithFormat:@"Curl failed with status %d: %@", [task terminationStatus], stderrText] :
            [NSString stringWithFormat:@"Curl failed with status %d", [task terminationStatus]];
        NSError *curlError = [NSError errorWithDomain:@"IGSettingsCurlError"
                                                 code:[task terminationStatus]
                                             userInfo:@{NSLocalizedDescriptionKey: message}];
        completionBlock(nil, curlError);
    });
}

static NSArray *IGSettingsVersionParts(NSString *version) {
    NSMutableArray *parts = [NSMutableArray array];
    NSScanner *scanner = [NSScanner scannerWithString:version ?: @""];
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    while (![scanner isAtEnd]) {
        NSString *number = nil;
        if ([scanner scanCharactersFromSet:digits intoString:&number]) {
            [parts addObject:@([number integerValue])];
        } else {
            [scanner scanUpToCharactersFromSet:digits intoString:NULL];
        }
    }
    return parts;
}

static NSComparisonResult IGSettingsCompareVersions(NSString *left, NSString *right) {
    NSArray *leftParts = IGSettingsVersionParts(left);
    NSArray *rightParts = IGSettingsVersionParts(right);
    NSUInteger count = MAX(leftParts.count, rightParts.count);
    NSUInteger index = 0;
    for (index = 0; index < count; index++) {
        NSInteger leftValue = index < leftParts.count ? [[leftParts objectAtIndex:index] integerValue] : 0;
        NSInteger rightValue = index < rightParts.count ? [[rightParts objectAtIndex:index] integerValue] : 0;
        if (leftValue > rightValue) return NSOrderedDescending;
        if (leftValue < rightValue) return NSOrderedAscending;
    }
    return NSOrderedSame;
}

@interface IGSettingsViewController () <NSComboBoxDelegate>

@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *langLabel;
@property (nonatomic, strong) NSPopUpButton *langPopup;
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
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 500)];
    [self setupUI];
    [self loadSettings];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(localizationChanged:)
                                                 name:@"IGLanguageChangedNotification"
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
#if !__has_feature(objc_arc)
    [super dealloc];
#endif
}

- (void)setupUI {
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    CGFloat y = 465;
    self.latestUpdateURL = @"https://github.com/MiChiRose/Syncrosa/releases/latest";
    self.latestReleaseTitle = @"";
    self.latestReleaseNotes = @"";
    
    // Title
    self.titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 480, 30)];
    self.titleLabel.font = [NSFont boldSystemFontOfSize:18];
    self.titleLabel.editable = NO;
    self.titleLabel.bordered = NO;
    self.titleLabel.drawsBackground = NO;
    [self.view addSubview:self.titleLabel];
    
    y -= 45;
    // Language Section
    self.langLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 120, 20)];
    self.langLabel.font = [NSFont systemFontOfSize:13];
    self.langLabel.editable = NO;
    self.langLabel.bordered = NO;
    self.langLabel.drawsBackground = NO;
    [self.view addSubview:self.langLabel];
    
    self.langPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(150, y-2, 200, 26) pullsDown:NO];
    [self.langPopup addItemsWithTitles:@[@"English", @"Русский", @"Беларуская", @"한국어", @"日本語", @"中文", @"Deutsch", @"Polski", @"Eesti", @"Español"]];
    self.langPopup.target = self;
    self.langPopup.action = @selector(languagePopupChanged:);
    [self.view addSubview:self.langPopup];
    
    y -= 45;
    // AI Provider Section
    self.providerLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 120, 20)];
    self.providerLabel.font = [NSFont systemFontOfSize:13];
    self.providerLabel.editable = NO;
    self.providerLabel.bordered = NO;
    self.providerLabel.drawsBackground = NO;
    [self.view addSubview:self.providerLabel];
    
    self.providerCombo = [[NSComboBox alloc] initWithFrame:NSMakeRect(150, y-2, 200, 26)];
    [self.providerCombo addItemsWithObjectValues:@[@"Gemini", @"OpenRouter", @"Groq"]];
    self.providerCombo.editable = NO;
    self.providerCombo.delegate = self;
    [self.view addSubview:self.providerCombo];
    
    y -= 45;
    // Model Section
    self.modelLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 120, 20)];
    self.modelLabel.font = [NSFont systemFontOfSize:13];
    self.modelLabel.editable = NO;
    self.modelLabel.bordered = NO;
    self.modelLabel.drawsBackground = NO;
    [self.view addSubview:self.modelLabel];
    
    self.modelCombo = [[NSComboBox alloc] initWithFrame:NSMakeRect(150, y-2, 270, 26)];
    [self.view addSubview:self.modelCombo];
    
    self.syncModelsBtn = [[NSButton alloc] initWithFrame:NSMakeRect(430, y-2, 130, 30)];
    self.syncModelsBtn.bezelStyle = NSRoundedBezelStyle;
    self.syncModelsBtn.target = self;
    self.syncModelsBtn.action = @selector(syncClicked:);
    [self.view addSubview:self.syncModelsBtn];
    
    y -= 45;
    // API Key Section
    self.apiKeyLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 120, 20)];
    self.apiKeyLabel.font = [NSFont systemFontOfSize:13];
    self.apiKeyLabel.editable = NO;
    self.apiKeyLabel.bordered = NO;
    self.apiKeyLabel.drawsBackground = NO;
    [self.view addSubview:self.apiKeyLabel];
    
    self.apiKeyField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(150, y-2, 410, 24)];
    [self.view addSubview:self.apiKeyField];
    
    y -= 35;
    // Logging Checkbox
    self.enableLoggingCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(20, y, 540, 20)];
    self.enableLoggingCheckbox.buttonType = NSSwitchButton;
    self.enableLoggingCheckbox.hidden = ![IGLogger desktopDiagnosticsEnabled];
    self.enableLoggingCheckbox.enabled = [IGLogger desktopDiagnosticsEnabled];
    [self.view addSubview:self.enableLoggingCheckbox];

    y -= 25;
    self.onlyLocalCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(20, y, 260, 20)];
    self.onlyLocalCheckbox.buttonType = NSSwitchButton;
    self.onlyLocalCheckbox.title = @"Only Local Mode";
    [self.view addSubview:self.onlyLocalCheckbox];

    self.historyButton = [[NSButton alloc] initWithFrame:NSMakeRect(300, y - 4, 180, 28)];
    self.historyButton.bezelStyle = NSRoundedBezelStyle;
    self.historyButton.title = @"Operation History";
    self.historyButton.target = self;
    self.historyButton.action = @selector(historyClicked:);
    [self.view addSubview:self.historyButton];

    y -= 25;
    self.hddSafeCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(20, y, 260, 20)];
    self.hddSafeCheckbox.buttonType = NSSwitchButton;
    self.hddSafeCheckbox.title = @"HDD Safe Mode";
    [self.view addSubview:self.hddSafeCheckbox];

    self.recoveryButton = [[NSButton alloc] initWithFrame:NSMakeRect(300, y - 4, 180, 28)];
    self.recoveryButton.bezelStyle = NSRoundedBezelStyle;
    self.recoveryButton.title = @"Recovery Center";
    self.recoveryButton.target = self;
    self.recoveryButton.action = @selector(recoveryClicked:);
    [self.view addSubview:self.recoveryButton];
    
    y -= 35;
    // Library Sync Section
    self.syncLibButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, y, 200, 30)];
    self.syncLibButton.bezelStyle = NSRoundedBezelStyle;
    self.syncLibButton.target = self;
    self.syncLibButton.action = @selector(syncLibClicked:);
    [self.view addSubview:self.syncLibButton];
    
    self.syncLibStatusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(230, y+5, 330, 20)];
    self.syncLibStatusLabel.font = [NSFont systemFontOfSize:11];
    self.syncLibStatusLabel.textColor = [NSColor grayColor];
    self.syncLibStatusLabel.editable = NO;
    self.syncLibStatusLabel.bordered = NO;
    self.syncLibStatusLabel.drawsBackground = NO;
    [self.view addSubview:self.syncLibStatusLabel];

    y -= 40;
    // Updates Section
    self.updateCheckButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, y, 145, 30)];
    self.updateCheckButton.bezelStyle = NSRoundedBezelStyle;
    self.updateCheckButton.target = self;
    self.updateCheckButton.action = @selector(checkUpdatesClicked:);
    [self.view addSubview:self.updateCheckButton];

    self.updateOpenButton = [[NSButton alloc] initWithFrame:NSMakeRect(175, y, 120, 30)];
    self.updateOpenButton.bezelStyle = NSRoundedBezelStyle;
    self.updateOpenButton.target = self;
    self.updateOpenButton.action = @selector(openUpdateClicked:);
    self.updateOpenButton.enabled = NO;
    [self.view addSubview:self.updateOpenButton];

    self.releaseNotesButton = [[NSButton alloc] initWithFrame:NSMakeRect(305, y, 125, 30)];
    self.releaseNotesButton.bezelStyle = NSRoundedBezelStyle;
    self.releaseNotesButton.target = self;
    self.releaseNotesButton.action = @selector(releaseNotesClicked:);
    self.releaseNotesButton.enabled = NO;
    [self.view addSubview:self.releaseNotesButton];

    self.updateStatusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y - 20, 540, 20)];
    self.updateStatusLabel.font = [NSFont systemFontOfSize:11];
    self.updateStatusLabel.textColor = [NSColor grayColor];
    self.updateStatusLabel.editable = NO;
    self.updateStatusLabel.bordered = NO;
    self.updateStatusLabel.drawsBackground = NO;
    self.updateStatusLabel.stringValue = [NSString stringWithFormat:@"Current version: %@", IGSettingsCurrentVersion()];
    [self.view addSubview:self.updateStatusLabel];
    
    y -= 56;
    // Save Button
    self.saveButton = [[NSButton alloc] initWithFrame:NSMakeRect(190, y, 200, 40)];
    self.saveButton.bezelStyle = NSTexturedRoundedBezelStyle;
    self.saveButton.target = self;
    self.saveButton.action = @selector(saveClicked:);
    [self.view addSubview:self.saveButton];
    
    y -= 36;
    self.statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 20)];
    self.statusLabel.stringValue = @"";
    self.statusLabel.editable = NO;
    self.statusLabel.bordered = NO;
    self.statusLabel.drawsBackground = NO;
    self.statusLabel.alignment = NSCenterTextAlignment;
    [self.view addSubview:self.statusLabel];
    
    // Help Button
    self.helpBtn = [[NSButton alloc] initWithFrame:NSMakeRect(520, 467, 25, 25)];
    self.helpBtn.bezelStyle = NSHelpButtonBezelStyle;
    self.helpBtn.title = @"";
    self.helpBtn.target = self;
    self.helpBtn.action = @selector(helpClicked:);
    [self.view addSubview:self.helpBtn];
    
    // Footer
    self.footerLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 4, 500, 30)];
    self.footerLabel.font = [NSFont systemFontOfSize:10];
    self.footerLabel.textColor = [NSColor grayColor];
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
        self.updateStatusLabel.stringValue = [NSString stringWithFormat:@"Current version: %@", IGSettingsCurrentVersion()];
    }
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

- (void)languagePopupChanged:(id)sender {
    NSArray *codes = @[@"en", @"ru", @"be", @"ko", @"ja", @"zh", @"de", @"pl", @"et", @"es"];
    NSInteger index = [self.langPopup indexOfSelectedItem];
    if (index >= 0 && index < codes.count) {
        [IGLocalizationService sharedService].selectedLanguage = codes[index];
    }
}

- (void)helpClicked:(id)sender {
    NSString *helpText = @"API Key Setup Guide\n\n"
                          "To use Syncrosa, you need an API key from one of our supported AI providers:\n\n"
                          "1. OpenRouter (Recommended)\n"
                          "- Where: openrouter.ai/keys\n"
                          "- Format: 'sk-or-v1-...' (starts with sk-or)\n"
                          "- Why: Gives access to many free models (like google/gemini-2.0-flash-exp:free) even in geo-blocked regions.\n\n"
                          "2. Google Gemini\n"
                          "- Where: aistudio.google.com/app/apikey\n"
                          "- Format: 'AIzaSy...'\n"
                          "- Why: Direct access to Google's fast models.\n\n"
                          "3. Groq\n"
                          "- Where: console.groq.com/keys\n"
                          "- Format: 'gsk_...'\n"
                          "- Why: Extremely fast generation.\n\n"
                          "Common Errors:\n"
                          "- 'Invalid Key': Make sure there are no spaces at the start or end.\n"
                          "- 'Model Not Found': Click 'Sync Models' to get the latest available list.\n\n"
                          "How to Check:\n"
                          "Enter the key above and click 'VALIDATE & SAVE'. The app will test it immediately.";
    
    NSWindow *sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 280)
                                                  styleMask:NSTitledWindowMask
                                                    backing:NSBackingStoreBuffered
                                                      defer:YES];
    
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 60, 380, 200)];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    
    NSTextView *textView = [[NSTextView alloc] initWithFrame:scroll.bounds];
    textView.editable = NO;
    textView.string = helpText;
    textView.font = [NSFont systemFontOfSize:12];
    scroll.documentView = textView;
    [sheet.contentView addSubview:scroll];
    
    NSButton *closeButton = [[NSButton alloc] initWithFrame:NSMakeRect(160, 15, 100, 30)];
    closeButton.title = @"OK";
    closeButton.bezelStyle = NSRoundedBezelStyle;
    closeButton.target = self;
    closeButton.action = @selector(closeHelpSheet:);
    [sheet.contentView addSubview:closeButton];
    
    self.helpSheetWindow = sheet;
    if ([self.view.window respondsToSelector:@selector(beginSheet:completionHandler:)]) {
        [self.view.window beginSheet:sheet completionHandler:nil];
    } else {
        [NSApp beginSheet:sheet modalForWindow:self.view.window modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
    }
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
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (text.length == 0) {
        text = [NSString stringWithFormat:@"No history file found yet.\n\nExpected path:\n%@", path];
    }

    NSWindow *sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 520, 360)
                                                  styleMask:NSTitledWindowMask
                                                    backing:NSBackingStoreBuffered
                                                      defer:YES];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 60, 480, 280)];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    NSTextView *textView = [[NSTextView alloc] initWithFrame:scroll.bounds];
    textView.editable = NO;
    textView.string = text;
    textView.font = [NSFont fontWithName:@"Monaco" size:10] ?: [NSFont systemFontOfSize:10];
    scroll.documentView = textView;
    [sheet.contentView addSubview:scroll];

    NSButton *closeButton = [[NSButton alloc] initWithFrame:NSMakeRect(210, 15, 100, 30)];
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    closeButton.title = [lang.selectedLanguage isEqualToString:@"ru"] ? @"Закрыть" : @"Close";
    closeButton.bezelStyle = NSRoundedBezelStyle;
    closeButton.target = self;
    closeButton.action = @selector(closeHelpSheet:);
    [sheet.contentView addSubview:closeButton];

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
    NSString *text = self.latestReleaseNotes.length > 0 ? self.latestReleaseNotes : @"Run Check Updates first.";
    [self showTextSheetWithTitle:title text:text monospace:NO];
}

- (void)showTextSheetWithTitle:(NSString *)title text:(NSString *)text monospace:(BOOL)monospace {
    NSWindow *sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 540, 380)
                                                  styleMask:NSTitledWindowMask
                                                    backing:NSBackingStoreBuffered
                                                      defer:YES];
    NSTextField *titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(24, 338, 492, 24)];
    titleLabel.stringValue = title ?: @"";
    titleLabel.font = [NSFont boldSystemFontOfSize:15];
    titleLabel.editable = NO;
    titleLabel.bordered = NO;
    titleLabel.drawsBackground = NO;
    [sheet.contentView addSubview:titleLabel];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(24, 62, 492, 258)];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    NSTextView *textView = [[NSTextView alloc] initWithFrame:scroll.bounds];
    textView.editable = NO;
    textView.string = text ?: @"";
    textView.font = monospace ? ([NSFont fontWithName:@"Monaco" size:10] ?: [NSFont systemFontOfSize:10]) : [NSFont systemFontOfSize:12];
    scroll.documentView = textView;
    [sheet.contentView addSubview:scroll];

    NSButton *closeButton = [[NSButton alloc] initWithFrame:NSMakeRect(220, 16, 100, 30)];
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    closeButton.title = [lang.selectedLanguage isEqualToString:@"ru"] ? @"Закрыть" : @"Close";
    closeButton.bezelStyle = NSRoundedBezelStyle;
    closeButton.target = self;
    closeButton.action = @selector(closeHelpSheet:);
    [sheet.contentView addSubview:closeButton];

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
    
    // Sync AIService state
    [IGAIService sharedService].provider = provider;
    [IGAIService sharedService].model = self.modelCombo.stringValue;
    [IGAIService sharedService].apiKey = self.apiKeyField.stringValue;
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
    
    [[IGAIService sharedService] fetchOpenRouterModelsWithCompletion:^(NSArray *models) {
        if (models.count > 0) {
            [self.modelCombo removeAllItems];
            [self.modelCombo addItemsWithObjectValues:models];
            
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            [defaults setObject:models forKey:@"cachedOpenRouterModels"];
            [defaults synchronize];
            
            self.statusLabel.stringValue = [[IGLocalizationService sharedService] t:@"sync_success"];
            
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Success"];
            [alert setInformativeText:[NSString stringWithFormat:@"Synced %ld models from OpenRouter.", (long)models.count]];
            [alert runModal];
        } else {
            self.statusLabel.stringValue = @"Sync failed. Check connection.";
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Network Error"];
            [alert setInformativeText:@"Failed to connect to AI server. On macOS 10.9-10.13, ensure your system clock is correct and root certificates are updated."];
            [alert runModal];
        }
    }];
}

- (void)syncLibClicked:(id)sender {
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
    self.releaseNotesButton.enabled = NO;
    self.latestUpdateURL = @"";
    self.latestReleaseTitle = @"";
    self.latestReleaseNotes = @"";
    self.updateStatusLabel.stringValue = [lang.selectedLanguage isEqualToString:@"ru"] ? @"Проверяю GitHub Releases..." : @"Checking GitHub Releases...";

    NSURL *url = [NSURL URLWithString:@"https://api.github.com/repos/MiChiRose/Syncrosa/releases/latest"];
    NSDictionary *headers = @{@"Accept": @"application/vnd.github+json"};

    IGSettingsFetchURLWithCurl(url, headers, ^(NSData *data, NSError *error) {
        NSString *message = nil;
        NSString *targetURL = @"https://github.com/MiChiRose/Syncrosa/releases/latest";
        BOOL isError = NO;
        BOOL updateAvailable = NO;

        if (error) {
            message = IGSettingsUpdateErrorSummary();
            self.latestReleaseTitle = @"Update Check Details";
            self.latestReleaseNotes = IGSettingsFriendlyUpdateError(error.localizedDescription);
            isError = YES;
        } else if (data.length == 0) {
            message = IGSettingsUpdateErrorSummary();
            self.latestReleaseTitle = @"Update Check Details";
            self.latestReleaseNotes = @"GitHub returned an empty response while checking for updates.";
            isError = YES;
        } else {
            NSError *jsonError = nil;
            id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            if (![parsed isKindOfClass:[NSDictionary class]]) {
                message = IGSettingsUpdateErrorSummary();
                self.latestReleaseTitle = @"Update Check Details";
                self.latestReleaseNotes = @"GitHub returned an unexpected response while checking for updates.";
                isError = YES;
            } else {
                NSDictionary *release = (NSDictionary *)parsed;
                NSString *latest = [release objectForKey:@"tag_name"] ?: [release objectForKey:@"name"];
                latest = [latest stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if ([latest hasPrefix:@"v"]) {
                    latest = [latest substringFromIndex:1];
                }
                NSString *releaseName = [release objectForKey:@"name"];
                NSString *releaseBody = [release objectForKey:@"body"];
                if ([releaseName isKindOfClass:[NSString class]]) {
                    self.latestReleaseTitle = releaseName;
                }
                if ([releaseBody isKindOfClass:[NSString class]]) {
                    self.latestReleaseNotes = releaseBody;
                }
                NSString *htmlURL = [release objectForKey:@"html_url"];
                if (htmlURL.length > 0) {
                    targetURL = htmlURL;
                }

                NSArray *assets = [release objectForKey:@"assets"];
                if ([assets isKindOfClass:[NSArray class]]) {
                    for (NSDictionary *asset in assets) {
                        if (![asset isKindOfClass:[NSDictionary class]]) continue;
                        NSString *name = [asset objectForKey:@"name"];
                        NSString *download = [asset objectForKey:@"browser_download_url"];
                        if ([name rangeOfString:@"Syncrosa_Cocoa_v"].location != NSNotFound && [[name pathExtension] isEqualToString:@"zip"] && download.length > 0) {
                            targetURL = download;
                            break;
                        }
                    }
                }

                NSString *current = IGSettingsCurrentVersion();
                if (latest.length == 0) {
                    message = IGSettingsUpdateErrorSummary();
                    self.latestReleaseTitle = @"Update Check Details";
                    self.latestReleaseNotes = @"GitHub did not include a readable Syncrosa version in the latest release response.";
                    isError = YES;
                } else if ([current isEqualToString:@"Development"]) {
                    message = [NSString stringWithFormat:@"Latest release: Syncrosa %@. This is a development build.", latest];
                } else if (IGSettingsCompareVersions(latest, current) == NSOrderedDescending) {
                    message = [NSString stringWithFormat:@"Syncrosa %@ is available. Click Update App.", latest];
                    updateAvailable = YES;
                } else {
                    message = [NSString stringWithFormat:@"You are up to date on Syncrosa %@.", current];
                }
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.latestUpdateURL = updateAvailable ? targetURL : @"";
            self.updateStatusLabel.stringValue = message ?: @"Update check finished.";
            self.updateCheckButton.enabled = YES;
            self.updateOpenButton.enabled = updateAvailable;
            self.releaseNotesButton.enabled = (self.latestReleaseNotes.length > 0);
            [IGNotificationView showInView:self.view message:self.updateStatusLabel.stringValue isError:isError];
        });
    });
}

- (void)openUpdateClicked:(id)sender {
    if (!self.updateOpenButton.enabled || self.latestUpdateURL.length == 0) {
        return;
    }
    NSString *urlString = self.latestUpdateURL;
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
            
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Settings Saved"];
            [alert setInformativeText:@"AI Provider configuration has been validated and saved securely in the Keychain."];
            [alert runModal];
        } else {
            self.statusLabel.stringValue = [NSString stringWithFormat:@"Validation failed: %@", errorMsg];
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Validation Error"];
            [alert setInformativeText:errorMsg];
            [alert runModal];
        }
        self.saveButton.enabled = YES;
    }];
}

@end
