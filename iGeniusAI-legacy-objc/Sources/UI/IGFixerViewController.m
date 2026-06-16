#import "IGFixerViewController.h"
#import "IGiTunesService.h"
#import "IGMediaFixerManager.h"

@interface IGFixerViewController ()
@property (nonatomic, strong) NSButton *startButton;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextView *logView;
@end

@implementation IGFixerViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 480)];
    [self setupUI];
}

- (void)setupUI {
    CGFloat y = 430;
    
    NSTextField *titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 30)];
    titleLabel.stringValue = @"iTunes Media Info Fixer";
    titleLabel.font = [NSFont boldSystemFontOfSize:18];
    titleLabel.editable = NO;
    titleLabel.bordered = NO;
    titleLabel.drawsBackground = NO;
    titleLabel.alignment = NSCenterTextAlignment;
    [self.view addSubview:titleLabel];
    
    y -= 50;
    self.progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(40, y, 500, 20)];
    self.progressIndicator.style = NSProgressIndicatorBarStyle;
    self.progressIndicator.indeterminate = NO;
    [self.view addSubview:self.progressIndicator];
    
    y -= 30;
    self.statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 20)];
    self.statusLabel.stringValue = @"Ready to scan for metadata issues";
    self.statusLabel.editable = NO;
    self.statusLabel.bordered = NO;
    self.statusLabel.drawsBackground = NO;
    self.statusLabel.alignment = NSCenterTextAlignment;
    [self.view addSubview:self.statusLabel];

    y -= 180;
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(40, y, 500, 150)];
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;
    
    self.logView = [[NSTextView alloc] initWithFrame:scrollView.bounds];
    self.logView.editable = NO;
    self.logView.backgroundColor = [NSColor blackColor];
    self.logView.textColor = [NSColor greenColor];
    self.logView.font = [NSFont fontWithName:@"Monaco" size:10];
    
    scrollView.documentView = self.logView;
    [self.view addSubview:scrollView];
    
    y -= 60;
    self.startButton = [[NSButton alloc] initWithFrame:NSMakeRect(190, y, 200, 40)];
    self.startButton.title = @"START RESTORATION";
    self.startButton.bezelStyle = NSTexturedRoundedBezelStyle;
    self.startButton.target = self;
    self.startButton.action = @selector(startClicked:);
    [self.view addSubview:self.startButton];

    // Footer
    NSTextField *footer = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 20, 540, 40)];
    footer.stringValue = @"© 2026 iGeniusAI | Note: AI models are not perfect.\nFor better results, try different models in Settings.";
    footer.font = [NSFont systemFontOfSize:10];
    footer.textColor = [NSColor grayColor];
    footer.alignment = NSCenterTextAlignment;
    footer.editable = NO;
    footer.bordered = NO;
    footer.drawsBackground = NO;
    [self.view addSubview:footer];
}

- (void)log:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *line = [NSString stringWithFormat:@"> %@\n", text];
        NSAttributedString *attrLine = [[NSAttributedString alloc] initWithString:line attributes:@{NSForegroundColorAttributeName: [NSColor greenColor]}];
        [self.logView.textStorage appendAttributedString:attrLine];
        [self.logView scrollRangeToVisible:NSMakeRange(self.logView.string.length, 0)];
    });
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
            NSString *pid = t[@"pid"];
            NSString *script = [NSString stringWithFormat:@"tell application \"iTunes\" to set album of (some track whose persistent ID is \"%@\") to \"%@\"", pid, [main stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
            [service runAppleScript:script];
        }
        
        processed++;
        self.progressIndicator.doubleValue = processed;
        [self log:[NSString stringWithFormat:@"Merged variants into: %@", main]];
    }

    [self log:@"Merge phase complete."];
    [self runMetadataPhase];
}

- (void)runMetadataPhase {
    [self log:@"Phase 2: Fetching missing metadata from iTunes API..."];
    [[IGMediaFixerManager sharedManager] runMetadataFixWithProgress:^(NSInteger current, NSInteger total) {
        self.progressIndicator.maxValue = total;
        self.progressIndicator.doubleValue = current;
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Processing track %ld of %ld...", (long)current, (long)total];
    } completion:^{
        self.statusLabel.stringValue = @"Restoration Complete!";
        [self log:@"All metadata tasks finished."];
        self.startButton.enabled = YES;
    }];
}

@end
