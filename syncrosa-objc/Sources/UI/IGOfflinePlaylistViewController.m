#import "IGOfflinePlaylistViewController.h"
#import "IGiTunesService.h"
#import "IGLocalizationService.h"
#import "IGNotificationView.h"

@interface IGOfflinePlaylistViewController ()
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSPopUpButton *genrePopup;
@property (nonatomic, strong) NSPopUpButton *fromYearPopup;
@property (nonatomic, strong) NSPopUpButton *toYearPopup;
@property (nonatomic, strong) NSButton *coverCheckbox;
@property (nonatomic, strong) NSButton *ratingCheckbox;

@property (nonatomic, strong) NSButton *dec60s;
@property (nonatomic, strong) NSButton *dec70s;
@property (nonatomic, strong) NSButton *dec80s;
@property (nonatomic, strong) NSButton *dec90s;
@property (nonatomic, strong) NSButton *dec2000s;
@property (nonatomic, strong) NSButton *dec2010s;
@property (nonatomic, strong) NSButton *dec2020s;

@property (nonatomic, strong) NSButton *generateButton;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextField *footerLabel;
@property (nonatomic, strong) NSWindow *helpSheetWindow;
@end

@implementation IGOfflinePlaylistViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 480)];
    [self setupUI];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self populateYears];
    [self loadGenres];
}

- (void)setupUI {
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    CGFloat y = 430;
    
    self.titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 30)];
    self.titleLabel.stringValue = [lang t:@"offline_playlist"];
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
    
    // Genre selection
    y -= 45;
    NSTextField *genreLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(40, y, 120, 20)];
    genreLabel.stringValue = @"Genre:";
    genreLabel.font = [NSFont systemFontOfSize:12];
    genreLabel.editable = NO;
    genreLabel.bordered = NO;
    genreLabel.drawsBackground = NO;
    [self.view addSubview:genreLabel];
    
    self.genrePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(180, y-2, 200, 25) pullsDown:NO];
    [self.view addSubview:self.genrePopup];
    
    // Year range selection
    y -= 40;
    NSTextField *fromYearLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(40, y, 120, 20)];
    fromYearLabel.stringValue = @"From Year:";
    fromYearLabel.font = [NSFont systemFontOfSize:12];
    fromYearLabel.editable = NO;
    fromYearLabel.bordered = NO;
    fromYearLabel.drawsBackground = NO;
    [self.view addSubview:fromYearLabel];
    
    self.fromYearPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(180, y-2, 100, 25) pullsDown:NO];
    self.fromYearPopup.target = self;
    self.fromYearPopup.action = @selector(fromYearChanged:);
    [self.view addSubview:self.fromYearPopup];
    
    NSTextField *toYearLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(300, y, 60, 20)];
    toYearLabel.stringValue = @"To Year:";
    toYearLabel.font = [NSFont systemFontOfSize:12];
    toYearLabel.editable = NO;
    toYearLabel.bordered = NO;
    toYearLabel.drawsBackground = NO;
    [self.view addSubview:toYearLabel];
    
    self.toYearPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(370, y-2, 100, 25) pullsDown:NO];
    self.toYearPopup.target = self;
    self.toYearPopup.action = @selector(toYearChanged:);
    [self.view addSubview:self.toYearPopup];
    
    // Cover and Rating Filters (marked optional)
    y -= 40;
    self.coverCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(40, y, 230, 20)];
    [self.coverCheckbox setButtonType:NSSwitchButton];
    self.coverCheckbox.title = @"Require cover art (optional)";
    self.coverCheckbox.state = NSOffState;
    [self.view addSubview:self.coverCheckbox];
    
    self.ratingCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(300, y, 230, 20)];
    [self.ratingCheckbox setButtonType:NSSwitchButton];
    self.ratingCheckbox.title = @"Filter by rating (optional)";
    self.ratingCheckbox.state = NSOffState;
    [self.view addSubview:self.ratingCheckbox];
    
    // Decades section
    y -= 40;
    NSTextField *decLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(40, y, 500, 20)];
    decLabel.stringValue = @"Select Decades to Generate Playlists:";
    decLabel.font = [NSFont boldSystemFontOfSize:12];
    decLabel.editable = NO;
    decLabel.bordered = NO;
    decLabel.drawsBackground = NO;
    [self.view addSubview:decLabel];
    
    y -= 30;
    self.dec60s = [[NSButton alloc] initWithFrame:NSMakeRect(40, y, 80, 20)];
    [self.dec60s setButtonType:NSSwitchButton];
    self.dec60s.title = @"60s";
    self.dec60s.state = NSOnState;
    [self.view addSubview:self.dec60s];
    
    self.dec70s = [[NSButton alloc] initWithFrame:NSMakeRect(140, y, 80, 20)];
    [self.dec70s setButtonType:NSSwitchButton];
    self.dec70s.title = @"70s";
    self.dec70s.state = NSOnState;
    [self.view addSubview:self.dec70s];
    
    self.dec80s = [[NSButton alloc] initWithFrame:NSMakeRect(240, y, 80, 20)];
    [self.dec80s setButtonType:NSSwitchButton];
    self.dec80s.title = @"80s";
    self.dec80s.state = NSOnState;
    [self.view addSubview:self.dec80s];
    
    self.dec90s = [[NSButton alloc] initWithFrame:NSMakeRect(340, y, 80, 20)];
    [self.dec90s setButtonType:NSSwitchButton];
    self.dec90s.title = @"90s";
    self.dec90s.state = NSOnState;
    [self.view addSubview:self.dec90s];
    
    y -= 30;
    self.dec2000s = [[NSButton alloc] initWithFrame:NSMakeRect(40, y, 80, 20)];
    [self.dec2000s setButtonType:NSSwitchButton];
    self.dec2000s.title = @"2000s";
    self.dec2000s.state = NSOnState;
    [self.view addSubview:self.dec2000s];
    
    self.dec2010s = [[NSButton alloc] initWithFrame:NSMakeRect(140, y, 80, 20)];
    [self.dec2010s setButtonType:NSSwitchButton];
    self.dec2010s.title = @"2010s";
    self.dec2010s.state = NSOnState;
    [self.view addSubview:self.dec2010s];
    
    self.dec2020s = [[NSButton alloc] initWithFrame:NSMakeRect(240, y, 80, 20)];
    [self.dec2020s setButtonType:NSSwitchButton];
    self.dec2020s.title = @"2020+";
    self.dec2020s.state = NSOnState;
    [self.view addSubview:self.dec2020s];
    
    // Generate Button
    y -= 65;
    self.generateButton = [[NSButton alloc] initWithFrame:NSMakeRect(140, y, 300, 40)];
    self.generateButton.title = @"Generate Playlists by Epochs";
    self.generateButton.bezelStyle = NSTexturedRoundedBezelStyle;
    self.generateButton.target = self;
    self.generateButton.action = @selector(generateClicked:);
    [self.view addSubview:self.generateButton];
    
    // Progress and Status
    y -= 35;
    self.progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(40, y, 500, 20)];
    self.progressIndicator.style = NSProgressIndicatorBarStyle;
    self.progressIndicator.indeterminate = YES;
    self.progressIndicator.displayedWhenStopped = NO;
    [self.view addSubview:self.progressIndicator];
    
    y -= 25;
    self.statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 20)];
    self.statusLabel.stringValue = @"Ready to generate offline playlists";
    self.statusLabel.editable = NO;
    self.statusLabel.bordered = NO;
    self.statusLabel.drawsBackground = NO;
    self.statusLabel.alignment = NSCenterTextAlignment;
    [self.view addSubview:self.statusLabel];
    
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

- (void)populateYears {
    [self.fromYearPopup removeAllItems];
    [self.fromYearPopup addItemWithTitle:@"Any"];
    [self.toYearPopup removeAllItems];
    [self.toYearPopup addItemWithTitle:@"Any"];
    
    NSDateComponents *components = [[NSCalendar currentCalendar] components:NSCalendarUnitYear fromDate:[NSDate date]];
    NSInteger currentYear = [components year];
    
    for (NSInteger year = 1950; year <= currentYear; year++) {
        NSString *yearStr = [NSString stringWithFormat:@"%ld", (long)year];
        [self.fromYearPopup addItemWithTitle:yearStr];
        [self.toYearPopup addItemWithTitle:yearStr];
    }
}

- (void)loadGenres {
    [self.genrePopup removeAllItems];
    [self.genrePopup addItemWithTitle:@"Any"];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        IGiTunesService *service = [IGiTunesService sharedService];
        NSString *script = 
            @"set out to \"\"\n"
            "tell application \"iTunes\"\n"
            "    set trks to every track of library playlist 1\n"
            "    repeat with t in trks\n"
            "        try\n"
            "            set gen to genre of t\n"
            "            if gen is not \"\" then\n"
            "                set out to out & gen & \"\\n\"\n"
            "            end if\n"
            "        end try\n"
            "    end repeat\n"
            "end tell\n"
            "return out";
            
        NSString *raw = [service runAppleScript:script];
        NSMutableSet *genreSet = [NSMutableSet set];
        if (raw && raw.length > 0) {
            NSArray *lines = [raw componentsSeparatedByString:@"\n"];
            for (NSString *line in lines) {
                NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (trimmed.length > 0) {
                    [genreSet addObject:trimmed];
                }
            }
        }
        
        NSArray *sortedGenres = [[genreSet allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            for (NSString *genre in sortedGenres) {
                [self.genrePopup addItemWithTitle:genre];
            }
        });
    });
}

- (void)fromYearChanged:(id)sender {
    NSString *fromVal = self.fromYearPopup.titleOfSelectedItem;
    NSString *toVal = self.toYearPopup.titleOfSelectedItem;
    
    if ([fromVal isEqualToString:@"Any"] || [toVal isEqualToString:@"Any"]) {
        return;
    }
    
    NSInteger fromYear = [fromVal integerValue];
    NSInteger toYear = [toVal integerValue];
    if (fromYear > toYear) {
        [self.toYearPopup selectItemWithTitle:fromVal];
    }
}

- (void)toYearChanged:(id)sender {
    NSString *fromVal = self.fromYearPopup.titleOfSelectedItem;
    NSString *toVal = self.toYearPopup.titleOfSelectedItem;
    
    if ([fromVal isEqualToString:@"Any"] || [toVal isEqualToString:@"Any"]) {
        return;
    }
    
    NSInteger fromYear = [fromVal integerValue];
    NSInteger toYear = [toVal integerValue];
    if (toYear < fromYear) {
        [self.fromYearPopup selectItemWithTitle:toVal];
    }
}

- (void)helpClicked:(id)sender {
    NSString *helpText = @"Offline Playlist Generator Help\n\n"
                          "This utility allows you to create smart playlists based on epochs (decades) directly in your iTunes/Music library.\n\n"
                          "1. Genre & Year Range: Select a specific genre or a release year range. 'To Year' is constrained to be greater than or equal to 'From Year'.\n"
                          "2. Cover Art & Rating: Optionally filter to include only tracks that contain cover art or are rated (>= 3 stars / 60%).\n"
                          "3. Decades: Check which decades you want to generate playlists for. The tool will loop through all selected decades, create a playlist named 'Epoch - {Decade}', and populate it with matching tracks.\n"
                          "4. Skip Empty: If a decade contains zero matching tracks, it will log a console warning and skip creating the playlist entirely.\n"
                          "5. Warning Modal: If the filters yield zero matches across your library, a warning dialog will prompt you to ignore filters and run by decade anyway, or cancel.";
    
    NSWindow *sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 280)
                                                  styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered
                                                      defer:YES];
    
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 60, 380, 200)];
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

- (void)generateClicked:(id)sender {
    [self generatePlaylists];
}

- (void)generatePlaylists {
    self.generateButton.enabled = NO;
    [self.progressIndicator startAnimation:nil];
    self.statusLabel.stringValue = @"Fetching library details...";
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        IGiTunesService *service = [IGiTunesService sharedService];
        NSString *script = 
            @"set out to \"\"\n"
            "tell application \"iTunes\"\n"
            "    set trks to every track of library playlist 1\n"
            "    repeat with t in trks\n"
            "        try\n"
            "            set pid to persistent ID of t\n"
            "            set gen to genre of t\n"
            "            set yr to year of t\n"
            "            set rt to rating of t\n"
            "            set artCount to count of artworks of t\n"
            "            set out to out & pid & \"|\" & gen & \"|\" & yr & \"|\" & rt & \"|\" & artCount & \"\\n\"\n"
            "        end try\n"
            "    end repeat\n"
            "end tell\n"
            "return out";
            
        NSString *raw = [service runAppleScript:script];
        if (!raw || raw.length == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.generateButton.enabled = YES;
                [self.progressIndicator stopAnimation:nil];
                self.statusLabel.stringValue = @"No tracks found in library.";
            });
            return;
        }
        
        NSArray *lines = [raw componentsSeparatedByString:@"\n"];
        NSMutableArray *allTracks = [NSMutableArray array];
        
        for (NSString *line in lines) {
            NSArray *parts = [line componentsSeparatedByString:@"|"];
            if (parts.count < 5) continue;
            
            [allTracks addObject:@{
                @"pid": parts[0],
                @"genre": parts[1],
                @"year": @([parts[2] integerValue]),
                @"rating": @([parts[3] integerValue]),
                @"artCount": @([parts[4] integerValue])
            }];
        }
        
        // Filter track list
        dispatch_async(dispatch_get_main_queue(), ^{
            [self processTrackList:allTracks ignoreFilters:NO];
        });
    });
}

- (void)processTrackList:(NSArray *)allTracks ignoreFilters:(BOOL)ignoreFilters {
    NSString *selectedGenre = self.genrePopup.titleOfSelectedItem;
    NSString *fromYearStr = self.fromYearPopup.titleOfSelectedItem;
    NSString *toYearStr = self.toYearPopup.titleOfSelectedItem;
    
    BOOL requireCover = (self.coverCheckbox.state == NSOnState);
    BOOL filterRating = (self.ratingCheckbox.state == NSOnState);
    
    NSMutableArray *filteredTracks = [NSMutableArray array];
    
    for (NSDictionary *track in allTracks) {
        BOOL matches = YES;
        
        if (!ignoreFilters) {
            // Genre filter
            if (![selectedGenre isEqualToString:@"Any"]) {
                if (![track[@"genre"] isEqualToString:selectedGenre]) {
                    matches = NO;
                }
            }
            // Year From filter
            if (![fromYearStr isEqualToString:@"Any"]) {
                if ([track[@"year"] integerValue] < [fromYearStr integerValue]) {
                    matches = NO;
                }
            }
            // Year To filter
            if (![toYearStr isEqualToString:@"Any"]) {
                if ([track[@"year"] integerValue] > [toYearStr integerValue]) {
                    matches = NO;
                }
            }
            // Cover Art filter
            if (requireCover) {
                if ([track[@"artCount"] integerValue] == 0) {
                    matches = NO;
                }
            }
            // Rating filter
            if (filterRating) {
                if ([track[@"rating"] integerValue] < 60) {
                    matches = NO;
                }
            }
        }
        
        if (matches) {
            [filteredTracks addObject:track];
        }
    }
    
    if (filteredTracks.count == 0 && !ignoreFilters) {
        [self.progressIndicator stopAnimation:nil];
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"No matching tracks";
        alert.informativeText = @"No tracks in your library match the selected filters. Do you want to ignore all filters and generate the playlists based only on decades, or cancel?";
        [alert addButtonWithTitle:@"Ignore Filters"];
        [alert addButtonWithTitle:@"Cancel"];
        
        NSInteger response = [alert runModal];
        if (response == NSAlertFirstButtonReturn) {
            // Re-run with ignoreFilters = YES
            [self.progressIndicator startAnimation:nil];
            self.statusLabel.stringValue = @"Generating without filters...";
            [self processTrackList:allTracks ignoreFilters:YES];
        } else {
            self.generateButton.enabled = YES;
            self.statusLabel.stringValue = @"Generation cancelled.";
        }
        return;
    }
    
    // Now, run the decade playlist creation
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *decades = @[@"60s", @"70s", @"80s", @"90s", @"2000s", @"2010s", @"2020+"];
        NSArray *decadeCheckboxes = @[self.dec60s, self.dec70s, self.dec80s, self.dec90s, self.dec2000s, self.dec2010s, self.dec2020s];
        
        IGiTunesService *service = [IGiTunesService sharedService];
        
        for (NSInteger i = 0; i < decades.count; i++) {
            NSString *decadeName = decades[i];
            NSButton *chk = decadeCheckboxes[i];
            
            // Check if decade checkbox on main thread is checked
            __block BOOL isChecked = NO;
            dispatch_sync(dispatch_get_main_queue(), ^{
                isChecked = (chk.state == NSOnState);
            });
            
            if (!isChecked) continue;
            
            // Find matching tracks in this decade
            NSMutableArray *decadeTracks = [NSMutableArray array];
            for (NSDictionary *t in filteredTracks) {
                NSInteger yr = [t[@"year"] integerValue];
                if ([self isYear:yr inDecade:decadeName]) {
                    [decadeTracks addObject:t[@"pid"]];
                }
            }
            
            if (decadeTracks.count == 0) {
                NSLog(@"[Warning] No matching tracks found for decade: %@. Skipping playlist creation.", decadeName);
                continue;
            }
            
            // Create playlist and populate it
            NSString *playlistName = [NSString stringWithFormat:@"Epoch - %@", decadeName];
            
            // Build the Applescript to create/clear playlist
            NSString *createScript = [NSString stringWithFormat:
                @"tell application \"iTunes\"\n"
                "    try\n"
                "        if not (exists playlist \"%@\") then\n"
                "            make new user playlist with properties {name:\"%@\"}\n"
                "        end if\n"
                "        set pl to playlist \"%@\"\n"
                "        delete every track of pl\n"
                "    end try\n"
                "end tell", playlistName, playlistName, playlistName];
            [service runAppleScript:createScript];
            
            // Add tracks to it
            for (NSString *pid in decadeTracks) {
                NSString *addScript = [NSString stringWithFormat:
                    @"tell application \"iTunes\"\n"
                    "    try\n"
                    "        set pl to playlist \"%@\"\n"
                    "        duplicate (some track of library playlist 1 whose persistent ID is \"%@\") to pl\n"
                    "    end try\n"
                    "end tell", playlistName, pid];
                [service runAppleScript:addScript];
            }
            
            NSLog(@"Created playlist '%@' with %ld tracks.", playlistName, (long)decadeTracks.count);
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.generateButton.enabled = YES;
            [self.progressIndicator stopAnimation:nil];
            self.statusLabel.stringValue = @"Playlist generation completed!";
            [IGNotificationView showInView:self.view message:@"Playlists generated!" isError:NO];
        });
    });
}

- (BOOL)isYear:(NSInteger)year inDecade:(NSString *)decade {
    if ([decade isEqualToString:@"60s"]) {
        return year >= 1960 && year <= 1969;
    } else if ([decade isEqualToString:@"70s"]) {
        return year >= 1970 && year <= 1979;
    } else if ([decade isEqualToString:@"80s"]) {
        return year >= 1980 && year <= 1989;
    } else if ([decade isEqualToString:@"90s"]) {
        return year >= 1990 && year <= 1999;
    } else if ([decade isEqualToString:@"2000s"]) {
        return year >= 2000 && year <= 2009;
    } else if ([decade isEqualToString:@"2010s"]) {
        return year >= 2010 && year <= 2019;
    } else if ([decade isEqualToString:@"2020+"]) {
        return year >= 2020;
    }
    return NO;
}

@end
