#import "IGFixerViewController.h"
#import "IGiTunesService.h"

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
    [self log:@"Starting metadata restoration..."];
    
    [[IGiTunesService sharedService] runMetadataFixWithProgress:^(NSInteger current, NSInteger total) {
        self.progressIndicator.maxValue = total;
        self.progressIndicator.doubleValue = current;
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Processing track %ld of %ld...", (long)current, (long)total];
    } completion:^{
        self.statusLabel.stringValue = @"Restoration Complete!";
        [self log:@"Finished."];
        self.startButton.enabled = YES;
    }];
}

@end
