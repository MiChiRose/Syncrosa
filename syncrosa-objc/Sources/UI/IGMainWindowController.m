#import "IGMainWindowController.h"
#import "IGSettingsViewController.h"
#import "IGFileFixerViewController.h"
#import "IGInfoEraserViewController.h"
#import "IGUSBExportViewController.h"
#import "IGCoversOptimizerViewController.h"
#import "IGDuplicateFinderViewController.h"
#import "IGOfflinePlaylistViewController.h"
#import "IGUSBService.h"
#import "IGiTunesService.h"
#import "IGAIService.h"
#import "IGKeychainHelper.h"
#import "IGLocalizationService.h"
#import "IGLogger.h"

@class IGMainWindowController;

@interface IGOverviewViewController : NSViewController
@property (nonatomic, assign) IGMainWindowController *mainController;
@property (nonatomic, strong) NSTextField *statusLabel;
@end

@implementation IGOverviewViewController

- (void)loadView {
    self.view = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 480)] autorelease];
    CGFloat y = 430;

    NSTextField *title = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 30)] autorelease];
    title.stringValue = @"Overview";
    title.font = [NSFont boldSystemFontOfSize:18];
    title.editable = NO;
    title.bordered = NO;
    title.drawsBackground = NO;
    title.alignment = NSCenterTextAlignment;
    [self.view addSubview:title];

    y -= 65;
    self.statusLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(40, y, 500, 70)] autorelease];
    self.statusLabel.stringValue = @"Syncrosa keeps iTunes tools disabled when the library is empty, runs long tasks in chunks, and stores restore data in safe backup folders.";
    self.statusLabel.font = [NSFont systemFontOfSize:13];
    self.statusLabel.textColor = [NSColor colorWithCalibratedWhite:0.30 alpha:1.0];
    self.statusLabel.editable = NO;
    self.statusLabel.bordered = NO;
    self.statusLabel.drawsBackground = NO;
    self.statusLabel.alignment = NSCenterTextAlignment;
    self.statusLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [self.view addSubview:self.statusLabel];

    y -= 70;
    NSButton *refresh = [[[NSButton alloc] initWithFrame:NSMakeRect(70, y, 190, 34)] autorelease];
    refresh.title = @"Refresh iTunes Status";
    refresh.bezelStyle = NSRoundedBezelStyle;
    refresh.target = self;
    refresh.action = @selector(refreshClicked:);
    [self.view addSubview:refresh];

    NSButton *doctor = [[[NSButton alloc] initWithFrame:NSMakeRect(320, y, 190, 34)] autorelease];
    doctor.title = @"Open Library Doctor";
    doctor.bezelStyle = NSRoundedBezelStyle;
    doctor.target = self;
    doctor.action = @selector(openDoctorClicked:);
    [self.view addSubview:doctor];

    y -= 65;
    NSButton *wizard = [[[NSButton alloc] initWithFrame:NSMakeRect(190, y, 200, 34)] autorelease];
    wizard.title = @"Show First Launch Setup";
    wizard.bezelStyle = NSRoundedBezelStyle;
    wizard.target = self;
    wizard.action = @selector(wizardClicked:);
    [self.view addSubview:wizard];
}

- (void)refreshClicked:(id)sender {
    self.statusLabel.stringValue = @"Checking iTunes...";
    [self.mainController refreshLibraryStatusWithCompletion:^{
        self.statusLabel.stringValue = @"iTunes status refreshed. Use the sidebar status for the current track count.";
    }];
}

- (void)openDoctorClicked:(id)sender {
    [self.mainController switchViewToIndex:9];
}

- (void)wizardClicked:(id)sender {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:@"Syncrosa First Launch Setup"];
    [alert setInformativeText:@"1. Allow iTunes automation if OS X asks.\n2. Check Overview before using library tools.\n3. Work on copies before destructive local file operations.\n4. Use Only Local Mode in Settings when you want to avoid online metadata lookups."];
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

@end

@interface IGLibraryDoctorViewController : NSViewController
@property (nonatomic, strong) NSSegmentedControl *toolSelector;
@property (nonatomic, strong) NSButton *runButton;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSTextView *logView;
@property (nonatomic, assign) BOOL isRunning;
@end

@implementation IGLibraryDoctorViewController

static void IGLibraryDoctorRecordHistory(NSString *title, NSString *status, NSString *message) {
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *base = dirs.count > 0 ? [dirs objectAtIndex:0] : NSHomeDirectory();
    NSString *dir = [base stringByAppendingPathComponent:@"Syncrosa"];
    NSString *path = [dir stringByAppendingPathComponent:@"operation-history.json"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];

    NSMutableArray *entries = [NSMutableArray array];
    NSData *existingData = [NSData dataWithContentsOfFile:path];
    if (existingData.length > 0) {
        id json = [NSJSONSerialization JSONObjectWithData:existingData options:0 error:nil];
        if ([json isKindOfClass:[NSArray class]]) {
            [entries addObjectsFromArray:(NSArray *)json];
        }
    }
    NSDictionary *entry = @{
        @"id": [[NSProcessInfo processInfo] globallyUniqueString],
        @"tool": @"Library Doctor",
        @"title": title ?: @"",
        @"status": status ?: @"",
        @"message": message ?: @"",
        @"createdAt": @([[NSDate date] timeIntervalSince1970]),
        @"affectedCount": @0,
        @"backupPath": @""
    };
    [entries insertObject:entry atIndex:0];
    while (entries.count > 250) {
        [entries removeLastObject];
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:entries options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:path atomically:YES];
}

- (void)loadView {
    self.view = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 480)] autorelease];
    CGFloat y = 430;

    NSTextField *title = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 30)] autorelease];
    title.stringValue = @"Library Doctor";
    title.font = [NSFont boldSystemFontOfSize:18];
    title.editable = NO;
    title.bordered = NO;
    title.drawsBackground = NO;
    title.alignment = NSCenterTextAlignment;
    [self.view addSubview:title];

    y -= 45;
    self.toolSelector = [[[NSSegmentedControl alloc] initWithFrame:NSMakeRect(70, y, 440, 26)] autorelease];
    self.toolSelector.segmentCount = 3;
    [self.toolSelector setLabel:@"Cover Restore" forSegment:0];
    [self.toolSelector setLabel:@"Cover Audit" forSegment:1];
    [self.toolSelector setLabel:@"Library Audit" forSegment:2];
    [self.toolSelector setSelectedSegment:1];
    [self.view addSubview:self.toolSelector];

    y -= 48;
    self.runButton = [[[NSButton alloc] initWithFrame:NSMakeRect(190, y, 200, 34)] autorelease];
    self.runButton.title = @"Run Doctor";
    self.runButton.bezelStyle = NSTexturedRoundedBezelStyle;
    self.runButton.target = self;
    self.runButton.action = @selector(runClicked:);
    [self.view addSubview:self.runButton];

    y -= 35;
    self.progressIndicator = [[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(40, y, 500, 18)] autorelease];
    self.progressIndicator.style = NSProgressIndicatorBarStyle;
    self.progressIndicator.indeterminate = NO;
    self.progressIndicator.maxValue = 1;
    [self.view addSubview:self.progressIndicator];

    y -= 215;
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(40, y, 500, 200)] autorelease];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    self.logView = [[[NSTextView alloc] initWithFrame:scroll.bounds] autorelease];
    self.logView.editable = NO;
    self.logView.backgroundColor = [NSColor blackColor];
    self.logView.textColor = [NSColor greenColor];
    self.logView.font = [NSFont fontWithName:@"Monaco" size:10];
    scroll.documentView = self.logView;
    [self.view addSubview:scroll];
}

- (void)clearLog {
    [self.logView setString:@""];
}

- (void)log:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *line = [NSString stringWithFormat:@"> %@\n", text ?: @""];
        NSAttributedString *attr = [[[NSAttributedString alloc] initWithString:line attributes:@{NSForegroundColorAttributeName: [NSColor greenColor]}] autorelease];
        [self.logView.textStorage appendAttributedString:attr];
        [self.logView scrollRangeToVisible:NSMakeRange(self.logView.textStorage.length, 0)];
    });
}

- (void)runClicked:(id)sender {
    if (self.isRunning) return;
    self.isRunning = YES;
    self.runButton.enabled = NO;
    self.progressIndicator.doubleValue = 0;
    [self clearLog];

    NSInteger selected = self.toolSelector.selectedSegment;
    NSString *selectedTitle = selected == 0 ? @"Cover Restore" : (selected == 1 ? @"Cover Audit" : @"Library Audit");
    __block NSString *historyMessage = @"Library Doctor finished.";
    __block NSString *historyStatus = @"OK";
    [self log:@"Library Doctor started."];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (selected == 0) {
            historyMessage = @"Cover Restore is handled by Covers Optimizer in the legacy app.";
            [self log:@"Cover Restore: open Covers Optimizer when you need to restore artwork from the backup manifest."];
            [self log:@"This legacy doctor keeps restore writes inside the dedicated Covers Optimizer tab."];
        } else if (selected == 1) {
            NSString *errorMessage = nil;
            NSInteger total = [[IGiTunesService sharedService] readLibraryTrackCountSyncWithErrorMessage:&errorMessage];
            if (total < 0) {
                historyStatus = @"WARN";
                historyMessage = [NSString stringWithFormat:@"Could not read iTunes library: %@", errorMessage ?: @""];
                [self log:historyMessage];
            } else {
                NSInteger coverCount = 0;
                NSInteger chunkSize = 150;
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.progressIndicator.maxValue = MAX(total, 1);
                    self.progressIndicator.doubleValue = 0;
                });
                for (NSInteger start = 1; start <= total; start += chunkSize) {
                    NSInteger end = MIN(start + chunkSize - 1, total);
                    NSString *script = [NSString stringWithFormat:
                        @"set coverCount to 0\n"
                        "tell application \"iTunes\"\n"
                        "    try\n"
                        "        set trks to (tracks %ld thru %ld of library playlist 1)\n"
                        "        repeat with t in trks\n"
                        "            try\n"
                        "                if (count of artworks of t) > 0 then set coverCount to coverCount + 1\n"
                        "            end try\n"
                        "        end repeat\n"
                        "    end try\n"
                        "end tell\n"
                        "return coverCount as text", (long)start, (long)end];
                    NSString *raw = [[IGiTunesService sharedService] runAppleScriptNamed:@"libraryDoctor.coverAudit.chunk" source:script];
                    coverCount += [raw integerValue];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.progressIndicator.doubleValue = end;
                        [self log:[NSString stringWithFormat:@"Cover audit chunk %ld-%ld of %ld", (long)start, (long)end, (long)total]];
                    });
                }
                historyMessage = [NSString stringWithFormat:@"Cover audit complete. Tracks: %ld. Tracks with covers: %ld.", (long)total, (long)coverCount];
                [self log:historyMessage];
            }
        } else {
            NSString *errorMessage = nil;
            NSInteger count = [[IGiTunesService sharedService] readLibraryTrackCountSyncWithErrorMessage:&errorMessage];
            if (count >= 0) {
                historyMessage = [NSString stringWithFormat:@"iTunes library track count: %ld", (long)count];
                [self log:[NSString stringWithFormat:@"iTunes library track count: %ld", (long)count]];
            } else {
                historyStatus = @"WARN";
                historyMessage = [NSString stringWithFormat:@"Could not read iTunes library: %@", errorMessage ?: @""];
                [self log:[NSString stringWithFormat:@"Could not read iTunes library: %@", errorMessage ?: @""]];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressIndicator.doubleValue = 1;
            self.isRunning = NO;
            self.runButton.enabled = YES;
            [self log:@"Library Doctor finished."];
            IGLibraryDoctorRecordHistory(selectedTitle, historyStatus, historyMessage);
        });
    });
}

@end

@interface IGMainWindowController () <NSSplitViewDelegate>
@property (nonatomic, strong) NSSplitView *splitView;
@property (nonatomic, strong) NSView *sidebarContainer;
@property (nonatomic, strong) NSView *contentContainer;
@property (nonatomic, strong) NSMutableArray *sidebarButtons;
@property (nonatomic, strong) NSTextField *libraryStatusLabel;
@property (nonatomic, strong) NSButton *libraryRefreshButton;
@property (nonatomic, assign) NSInteger libraryTrackCount;
@property (nonatomic, assign) BOOL libraryStatusKnown;
@property (nonatomic, assign) BOOL refreshingLibraryStatus;
@property (nonatomic, assign) NSInteger activeIndex;

@property (nonatomic, strong) IGGeniusViewController *geniusVC;
@property (nonatomic, strong) IGFixerViewController *fixerVC;
@property (nonatomic, strong) IGFileFixerViewController *fileFixerVC;
@property (nonatomic, strong) IGInfoEraserViewController *infoEraserVC;
@property (nonatomic, strong) IGUSBExportViewController *usbExportVC;
@property (nonatomic, strong) IGCoversOptimizerViewController *coversOptimizerVC;
@property (nonatomic, strong) IGDuplicateFinderViewController *duplicateFinderVC;
@property (nonatomic, strong) IGOfflinePlaylistViewController *offlinePlaylistVC;
@property (nonatomic, strong) IGSettingsViewController *settingsVC;
@property (nonatomic, strong) IGOverviewViewController *overviewVC;
@property (nonatomic, strong) IGLibraryDoctorViewController *libraryDoctorVC;
@end

@implementation IGMainWindowController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 500)
                                                   styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window center];
    window.title = @"Syncrosa";
    
	    self = [super initWithWindow:window];
#if !__has_feature(objc_arc)
	    [window release];
#endif
	    if (self) {
	        _libraryTrackCount = -1;
	        _libraryStatusKnown = NO;
	        _refreshingLibraryStatus = NO;
	        _activeIndex = -1;
	        [self setupUI];
	    }
    return self;
}

	- (void)dealloc {
	    [[NSNotificationCenter defaultCenter] removeObserver:self];
	#if !__has_feature(objc_arc)
	    [_splitView release];
	    [_sidebarContainer release];
	    [_contentContainer release];
	    [_sidebarButtons release];
	    [_libraryStatusLabel release];
	    [_libraryRefreshButton release];
	    [_geniusVC release];
	    [_fixerVC release];
	    [_fileFixerVC release];
	    [_infoEraserVC release];
	    [_usbExportVC release];
	    [_coversOptimizerVC release];
	    [_duplicateFinderVC release];
	    [_offlinePlaylistVC release];
	    [_settingsVC release];
	    [_overviewVC release];
	    [_libraryDoctorVC release];
	    [super dealloc];
	#endif
	}

- (void)setupUI {
    NSView *rootView = self.window.contentView;
    
	    self.splitView = [[NSSplitView alloc] initWithFrame:rootView.bounds];
    self.splitView.vertical = YES;
    self.splitView.dividerStyle = NSSplitViewDividerStyleThin;
    self.splitView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.splitView.delegate = self;
    
	    self.sidebarContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 180, 500)];
	    self.contentContainer = [[NSView alloc] initWithFrame:NSMakeRect(180, 0, 620, 500)];
#if !__has_feature(objc_arc)
	    [self.splitView release];
	    [self.sidebarContainer release];
	    [self.contentContainer release];
#endif
    
    // Add a classic textured background to the sidebar
    NSBox *sidebarBackground = [[NSBox alloc] initWithFrame:self.sidebarContainer.bounds];
    sidebarBackground.boxType = NSBoxCustom;
    sidebarBackground.borderType = NSNoBorder;
    sidebarBackground.fillColor = [NSColor colorWithCalibratedWhite:0.92 alpha:1.0];
    sidebarBackground.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	    [self.sidebarContainer addSubview:sidebarBackground];
#if !__has_feature(objc_arc)
	    [sidebarBackground release];
#endif
    
    [self.splitView addSubview:self.sidebarContainer];
    [self.splitView addSubview:self.contentContainer];
    [self.splitView adjustSubviews];
    
    [rootView addSubview:self.splitView];
    
    self.sidebarButtons = [NSMutableArray array];
    [self setupSidebar];
    [self updateButtonStates];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(localizationChanged:)
                                                 name:@"IGLanguageChangedNotification"
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(drivesUpdatedNotification:)
                                                 name:@"IGUSBDrivesUpdatedNotification"
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:NSApplicationDidBecomeActiveNotification
                                               object:nil];
    
    // Initial VC: if API key exists, show Genius Playlist, otherwise Settings
	    NSString *provider = [[NSUserDefaults standardUserDefaults] stringForKey:@"provider"] ?: @"Gemini";
    NSString *apiKey = [[IGKeychainHelper sharedHelper] readStringForAccount:[provider lowercaseString]];
    if (apiKey && apiKey.length > 0) {
        [self switchViewToIndex:0];
    } else {
        [self switchViewToIndex:10];
    }
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    if (self.libraryStatusKnown || self.refreshingLibraryStatus) {
        return;
    }
    [self updateButtonStates];
}

- (void)drivesUpdatedNotification:(NSNotification *)notification {
    [self updateButtonStates];
}

- (BOOL)indexRequiresReadableLibrary:(NSInteger)index {
    return (index == 1 || index == 2 || index == 4 || index == 5 || index == 6 || index == 7 || index == 9);
}

- (BOOL)libraryIsConfirmedEmpty {
    return (self.libraryStatusKnown && self.libraryTrackCount == 0);
}

- (void)showEmptyLibraryAlert {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"iTunes Library Is Empty"];
    [alert setInformativeText:@"This tool needs tracks in your iTunes library. Add music to iTunes, then click Refresh iTunes."];
    [alert runModal];
#if !__has_feature(objc_arc)
    [alert release];
#endif
}

- (void)refreshLibraryStatusWithCompletion:(void(^)(void))completionBlock {
    if (self.refreshingLibraryStatus) {
        if (completionBlock) {
            completionBlock();
        }
        return;
    }

    void (^completionCopy)(void) = completionBlock ? [completionBlock copy] : nil;
    self.refreshingLibraryStatus = YES;
    self.libraryStatusLabel.stringValue = @"Checking iTunes...";
    self.libraryRefreshButton.enabled = NO;
    [self updateButtonStates];

    [[IGiTunesService sharedService] fetchLibraryTrackCountWithCompletion:^(NSInteger trackCount, NSString *errorMessage) {
        self.refreshingLibraryStatus = NO;
        self.libraryStatusKnown = YES;
        self.libraryTrackCount = trackCount;
        self.libraryRefreshButton.enabled = YES;

        if (trackCount == 0) {
            self.libraryStatusLabel.stringValue = @"iTunes library is empty.";
        } else if (trackCount > 0) {
            self.libraryStatusLabel.stringValue = [NSString stringWithFormat:@"iTunes tracks: %ld", (long)trackCount];
        } else {
            self.libraryStatusLabel.stringValue = @"iTunes status unknown.";
            [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"Could not read iTunes library count: %@", errorMessage ?: @""]];
        }

        [self updateButtonStates];

        if ([self libraryIsConfirmedEmpty] && [self indexRequiresReadableLibrary:self.activeIndex]) {
            [self switchViewToIndex:0];
        }

        if (completionCopy) {
            completionCopy();
#if !__has_feature(objc_arc)
            [completionCopy release];
#endif
        }
    }];
}

- (void)refreshLibraryButtonClicked:(id)sender {
    [self refreshLibraryStatusWithCompletion:nil];
}

- (void)updateButtonStates {
	    NSString *provider = [[NSUserDefaults standardUserDefaults] stringForKey:@"provider"] ?: @"Gemini";
    NSString *apiKey = [[IGKeychainHelper sharedHelper] readStringForAccount:[provider lowercaseString]];
    BOOL hasKey = (apiKey && apiKey.length > 0);
    BOOL isUSBSearching = [IGUSBService sharedService].isSearching;
    
    for (NSInteger i = 0; i < self.sidebarButtons.count; i++) {
        NSButton *btn = self.sidebarButtons[i];
        BOOL disabledByEmptyLibrary = ([self libraryIsConfirmedEmpty] && [self indexRequiresReadableLibrary:i]);
        if (i == 1) { // Only Genius Playlist requires an API key
            btn.enabled = hasKey && !disabledByEmptyLibrary && !self.refreshingLibraryStatus;
        } else if (i == 4) { // USB Export button
            btn.enabled = !isUSBSearching && !disabledByEmptyLibrary && !self.refreshingLibraryStatus;
        } else if ([self indexRequiresReadableLibrary:i]) {
            btn.enabled = !disabledByEmptyLibrary && !self.refreshingLibraryStatus;
        } else {
            btn.enabled = YES;
        }
    }
}

- (void)setupSidebar {
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    NSArray *titles = @[
        @"Overview",
        [lang t:@"ai_playlist"],
        [lang t:@"media_fixer"],
        [lang t:@"folder_fix"],
        [lang t:@"usb_export"],
        [lang t:@"covers_optimizer"],
        [lang t:@"duplicate_finder"],
        [lang t:@"offline_playlist"],
        @"Info Eraser",
        @"Library Doctor",
        [lang t:@"settings"]
    ];
    
    // Clean old buttons
    for (NSButton *btn in self.sidebarButtons) {
        [btn removeFromSuperview];
    }
    [self.sidebarButtons removeAllObjects];
    
    CGFloat y = 438;
    for (NSInteger i = 0; i < titles.count; i++) {
        NSButton *btn = [[NSButton alloc] initWithFrame:NSMakeRect(15, y, 150, 28)];
        btn.title = titles[i];
        btn.bezelStyle = NSTexturedSquareBezelStyle;
        btn.target = self;
        btn.action = @selector(sidebarClicked:);
        btn.tag = i;
        btn.autoresizingMask = NSViewWidthSizable;
	        [self.sidebarContainer addSubview:btn];
	        [self.sidebarButtons addObject:btn];
#if !__has_feature(objc_arc)
	        [btn release];
#endif
	        y -= 32;
	    }

    if (!self.libraryStatusLabel) {
        NSTextField *statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(15, 68, 150, 34)];
        statusLabel.editable = NO;
        statusLabel.selectable = NO;
        statusLabel.bordered = NO;
        statusLabel.drawsBackground = NO;
        statusLabel.font = [NSFont systemFontOfSize:10.0];
        statusLabel.textColor = [NSColor colorWithCalibratedWhite:0.38 alpha:1.0];
        statusLabel.alignment = NSCenterTextAlignment;
        statusLabel.lineBreakMode = NSLineBreakByWordWrapping;
        statusLabel.stringValue = @"iTunes status unknown.";
        statusLabel.autoresizingMask = NSViewWidthSizable;
        self.libraryStatusLabel = statusLabel;
        [self.sidebarContainer addSubview:statusLabel];
#if !__has_feature(objc_arc)
        [statusLabel release];
#endif
    } else {
        self.libraryStatusLabel.frame = NSMakeRect(15, 68, 150, 34);
    }

    if (!self.libraryRefreshButton) {
        NSButton *refreshButton = [[NSButton alloc] initWithFrame:NSMakeRect(15, 34, 150, 28)];
        refreshButton.title = @"Refresh iTunes";
        refreshButton.bezelStyle = NSTexturedSquareBezelStyle;
        refreshButton.target = self;
        refreshButton.action = @selector(refreshLibraryButtonClicked:);
        refreshButton.autoresizingMask = NSViewWidthSizable;
        self.libraryRefreshButton = refreshButton;
        [self.sidebarContainer addSubview:refreshButton];
#if !__has_feature(objc_arc)
        [refreshButton release];
#endif
    } else {
        self.libraryRefreshButton.frame = NSMakeRect(15, 34, 150, 28);
    }
}

- (void)localizationChanged:(NSNotification *)notification {
    NSInteger activeIndex = -1;
    for (NSInteger i = 0; i < self.sidebarButtons.count; i++) {
        NSButton *btn = self.sidebarButtons[i];
        if (btn.state == NSOnState) {
            activeIndex = i;
            break;
        }
    }
    
    [self setupSidebar];
    [self updateButtonStates];
    
    if (activeIndex >= 0 && activeIndex < self.sidebarButtons.count) {
        NSButton *btn = self.sidebarButtons[activeIndex];
        btn.state = NSOnState;
    }
}

- (void)sidebarClicked:(NSButton *)sender {
    [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"Sidebar clicked index=%ld title=%@", (long)sender.tag, sender.title ?: @""]];
    [self switchViewToIndex:sender.tag];
}

- (void)switchViewToIndex:(NSInteger)index {
    [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"Switch view requested index=%ld", (long)index]];
	    NSString *provider = [[NSUserDefaults standardUserDefaults] stringForKey:@"provider"] ?: @"Gemini";
    NSString *apiKey = [[IGKeychainHelper sharedHelper] readStringForAccount:[provider lowercaseString]];
    BOOL hasKey = (apiKey && apiKey.length > 0);
    
    if (index == 1 && !hasKey) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Access Restricted"];
        [alert setInformativeText:@"Please enter and validate your API Key in Settings to unlock AI features."];
        [alert runModal];
#if !__has_feature(objc_arc)
        [alert release];
#endif
        return;
    }

    if ([self indexRequiresReadableLibrary:index] && !self.libraryStatusKnown) {
        if (!self.refreshingLibraryStatus) {
            [self refreshLibraryStatusWithCompletion:^{
                if ([self libraryIsConfirmedEmpty]) {
                    [self showEmptyLibraryAlert];
                    [self switchViewToIndex:0];
                } else {
                    [self switchViewToIndex:index];
                }
            }];
        }
        return;
    }

    if ([self indexRequiresReadableLibrary:index] && [self libraryIsConfirmedEmpty]) {
        [self showEmptyLibraryAlert];
        return;
    }

    self.activeIndex = index;

    // Highlight button state
    for (NSInteger i = 0; i < self.sidebarButtons.count; i++) {
        NSButton *btn = self.sidebarButtons[i];
        if (i == index) {
            btn.state = NSOnState;
        } else {
            btn.state = NSOffState;
        }
    }

	    // Clear content
	    NSArray *contentSubviews = [self.contentContainer.subviews copy];
	    for (NSView *v in contentSubviews) {
	        [v removeFromSuperview];
	    }
#if !__has_feature(objc_arc)
	    [contentSubviews release];
#endif
    
    NSViewController *targetVC = nil;
    switch (index) {
	        case 0:
	            if (!self.overviewVC) {
	                IGOverviewViewController *vc = [[IGOverviewViewController alloc] init];
	                vc.mainController = self;
	                self.overviewVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.overviewVC;
	            break;
	        case 1:
	            if (!self.geniusVC) {
	                IGGeniusViewController *vc = [[IGGeniusViewController alloc] init];
	                self.geniusVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.geniusVC;
	            break;
	        case 2:
	            if (!self.fixerVC) {
	                IGFixerViewController *vc = [[IGFixerViewController alloc] init];
	                self.fixerVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.fixerVC;
	            break;
	        case 3:
	            if (!self.fileFixerVC) {
	                IGFileFixerViewController *vc = [[IGFileFixerViewController alloc] init];
	                self.fileFixerVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.fileFixerVC;
	            break;
	        case 4:
	            if (!self.usbExportVC) {
	                IGUSBExportViewController *vc = [[IGUSBExportViewController alloc] init];
	                self.usbExportVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.usbExportVC;
	            break;
	        case 5:
	            if (!self.coversOptimizerVC) {
	                IGCoversOptimizerViewController *vc = [[IGCoversOptimizerViewController alloc] init];
	                self.coversOptimizerVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.coversOptimizerVC;
	            break;
	        case 6:
	            if (!self.duplicateFinderVC) {
	                IGDuplicateFinderViewController *vc = [[IGDuplicateFinderViewController alloc] init];
	                self.duplicateFinderVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.duplicateFinderVC;
	            break;
	        case 7:
	            if (!self.offlinePlaylistVC) {
	                IGOfflinePlaylistViewController *vc = [[IGOfflinePlaylistViewController alloc] init];
	                self.offlinePlaylistVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.offlinePlaylistVC;
	            break;
	        case 8:
	            if (!self.infoEraserVC) {
	                IGInfoEraserViewController *vc = [[IGInfoEraserViewController alloc] init];
	                self.infoEraserVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.infoEraserVC;
	            break;
	        case 9:
	            if (!self.libraryDoctorVC) {
	                IGLibraryDoctorViewController *vc = [[IGLibraryDoctorViewController alloc] init];
	                self.libraryDoctorVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.libraryDoctorVC;
	            break;
	        case 10:
	            if (!self.settingsVC) {
	                IGSettingsViewController *vc = [[IGSettingsViewController alloc] init];
	                self.settingsVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.settingsVC;
	            break;
    }
    
    if (targetVC) {
        [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"Switch view showing %@ for index=%ld", NSStringFromClass([targetVC class]), (long)index]];
        targetVC.view.frame = self.contentContainer.bounds;
        targetVC.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [self.contentContainer addSubview:targetVC.view];
    }
}

- (void)windowWillClose:(NSNotification *)notification {
    [NSApp terminate:nil];
}

#pragma mark - SplitView Delegate
- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)dividerIndex {
    return 250;
}
- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)dividerIndex {
    return 150;
}

@end
