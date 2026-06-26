#import "IGSettingsViewController.h"
#import "IGAIService.h"
#import "IGMainWindowController.h"
#import "IGKeychainHelper.h"
#import "IGLocalizationService.h"
#import "IGNotificationView.h"
#import "IGiTunesService.h"

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
@property (nonatomic, strong) NSButton *syncLibButton;
@property (nonatomic, strong) NSTextField *syncLibStatusLabel;
@property (nonatomic, strong) NSButton *saveButton;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextField *footerLabel;
@property (nonatomic, strong) NSButton *helpBtn;
@property (nonatomic, strong) NSWindow *helpSheetWindow;

@end

@implementation IGSettingsViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 480)];
    [self setupUI];
    [self loadSettings];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(localizationChanged:)
                                                 name:@"IGLanguageChangedNotification"
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupUI {
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    CGFloat y = 430;
    
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
    [self.view addSubview:self.enableLoggingCheckbox];
    
    y -= 45;
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
    
    y -= 55;
    // Save Button
    self.saveButton = [[NSButton alloc] initWithFrame:NSMakeRect(190, y, 200, 40)];
    self.saveButton.bezelStyle = NSTexturedRoundedBezelStyle;
    self.saveButton.target = self;
    self.saveButton.action = @selector(saveClicked:);
    [self.view addSubview:self.saveButton];
    
    y -= 40;
    self.statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 20)];
    self.statusLabel.stringValue = @"";
    self.statusLabel.editable = NO;
    self.statusLabel.bordered = NO;
    self.statusLabel.drawsBackground = NO;
    self.statusLabel.alignment = NSCenterTextAlignment;
    [self.view addSubview:self.statusLabel];
    
    // Help Button
    self.helpBtn = [[NSButton alloc] initWithFrame:NSMakeRect(520, 432, 25, 25)];
    self.helpBtn.bezelStyle = NSBezelStyleHelpButton;
    self.helpBtn.title = @"";
    self.helpBtn.target = self;
    self.helpBtn.action = @selector(helpClicked:);
    [self.view addSubview:self.helpBtn];
    
    // Footer
    self.footerLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 20, 500, 40)];
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
    
    if (self.syncLibStatusLabel.stringValue.length == 0 || 
        [self.syncLibStatusLabel.stringValue isEqualToString:@"Refresh your local music database cache."] ||
        [self.syncLibStatusLabel.stringValue isEqualToString:@"Обновите локальный кэш музыкальной базы."]) {
        self.syncLibStatusLabel.stringValue = [lang t:@"refresh_cache"];
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
                                                  styleMask:NSWindowStyleMaskTitled
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
    [self.view.window beginSheet:sheet completionHandler:nil];
}

- (void)closeHelpSheet:(id)sender {
    if (self.helpSheetWindow) {
        [self.view.window endSheet:self.helpSheetWindow];
        [self.helpSheetWindow orderOut:nil];
        self.helpSheetWindow = nil;
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
    NSString *provider = [defaults stringForKey:@"provider"] ?: @"Gemini";
    self.providerCombo.stringValue = provider;
    
    // 3. Key & Model
    [self updateModelAndKeyForProvider:provider];
    
    // 4. Logging
    self.enableLoggingCheckbox.state = [defaults boolForKey:@"enable_logging"] ? NSOnState : NSOffState;
    
    // Sync AIService state
    [IGAIService sharedService].provider = provider;
    [IGAIService sharedService].model = self.modelCombo.stringValue;
    [IGAIService sharedService].apiKey = self.apiKeyField.stringValue;
}

- (void)migrateLegacyUserDefaultsAPIKey {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *legacyKey = [defaults stringForKey:@"api_key"];
    
    if (legacyKey && legacyKey.length > 0) {
        NSString *provider = [[defaults stringForKey:@"provider"] lowercaseString] ?: @"gemini";
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
    
    [[IGiTunesService sharedService] fetchAllTracksWithProgress:^(NSInteger current, NSInteger total) {
        self.syncLibStatusLabel.stringValue = [NSString stringWithFormat:@"Synced %ld / %ld tracks...", (long)current, (long)total];
    } completion:^(NSArray *tracks) {
        self.syncLibStatusLabel.stringValue = [[IGLocalizationService sharedService] t:@"msg_lib_synced"];
        self.syncLibButton.enabled = YES;
        
        [IGNotificationView showInView:self.view message:[[IGLocalizationService sharedService] t:@"msg_lib_synced"] isError:NO];
    }];
}

- (void)saveClicked:(id)sender {
    self.statusLabel.stringValue = [[IGLocalizationService sharedService] t:@"checking"];
    self.saveButton.enabled = NO;
    
    NSString *currentProvider = self.providerCombo.stringValue;
    NSString *currentModel = self.modelCombo.stringValue;
    NSString *currentKey = self.apiKeyField.stringValue;
    
    [IGAIService sharedService].provider = currentProvider;
    [IGAIService sharedService].model = currentModel;
    [IGAIService sharedService].apiKey = currentKey;
    
    [[IGAIService sharedService] validateAPIKeyWithCompletion:^(BOOL success, NSString *errorMsg) {
        if (success) {
            self.statusLabel.stringValue = @"Settings saved successfully!";
            
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            [defaults setObject:currentProvider forKey:@"provider"];
            [defaults setObject:currentModel forKey:@"model"];
            
            // Save model per-provider
            NSString *providerKey = [NSString stringWithFormat:@"model_%@", [currentProvider lowercaseString]];
            [defaults setObject:currentModel forKey:providerKey];
            
            [defaults setBool:(self.enableLoggingCheckbox.state == NSOnState) forKey:@"enable_logging"];
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
