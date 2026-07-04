#import "IGDuplicateFinderViewController.h"
#import "IGiTunesService.h"
#import "IGLocalizationService.h"
#import "IGNotificationView.h"

static NSString *IGDuplicateAppleScriptLiteral(NSString *value) {
    if (![value isKindOfClass:[NSString class]]) {
        return @"\"\"";
    }

    NSMutableString *escaped = [value mutableCopy];
    [escaped replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\r\n" withString:@"\n" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\r" withString:@"\n" options:0 range:NSMakeRange(0, escaped.length)];
    NSString *literal = [NSString stringWithFormat:@"\"%@\"", escaped];
#if !__has_feature(objc_arc)
    [escaped release];
#endif
    return literal;
}

static NSString *IGDuplicateAppleScriptListLiteral(NSArray *values) {
    NSMutableArray *parts = [NSMutableArray arrayWithCapacity:values.count];
    for (id value in values) {
        [parts addObject:IGDuplicateAppleScriptLiteral([value isKindOfClass:[NSString class]] ? value : @"")];
    }
    return [NSString stringWithFormat:@"{%@}", [parts componentsJoinedByString:@", "]];
}

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
@property (nonatomic, strong) NSButton *applyButton;
@property (nonatomic, strong) NSBox *progressBorderBox;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) IGFlippedView *documentView;
@property (nonatomic, strong) NSTextField *footerLabel;
@property (nonatomic, strong) NSArray *duplicatePairs;
@property (nonatomic, strong) NSMutableDictionary *pendingActions;
@property (nonatomic, strong) NSWindow *helpSheetWindow;
@end

@implementation IGDuplicateFinderViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 480)];
    [self setupUI];
}

- (void)setupUI {
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    self.pendingActions = [NSMutableDictionary dictionary];
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
    self.scanButton = [[NSButton alloc] initWithFrame:NSMakeRect(130, y, 160, 35)];
    self.scanButton.title = @"Show Duplicates";
    self.scanButton.bezelStyle = NSTexturedRoundedBezelStyle;
    self.scanButton.target = self;
    self.scanButton.action = @selector(scanClicked:);
    [self.view addSubview:self.scanButton];

    self.applyButton = [[NSButton alloc] initWithFrame:NSMakeRect(300, y, 150, 35)];
    self.applyButton.title = @"Apply Selected";
    self.applyButton.bezelStyle = NSTexturedRoundedBezelStyle;
    self.applyButton.target = self;
    self.applyButton.action = @selector(applyClicked:);
    self.applyButton.enabled = NO;
    [self.view addSubview:self.applyButton];
    
    y -= 30;
    self.progressBorderBox = [[NSBox alloc] initWithFrame:NSMakeRect(40, y, 500, 20)];
    self.progressBorderBox.boxType = NSBoxCustom;
    self.progressBorderBox.borderType = NSLineBorder;
    self.progressBorderBox.titlePosition = NSNoTitle;
    self.progressBorderBox.hidden = YES;
    [self.view addSubview:self.progressBorderBox];

    self.progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(41, y + 1, 498, 18)];
    self.progressIndicator.style = NSProgressIndicatorBarStyle;
    self.progressIndicator.indeterminate = YES;
    self.progressIndicator.displayedWhenStopped = NO;
    self.progressIndicator.hidden = YES;
    [self.view addSubview:self.progressIndicator];
    
    y -= 25;
    self.statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 20)];
    self.statusLabel.stringValue = @"Ready to scan for duplicates";
    self.statusLabel.editable = NO;
    self.statusLabel.bordered = NO;
    self.statusLabel.drawsBackground = NO;
    self.statusLabel.alignment = NSCenterTextAlignment;
    [self.view addSubview:self.statusLabel];
    
    self.scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 70, 560, 240)];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.hasHorizontalScroller = NO;
    self.scrollView.borderType = NSBezelBorder;
    self.scrollView.autoresizesSubviews = YES;
    
    self.documentView = [[IGFlippedView alloc] initWithFrame:NSMakeRect(0, 0, 540, 240)];
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
                          "3. Select Ignore or Delete for any pairs you want to process.\n"
                          "4. Apply Selected: Saves ignored pairs and deletes selected copy tracks in one batch, then refreshes the scan once.";
    
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
    if ([self.view.window respondsToSelector:@selector(beginSheet:completionHandler:)]) {
        [self.view.window beginSheet:sheet completionHandler:nil];
    } else {
        [NSApp beginSheet:sheet modalForWindow:self.view.window modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
    }
}

- (void)closeHelpSheet:(id)sender {
    if (self.helpSheetWindow) {
        if ([self.view.window respondsToSelector:@selector(endSheet:)]) {
            [self.view.window endSheet:self.helpSheetWindow];
        } else {
            [NSApp endSheet:self.helpSheetWindow];
        }
        [self.helpSheetWindow orderOut:nil];
        self.helpSheetWindow = nil;
    }
}

- (void)scanClicked:(id)sender {
    [self scanForDuplicates];
}

- (void)setProgressVisible:(BOOL)visible {
    self.progressBorderBox.hidden = !visible;
    self.progressIndicator.hidden = !visible;
    if (visible) {
        [self.progressIndicator startAnimation:nil];
    } else {
        [self.progressIndicator stopAnimation:nil];
    }
}

- (void)setDuplicateActionControlsEnabled:(BOOL)enabled {
    for (NSView *row in self.documentView.subviews) {
        for (NSView *subview in row.subviews) {
            if ([subview isKindOfClass:[NSButton class]]) {
                [(NSButton *)subview setEnabled:enabled];
            }
        }
    }
}

- (void)scanForDuplicates {
    self.scanButton.enabled = NO;
    self.applyButton.enabled = NO;
    [self.pendingActions removeAllObjects];
    [self setProgressVisible:YES];
    self.statusLabel.stringValue = @"Scanning library for duplicates...";
    
    // Clear old subviews
    NSArray *oldSubviews = [self.documentView.subviews copy];
    for (NSView *v in oldSubviews) {
        [v removeFromSuperview];
    }
#if !__has_feature(objc_arc)
    [oldSubviews release];
#endif
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        IGiTunesService *service = [IGiTunesService sharedService];
        NSString *script =
            @"on replaceText(theText, oldText, newText)\n"
            "    set AppleScript's text item delimiters to oldText\n"
            "    set textItems to every text item of theText\n"
            "    set AppleScript's text item delimiters to newText\n"
            "    set newString to textItems as text\n"
            "    set AppleScript's text item delimiters to \"\"\n"
            "    return newString\n"
            "end replaceText\n"
            "on textValue(v)\n"
            "    try\n"
            "        if v is missing value then return \"\"\n"
            "        set s to v as text\n"
            "        set s to my replaceText(s, tab, \" \")\n"
            "        set s to my replaceText(s, linefeed, \" \")\n"
            "        set s to my replaceText(s, return, \" \")\n"
            "        return s\n"
            "    on error\n"
            "        return \"\"\n"
            "    end try\n"
            "end textValue\n"
            "set out to \"\"\n"
            "tell application \"iTunes\"\n"
            "    set trks to every track of library playlist 1\n"
            "    repeat with t in trks\n"
            "        try\n"
            "            set pid to my textValue(persistent ID of t)\n"
            "            set nm to my textValue(name of t)\n"
            "            set art to my textValue(artist of t)\n"
            "            set alb to my textValue(album of t)\n"
            "            set gen to my textValue(genre of t)\n"
            "            set trk to track number of t\n"
            "            set knd to my textValue(kind of t)\n"
            "            set sz to size of t\n"
            "            set loc to \"\"\n"
            "            try\n"
                "                set loc to (POSIX path of (location of t as alias))\n"
            "            end try\n"
            "            set out to out & pid & tab & nm & tab & art & tab & alb & tab & gen & tab & trk & tab & knd & tab & sz & tab & my textValue(loc) & linefeed\n"
            "        end try\n"
            "    end repeat\n"
            "end tell\n"
            "return out";
            
        NSString *raw = [service runAppleScriptNamed:@"duplicates.scan" source:script];
        if (!raw || raw.length == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.scanButton.enabled = YES;
                [self setProgressVisible:NO];
                self.statusLabel.stringValue = @"No tracks found in library.";
            });
            return;
        }
        
        NSArray *lines = [raw componentsSeparatedByString:@"\n"];
        NSMutableDictionary *groups = [NSMutableDictionary dictionary];
        
        for (NSString *line in lines) {
            NSArray *parts = [line componentsSeparatedByString:@"\t"];
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
            [self setProgressVisible:NO];
            self.duplicatePairs = pairs;
            self.applyButton.enabled = NO;
            
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
    NSArray *oldSubviews = [self.documentView.subviews copy];
    for (NSView *v in oldSubviews) {
        [v removeFromSuperview];
    }
#if !__has_feature(objc_arc)
    [oldSubviews release];
#endif

    CGFloat rowHeight = 96;
    CGFloat width = self.scrollView.contentView.bounds.size.width;
    if (width < 520) width = 540;
    CGFloat visibleHeight = self.scrollView.contentView.bounds.size.height;
    if (visibleHeight < 220) visibleHeight = 240;
    CGFloat totalHeight = self.duplicatePairs.count * rowHeight;
    if (totalHeight < visibleHeight) totalHeight = visibleHeight;
    
    self.documentView.frame = NSMakeRect(0, 0, width, totalHeight);

    CGFloat padding = 10;
    CGFloat gap = 10;
    CGFloat actionWidth = 74;
    CGFloat columnWidth = floor((width - (padding * 2) - (gap * 2) - actionWidth) / 2.0);
    if (columnWidth < 190) columnWidth = 190;
    CGFloat originalX = padding;
    CGFloat copyX = originalX + columnWidth + gap;
    CGFloat actionX = width - padding - actionWidth;
    
    for (NSInteger idx = 0; idx < self.duplicatePairs.count; idx++) {
        NSDictionary *pair = self.duplicatePairs[idx];
        NSDictionary *orig = pair[@"original"];
        NSDictionary *copy = pair[@"copy"];
        
        CGFloat y = idx * rowHeight;
        
        NSView *rowView = [[NSView alloc] initWithFrame:NSMakeRect(0, y, width, rowHeight)];
        
        // Track 1 (Original)
        NSTextField *origLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(originalX, 9, columnWidth, 78)];
        origLabel.editable = NO;
        origLabel.bordered = NO;
        origLabel.drawsBackground = NO;
        origLabel.font = [NSFont systemFontOfSize:10];
        [[origLabel cell] setWraps:YES];
        [[origLabel cell] setLineBreakMode:NSLineBreakByTruncatingTail];
        
        NSString *origExt = [orig[@"location"] pathExtension].uppercaseString;
        if (origExt.length == 0) origExt = @"AAC";
        double origSizeMB = [orig[@"size"] doubleValue] / (1024.0 * 1024.0);
        double origComp = [self completenessForTrack:orig];
        
        origLabel.stringValue = [NSString stringWithFormat:
            @"ORIGINAL:\n%@\nFormat: %@ | Size: %.2f MB\nCompleteness: %.0f%%", 
            orig[@"title"], origExt, origSizeMB, origComp];
        [rowView addSubview:origLabel];
#if !__has_feature(objc_arc)
        [origLabel release];
#endif
        
        // Track 2 (Copy)
        NSTextField *copyLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(copyX, 9, columnWidth, 78)];
        copyLabel.editable = NO;
        copyLabel.bordered = NO;
        copyLabel.drawsBackground = NO;
        copyLabel.font = [NSFont systemFontOfSize:10];
        [[copyLabel cell] setWraps:YES];
        [[copyLabel cell] setLineBreakMode:NSLineBreakByTruncatingTail];
        
        NSString *copyExt = [copy[@"location"] pathExtension].uppercaseString;
        if (copyExt.length == 0) copyExt = @"AAC";
        double copySizeMB = [copy[@"size"] doubleValue] / (1024.0 * 1024.0);
        double copyComp = [self completenessForTrack:copy];
        
        copyLabel.stringValue = [NSString stringWithFormat:
            @"COPY (Delete candidate):\n%@\nFormat: %@ | Size: %.2f MB\nCompleteness: %.0f%%", 
            copy[@"title"], copyExt, copySizeMB, copyComp];
        [rowView addSubview:copyLabel];
#if !__has_feature(objc_arc)
        [copyLabel release];
#endif
        
        NSButton *ignoreRadio = [[NSButton alloc] initWithFrame:NSMakeRect(actionX, 53, actionWidth, 20)];
        [ignoreRadio setButtonType:NSRadioButton];
        ignoreRadio.title = @"Ignore";
        ignoreRadio.font = [NSFont systemFontOfSize:10];
        ignoreRadio.target = self;
        ignoreRadio.action = @selector(actionRadioClicked:);
        ignoreRadio.tag = idx * 10 + 1;
        ignoreRadio.state = NSOffState;
        [rowView addSubview:ignoreRadio];
#if !__has_feature(objc_arc)
        [ignoreRadio release];
#endif
        
        NSButton *deleteRadio = [[NSButton alloc] initWithFrame:NSMakeRect(actionX, 27, actionWidth, 20)];
        [deleteRadio setButtonType:NSRadioButton];
        deleteRadio.title = @"Delete";
        deleteRadio.font = [NSFont systemFontOfSize:10];
        deleteRadio.target = self;
        deleteRadio.action = @selector(actionRadioClicked:);
        deleteRadio.tag = idx * 10 + 2;
        deleteRadio.state = NSOffState;
        [rowView addSubview:deleteRadio];
#if !__has_feature(objc_arc)
        [deleteRadio release];
#endif
        
        // Separator
        NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(padding, 0, width - (padding * 2), 1)];
        separator.boxType = NSBoxSeparator;
        [rowView addSubview:separator];
#if !__has_feature(objc_arc)
        [separator release];
#endif
        
        [self.documentView addSubview:rowView];
#if !__has_feature(objc_arc)
        [rowView release];
#endif
    }
}

- (void)actionRadioClicked:(NSButton *)sender {
    NSInteger idx = sender.tag / 10;
    NSInteger actionCode = sender.tag % 10;
    if (idx < 0 || idx >= self.duplicatePairs.count) return;

    sender.state = NSOnState;
    for (NSView *subview in sender.superview.subviews) {
        if ([subview isKindOfClass:[NSButton class]]) {
            NSButton *button = (NSButton *)subview;
            if (button != sender && button.tag / 10 == idx) {
                button.state = NSOffState;
            }
        }
    }

    NSDictionary *pair = self.duplicatePairs[idx];
    NSString *pairKey = pair[@"pairKey"];
    if (pairKey.length == 0) return;

    self.pendingActions[pairKey] = actionCode == 1 ? @"ignore" : @"delete";
    self.applyButton.enabled = self.pendingActions.count > 0;
    self.statusLabel.stringValue = [NSString stringWithFormat:@"Selected %ld duplicate actions", (long)self.pendingActions.count];
}

- (void)applyClicked:(id)sender {
    if (self.pendingActions.count == 0) {
        [IGNotificationView showInView:self.view message:@"No duplicate actions selected." isError:YES];
        return;
    }

    NSArray *pairsSnapshot = [NSArray arrayWithArray:(self.duplicatePairs ?: @[])];
    NSDictionary *actionsSnapshot = [NSDictionary dictionaryWithDictionary:self.pendingActions];

    self.scanButton.enabled = NO;
    self.applyButton.enabled = NO;
    [self setDuplicateActionControlsEnabled:NO];
    [self setProgressVisible:YES];
    self.statusLabel.stringValue = @"Applying duplicate actions...";

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSInteger ignoredCount = 0;
        NSInteger deletedCount = 0;
        NSInteger deleteErrorCount = 0;
        NSMutableArray *deletePIDs = [NSMutableArray array];

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSMutableArray *ignoredList = [NSMutableArray arrayWithArray:([defaults stringArrayForKey:@"IgnoredDuplicatePairs"] ?: @[])];

        for (NSDictionary *pair in pairsSnapshot) {
            NSString *pairKey = pair[@"pairKey"];
            NSString *action = actionsSnapshot[pairKey];
            if (action.length == 0) continue;

            if ([action isEqualToString:@"ignore"]) {
                if (![ignoredList containsObject:pairKey]) {
                    [ignoredList addObject:pairKey];
                    ignoredCount++;
                }
            } else if ([action isEqualToString:@"delete"]) {
                NSString *pid = pair[@"copy"][@"pid"];
                if (pid.length > 0) {
                    [deletePIDs addObject:pid];
                }
            }
        }

        if (ignoredCount > 0) {
            [defaults setObject:ignoredList forKey:@"IgnoredDuplicatePairs"];
            [defaults synchronize];
        }
        if (deletePIDs.count > 0) {
            NSString *script = [NSString stringWithFormat:
                @"set pidList to %@\n"
                "set out to \"\"\n"
                "tell application \"iTunes\"\n"
                "    repeat with pidItem in pidList\n"
                "        set pidText to (contents of pidItem) as text\n"
                "        try\n"
                "            delete (some track of library playlist 1 whose persistent ID is pidText)\n"
                "            set out to out & \"OK\" & tab & pidText & linefeed\n"
                "        on error errMsg number errNum\n"
                "            set out to out & \"ERROR\" & tab & pidText & tab & (errNum as text) & tab & errMsg & linefeed\n"
                "        end try\n"
                "    end repeat\n"
                "end tell\n"
                "return out", IGDuplicateAppleScriptListLiteral(deletePIDs)];

            NSString *raw = [[IGiTunesService sharedService] runAppleScriptNamed:@"duplicates.applyDeletes" source:script];
            if (raw.length == 0) {
                deleteErrorCount += deletePIDs.count;
            } else {
                NSArray *lines = [raw componentsSeparatedByString:@"\n"];
                for (NSString *line in lines) {
                    if ([line hasPrefix:@"OK\t"]) {
                        deletedCount++;
                    } else if ([line hasPrefix:@"ERROR\t"]) {
                        deleteErrorCount++;
                    }
                }
                if (deletedCount + deleteErrorCount == 0) {
                    deleteErrorCount += deletePIDs.count;
                }
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.pendingActions removeAllObjects];
            NSString *message = deleteErrorCount > 0 ?
                [NSString stringWithFormat:@"Applied: %ld ignored, %ld deleted, %ld delete errors.",
                 (long)ignoredCount, (long)deletedCount, (long)deleteErrorCount] :
                [NSString stringWithFormat:@"Applied: %ld ignored, %ld deleted.",
                 (long)ignoredCount, (long)deletedCount];
            [IGNotificationView showInView:self.view message:message isError:(deleteErrorCount > 0)];
            [self scanForDuplicates];
        });
    });
}

@end
