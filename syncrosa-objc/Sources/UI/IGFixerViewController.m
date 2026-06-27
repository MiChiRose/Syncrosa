#import "IGFixerViewController.h"
#import "IGiTunesService.h"
#import "IGMediaFixerManager.h"
#import "IGLocalizationService.h"
#import "IGNotificationView.h"

@interface IGFixerViewController ()

@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSButton *startButton;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextView *logView;
@property (nonatomic, strong) NSTextField *footerLabel;

@property (nonatomic, strong) NSButton *selectAllCheckbox;
@property (nonatomic, strong) NSButton *albumCheckbox;
@property (nonatomic, strong) NSButton *titleCheckbox;
@property (nonatomic, strong) NSButton *artistCheckbox;
@property (nonatomic, strong) NSButton *genreCheckbox;
@property (nonatomic, strong) NSButton *trackNumberCheckbox;
@property (nonatomic, strong) NSButton *lyricsCheckbox;
@property (nonatomic, strong) NSWindow *helpSheetWindow;

@end

@implementation IGFixerViewController

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
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupUI {
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    CGFloat y = 430;
    
    self.titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 30)];
    self.titleLabel.font = [NSFont boldSystemFontOfSize:18];
    self.titleLabel.editable = NO;
    self.titleLabel.bordered = NO;
    self.titleLabel.drawsBackground = NO;
    self.titleLabel.alignment = NSCenterTextAlignment;
    [self.view addSubview:self.titleLabel];
    
    NSButton *helpButton = [[NSButton alloc] initWithFrame:NSMakeRect(520, y, 25, 25)];
    helpButton.bezelStyle = NSHelpButtonBezelStyle;
    helpButton.title = @"";
    helpButton.target = self;
    helpButton.action = @selector(helpClicked:);
    [self.view addSubview:helpButton];
    
    y -= 40;
    self.progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(40, y, 500, 20)];
    self.progressIndicator.style = NSProgressIndicatorBarStyle;
    self.progressIndicator.indeterminate = NO;
    [self.view addSubview:self.progressIndicator];
    
    y -= 25;
    self.statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 20)];
    self.statusLabel.editable = NO;
    self.statusLabel.bordered = NO;
    self.statusLabel.drawsBackground = NO;
    self.statusLabel.alignment = NSCenterTextAlignment;
    [self.view addSubview:self.statusLabel];

    // Selective Tag Checkboxes
    y -= 30;
    self.selectAllCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(40, y, 150, 20)];
    [self.selectAllCheckbox setButtonType:NSSwitchButton];
    self.selectAllCheckbox.target = self;
    self.selectAllCheckbox.action = @selector(selectAllClicked:);
    self.selectAllCheckbox.state = NSOnState;
    [self.view addSubview:self.selectAllCheckbox];
    
    y -= 25;
    self.albumCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(40, y, 140, 20)];
    [self.albumCheckbox setButtonType:NSSwitchButton];
    self.albumCheckbox.state = NSOnState;
    [self.view addSubview:self.albumCheckbox];
    
    self.titleCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(200, y, 140, 20)];
    [self.titleCheckbox setButtonType:NSSwitchButton];
    self.titleCheckbox.state = NSOnState;
    [self.view addSubview:self.titleCheckbox];
    
    self.artistCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(360, y, 140, 20)];
    [self.artistCheckbox setButtonType:NSSwitchButton];
    self.artistCheckbox.state = NSOnState;
    [self.view addSubview:self.artistCheckbox];
    
    y -= 25;
    self.genreCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(40, y, 140, 20)];
    [self.genreCheckbox setButtonType:NSSwitchButton];
    self.genreCheckbox.state = NSOnState;
    [self.view addSubview:self.genreCheckbox];
    
    self.trackNumberCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(200, y, 140, 20)];
    [self.trackNumberCheckbox setButtonType:NSSwitchButton];
    self.trackNumberCheckbox.state = NSOnState;
    [self.view addSubview:self.trackNumberCheckbox];
    
    self.lyricsCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(360, y, 140, 20)];
    [self.lyricsCheckbox setButtonType:NSSwitchButton];
    self.lyricsCheckbox.state = NSOnState;
    [self.view addSubview:self.lyricsCheckbox];

    y -= 140;
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(40, y, 500, 130)];
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;
    
    self.logView = [[NSTextView alloc] initWithFrame:scrollView.bounds];
    self.logView.editable = NO;
    self.logView.backgroundColor = [NSColor blackColor];
    self.logView.textColor = [NSColor greenColor];
    self.logView.font = [NSFont fontWithName:@"Monaco" size:10];
    
    scrollView.documentView = self.logView;
    [self.view addSubview:scrollView];
    
    y -= 50;
    self.startButton = [[NSButton alloc] initWithFrame:NSMakeRect(190, y, 200, 40)];
    self.startButton.bezelStyle = NSTexturedRoundedBezelStyle;
    self.startButton.target = self;
    self.startButton.action = @selector(startClicked:);
    [self.view addSubview:self.startButton];

    // Footer
    self.footerLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 15, 540, 30)];
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
    
    self.titleLabel.stringValue = [lang t:@"media_fixer"];
    self.startButton.title = [lang t:@"analyze_lib"];
    self.footerLabel.stringValue = [lang t:@"footer"];
    
    self.selectAllCheckbox.title = [lang t:@"select_all"];
    self.albumCheckbox.title = [lang t:@"tag_album"];
    self.titleCheckbox.title = [lang t:@"tag_title"];
    self.artistCheckbox.title = [lang t:@"tag_artist"];
    self.genreCheckbox.title = [lang t:@"tag_genre"];
    self.trackNumberCheckbox.title = [lang t:@"tag_track_number"];
    self.lyricsCheckbox.title = [lang t:@"tag_lyrics"];
    
    if (self.statusLabel.stringValue.length == 0 ||
        [self.statusLabel.stringValue isEqualToString:@"Ready to scan for metadata issues"] ||
        [self.statusLabel.stringValue isEqualToString:@"Готов к сканированию медиатеки на ошибки."]) {
        self.statusLabel.stringValue = [lang.selectedLanguage isEqualToString:@"ru"] ? 
            @"Готов к сканированию медиатеки на ошибки." : 
            @"Ready to scan for metadata issues";
    }
}

- (void)localizationChanged:(NSNotification *)notification {
    [self updateLocalization];
}

- (void)log:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *line = [NSString stringWithFormat:@"> %@\n", text];
        NSAttributedString *attrLine = [[NSAttributedString alloc] initWithString:line attributes:@{NSForegroundColorAttributeName: [NSColor greenColor]}];
        [self.logView.textStorage appendAttributedString:attrLine];
        [self.logView scrollRangeToVisible:NSMakeRange(self.logView.string.length, 0)];
    });
}

- (void)selectAllClicked:(id)sender {
    NSInteger state = self.selectAllCheckbox.state;
    self.albumCheckbox.state = state;
    self.titleCheckbox.state = state;
    self.artistCheckbox.state = state;
    self.genreCheckbox.state = state;
    self.trackNumberCheckbox.state = state;
    self.lyricsCheckbox.state = state;
}

- (void)helpClicked:(id)sender {
    NSString *helpText = @"iTunes Media Fixer Help\n\n"
                          "This utility scans your iTunes/Music library for split albums and missing metadata (Album, Title, Artist, Genre, Track Number, and Lyrics).\n\n"
                          "1. Select All / Individual Tags: Use the checkboxes to choose which metadata tags should be corrected. Only the checked tags will be updated via AppleScript.\n"
                          "2. Safe Operation: Every single track operation is wrapped in a safe error handling block, ensuring that if any track write fails (due to write permissions, locked files, etc.), the app will skip it and continue without crashing.";
    
    NSWindow *sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 260)
                                                  styleMask:NSTitledWindowMask
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

- (void)startClicked:(id)sender {
    self.startButton.enabled = NO;
    [self log:@"Phase 1: Scanning for split albums..."];
    self.statusLabel.stringValue = @"Scanning for merge candidates...";
    self.progressIndicator.indeterminate = YES;
    [self.progressIndicator startAnimation:nil];

    [[IGMediaFixerManager sharedManager] getMergeCandidatesWithCompletion:^(NSArray *candidates) {
        if (candidates.count > 0) {
            [self log:[NSString stringWithFormat:@"Found %ld split albums to merge.", (long)candidates.count]];
            [self runMergePhase:candidates];
        } else {
            [self log:@"No split albums found. Proceeding to metadata check."];
            [self runMetadataPhase];
        }
    }];
}

- (void)runMergePhase:(NSArray *)candidates {
    self.progressIndicator.indeterminate = NO;
    self.progressIndicator.maxValue = candidates.count;
    self.progressIndicator.doubleValue = 0;

    __block NSInteger processed = 0;
    IGiTunesService *service = [IGiTunesService sharedService];

    for (NSDictionary *item in candidates) {
        NSString *main = item[@"main"];
        NSArray *targets = item[@"targets"];
        
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Merging: %@", main];
        
        for (NSDictionary *t in targets) {
            @try {
                NSString *pid = t[@"pid"];
                NSString *script = [NSString stringWithFormat:@"tell application \"iTunes\" to set album of (some track whose persistent ID is \"%@\") to \"%@\"", pid, [main stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
                [service runAppleScript:script];
            } @catch (NSException *ex) {
                NSLog(@"Error merging split album: %@", ex);
            }
        }
        
        processed++;
        self.progressIndicator.doubleValue = processed;
        [self log:[NSString stringWithFormat:@"Merged variants into: %@", main]];
    }

    [self log:@"Merge phase complete."];
    [self runMetadataPhase];
}

- (void)runMetadataPhase {
    [self log:@"Phase 2: Fetching missing metadata..."];
    
    NSDictionary *options = @{
        @"album": @(self.albumCheckbox.state == NSOnState),
        @"title": @(self.titleCheckbox.state == NSOnState),
        @"artist": @(self.artistCheckbox.state == NSOnState),
        @"genre": @(self.genreCheckbox.state == NSOnState),
        @"trackNumber": @(self.trackNumberCheckbox.state == NSOnState),
        @"lyrics": @(self.lyricsCheckbox.state == NSOnState)
    };
    
    [[IGMediaFixerManager sharedManager] runMetadataFixWithOptions:options progress:^(NSInteger current, NSInteger total) {
        self.progressIndicator.maxValue = total;
        self.progressIndicator.doubleValue = current;
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Processing track %ld of %ld...", (long)current, (long)total];
    } completion:^{
        self.statusLabel.stringValue = [[IGLocalizationService sharedService] t:@"done"];
        [self log:@"All metadata tasks finished."];
        self.startButton.enabled = YES;
        [self.progressIndicator stopAnimation:nil];
        self.progressIndicator.indeterminate = NO;
        self.progressIndicator.doubleValue = self.progressIndicator.maxValue;
        
        [IGNotificationView showInView:self.view message:[[IGLocalizationService sharedService] t:@"done"] isError:NO];
    }];
}

@end
