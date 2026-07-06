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
        [self switchViewToIndex:8];
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
    return (index == 0 || index == 1 || index == 3 || index == 4 || index == 5 || index == 6);
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
            [self switchViewToIndex:8];
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
        if (i == 0) { // Only Genius Playlist requires an API key
            btn.enabled = hasKey && !disabledByEmptyLibrary && !self.refreshingLibraryStatus;
        } else if (i == 3) { // USB Export button
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
        [lang t:@"ai_playlist"],
        [lang t:@"media_fixer"],
        [lang t:@"folder_fix"],
        [lang t:@"usb_export"],
        [lang t:@"covers_optimizer"],
        [lang t:@"duplicate_finder"],
        [lang t:@"offline_playlist"],
        @"Info Eraser",
        [lang t:@"settings"]
    ];
    
    // Clean old buttons
    for (NSButton *btn in self.sidebarButtons) {
        [btn removeFromSuperview];
    }
    [self.sidebarButtons removeAllObjects];
    
    CGFloat y = 440;
    for (NSInteger i = 0; i < titles.count; i++) {
        NSButton *btn = [[NSButton alloc] initWithFrame:NSMakeRect(15, y, 150, 30)];
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
	        y -= 38;
	    }

    if (!self.libraryStatusLabel) {
        NSTextField *statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(15, 92, 150, 34)];
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
        self.libraryStatusLabel.frame = NSMakeRect(15, 92, 150, 34);
    }

    if (!self.libraryRefreshButton) {
        NSButton *refreshButton = [[NSButton alloc] initWithFrame:NSMakeRect(15, 55, 150, 28)];
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
        self.libraryRefreshButton.frame = NSMakeRect(15, 55, 150, 28);
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
    
    if (index == 0 && !hasKey) {
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
                    [self switchViewToIndex:8];
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
	            if (!self.geniusVC) {
	                IGGeniusViewController *vc = [[IGGeniusViewController alloc] init];
	                self.geniusVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.geniusVC;
	            break;
	        case 1:
	            if (!self.fixerVC) {
	                IGFixerViewController *vc = [[IGFixerViewController alloc] init];
	                self.fixerVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.fixerVC;
	            break;
	        case 2:
	            if (!self.fileFixerVC) {
	                IGFileFixerViewController *vc = [[IGFileFixerViewController alloc] init];
	                self.fileFixerVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.fileFixerVC;
	            break;
	        case 3:
	            if (!self.usbExportVC) {
	                IGUSBExportViewController *vc = [[IGUSBExportViewController alloc] init];
	                self.usbExportVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.usbExportVC;
	            break;
	        case 4:
	            if (!self.coversOptimizerVC) {
	                IGCoversOptimizerViewController *vc = [[IGCoversOptimizerViewController alloc] init];
	                self.coversOptimizerVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.coversOptimizerVC;
	            break;
	        case 5:
	            if (!self.duplicateFinderVC) {
	                IGDuplicateFinderViewController *vc = [[IGDuplicateFinderViewController alloc] init];
	                self.duplicateFinderVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.duplicateFinderVC;
	            break;
	        case 6:
	            if (!self.offlinePlaylistVC) {
	                IGOfflinePlaylistViewController *vc = [[IGOfflinePlaylistViewController alloc] init];
	                self.offlinePlaylistVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.offlinePlaylistVC;
	            break;
	        case 7:
	            if (!self.infoEraserVC) {
	                IGInfoEraserViewController *vc = [[IGInfoEraserViewController alloc] init];
	                self.infoEraserVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.infoEraserVC;
	            break;
	        case 8:
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
