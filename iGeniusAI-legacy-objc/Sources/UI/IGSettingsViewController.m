#import "IGSettingsViewController.h"
#import "IGAIService.h"
#import "IGMainWindowController.h"

@interface IGSettingsViewController ()
@property (nonatomic, strong) NSComboBox *providerCombo;
@property (nonatomic, strong) NSComboBox *modelCombo;
@property (nonatomic, strong) NSTextField *apiKeyField;
@property (nonatomic, strong) NSButton *saveButton;
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
    
    NSButton *helpBtn = [[NSButton alloc] initWithFrame:NSMakeRect(520, y, 32, 32)];
    helpBtn.bezelStyle = NSHelpButtonBezelStyle;
    helpBtn.title = @"";
    helpBtn.target = self;
    helpBtn.action = @selector(helpClicked:);
    [self.view addSubview:helpBtn];
    
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
    NSTextField *footer = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 20, 540, 40)];
    footer.stringValue = @"Note: AI models are not perfect.\nFor better results, try different models in Settings.";
    footer.font = [NSFont systemFontOfSize:10];
    footer.textColor = [NSColor grayColor];
    footer.alignment = NSCenterTextAlignment;
    footer.editable = NO;
    footer.bordered = NO;
    footer.drawsBackground = NO;
    [self.view addSubview:footer];
}

- (void)helpClicked:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"About iGeniusAI"];
    [alert setInformativeText:@"v1.0 (Legacy Objective-C)\n\nA native port for macOS 10.9-10.13.\nSupports iTunes library reconciliation and AI playlist generation.\n\nAuthor: Gemini CLI"];
    [alert runModal];
}

- (void)loadSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.providerCombo.stringValue = [defaults stringForKey:@"provider"] ?: @"Gemini";
    self.modelCombo.stringValue = [defaults stringForKey:@"model"] ?: @"google/gemini-2.0-flash-exp:free";
    self.apiKeyField.stringValue = [defaults stringForKey:@"api_key"] ?: @"";
    
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
