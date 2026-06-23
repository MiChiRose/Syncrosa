#import "IGMainWindowController.h"
#import "IGSettingsViewController.h"
#import "IGFileFixerViewController.h"
#import "IGUSBExportViewController.h"
#import "IGUSBService.h"
#import "IGAIService.h"
#import "IGKeychainHelper.h"
#import "IGLocalizationService.h"

@interface IGMainWindowController () <NSSplitViewDelegate>
@property (nonatomic, strong) NSSplitView *splitView;
@property (nonatomic, strong) NSView *sidebarContainer;
@property (nonatomic, strong) NSView *contentContainer;
@property (nonatomic, strong) NSMutableArray *sidebarButtons;

@property (nonatomic, strong) IGGeniusViewController *geniusVC;
@property (nonatomic, strong) IGFixerViewController *fixerVC;
@property (nonatomic, strong) IGFileFixerViewController *fileFixerVC;
@property (nonatomic, strong) IGUSBExportViewController *usbExportVC;
@property (nonatomic, strong) IGSettingsViewController *settingsVC;
@end

@implementation IGMainWindowController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 500)
                                                   styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window center];
    window.title = @"iGeniusAI";
    
    self = [super initWithWindow:window];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
    
    // Add a classic textured background to the sidebar
    NSBox *sidebarBackground = [[NSBox alloc] initWithFrame:self.sidebarContainer.bounds];
    sidebarBackground.boxType = NSBoxCustom;
    sidebarBackground.borderType = NSNoBorder;
    sidebarBackground.fillColor = [NSColor colorWithCalibratedWhite:0.92 alpha:1.0];
    sidebarBackground.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.sidebarContainer addSubview:sidebarBackground];
    
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
    
    // Initial VC: if API key exists, show Genius Playlist, otherwise Settings
    NSString *provider = [[NSUserDefaults standardUserDefaults] stringForKey:@"provider"] ?: @"gemini";
    NSString *apiKey = [[IGKeychainHelper sharedHelper] readStringForAccount:[provider lowercaseString]];
    if (apiKey && apiKey.length > 0) {
        [self switchViewToIndex:0];
    } else {
        [self switchViewToIndex:4];
    }
}

- (void)updateButtonStates {
    NSString *provider = [[NSUserDefaults standardUserDefaults] stringForKey:@"provider"] ?: @"gemini";
    NSString *apiKey = [[IGKeychainHelper sharedHelper] readStringForAccount:[provider lowercaseString]];
    BOOL hasKey = (apiKey && apiKey.length > 0);
    
    for (NSInteger i = 0; i < self.sidebarButtons.count; i++) {
        NSButton *btn = self.sidebarButtons[i];
        if (i == 0) { // Only Genius Playlist requires an API key
            btn.enabled = hasKey;
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
        [lang t:@"settings"]
    ];
    
    // Clean old buttons
    for (NSButton *btn in self.sidebarButtons) {
        [btn removeFromSuperview];
    }
    [self.sidebarButtons removeAllObjects];
    
    CGFloat y = 450;
    for (NSInteger i = 0; i < titles.count; i++) {
        NSButton *btn = [[NSButton alloc] initWithFrame:NSMakeRect(15, y, 150, 32)];
        btn.title = titles[i];
        btn.bezelStyle = NSTexturedSquareBezelStyle;
        btn.target = self;
        btn.action = @selector(sidebarClicked:);
        btn.tag = i;
        btn.autoresizingMask = NSViewWidthSizable;
        [self.sidebarContainer addSubview:btn];
        [self.sidebarButtons addObject:btn];
        y -= 40;
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
    [self switchViewToIndex:sender.tag];
}

- (void)switchViewToIndex:(NSInteger)index {
    NSString *provider = [[NSUserDefaults standardUserDefaults] stringForKey:@"provider"] ?: @"gemini";
    NSString *apiKey = [[IGKeychainHelper sharedHelper] readStringForAccount:[provider lowercaseString]];
    BOOL hasKey = (apiKey && apiKey.length > 0);
    
    if (index == 0 && !hasKey) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Access Restricted"];
        [alert setInformativeText:@"Please enter and validate your API Key in Settings to unlock AI features."];
        [alert runModal];
        return;
    }

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
    for (NSView *v in self.contentContainer.subviews) {
        [v removeFromSuperview];
    }
    
    NSViewController *targetVC = nil;
    switch (index) {
        case 0:
            if (!self.geniusVC) self.geniusVC = [[IGGeniusViewController alloc] init];
            targetVC = self.geniusVC;
            break;
        case 1:
            if (!self.fixerVC) self.fixerVC = [[IGFixerViewController alloc] init];
            targetVC = self.fixerVC;
            break;
        case 2:
            if (!self.fileFixerVC) self.fileFixerVC = [[IGFileFixerViewController alloc] init];
            targetVC = self.fileFixerVC;
            break;
        case 3:
            if (!self.usbExportVC) self.usbExportVC = [[IGUSBExportViewController alloc] init];
            targetVC = self.usbExportVC;
            break;
        case 4:
            if (!self.settingsVC) self.settingsVC = [[IGSettingsViewController alloc] init];
            targetVC = self.settingsVC;
            break;
    }
    
    if (targetVC) {
        targetVC.view.frame = self.contentContainer.bounds;
        targetVC.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [self.contentContainer addSubview:targetVC.view];
        
        if ([targetVC isKindOfClass:[IGUSBExportViewController class]]) {
            [[IGUSBService sharedService] updateDrives];
            [(IGUSBExportViewController *)targetVC reloadPlaylists];
        }
    }
}

#pragma mark - SplitView Delegate
- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)dividerIndex {
    return 250;
}
- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)dividerIndex {
    return 150;
}

@end
