#import "IGSettingsViewController.h"
#import "IGAIService.h"
#import "IGMainWindowController.h"

@interface IGSettingsViewController () <NSComboBoxDelegate>
@property (nonatomic, strong) NSComboBox *providerCombo;
@property (nonatomic, strong) NSComboBox *modelCombo;
@property (nonatomic, strong) NSTextField *apiKeyField;
@property (nonatomic, strong) NSButton *saveButton;
@property (nonatomic, strong) NSButton *enableLoggingCheckbox;
@property (nonatomic, strong) NSTextField *statusLabel;
@end

@implementation IGSettingsViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 480)];
    [self setupUI];
    [self loadSettings];
}

- (void)setupUI {
    CGFloat y = 430;
    
    NSTextField *titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 480, 30)];
    titleLabel.stringValue = @"AI Settings";
    titleLabel.font = [NSFont boldSystemFontOfSize:18];
    titleLabel.editable = NO;
    titleLabel.bordered = NO;
    titleLabel.drawsBackground = NO;
    [self.view addSubview:titleLabel];
    
    y -= 50;
    NSTextField *pLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 20)];
    pLabel.stringValue = @"AI Provider:";
    pLabel.editable = NO;
    pLabel.bordered = NO;
    pLabel.drawsBackground = NO;
    [self.view addSubview:pLabel];
    
    y -= 25;
    self.providerCombo = [[NSComboBox alloc] initWithFrame:NSMakeRect(20, y, 200, 26)];
    [self.providerCombo addItemsWithObjectValues:@[@"Gemini", @"OpenRouter", @"Groq"]];
    self.providerCombo.editable = NO;
    self.providerCombo.delegate = self;
    [self.view addSubview:self.providerCombo];
    
    y -= 40;
    NSTextField *mLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 20)];
    mLabel.stringValue = @"Model ID:";
    mLabel.editable = NO;
    mLabel.bordered = NO;
    mLabel.drawsBackground = NO;
    [self.view addSubview:mLabel];
    
    y -= 25;
    self.modelCombo = [[NSComboBox alloc] initWithFrame:NSMakeRect(20, y, 400, 26)];
    [self.modelCombo addItemsWithObjectValues:@[@"google/gemini-2.0-flash-exp:free", @"meta-llama/llama-3.1-8b-instruct:free"]];
    [self.view addSubview:self.modelCombo];
    
    NSButton *syncBtn = [[NSButton alloc] initWithFrame:NSMakeRect(430, y-2, 130, 30)];
    syncBtn.title = @"Sync Models";
    syncBtn.bezelStyle = NSRoundedBezelStyle;
    syncBtn.target = self;
    syncBtn.action = @selector(syncClicked:);
    [self.view addSubview:syncBtn];
    
    y -= 40;
    NSTextField *kLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 20)];
    kLabel.stringValue = @"API Key:";
    kLabel.editable = NO;
    kLabel.bordered = NO;
    kLabel.drawsBackground = NO;
    [self.view addSubview:kLabel];
    
    y -= 25;
    self.apiKeyField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 24)];
    [self.view addSubview:self.apiKeyField];
    
    y -= 40;
    self.enableLoggingCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(20, y, 540, 20)];
    self.enableLoggingCheckbox.buttonType = NSSwitchButton;
    self.enableLoggingCheckbox.title = @"Prompt to save text logs for errors and successful generation";
    [self.view addSubview:self.enableLoggingCheckbox];
    
    y -= 60;
    self.saveButton = [[NSButton alloc] initWithFrame:NSMakeRect(190, y, 200, 40)];
    self.saveButton.title = @"VALIDATE & SAVE";
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

    // Footer
    NSTextField *footer = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 20, 500, 40)];
    footer.stringValue = @"© 2026 iGeniusAI | Note: AI models are not perfect.\nFor better results, try different models in Settings.";
    footer.font = [NSFont systemFontOfSize:10];
    footer.textColor = [NSColor grayColor];
    footer.alignment = NSCenterTextAlignment;
    footer.editable = NO;
    footer.bordered = NO;
    footer.drawsBackground = NO;
    [self.view addSubview:footer];
    
    // Y-coordinate 25 aligns the center of the 21x21 button with the visual center of the 40px high text field.
    NSButton *helpBtn = [[NSButton alloc] initWithFrame:NSMakeRect(525, 29, 21, 21)];
    helpBtn.bezelStyle = NSHelpButtonBezelStyle;
    helpBtn.title = @"";
    helpBtn.target = self;
    helpBtn.action = @selector(helpClicked:);
    [self.view addSubview:helpBtn];
}

- (void)helpClicked:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"API Key Setup Guide"];
    [alert setInformativeText:@"To use iGeniusAI, you need an API key from one of our supported AI providers:\n\n1. OpenRouter (Recommended)\n- Where: openrouter.ai/keys\n- Format: 'sk-or-v1-...' (starts with sk-or)\n- Why: Gives access to many free models (like google/gemini-2.0-flash-exp:free) even in geo-blocked regions.\n\n2. Google Gemini\n- Where: aistudio.google.com/app/apikey\n- Format: 'AIzaSy...'\n- Why: Direct access to Google's fast models.\n\n3. Groq\n- Where: console.groq.com/keys\n- Format: 'gsk_...'\n- Why: Extremely fast generation.\n\nCommon Errors:\n- 'Invalid Key': Make sure there are no spaces at the start or end.\n- 'Model Not Found': Click 'Sync Models' to get the latest available list.\n\nHow to Check:\nEnter the key above and click 'VALIDATE & SAVE'. The app will test it immediately."];
    [alert runModal];
}

- (void)comboBoxSelectionDidChange:(NSNotification *)notification {
    if (notification.object == self.providerCombo) {
        NSInteger index = [self.providerCombo indexOfSelectedItem];
        if (index >= 0 && index < self.providerCombo.numberOfItems) {
            NSString *selected = [self.providerCombo itemObjectValueAtIndex:index];
            [self.modelCombo removeAllItems];
            if ([selected isEqualToString:@"Gemini"]) {
                [self.modelCombo addItemsWithObjectValues:@[@"google/gemini-2.0-flash-exp:free", @"google/gemini-1.5-pro"]];
                self.modelCombo.stringValue = @"google/gemini-2.0-flash-exp:free";
            } else if ([selected isEqualToString:@"Groq"]) {
                [self.modelCombo addItemsWithObjectValues:@[@"llama3-8b-8192", @"mixtral-8x7b-32768"]];
                self.modelCombo.stringValue = @"llama3-8b-8192";
            } else if ([selected isEqualToString:@"OpenRouter"]) {
                [self.modelCombo addItemsWithObjectValues:@[@"google/gemini-2.0-flash-exp:free"]];
                self.modelCombo.stringValue = @"google/gemini-2.0-flash-exp:free";
            }
        }
    }
}

- (void)loadSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.providerCombo.stringValue = [defaults stringForKey:@"provider"] ?: @"Gemini";
    self.modelCombo.stringValue = [defaults stringForKey:@"model"] ?: @"google/gemini-2.0-flash-exp:free";
    self.apiKeyField.stringValue = [defaults stringForKey:@"api_key"] ?: @"";
    self.enableLoggingCheckbox.state = [defaults boolForKey:@"enable_logging"] ? NSOnState : NSOffState;
    
    [IGAIService sharedService].provider = self.providerCombo.stringValue;
    [IGAIService sharedService].model = self.modelCombo.stringValue;
    [IGAIService sharedService].apiKey = self.apiKeyField.stringValue;
}

- (void)syncClicked:(id)sender {
    self.statusLabel.stringValue = @"Syncing models...";
    [[IGAIService sharedService] fetchOpenRouterModelsWithCompletion:^(NSArray *models) {
        if (models.count > 0) {
            [self.modelCombo removeAllItems];
            [self.modelCombo addItemsWithObjectValues:models];
            self.statusLabel.stringValue = @"Models updated!";
            
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Success"];
            [alert setInformativeText:[NSString stringWithFormat:@"Synced %ld models from OpenRouter.", (long)models.count]];
            [alert runModal];
        } else {
            self.statusLabel.stringValue = @"Sync failed. Check connection.";
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Network Error"];
            [alert setInformativeText:@"Failed to connect to AI server. On macOS 10.9, ensure your system clock is correct and root certificates are updated."];
            [alert runModal];
        }
    }];
}

- (void)saveClicked:(id)sender {
    self.statusLabel.stringValue = @"Validating...";
    self.saveButton.enabled = NO;
    
    [IGAIService sharedService].provider = self.providerCombo.stringValue;
    [IGAIService sharedService].model = self.modelCombo.stringValue;
    [IGAIService sharedService].apiKey = self.apiKeyField.stringValue;
    
    [[IGAIService sharedService] validateAPIKeyWithCompletion:^(BOOL success, NSString *errorMsg) {
        if (success) {
            self.statusLabel.stringValue = @"Settings saved successfully!";
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            [defaults setObject:self.providerCombo.stringValue forKey:@"provider"];
            [defaults setObject:self.modelCombo.stringValue forKey:@"model"];
            [defaults setObject:self.apiKeyField.stringValue forKey:@"api_key"];
            [defaults setBool:(self.enableLoggingCheckbox.state == NSOnState) forKey:@"enable_logging"];
            [defaults synchronize];
            
            // Notify UI to update buttons
            id controller = self.view.window.windowController;
            if ([controller isKindOfClass:[IGMainWindowController class]]) {
                [(IGMainWindowController *)controller updateButtonStates];
            }
            
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Settings Saved"];
            [alert setInformativeText:@"AI Provider configuration has been validated and saved."];
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
