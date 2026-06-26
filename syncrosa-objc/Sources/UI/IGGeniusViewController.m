#import "IGGeniusViewController.h"
#import "IGiTunesService.h"
#import "IGAIService.h"
#import "IGLocalizationService.h"
#import "IGNotificationView.h"

@interface IGGeniusViewController () <NSTextFieldDelegate>

@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *configLabel;
@property (nonatomic, strong) NSTextField *nameLabel;
@property (nonatomic, strong) NSTextField *nameCounterLabel;
@property (nonatomic, strong) NSTextField *playlistNameField;
@property (nonatomic, strong) NSTextField *promptLabel;
@property (nonatomic, strong) NSTextField *promptCounterLabel;
@property (nonatomic, strong) NSTextField *promptField;
@property (nonatomic, strong) NSTextField *countLabel;
@property (nonatomic, strong) NSTextField *countField;
@property (nonatomic, strong) NSStepper *stepper;
@property (nonatomic, strong) NSButton *generateButton;
@property (nonatomic, strong) NSWindow *helpSheetWindow;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextField *footerLabel;

@end

@implementation IGGeniusViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 480)];
    [self setupUI];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(localizationChanged:)
                                                 name:@"IGLanguageChangedNotification"
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(apiSettingsSaved:)
                                                 name:@"IGAPISettingsSavedNotification"
                                               object:nil];
    [self updateConfigLabel];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupUI {
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    CGFloat y = 430;
    
    // Title
    self.titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 30)];
    self.titleLabel.font = [NSFont boldSystemFontOfSize:18];
    self.titleLabel.editable = NO;
    self.titleLabel.bordered = NO;
    self.titleLabel.drawsBackground = NO;
    self.titleLabel.alignment = NSCenterTextAlignment;
    [self.view addSubview:self.titleLabel];
    
    NSButton *helpButton = [[NSButton alloc] initWithFrame:NSMakeRect(520, y, 25, 25)];
    helpButton.bezelStyle = NSBezelStyleHelpButton;
    helpButton.title = @"";
    helpButton.target = self;
    helpButton.action = @selector(helpClicked:);
    [self.view addSubview:helpButton];
    
    y -= 25;
    // Active configuration label
    self.configLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 16)];
    self.configLabel.font = [NSFont systemFontOfSize:11];
    self.configLabel.textColor = [NSColor grayColor];
    self.configLabel.editable = NO;
    self.configLabel.bordered = NO;
    self.configLabel.drawsBackground = NO;
    self.configLabel.alignment = NSCenterTextAlignment;
    [self.view addSubview:self.configLabel];
    
    y -= 45;
    // Playlist Name
    self.nameLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 350, 20)];
    self.nameLabel.font = [NSFont systemFontOfSize:13];
    self.nameLabel.editable = NO;
    self.nameLabel.bordered = NO;
    self.nameLabel.drawsBackground = NO;
    [self.view addSubview:self.nameLabel];
    
    self.nameCounterLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(400, y, 160, 20)];
    self.nameCounterLabel.font = [NSFont systemFontOfSize:11];
    self.nameCounterLabel.textColor = [NSColor grayColor];
    self.nameCounterLabel.alignment = NSRightTextAlignment;
    self.nameCounterLabel.editable = NO;
    self.nameCounterLabel.bordered = NO;
    self.nameCounterLabel.drawsBackground = NO;
    [self.view addSubview:self.nameCounterLabel];
    
    y -= 25;
    self.playlistNameField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 24)];
    self.playlistNameField.stringValue = @"My AI Playlist";
    self.playlistNameField.delegate = self;
    [self.view addSubview:self.playlistNameField];
    
    y -= 40;
    // Prompt
    self.promptLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 350, 20)];
    self.promptLabel.font = [NSFont systemFontOfSize:13];
    self.promptLabel.editable = NO;
    self.promptLabel.bordered = NO;
    self.promptLabel.drawsBackground = NO;
    [self.view addSubview:self.promptLabel];
    
    self.promptCounterLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(400, y, 160, 20)];
    self.promptCounterLabel.font = [NSFont systemFontOfSize:11];
    self.promptCounterLabel.textColor = [NSColor grayColor];
    self.promptCounterLabel.alignment = NSRightTextAlignment;
    self.promptCounterLabel.editable = NO;
    self.promptCounterLabel.bordered = NO;
    self.promptCounterLabel.drawsBackground = NO;
    [self.view addSubview:self.promptCounterLabel];
    
    y -= 25;
    self.promptField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 24)];
    self.promptField.delegate = self;
    [self.view addSubview:self.promptField];
    
    y -= 40;
    // Count
    self.countLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 20)];
    self.countLabel.font = [NSFont systemFontOfSize:13];
    self.countLabel.editable = NO;
    self.countLabel.bordered = NO;
    self.countLabel.drawsBackground = NO;
    [self.view addSubview:self.countLabel];
    
    y -= 25;
    self.countField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 80, 24)];
    self.countField.stringValue = @"20";
    self.countField.delegate = self;
    [self.view addSubview:self.countField];
    
    self.stepper = [[NSStepper alloc] initWithFrame:NSMakeRect(105, y-2, 19, 28)];
    self.stepper.minValue = 1;
    self.stepper.maxValue = 100;
    self.stepper.integerValue = 20;
    self.stepper.target = self;
    self.stepper.action = @selector(stepperChanged:);
    [self.view addSubview:self.stepper];
    
    y -= 60;
    self.generateButton = [[NSButton alloc] initWithFrame:NSMakeRect(190, y, 200, 40)];
    self.generateButton.bezelStyle = NSTexturedRoundedBezelStyle;
    self.generateButton.target = self;
    self.generateButton.action = @selector(generateClicked:);
    [self.view addSubview:self.generateButton];
    
    y -= 50;
    self.progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(20, y, 540, 20)];
    self.progressIndicator.style = NSProgressIndicatorBarStyle;
    self.progressIndicator.indeterminate = NO;
    self.progressIndicator.hidden = YES;
    [self.view addSubview:self.progressIndicator];
    
    y -= 30;
    self.statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 20)];
    self.statusLabel.editable = NO;
    self.statusLabel.bordered = NO;
    self.statusLabel.drawsBackground = NO;
    self.statusLabel.alignment = NSCenterTextAlignment;
    [self.view addSubview:self.statusLabel];
    
    // Footer
    self.footerLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 20, 540, 40)];
    self.footerLabel.font = [NSFont systemFontOfSize:10];
    self.footerLabel.textColor = [NSColor grayColor];
    self.footerLabel.alignment = NSCenterTextAlignment;
    self.footerLabel.editable = NO;
    self.footerLabel.bordered = NO;
    self.footerLabel.drawsBackground = NO;
    [self.view addSubview:self.footerLabel];
    
    [self updateLocalization];
    [self updateCharacterCounters];
}

- (void)updateLocalization {
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    
    self.titleLabel.stringValue = [lang t:@"ai_playlist"];
    self.nameLabel.stringValue = [lang t:@"pl_name"];
    self.promptLabel.stringValue = [lang t:@"pl_mood"];
    self.countLabel.stringValue = [lang t:@"track_count"];
    self.generateButton.title = [lang t:@"generate_playlist"];
    self.footerLabel.stringValue = [lang t:@"footer"];
    
    if (self.statusLabel.stringValue.length == 0 || 
        [self.statusLabel.stringValue isEqualToString:@"Ready"] || 
        [self.statusLabel.stringValue isEqualToString:@"Готово."]) {
        self.statusLabel.stringValue = [lang t:@"ready"];
    }
    
    [[self.promptField cell] setPlaceholderString:[lang.selectedLanguage isEqualToString:@"ru"] ? 
        @"например: синтвейв 80-х для ночной поездки" : 
        @"e.g. 80s synthwave for late night drive"];
    
    [self updateConfigLabel];
}

- (void)updateConfigLabel {
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    NSString *provider = [IGAIService sharedService].provider ?: @"-";
    NSString *model = [IGAIService sharedService].model ?: @"-";
    self.configLabel.stringValue = [NSString stringWithFormat:@"%@: %@ / %@", [lang t:@"active_config"], provider, model];
}

- (void)localizationChanged:(NSNotification *)notification {
    [self updateLocalization];
}

- (void)apiSettingsSaved:(NSNotification *)notification {
    [self updateConfigLabel];
}

- (void)stepperChanged:(id)sender {
    self.countField.stringValue = [NSString stringWithFormat:@"%ld", (long)self.stepper.integerValue];
}

#pragma mark - TextField Delegate (Character Counting)

- (void)controlTextDidChange:(NSNotification *)obj {
    NSTextField *textField = [obj object];
    if (textField == self.playlistNameField) {
        if (self.playlistNameField.stringValue.length > 30) {
            self.playlistNameField.stringValue = [self.playlistNameField.stringValue substringToIndex:30];
        }
    } else if (textField == self.promptField) {
        if (self.promptField.stringValue.length > 150) {
            self.promptField.stringValue = [self.promptField.stringValue substringToIndex:150];
        }
    } else if (textField == self.countField) {
        NSInteger val = [self.countField integerValue];
        if (val < 1) val = 1;
        if (val > 100) val = 100;
        self.stepper.integerValue = val;
    }
    [self updateCharacterCounters];
}

- (void)updateCharacterCounters {
    self.nameCounterLabel.stringValue = [NSString stringWithFormat:@"%ld/30", (long)self.playlistNameField.stringValue.length];
    self.promptCounterLabel.stringValue = [NSString stringWithFormat:@"%ld/150", (long)self.promptField.stringValue.length];
}

#pragma mark - Generation

- (void)generateClicked:(id)sender {
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    self.generateButton.enabled = NO;
    self.progressIndicator.hidden = NO;
    self.progressIndicator.doubleValue = 0;
    self.statusLabel.stringValue = @"Reading iTunes Library...";
    
    [[IGiTunesService sharedService] fetchAllTracksWithProgress:^(NSInteger current, NSInteger total) {
        self.progressIndicator.maxValue = total;
        self.progressIndicator.doubleValue = current;
    } completion:^(NSArray *tracks) {
        if (tracks.count == 0) {
            self.statusLabel.stringValue = [lang t:@"lib_empty"];
            self.generateButton.enabled = YES;
            [IGNotificationView showInView:self.view message:[lang t:@"lib_empty"] isError:YES];
            return;
        }
        
        self.statusLabel.stringValue = [lang t:@"asking_ai"];
        self.progressIndicator.indeterminate = YES;
        [self.progressIndicator startAnimation:nil];
        
        NSArray *shuffledTracks = [tracks sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
            return arc4random_uniform(3) - 1;
        }];
        
        NSInteger maxSample = 500;
        NSArray *limitedSample = [shuffledTracks subarrayWithRange:NSMakeRange(0, MIN(tracks.count, maxSample))];
        
        NSMutableArray *sampleStrings = [NSMutableArray array];
        for (IGTrack *t in limitedSample) {
            [sampleStrings addObject:[NSString stringWithFormat:@"%@|%@|%@|%@|%ld", t.persistentID, t.artist, t.name, t.genre, (long)t.year]];
        }
        
        [[IGAIService sharedService] generatePlaylistWithPrompt:self.promptField.stringValue
                                                           count:[self.countField integerValue]
                                                   librarySample:sampleStrings
                                                      completion:^(NSArray *suggestedIDs) {
            [self.progressIndicator stopAnimation:nil];
            self.progressIndicator.indeterminate = NO;
            
            if (!suggestedIDs || suggestedIDs.count == 0) {
                self.statusLabel.stringValue = [lang t:@"ai_fail"];
                self.generateButton.enabled = YES;
                [IGNotificationView showInView:self.view message:[lang t:@"ai_fail"] isError:YES];
                return;
            }
            
            self.statusLabel.stringValue = [lang t:@"creating_playlist"];
            
            [[IGiTunesService sharedService] createPlaylistWithName:self.playlistNameField.stringValue
                                                      persistentIDs:suggestedIDs
                                                         completion:^(NSInteger addedCount) {
                NSString *successMsg = [lang t:@"success_added" args:@[@((long)addedCount)]];
                self.statusLabel.stringValue = successMsg;
                self.generateButton.enabled = YES;
                self.progressIndicator.hidden = YES;
                
                [IGNotificationView showInView:self.view message:successMsg isError:NO];
            }];
        }];
    }];
}

- (void)helpClicked:(id)sender {
    NSString *helpText = @"AI Playlist Generator Help\n\n"
                          "This utility lets you generate customized smart playlists using Artificial Intelligence (based on Google Gemini or other providers configured in Settings):\n\n"
                          "1. Playlist Name: Set a name for the new playlist that will be created in iTunes/Music.\n"
                          "2. Prompt / Mood: Describe the mood, style, or genres you want (e.g., 'chill electronic music for coding' or 'energetic 80s rock').\n"
                          "3. Track Count: Select how many tracks you want in the playlist.\n"
                          "4. Generation: Syncrosa will analyze your library cache, request matching recommendations from the AI API, and automatically create and populate the playlist in iTunes/Music.";
    
    NSWindow *sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 260)
                                                  styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered
                                                      defer:YES];
    
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 60, 380, 180)];
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

@end
