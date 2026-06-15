#import "IGGeniusViewController.h"
#import "IGiTunesService.h"
#import "IGAIService.h"

@interface IGGeniusViewController ()
@property (nonatomic, strong) NSTextField *playlistNameField;
@property (nonatomic, strong) NSTextField *promptField;
@property (nonatomic, strong) NSTextField *countField;
@property (nonatomic, strong) NSButton *generateButton;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSTextField *statusLabel;
@end

@implementation IGGeniusViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 480)];
    [self setupUI];
}

- (void)setupUI {
    CGFloat y = 430;
    
    NSTextField *titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 30)];
    titleLabel.stringValue = @"AI Playlist Generator";
    titleLabel.font = [NSFont boldSystemFontOfSize:18];
    titleLabel.editable = NO;
    titleLabel.bordered = NO;
    titleLabel.drawsBackground = NO;
    titleLabel.alignment = NSCenterTextAlignment;
    [self.view addSubview:titleLabel];
    
    y -= 50;
    NSTextField *nameLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 20)];
    nameLabel.stringValue = @"Playlist Name:";
    nameLabel.editable = NO;
    nameLabel.bordered = NO;
    nameLabel.drawsBackground = NO;
    [self.view addSubview:nameLabel];
    
    y -= 25;
    self.playlistNameField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 24)];
    self.playlistNameField.stringValue = @"My AI Playlist";
    [self.view addSubview:self.playlistNameField];
    
    y -= 40;
    NSTextField *promptLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 20)];
    promptLabel.stringValue = @"Describe the mood or style:";
    promptLabel.editable = NO;
    promptLabel.bordered = NO;
    promptLabel.drawsBackground = NO;
    [self.view addSubview:promptLabel];
    
    y -= 25;
    self.promptField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 24)];
    [[self.promptField cell] setPlaceholderString:@"e.g. 80s synthwave for late night drive"];
    [self.view addSubview:self.promptField];
    
    y -= 40;
    NSTextField *countLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 20)];
    countLabel.stringValue = @"Number of tracks:";
    countLabel.editable = NO;
    countLabel.bordered = NO;
    countLabel.drawsBackground = NO;
    [self.view addSubview:countLabel];
    
    y -= 25;
    self.countField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 100, 24)];
    self.countField.stringValue = @"20";
    [self.view addSubview:self.countField];
    
    y -= 60;
    self.generateButton = [[NSButton alloc] initWithFrame:NSMakeRect(190, y, 200, 40)];
    self.generateButton.title = @"GENERATE PLAYLIST";
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
    self.statusLabel.stringValue = @"Ready";
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

- (void)generateClicked:(id)sender {
    self.generateButton.enabled = NO;
    self.progressIndicator.hidden = NO;
    self.progressIndicator.doubleValue = 0;
    self.statusLabel.stringValue = @"Reading iTunes Library...";
    
    [[IGiTunesService sharedService] fetchAllTracksWithProgress:^(NSInteger current, NSInteger total) {
        self.progressIndicator.maxValue = total;
        self.progressIndicator.doubleValue = current;
    } completion:^(NSArray *tracks) {
        if (tracks.count == 0) {
            self.statusLabel.stringValue = @"Error: Library is empty.";
            self.generateButton.enabled = YES;
            return;
        }
        
        self.statusLabel.stringValue = @"Asking AI Assistant...";
        self.progressIndicator.indeterminate = YES;
        [self.progressIndicator startAnimation:nil];
        
        // Prepare a sample of the library for the AI
        // For large libraries, we shuffle and take a sample to avoid context limits
        NSArray *shuffledTracks = [tracks sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
            return arc4random_uniform(3) - 1;
        }];
        
        NSInteger maxSample = 500; // Safe limit for most models
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
                self.statusLabel.stringValue = @"Error: AI returned no matches.";
                self.generateButton.enabled = YES;
                return;
            }
            
            self.statusLabel.stringValue = [NSString stringWithFormat:@"Creating playlist with %ld tracks...", (long)suggestedIDs.count];
            
            [[IGiTunesService sharedService] createPlaylistWithName:self.playlistNameField.stringValue
                                                      persistentIDs:suggestedIDs
                                                         completion:^(NSInteger addedCount) {
                self.statusLabel.stringValue = [NSString stringWithFormat:@"Success! Created playlist with %ld tracks.", (long)addedCount];
                self.generateButton.enabled = YES;
                self.progressIndicator.hidden = YES;
                
                NSAlert *alert = [[NSAlert alloc] init];
                [alert setMessageText:@"Playlist Created"];
                [alert setInformativeText:[NSString stringWithFormat:@"Success! Playlist '%@' has been created in iTunes with %ld tracks.", self.playlistNameField.stringValue, (long)addedCount]];
                [alert runModal];
            }];
        }];
    }];
}

@end
