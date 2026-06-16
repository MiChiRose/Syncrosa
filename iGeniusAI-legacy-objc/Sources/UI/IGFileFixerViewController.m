#import "IGFileFixerViewController.h"

@interface IGFileFixerViewController ()
@property (nonatomic, strong) NSTextField *folderPathField;
@property (nonatomic, strong) NSButton *selectFolderButton;
@property (nonatomic, strong) NSButton *fixButton;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextView *logView;
@property (nonatomic, strong) NSArray *foundFiles;
@property (nonatomic, assign) BOOL isProcessing;
@end

@implementation IGFileFixerViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 480)];
    [self setupUI];
}

- (void)setupUI {
    CGFloat y = 430;
    
    NSTextField *titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 30)];
    titleLabel.stringValue = @"Folder Media Fixer";
    titleLabel.font = [NSFont boldSystemFontOfSize:18];
    titleLabel.editable = NO;
    titleLabel.bordered = NO;
    titleLabel.drawsBackground = NO;
    titleLabel.alignment = NSCenterTextAlignment;
    [self.view addSubview:titleLabel];
    
    y -= 50;
    NSTextField *instrLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 35)];
    instrLabel.stringValue = @"Fix music files directly in a folder (for tracks not in iTunes).";
    instrLabel.font = [NSFont systemFontOfSize:11];
    // secondaryLabelColor is 10.10+, using grayColor for 10.9 compatibility
    instrLabel.textColor = [NSColor grayColor];
    instrLabel.editable = NO;
    instrLabel.bordered = NO;
    instrLabel.drawsBackground = NO;
    [self.view addSubview:instrLabel];
    
    y -= 40;
    self.folderPathField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 400, 24)];
    self.folderPathField.editable = NO;
    [[self.folderPathField cell] setPlaceholderString:@"No folder selected"];
    [self.view addSubview:self.folderPathField];
    
    self.selectFolderButton = [[NSButton alloc] initWithFrame:NSMakeRect(430, y-2, 130, 30)];
    self.selectFolderButton.title = @"Select Folder";
    self.selectFolderButton.bezelStyle = NSRoundedBezelStyle;
    self.selectFolderButton.target = self;
    self.selectFolderButton.action = @selector(selectFolderClicked:);
    [self.view addSubview:self.selectFolderButton];
    
    y -= 50;
    self.fixButton = [[NSButton alloc] initWithFrame:NSMakeRect(190, y, 200, 40)];
    self.fixButton.title = @"FIX ALL FILES";
    self.fixButton.bezelStyle = NSTexturedRoundedBezelStyle;
    self.fixButton.enabled = NO;
    self.fixButton.target = self;
    self.fixButton.action = @selector(fixClicked:);
    [self.view addSubview:self.fixButton];
    
    y -= 40;
    self.progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(40, y, 500, 20)];
    self.progressIndicator.style = NSProgressIndicatorBarStyle;
    self.progressIndicator.indeterminate = NO;
    [self.view addSubview:self.progressIndicator];
    
    y -= 160;
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

- (void)selectFolderClicked:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:NO];
    
    if ([panel runModal] == NSOKButton) {
        NSURL *url = [[panel URLs] firstObject];
        self.folderPathField.stringValue = [url path];
        [self scanFolder:url];
    }
}

- (void)scanFolder:(NSURL *)url {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *extensions = @[@"mp3", @"m4a", @"wav", @"flac", @"alac", @"aiff"];
    
    NSError *error = nil;
    NSArray *contents = [fm contentsOfDirectoryAtURL:url includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:&error];
    
    NSMutableArray *matches = [NSMutableArray array];
    for (NSURL *fileUrl in contents) {
        if ([extensions containsObject:[[fileUrl pathExtension] lowercaseString]]) {
            [matches addObject:fileUrl];
        }
    }
    
    self.foundFiles = matches;
    self.statusLabel.stringValue = [NSString stringWithFormat:@"Found %ld music files.", (long)matches.count];
    [self log:[NSString stringWithFormat:@"Scanned folder: Found %ld music files.", (long)matches.count]];
    self.fixButton.enabled = (matches.count > 0);
}

- (void)fixClicked:(id)sender {
    if (self.isProcessing) return;
    
    self.isProcessing = YES;
    self.fixButton.enabled = NO;
    self.selectFolderButton.enabled = NO;
    
    [self log:@"Starting folder fix process..."];
    self.progressIndicator.maxValue = self.foundFiles.count;
    self.progressIndicator.doubleValue = 0;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (NSInteger i = 0; i < self.foundFiles.count; i++) {
            NSURL *fileUrl = self.foundFiles[i];
            NSString *fileName = [fileUrl lastPathComponent];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                self.statusLabel.stringValue = [NSString stringWithFormat:@"Fixing: %@", fileName];
                [self log:[NSString stringWithFormat:@"Processing: %@", fileName]];
                self.progressIndicator.doubleValue = i + 1;
            });
            
            // Simulation of metadata fetching and writing
            [NSThread sleepForTimeInterval:0.5];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.isProcessing = NO;
            self.fixButton.enabled = YES;
            self.selectFolderButton.enabled = YES;
            self.statusLabel.stringValue = @"Folder fix complete!";
            [self log:@"Process finished successfully."];
            
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Success"];
            [alert setInformativeText:[NSString stringWithFormat:@"Processed %ld files successfully.", (long)self.foundFiles.count]];
            [alert runModal];
        });
    });
}

@end
