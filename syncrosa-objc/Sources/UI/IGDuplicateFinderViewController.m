#import "IGDuplicateFinderViewController.h"
#import "IGiTunesService.h"
#import "IGLocalizationService.h"
#import "IGNotificationView.h"

@interface IGFlippedView : NSView
@end

@implementation IGFlippedView
- (BOOL)isFlipped {
    return YES;
}
@end

@interface IGDuplicateFinderViewController ()
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSButton *scanButton;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) IGFlippedView *documentView;
@property (nonatomic, strong) NSTextField *footerLabel;
@property (nonatomic, strong) NSArray *duplicatePairs;
@property (nonatomic, strong) NSWindow *helpSheetWindow;
@end

@implementation IGDuplicateFinderViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 480)];
    [self setupUI];
}

- (void)setupUI {
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    CGFloat y = 430;
    
    self.titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 30)];
    self.titleLabel.stringValue = [lang t:@"duplicate_finder"];
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
    
    y -= 45;
    self.scanButton = [[NSButton alloc] initWithFrame:NSMakeRect(190, y, 200, 35)];
    self.scanButton.title = @"Show Duplicates";
    self.scanButton.bezelStyle = NSTexturedRoundedBezelStyle;
    self.scanButton.target = self;
    self.scanButton.action = @selector(scanClicked:);
    [self.view addSubview:self.scanButton];
    
    y -= 30;
    self.progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(40, y, 500, 20)];
    self.progressIndicator.style = NSProgressIndicatorBarStyle;
    self.progressIndicator.indeterminate = YES;
    self.progressIndicator.displayedWhenStopped = NO;
    [self.view addSubview:self.progressIndicator];
    
    y -= 25;
    self.statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 20)];
    self.statusLabel.stringValue = @"Ready to scan for duplicates";
    self.statusLabel.editable = NO;
    self.statusLabel.bordered = NO;
    self.statusLabel.drawsBackground = NO;
    self.statusLabel.alignment = NSCenterTextAlignment;
    [self.view addSubview:self.statusLabel];
    
    y -= 230;
    self.scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, y, 540, 220)];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.borderType = NSBezelBorder;
    self.scrollView.autoresizesSubviews = YES;
    
    self.documentView = [[IGFlippedView alloc] initWithFrame:NSMakeRect(0, 0, 520, 220)];
    self.scrollView.documentView = self.documentView;
    [self.view addSubview:self.scrollView];
    
    // Footer
    self.footerLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 15, 540, 30)];
    self.footerLabel.stringValue = [lang t:@"footer"];
    self.footerLabel.font = [NSFont systemFontOfSize:10];
    self.footerLabel.textColor = [NSColor grayColor];
    self.footerLabel.alignment = NSCenterTextAlignment;
    self.footerLabel.editable = NO;
    self.footerLabel.bordered = NO;
    self.footerLabel.drawsBackground = NO;
    [self.view addSubview:self.footerLabel];
}

- (void)helpClicked:(id)sender {
    NSString *helpText = @"Duplicate Finder Help\n\n"
                          "This tool scans your iTunes/Music library for duplicate tracks with matching artists and titles.\n\n"
                          "1. Show Duplicates: Press to search your library. Duplicate pairs will be listed side-by-side.\n"
                          "2. Original vs. Copy: The app compares the duplicates and automatically labels the one with higher metadata completeness and larger file size as the 'Original'. The other is marked as the 'Copy'.\n"
                          "3. Ignore Pair: Saves the combination of both tracks to NSUserDefaults so that this specific pair is ignored in future scans.\n"
                          "4. Delete Copy: Safely deletes the designated copy track from your iTunes/Music library using AppleScript.";
    
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

- (void)scanClicked:(id)sender {
    [self scanForDuplicates];
}

- (void)scanForDuplicates {
    self.scanButton.enabled = NO;
    [self.progressIndicator startAnimation:nil];
    self.statusLabel.stringValue = @"Scanning library for duplicates...";
    
    // Clear old subviews
    for (NSView *v in [self.documentView.subviews copy]) {
        [v removeFromSuperview];
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        IGiTunesService *service = [IGiTunesService sharedService];
        NSString *script = 
            @"set out to \"\"\n"
            "tell application \"iTunes\"\n"
            "    set trks to every track of library playlist 1\n"
            "    repeat with t in trks\n"
            "        try\n"
            "            set pid to persistent ID of t\n"
            "            set nm to name of t\n"
            "            set art to artist of t\n"
            "            set alb to album of t\n"
            "            set gen to genre of t\n"
            "            set trk to track number of t\n"
            "            set knd to kind of t\n"
            "            set sz to size of t\n"
            "            set loc to \"\"\n"
            "            try\n"
            "                set loc to (POSIX path of (location of t as alias))\n"
            "            end try\n"
            "            set out to out & pid & \"|\" & nm & \"|\" & art & \"|\" & alb & \"|\" & gen & \"|\" & trk & \"|\" & knd & \"|\" & sz & \"|\" & loc & \"\\n\"\n"
            "        end try\n"
            "    end repeat\n"
            "end tell\n"
            "return out";
            
        NSString *raw = [service runAppleScript:script];
        if (!raw || raw.length == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.scanButton.enabled = YES;
                [self.progressIndicator stopAnimation:nil];
                self.statusLabel.stringValue = @"No tracks found in library.";
            });
            return;
        }
        
        NSArray *lines = [raw componentsSeparatedByString:@"\n"];
        NSMutableDictionary *groups = [NSMutableDictionary dictionary];
        
        for (NSString *line in lines) {
            NSArray *parts = [line componentsSeparatedByString:@"|"];
            if (parts.count < 9) continue;
            
            NSString *pid = parts[0];
            NSString *title = parts[1];
            NSString *artist = parts[2];
            NSString *album = parts[3];
            NSString *genre = parts[4];
            NSString *trackNumber = parts[5];
            NSString *kind = parts[6];
            NSString *size = parts[7];
            NSString *location = parts[8];
            
            if (title.length == 0 || artist.length == 0) continue;
            
            NSString *normTitle = [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
            NSString *normArtist = [artist stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
            NSString *key = [NSString stringWithFormat:@"%@|%@", normArtist, normTitle];
            
            NSDictionary *trackInfo = @{
                @"pid": pid,
                @"title": title,
                @"artist": artist,
                @"album": album,
                @"genre": genre,
                @"trackNumber": trackNumber,
                @"kind": kind,
                @"size": size,
                @"location": location
            };
            
            if (!groups[key]) {
                groups[key] = [NSMutableArray array];
            }
            [groups[key] addObject:trackInfo];
        }
        
        // Find duplicate pairs
        NSMutableArray *pairs = [NSMutableArray array];
        NSArray *ignoredList = [[NSUserDefaults standardUserDefaults] stringArrayForKey:@"IgnoredDuplicatePairs"] ?: @[];
        
        for (NSString *key in groups) {
            NSArray *group = groups[key];
            if (group.count > 1) {
                // Pair them up
                for (NSInteger idx = 1; idx < group.count; idx++) {
                    NSDictionary *t1 = group[0];
                    NSDictionary *t2 = group[idx];
                    
                    NSString *pid1 = t1[@"pid"];
                    NSString *pid2 = t2[@"pid"];
                    NSString *pairKey = [pid1 compare:pid2] == NSOrderedAscending ?
                        [NSString stringWithFormat:@"%@-%@", pid1, pid2] :
                        [NSString stringWithFormat:@"%@-%@", pid2, pid1];
                        
                    if ([ignoredList containsObject:pairKey]) {
                        continue;
                    }
                    
                    // Determine Original vs Copy
                    double comp1 = [self completenessForTrack:t1];
                    double comp2 = [self completenessForTrack:t2];
                    
                    NSDictionary *original = t1;
                    NSDictionary *copy = t2;
                    
                    if (comp2 > comp1) {
                        original = t2;
                        copy = t1;
                    } else if (comp2 == comp1) {
                        double sz1 = [t1[@"size"] doubleValue];
                        double sz2 = [t2[@"size"] doubleValue];
                        if (sz2 > sz1) {
                            original = t2;
                            copy = t1;
                        }
                    }
                    
                    [pairs addObject:@{
                        @"original": original,
                        @"copy": copy,
                        @"pairKey": pairKey
                    }];
                }
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.scanButton.enabled = YES;
            [self.progressIndicator stopAnimation:nil];
            self.duplicatePairs = pairs;
            
            self.statusLabel.stringValue = [NSString stringWithFormat:@"Found %ld duplicate pairs", (long)pairs.count];
            [self populateDuplicateListView];
        });
    });
}

- (double)completenessForTrack:(NSDictionary *)track {
    NSInteger score = 0;
    if ([track[@"title"] length] > 0) score++;
    if ([track[@"artist"] length] > 0) score++;
    if ([track[@"album"] length] > 0) score++;
    if ([track[@"genre"] length] > 0) score++;
    if ([track[@"trackNumber"] integerValue] > 0) score++;
    return (score / 5.0) * 100.0;
}

- (void)populateDuplicateListView {
    CGFloat rowHeight = 85;
    CGFloat width = self.documentView.frame.size.width;
    CGFloat totalHeight = self.duplicatePairs.count * rowHeight;
    if (totalHeight < 220) totalHeight = 220;
    
    self.documentView.frame = NSMakeRect(0, 0, width, totalHeight);
    
    for (NSInteger idx = 0; idx < self.duplicatePairs.count; idx++) {
        NSDictionary *pair = self.duplicatePairs[idx];
        NSDictionary *orig = pair[@"original"];
        NSDictionary *copy = pair[@"copy"];
        NSString *pairKey = pair[@"pairKey"];
        
        CGFloat y = idx * rowHeight;
        
        NSView *rowView = [[NSView alloc] initWithFrame:NSMakeRect(0, y, width, rowHeight)];
        
        // Track 1 (Original)
        NSTextField *origLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 5, 210, 75)];
        origLabel.editable = NO;
        origLabel.bordered = NO;
        origLabel.drawsBackground = NO;
        origLabel.font = [NSFont systemFontOfSize:10];
        
        NSString *origExt = [orig[@"location"] pathExtension].uppercaseString;
        if (origExt.length == 0) origExt = @"AAC";
        double origSizeMB = [orig[@"size"] doubleValue] / (1024.0 * 1024.0);
        double origComp = [self completenessForTrack:orig];
        
        origLabel.stringValue = [NSString stringWithFormat:
            @"ORIGINAL:\n%@\nFormat: %@ | Size: %.2f MB\nCompleteness: %.0f%%", 
            orig[@"title"], origExt, origSizeMB, origComp];
        [rowView addSubview:origLabel];
        
        // Track 2 (Copy)
        NSTextField *copyLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(230, 5, 210, 75)];
        copyLabel.editable = NO;
        copyLabel.bordered = NO;
        copyLabel.drawsBackground = NO;
        copyLabel.font = [NSFont systemFontOfSize:10];
        
        NSString *copyExt = [copy[@"location"] pathExtension].uppercaseString;
        if (copyExt.length == 0) copyExt = @"AAC";
        double copySizeMB = [copy[@"size"] doubleValue] / (1024.0 * 1024.0);
        double copyComp = [self completenessForTrack:copy];
        
        copyLabel.stringValue = [NSString stringWithFormat:
            @"COPY (Delete candidate):\n%@\nFormat: %@ | Size: %.2f MB\nCompleteness: %.0f%%", 
            copy[@"title"], copyExt, copySizeMB, copyComp];
        [rowView addSubview:copyLabel];
        
        // Buttons
        NSButton *ignoreBtn = [[NSButton alloc] initWithFrame:NSMakeRect(450, 45, 80, 25)];
        ignoreBtn.title = @"Ignore";
        ignoreBtn.bezelStyle = NSRoundedBezelStyle;
        ignoreBtn.font = [NSFont systemFontOfSize:10];
        ignoreBtn.target = self;
        ignoreBtn.action = @selector(ignoreClicked:);
        // Store pair index in tag
        ignoreBtn.tag = idx;
        [rowView addSubview:ignoreBtn];
        
        NSButton *deleteBtn = [[NSButton alloc] initWithFrame:NSMakeRect(450, 15, 80, 25)];
        deleteBtn.title = @"Delete";
        deleteBtn.bezelStyle = NSRoundedBezelStyle;
        deleteBtn.font = [NSFont systemFontOfSize:10];
        deleteBtn.target = self;
        deleteBtn.action = @selector(deleteClicked:);
        deleteBtn.tag = idx;
        [rowView addSubview:deleteBtn];
        
        // Separator
        NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(10, 0, width - 20, 1)];
        separator.boxType = NSBoxSeparator;
        [rowView addSubview:separator];
        
        [self.documentView addSubview:rowView];
    }
}

- (void)ignoreClicked:(NSButton *)sender {
    NSInteger idx = sender.tag;
    if (idx >= self.duplicatePairs.count) return;
    
    NSDictionary *pair = self.duplicatePairs[idx];
    NSString *pairKey = pair[@"pairKey"];
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *ignoredList = [[defaults stringArrayForKey:@"IgnoredDuplicatePairs"] mutableCopy] ?: [NSMutableArray array];
    if (![ignoredList containsObject:pairKey]) {
        [ignoredList addObject:pairKey];
        [defaults setObject:ignoredList forKey:@"IgnoredDuplicatePairs"];
        [defaults synchronize];
    }
    
    [IGNotificationView showInView:self.view message:@"Ignored duplicate pair." isError:NO];
    [self scanForDuplicates];
}

- (void)deleteClicked:(NSButton *)sender {
    NSInteger idx = sender.tag;
    if (idx >= self.duplicatePairs.count) return;
    
    NSDictionary *pair = self.duplicatePairs[idx];
    NSDictionary *copy = pair[@"copy"];
    NSString *pid = copy[@"pid"];
    
    // Execute AppleScript to delete track
    IGiTunesService *service = [IGiTunesService sharedService];
    NSString *script = [NSString stringWithFormat:
        @"tell application \"iTunes\"\n"
        "    try\n"
        "        delete (some track of library playlist 1 whose persistent ID is \"%@\")\n"
        "    end try\n"
        "end tell", pid];
    [service runAppleScript:script];
    
    [IGNotificationView showInView:self.view message:@"Deleted copy track." isError:NO];
    [self scanForDuplicates];
}

@end
