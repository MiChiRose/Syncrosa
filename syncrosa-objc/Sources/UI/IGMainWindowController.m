#import "IGMainWindowController.h"
#import "IGSettingsViewController.h"
#import "IGFileFixerViewController.h"
#import "IGIPodConverterViewController.h"
#import "IGIPodCompatibilityService.h"
#import "IGInfoEraserViewController.h"
#import "IGUSBExportViewController.h"
#import "IGCoversOptimizerViewController.h"
#import "IGDuplicateFinderViewController.h"
#import "IGOfflinePlaylistViewController.h"
#import "IGRecoveryCenterViewController.h"
#import "IGUSBService.h"
#import "IGiTunesService.h"
#import "IGAIService.h"
#import "IGKeychainHelper.h"
#import "IGLocalizationService.h"
#import "IGLogger.h"
#import "IGTheme.h"
#import "IGIconProvider.h"
#import "IGHelpSheetPresenter.h"
#import "IGVideoMetadataViewController.h"
#import "IGOperationActivity.h"
#import "IGLibraryDoctorSupport.h"
#import <math.h>

static NSString * const IGSidebarCollapsedDefaultsKey = @"syncrosa_sidebar_collapsed";
static NSString * const IGSidebarWidthDefaultsKey = @"syncrosa_sidebar_width";
static NSString * const IGFooterHiddenDefaultsKey = @"syncrosa_footer_hidden";
NSString * const IGFooterVisibilityDidChangeNotification = @"IGFooterVisibilityDidChangeNotification";
static const CGFloat IGSidebarDefaultWidth = 180.0;
static const CGFloat IGSidebarMinimumWidth = 150.0;
static const CGFloat IGSidebarCollapsedWidth = 0.0;
static const CGFloat IGContentMinimumWidth = 580.0;
static const CGFloat IGGlobalFooterHeight = 36.0;

static BOOL IGDeveloperPreviewAllowsNavigationIndex(NSInteger index)
{
#ifdef DEBUG
    NSString *previewIndex = [[[NSProcessInfo processInfo] environment] objectForKey:@"SYNCROSA_DEV_OPEN_TAB_INDEX"];
    return [previewIndex length] > 0 && [previewIndex integerValue] == index;
#else
    (void)index;
    return NO;
#endif
}

BOOL IGNavigationItemRequiresReadableLibrary(IGNavigationItem item)
{
    switch (item) {
        case IGNavigationItemAIPlaylist:
        case IGNavigationItemMediaFixer:
        case IGNavigationItemUSBExport:
        case IGNavigationItemCoversOptimizer:
        case IGNavigationItemDuplicateFinder:
        case IGNavigationItemOfflinePlaylist:
        case IGNavigationItemLibraryDoctor:
            return YES;
        case IGNavigationItemOverview:
        case IGNavigationItemVideoMetadata:
        case IGNavigationItemFolderFixer:
        case IGNavigationItemIPodConverter:
        case IGNavigationItemInfoEraser:
        case IGNavigationItemRecoveryCenter:
        case IGNavigationItemSettings:
        case IGNavigationItemCount:
            return NO;
    }
    return NO;
}

NSRect IGCenteredLegacyPageFrame(NSSize preferredSize, NSRect availableBounds)
{
    CGFloat preferredWidth = preferredSize.width > 0.0 ? preferredSize.width : NSWidth(availableBounds);
    CGFloat preferredHeight = preferredSize.height > 0.0 ? preferredSize.height : NSHeight(availableBounds);
    CGFloat width = MIN(preferredWidth, NSWidth(availableBounds));
    CGFloat height = MIN(preferredHeight, NSHeight(availableBounds));
    CGFloat x = NSMinX(availableBounds) + floor((NSWidth(availableBounds) - width) / 2.0);
    CGFloat y = NSMinY(availableBounds) + MAX(0.0, NSHeight(availableBounds) - height);
    return NSMakeRect(x, y, width, height);
}

BOOL IGTextIsEmbeddedLegacyFooter(NSString *text)
{
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [trimmed hasPrefix:@"©"] && [trimmed rangeOfString:@"Syncrosa"].location != NSNotFound;
}

static void IGSetTextFieldLineBreakMode(NSTextField *textField, NSLineBreakMode mode)
{
    if (!textField) {
        return;
    }

    NSCell *cell = [textField cell];
    if ([cell respondsToSelector:@selector(setLineBreakMode:)]) {
        [cell setLineBreakMode:mode];
    }
}

@interface IGMainWindowController (IGFirstLaunchGuide)
- (void)showFirstLaunchGuideMarkingSeen:(BOOL)markSeen;
@end

static NSTextField *IGCreateGuideTextField(NSString *text, NSRect frame, NSFont *font, NSColor *color, NSTextAlignment alignment)
{
    NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    label.stringValue = text ?: @"";
    label.font = font;
    label.textColor = color ?: [NSColor textColor];
    label.alignment = alignment;
    label.editable = NO;
    label.selectable = NO;
    label.bordered = NO;
    label.drawsBackground = NO;
    IGSetTextFieldLineBreakMode(label, NSLineBreakByWordWrapping);
    return label;
}

@class IGMainWindowController;

@interface IGOverviewViewController : NSViewController
@property (nonatomic, assign) IGMainWindowController *mainController;
@property (nonatomic, strong) NSTextField *libraryValueLabel;
@property (nonatomic, strong) NSTextField *backupValueLabel;
@property (nonatomic, strong) NSTextField *recoveryValueLabel;
@property (nonatomic, strong) NSButton *localModeCheckbox;
@property (nonatomic, strong) NSButton *doctorButton;
@property (nonatomic, strong) NSMutableArray *statusLayouts;
- (void)refreshOverview;
@end

@implementation IGOverviewViewController

- (void)loadView {
    self.view = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 480)] autorelease];
    self.statusLayouts = [NSMutableArray array];
    NSTextField *title = IGCreateGuideTextField(@"Overview", NSMakeRect(20, 438, 540, 28),
                                                [NSFont boldSystemFontOfSize:18], nil, NSCenterTextAlignment);
    [self.view addSubview:title];

    NSTextField *subtitle = IGCreateGuideTextField(@"Library status, safety modes, and quick actions.", NSMakeRect(30, 414, 520, 20),
                                                   [NSFont systemFontOfSize:11], IGThemeMutedTextColor(), NSCenterTextAlignment);
    [self.view addSubview:subtitle];

    self.libraryValueLabel = [self addStatusBoxWithTitle:@"Library" icon:@"document" frame:NSMakeRect(25, 326, 255, 78)];
    self.localModeCheckbox = [[[NSButton alloc] initWithFrame:NSMakeRect(52, 20, 184, 28)] autorelease];
    self.localModeCheckbox.buttonType = NSSwitchButton;
    self.localModeCheckbox.title = @"Only Local Mode";
    self.localModeCheckbox.toolTip = @"Skip online metadata lookups. Useful on slower Macs or without a network connection.";
    self.localModeCheckbox.target = self;
    self.localModeCheckbox.action = @selector(localModeChanged:);
    NSBox *localBox = [[[NSBox alloc] initWithFrame:NSMakeRect(300, 326, 255, 78)] autorelease];
    localBox.title = @"Network Safety";
    localBox.boxType = NSBoxPrimary;
    NSView *localIcon = IGCreateThemedIconView(@"network-off", NSMakeRect(16, 22, 26, 26), IGThemeIconRoleAccent);
    [localBox addSubview:localIcon];
    [localBox addSubview:self.localModeCheckbox];
    [self.view addSubview:localBox];
    [self.statusLayouts addObject:@{ @"box": localBox, @"icon": localIcon, @"control": self.localModeCheckbox }];

    self.backupValueLabel = [self addStatusBoxWithTitle:@"Backups" icon:@"folder" frame:NSMakeRect(25, 238, 255, 78)];
    self.recoveryValueLabel = [self addStatusBoxWithTitle:@"Recovery" icon:@"restore" frame:NSMakeRect(300, 238, 255, 78)];

    NSBox *quickBox = [[[NSBox alloc] initWithFrame:NSMakeRect(25, 153, 530, 74)] autorelease];
    quickBox.title = @"Quick Actions";
    quickBox.boxType = NSBoxPrimary;
    [self.view addSubview:quickBox];

    NSButton *refresh = [self actionButton:@"Check iTunes" frame:NSMakeRect(15, 17, 117, 30) action:@selector(refreshClicked:)];
	    IGConfigureIconButton(refresh, @"refresh", @"Refresh iTunes library status", NO);
    [quickBox addSubview:refresh];
    self.doctorButton = [self actionButton:@"Library Doctor" frame:NSMakeRect(142, 17, 117, 30) action:@selector(openDoctorClicked:)];
    IGConfigureIconButton(self.doctorButton, @"doctor", @"Open Library Doctor", NO);
    [quickBox addSubview:self.doctorButton];
    NSButton *recovery = [self actionButton:@"Recovery Center" frame:NSMakeRect(269, 17, 117, 30) action:@selector(openRecoveryClicked:)];
	    IGConfigureIconButton(recovery, @"restore", @"Open Recovery Center", NO);
    [quickBox addSubview:recovery];
    NSButton *wizard = [self actionButton:@"Setup Guide" frame:NSMakeRect(396, 17, 117, 30) action:@selector(wizardClicked:)];
	    IGConfigureIconButton(wizard, @"info", @"Open the setup guide", NO);
    [quickBox addSubview:wizard];

    NSBox *safetyBox = [[[NSBox alloc] initWithFrame:NSMakeRect(25, 30, 530, 112)] autorelease];
    safetyBox.title = @"Current Safeguards";
    safetyBox.boxType = NSBoxPrimary;
    [self.view addSubview:safetyBox];
    NSArray *safeguards = @[
        @"Music tools stay disabled when the library is empty or unavailable.",
        @"Long jobs run in chunks and report progress on older hard drives.",
        @"Destructive file tools require confirmation and preserve recovery data.",
        @"Interrupted operations leave a marker in Recovery Center."
    ];
    CGFloat safeguardY = 72.0;
    for (NSString *text in safeguards) {
        NSTextField *row = IGCreateGuideTextField([@"- " stringByAppendingString:text], NSMakeRect(16, safeguardY, 498, 17),
                                                  [NSFont systemFontOfSize:10.5], IGThemeMutedTextColor(), NSLeftTextAlignment);
        [safetyBox addSubview:row];
        safeguardY -= 19.0;
    }

    [self refreshOverview];
}

- (NSTextField *)addStatusBoxWithTitle:(NSString *)title icon:(NSString *)iconName frame:(NSRect)frame {
    NSBox *box = [[[NSBox alloc] initWithFrame:frame] autorelease];
    box.title = title;
    box.boxType = NSBoxPrimary;
    NSView *icon = IGCreateThemedIconView(iconName, NSMakeRect(16, 22, 26, 26), IGThemeIconRoleAccent);
    [box addSubview:icon];
    NSTextField *value = IGCreateGuideTextField(@"-", NSMakeRect(52, 17, NSWidth(frame) - 66, 36),
                                                [NSFont boldSystemFontOfSize:12], nil, NSLeftTextAlignment);
    [box addSubview:value];
    [self.view addSubview:box];
    [self.statusLayouts addObject:@{ @"box": box, @"icon": icon, @"control": value }];
    return value;
}

- (void)layoutOverviewStatusContent {
    for (NSDictionary *layout in self.statusLayouts) {
        NSBox *box = [layout objectForKey:@"box"];
        NSView *icon = [layout objectForKey:@"icon"];
        NSControl *control = [layout objectForKey:@"control"];
        CGFloat iconSize = 26.0;
        CGFloat gap = 10.0;
        CGFloat maximumControlWidth = MAX(80.0, NSWidth(box.bounds) - iconSize - gap - 28.0);
        CGFloat controlWidth = 80.0;
        CGFloat controlHeight = 22.0;

        if ([control isKindOfClass:[NSTextField class]]) {
            NSTextField *label = (NSTextField *)control;
            NSDictionary *attributes = @{ NSFontAttributeName: label.font ?: [NSFont systemFontOfSize:12.0] };
            NSSize textSize = [label.stringValue sizeWithAttributes:attributes];
            controlWidth = MIN(maximumControlWidth, MAX(54.0, ceil(textSize.width) + 4.0));
            controlHeight = textSize.width > maximumControlWidth ? 36.0 : 22.0;
            label.alignment = NSLeftTextAlignment;
            IGSetTextFieldLineBreakMode(label, NSLineBreakByWordWrapping);
        } else if ([control isKindOfClass:[NSButton class]]) {
            NSSize cellSize = [[control cell] cellSize];
            controlWidth = MIN(maximumControlWidth, MAX(80.0, ceil(cellSize.width)));
            controlHeight = MAX(22.0, MIN(30.0, ceil(cellSize.height)));
        }

        CGFloat usableHeight = MAX(iconSize, NSHeight(box.bounds) - 18.0);
        CGFloat centerY = floor(usableHeight / 2.0);
        CGFloat groupWidth = iconSize + gap + controlWidth;
        CGFloat startX = floor((NSWidth(box.bounds) - groupWidth) / 2.0);
        icon.frame = NSMakeRect(startX, floor(centerY - iconSize / 2.0), iconSize, iconSize);
        control.frame = NSMakeRect(startX + iconSize + gap,
                                   floor(centerY - controlHeight / 2.0),
                                   controlWidth,
                                   controlHeight);
    }
}

- (NSButton *)actionButton:(NSString *)title frame:(NSRect)frame action:(SEL)action {
    NSButton *button = [[[NSButton alloc] initWithFrame:frame] autorelease];
    button.title = title;
    button.bezelStyle = NSTexturedRoundedBezelStyle;
    button.target = self;
    button.action = action;
    IGApplyThemeToButton(button, IGThemeButtonRoleSecondary);
    return button;
}

- (void)refreshOverview {
    self.libraryValueLabel.stringValue = self.mainController ? [self.mainController overviewLibraryStatusText] : @"Not checked";
    self.doctorButton.enabled = self.mainController ? [self.mainController overviewLibraryToolsAvailable] : NO;
    self.localModeCheckbox.state = [[NSUserDefaults standardUserDefaults] boolForKey:@"only_local_mode"] ? NSOnState : NSOffState;

    NSArray *directories = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *base = [directories count] > 0 ? [directories objectAtIndex:0] : NSHomeDirectory();
    NSString *support = [base stringByAppendingPathComponent:@"Syncrosa"];
    NSString *backups = [support stringByAppendingPathComponent:@"Backups"];
    self.backupValueLabel.stringValue = [[NSFileManager defaultManager] fileExistsAtPath:backups] ? @"Available in Application Support" : @"No shared backups yet";

    NSString *markerPath = [support stringByAppendingPathComponent:@"active-operation.plist"];
    NSDictionary *marker = [NSDictionary dictionaryWithContentsOfFile:markerPath];
    self.recoveryValueLabel.stringValue = [marker count] > 0 ? @"Interrupted operation needs review" : @"Clean - no interrupted operation";
    [self layoutOverviewStatusContent];
}

- (void)refreshClicked:(id)sender {
    BOOL started = [self.mainController refreshLibraryStatusWithCompletion:^{
        [self refreshOverview];
    }];
    if (!started) {
        [self refreshOverview];
    }
}

- (void)openDoctorClicked:(id)sender {
    [self.mainController switchViewToIndex:IGNavigationItemLibraryDoctor];
}

- (void)wizardClicked:(id)sender {
    [self.mainController showFirstLaunchGuideMarkingSeen:NO];
}

- (void)openRecoveryClicked:(id)sender {
    [self.mainController switchViewToIndex:IGNavigationItemRecoveryCenter];
}

- (void)localModeChanged:(NSButton *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:(sender.state == NSOnState) forKey:@"only_local_mode"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)dealloc {
#if !__has_feature(objc_arc)
    [_libraryValueLabel release];
    [_backupValueLabel release];
    [_recoveryValueLabel release];
	    [_localModeCheckbox release];
	    [_doctorButton release];
	    [_statusLayouts release];
	    [super dealloc];
#endif
}

@end

@interface IGLibraryDoctorViewController : NSViewController
@property (nonatomic, strong) NSPopUpButton *toolPopup;
@property (nonatomic, strong) NSButton *runButton;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextView *logView;
@property (nonatomic, strong) NSWindow *helpSheetWindow;
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, assign) NSInteger selectedToolIndex;
@property (nonatomic, strong) NSURL *compareFolderURL;
@property (nonatomic, strong) NSURL *reportDestinationURL;
@property (nonatomic, copy) NSString *reportFormat;
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

    NSTextField *title = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, 426, 540, 30)] autorelease];
    title.stringValue = @"Library Doctor";
    title.font = [NSFont boldSystemFontOfSize:18];
    title.editable = NO;
    title.bordered = NO;
    title.drawsBackground = NO;
    title.alignment = NSCenterTextAlignment;
    [self.view addSubview:title];

    NSButton *helpButton = [[[NSButton alloc] initWithFrame:NSMakeRect(520, 428, 25, 25)] autorelease];
    helpButton.bezelStyle = NSHelpButtonBezelStyle;
    helpButton.title = @"";
    helpButton.target = self;
    helpButton.action = @selector(helpClicked:);
    [self.view addSubview:helpButton];

    NSArray *toolTitles = @[@"Cover Restore", @"Cover Audit", @"Library Audit", @"iPod Report",
                            @"Broken Tracks", @"Tag Score", @"Link Audit", @"Export Report"];
    self.selectedToolIndex = 1;
    self.toolPopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(140, 382, 300, 28) pullsDown:NO] autorelease];
    [self.toolPopup addItemsWithTitles:toolTitles];
    [self.toolPopup selectItemAtIndex:self.selectedToolIndex];
    self.toolPopup.target = self;
    self.toolPopup.action = @selector(doctorToolChanged:);
    [self.view addSubview:self.toolPopup];

    self.runButton = [[[NSButton alloc] initWithFrame:NSMakeRect(190, 335, 200, 34)] autorelease];
    self.runButton.title = @"Run Doctor";
    self.runButton.bezelStyle = NSTexturedRoundedBezelStyle;
    self.runButton.target = self;
    self.runButton.action = @selector(runClicked:);
    [self.view addSubview:self.runButton];

    self.progressIndicator = [[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(40, 296, 500, 20)] autorelease];
    self.progressIndicator.style = NSProgressIndicatorBarStyle;
    self.progressIndicator.indeterminate = NO;
    self.progressIndicator.minValue = 0;
    self.progressIndicator.maxValue = 1;
    self.progressIndicator.doubleValue = 0;
    [self.view addSubview:self.progressIndicator];

    self.statusLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(40, 268, 500, 20)] autorelease];
    self.statusLabel.stringValue = @"Ready. Choose a doctor check and run it.";
    self.statusLabel.font = [NSFont systemFontOfSize:11];
    self.statusLabel.textColor = IGThemeMutedTextColor();
    self.statusLabel.editable = NO;
    self.statusLabel.bordered = NO;
    self.statusLabel.drawsBackground = NO;
    self.statusLabel.alignment = NSCenterTextAlignment;
    [self.view addSubview:self.statusLabel];

    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(40, 70, 500, 185)] autorelease];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    self.logView = [[[NSTextView alloc] initWithFrame:scroll.bounds] autorelease];
    self.logView.editable = NO;
    self.logView.backgroundColor = IGThemePanelInsetColor();
    self.logView.textColor = IGThemeAccentColor();
    self.logView.font = [NSFont fontWithName:@"Monaco" size:10];
    scroll.documentView = self.logView;
    [self.view addSubview:scroll];
}

- (NSArray *)toolDescriptions {
    return @[
        @"Restore cover backups from Covers Optimizer.",
        @"Count tracks with embedded artwork.",
        @"Check whether the iTunes library is readable.",
        @"Deep-check iPod 5G codec limits and decode every readable audio file through the end.",
        @"Find missing or unreadable local files.",
        @"Score title, artist, album, genre, and year completeness.",
        @"Compare iTunes file links with a folder without changing either source.",
        @"Save a read-only JSON or CSV library report."
    ];
}

- (NSArray *)toolTitles {
    return @[@"Cover Restore", @"Cover Audit", @"Library Audit", @"iPod Report",
             @"Broken Tracks", @"Tag Score", @"Link Audit", @"Export Report"];
}

- (void)doctorToolChanged:(id)sender {
    if ([sender isKindOfClass:[NSPopUpButton class]]) {
        self.selectedToolIndex = [(NSPopUpButton *)sender indexOfSelectedItem];
    }
    NSInteger selected = self.selectedToolIndex;
    NSArray *descriptions = [self toolDescriptions];
    if (selected >= 0 && selected < (NSInteger)descriptions.count) {
        self.statusLabel.stringValue = [descriptions objectAtIndex:selected];
    }
}

- (void)helpClicked:(id)sender {
    (void)sender;
    if (self.helpSheetWindow) return;
    NSArray *sections = @[
        IGHelpSectionMake(@"Choose a check", @"Cover Restore opens the artwork recovery flow. Cover Audit counts embedded artwork. Library Audit verifies that iTunes can be read."),
        IGHelpSectionMake(@"Inspect compatibility", @"iPod Report checks iPod 5G codec limits and decodes every readable audio file through the end. Large libraries can take time. Broken Tracks lists missing or unreadable references."),
        IGHelpSectionMake(@"Measure and export", @"Tag Score measures metadata completeness. Link Audit compares iTunes links with a folder without changing files. Export Report saves basic metadata as JSON or CSV.")
    ];
    self.helpSheetWindow = [IGHelpSheetPresenter sheetWithTitle:@"Library Doctor"
                                                        summary:@"Run read-only health checks before changing a large library."
                                                       sections:sections
                                                     closeTitle:@"Close"
                                                         target:self
                                                         action:@selector(closeHelpSheet:)];
    [IGHelpSheetPresenter presentSheet:self.helpSheetWindow forWindow:self.view.window];
}

- (void)closeHelpSheet:(id)sender {
    if (!self.helpSheetWindow) return;
    if ([self.view.window respondsToSelector:@selector(endSheet:)]) {
        [self.view.window endSheet:self.helpSheetWindow];
    } else {
        [NSApp endSheet:self.helpSheetWindow];
    }
    [self.helpSheetWindow orderOut:nil];
    self.helpSheetWindow = nil;
}

- (void)clearLog {
    [self.logView setString:@""];
}

- (void)log:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *line = [NSString stringWithFormat:@"> %@\n", text ?: @""];
        NSAttributedString *attr = [[[NSAttributedString alloc] initWithString:line attributes:@{NSForegroundColorAttributeName: IGThemeAccentColor()}] autorelease];
        [self.logView.textStorage appendAttributedString:attr];
        [self.logView scrollRangeToVisible:NSMakeRange(self.logView.textStorage.length, 0)];
    });
}

- (void)finishDoctorOperationTitle:(NSString *)title status:(NSString *)status message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.progressIndicator.indeterminate = NO;
        self.progressIndicator.maxValue = 1;
        self.progressIndicator.doubleValue = 1;
        self.isRunning = NO;
        self.runButton.enabled = YES;
        self.toolPopup.enabled = YES;
        self.statusLabel.stringValue = message ?: @"Library Doctor finished.";
        [self log:@"Library Doctor finished."];
        IGLibraryDoctorRecordHistory(title, status, message);
    });
}

- (BOOL)prepareLinkAudit {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"Choose Folder to Compare";
    panel.prompt = @"Choose";
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    if ([panel runModal] != NSFileHandlingPanelOKButton) {
        return NO;
    }
    self.compareFolderURL = [[panel URLs] count] > 0 ? [[panel URLs] objectAtIndex:0] : nil;
    return self.compareFolderURL != nil;
}

- (BOOL)prepareReportExport {
    NSAlert *formatAlert = [[[NSAlert alloc] init] autorelease];
    formatAlert.messageText = @"Choose Report Format";
    formatAlert.informativeText = @"JSON preserves structure. CSV opens easily in spreadsheet applications.";
    [formatAlert addButtonWithTitle:@"JSON"];
    [formatAlert addButtonWithTitle:@"CSV"];
    [formatAlert addButtonWithTitle:@"Cancel"];
    NSInteger response = [formatAlert runModal];
    if (response == NSAlertThirdButtonReturn) {
        return NO;
    }
    self.reportFormat = response == NSAlertSecondButtonReturn ? @"csv" : @"json";

    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.title = @"Save Library Doctor Report";
    panel.nameFieldStringValue = [NSString stringWithFormat:@"Syncrosa-Library-Report.%@", self.reportFormat];
    panel.allowedFileTypes = @[self.reportFormat];
    if ([panel runModal] != NSFileHandlingPanelOKButton) {
        return NO;
    }
    self.reportDestinationURL = [panel URL];
    return self.reportDestinationURL != nil;
}

- (void)runClicked:(id)sender {
    if (self.isRunning) return;

    NSInteger selected = self.selectedToolIndex;
    NSArray *titles = [self toolTitles];
    NSString *selectedTitle = (selected >= 0 && selected < (NSInteger)[titles count]) ? [titles objectAtIndex:selected] : @"Library Audit";
    if (selected != 0 && ![[IGiTunesService sharedService] iTunesIsRunning]) {
        self.statusLabel.stringValue = @"iTunes is not running. Syncrosa will not open it automatically.";
        [self clearLog];
        [self log:@"Start iTunes yourself, then run this check again."];
        return;
    }
    if (selected == 6 && ![self prepareLinkAudit]) {
        self.statusLabel.stringValue = @"Link Audit cancelled.";
        return;
    }
    if (selected == 7 && ![self prepareReportExport]) {
        self.statusLabel.stringValue = @"Report export cancelled.";
        return;
    }

    self.isRunning = YES;
    self.runButton.enabled = NO;
    self.toolPopup.enabled = NO;
    self.progressIndicator.indeterminate = NO;
    self.progressIndicator.maxValue = 1;
    self.progressIndicator.doubleValue = 0;
    [self clearLog];

    __block NSString *historyMessage = @"Library Doctor finished.";
    __block NSString *historyStatus = @"OK";
    self.statusLabel.stringValue = [NSString stringWithFormat:@"Running %@...", selectedTitle];
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
                BOOL stoppedBecauseITunesClosed = NO;
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.progressIndicator.maxValue = MAX(total, 1);
                    self.progressIndicator.doubleValue = 0;
                });
                for (NSInteger start = 1; start <= total; start += chunkSize) {
                    if (![[IGiTunesService sharedService] iTunesIsRunning]) {
                        historyStatus = @"WARN";
                        historyMessage = @"Cover audit stopped because iTunes was closed. Syncrosa did not reopen it.";
                        [self log:historyMessage];
                        stoppedBecauseITunesClosed = YES;
                        break;
                    }
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
                if (!stoppedBecauseITunesClosed) {
                    historyMessage = [NSString stringWithFormat:@"Cover audit complete. Tracks: %ld. Tracks with covers: %ld.", (long)total, (long)coverCount];
                    [self log:historyMessage];
                }
            }
        } else if (selected == 3 || selected == 4 || selected == 6) {
            dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
            __block NSArray *refs = nil;
            [[IGiTunesService sharedService] fetchLibraryFileTrackReferencesWithCompletion:^(NSArray *tracks) {
                refs = [tracks copy];
                dispatch_semaphore_signal(semaphore);
            }];
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
#if !__has_feature(objc_arc)
            dispatch_release(semaphore);
#endif
            if (selected == 6) {
                [self log:[NSString stringWithFormat:@"Scanning folder: %@", [self.compareFolderURL path] ?: @""]];
                NSArray *folderFiles = IGLibraryDoctorAudioFilePathsAtURL(self.compareFolderURL);
                NSDictionary *audit = IGLibraryDoctorLinkAudit(refs ?: @[], folderFiles);
                NSInteger missing = [[audit objectForKey:@"missingReferenceCount"] integerValue];
                NSInteger unlinked = [[audit objectForKey:@"unlinkedFileCount"] integerValue];
                [self log:[NSString stringWithFormat:@"iTunes file references: %@", [audit objectForKey:@"libraryReferenceCount"]]];
                [self log:[NSString stringWithFormat:@"audio files in folder: %@", [audit objectForKey:@"folderFileCount"]]];
                [self log:[NSString stringWithFormat:@"missing iTunes links: %ld", (long)missing]];
                [self log:[NSString stringWithFormat:@"folder files not linked in iTunes: %ld", (long)unlinked]];
                NSInteger shown = 0;
                for (NSString *path in [audit objectForKey:@"unlinkedFiles"]) {
                    if (shown >= 50) break;
                    [self log:[NSString stringWithFormat:@"unlinked: %@", path]];
                    shown++;
                }
                NSInteger warnings = missing + unlinked;
                historyStatus = warnings > 0 ? @"WARN" : @"OK";
                historyMessage = [NSString stringWithFormat:@"Link audit complete. Missing links: %ld. Unlinked folder files: %ld.", (long)missing, (long)unlinked];
            } else if (selected == 3) {
                NSArray *supported = @[@"mp3", @"m4a", @"mp4", @"aac", @"wav", @"aiff", @"aif"];
                NSInteger unsupported = 0;
                NSInteger missing = 0;
                NSInteger longNames = 0;
                NSInteger hugeFiles = 0;
                NSInteger deepCompatibilityWarnings = 0;
                unsigned long long totalBytes = 0;
                NSFileManager *fm = [NSFileManager defaultManager];
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.progressIndicator.minValue = 0.0;
                    self.progressIndicator.maxValue = MAX((double)[refs count], 1.0);
                    self.progressIndicator.doubleValue = 0.0;
                });
                [self log:@"deep audio compatibility scan started"];
                NSInteger trackIndex = 0;
                for (NSDictionary *track in refs) {
                    NSString *path = [track objectForKey:@"path"] ?: @"";
                    NSString *ext = [[path pathExtension] lowercaseString];
                    unsigned long long size = [[track objectForKey:@"size"] unsignedLongLongValue];
                    totalBytes += size;
                    BOOL readable = path.length > 0 && [fm fileExistsAtPath:path] && [fm isReadableFileAtPath:path];
                    if (!readable) {
                        missing++;
                    }
                    if (ext.length > 0 && ![supported containsObject:ext]) {
                        unsupported++;
                        [self log:[NSString stringWithFormat:@"format warning: %@ - %@ [%@]",
                                   [track objectForKey:@"artist"] ?: @"",
                                   [track objectForKey:@"name"] ?: @"",
                                   [ext uppercaseString]]];
                    }
                    if ([[path lastPathComponent] length] > 80) {
                        longNames++;
                    }
                    if (size > 100ULL * 1024ULL * 1024ULL) {
                        hugeFiles++;
                    }
                    if (readable && [supported containsObject:ext]) {
                        NSArray *issues = [IGIPodCompatibilityService compatibilityIssuesForFileURL:[NSURL fileURLWithPath:path]
                                                                                           deepScan:YES];
                        if ([issues count] > 0) {
                            deepCompatibilityWarnings++;
                            [self log:[NSString stringWithFormat:@"audio warning: %@ - %@ — %@",
                                       [track objectForKey:@"artist"] ?: @"",
                                       [track objectForKey:@"name"] ?: @"",
                                       [issues componentsJoinedByString:@"; "]]];
                        }
                    }
                    trackIndex++;
                    NSInteger completed = trackIndex;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.progressIndicator.doubleValue = completed;
                    });
                }
                NSString *sizeStr = [NSByteCountFormatter stringFromByteCount:(long long)totalBytes countStyle:NSByteCountFormatterCountStyleFile];
                [self log:[NSString stringWithFormat:@"file tracks scanned: %ld", (long)refs.count]];
                [self log:[NSString stringWithFormat:@"total local size: %@", sizeStr]];
                [self log:[NSString stringWithFormat:@"unsupported format warnings: %ld", (long)unsupported]];
                [self log:[NSString stringWithFormat:@"missing/unreadable files: %ld", (long)missing]];
                [self log:[NSString stringWithFormat:@"long filenames (>80 chars): %ld", (long)longNames]];
                [self log:[NSString stringWithFormat:@"large files (>100 MB): %ld", (long)hugeFiles]];
                [self log:[NSString stringWithFormat:@"deep codec/decoder warnings: %ld", (long)deepCompatibilityWarnings]];
                NSInteger warnings = unsupported + missing + longNames + hugeFiles + deepCompatibilityWarnings;
                historyStatus = warnings > 0 ? @"WARN" : @"OK";
                historyMessage = [NSString stringWithFormat:@"iPod report complete. Scanned: %ld. Warnings: %ld.", (long)refs.count, (long)warnings];
            } else {
                NSMutableArray *broken = [NSMutableArray array];
                NSFileManager *fm = [NSFileManager defaultManager];
                for (NSDictionary *track in refs) {
                    NSString *path = [track objectForKey:@"path"] ?: @"";
                    if (path.length == 0 || ![fm fileExistsAtPath:path] || ![fm isReadableFileAtPath:path]) {
                        [broken addObject:track];
                    }
                }
                [self log:[NSString stringWithFormat:@"file tracks scanned: %ld", (long)refs.count]];
                if (broken.count == 0) {
                    [self log:@"no missing file references found"];
                    historyStatus = @"OK";
                    historyMessage = @"Broken tracks scan complete. No missing files found.";
                } else {
                    [self log:[NSString stringWithFormat:@"missing/unreadable file references: %ld", (long)broken.count]];
                    NSInteger shown = 0;
                    for (NSDictionary *track in broken) {
                        if (shown >= 80) break;
                        [self log:[NSString stringWithFormat:@"missing: %@ - %@",
                                   [track objectForKey:@"artist"] ?: @"",
                                   [track objectForKey:@"name"] ?: @""]];
                        shown++;
                    }
                    if (broken.count > 80) {
                        [self log:[NSString stringWithFormat:@"...and %ld more", (long)(broken.count - 80)]];
                    }
                    historyStatus = @"WARN";
                    historyMessage = [NSString stringWithFormat:@"Broken tracks scan complete. Missing files: %ld.", (long)broken.count];
                }
            }
#if !__has_feature(objc_arc)
            [refs release];
#endif
        } else if (selected == 5 || selected == 7) {
            dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
            __block NSArray *tracks = nil;
            [[IGiTunesService sharedService] fetchAllTracksWithProgress:^(NSInteger current, NSInteger total) {
                self.progressIndicator.maxValue = MAX(total, 1);
                self.progressIndicator.doubleValue = current;
                self.statusLabel.stringValue = [NSString stringWithFormat:@"Reading tracks: %ld / %ld", (long)current, (long)total];
            } completion:^(NSArray *fetchedTracks) {
                tracks = [fetchedTracks copy];
                dispatch_semaphore_signal(semaphore);
            }];
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
#if !__has_feature(objc_arc)
            dispatch_release(semaphore);
#endif
            if ([tracks count] == 0) {
                historyStatus = @"WARN";
                historyMessage = @"iTunes returned no tracks for this check.";
                [self log:historyMessage];
            } else if (selected == 5) {
                NSDictionary *score = IGLibraryDoctorTagScore(tracks);
                NSInteger percent = [[score objectForKey:@"completenessPercent"] integerValue];
                [self log:[NSString stringWithFormat:@"tracks scored: %@", [score objectForKey:@"trackCount"]]];
                [self log:[NSString stringWithFormat:@"metadata completeness: %ld%%", (long)percent]];
                [self log:[NSString stringWithFormat:@"missing titles: %@", [score objectForKey:@"missingTitle"]]];
                [self log:[NSString stringWithFormat:@"missing artists: %@", [score objectForKey:@"missingArtist"]]];
                [self log:[NSString stringWithFormat:@"missing albums: %@", [score objectForKey:@"missingAlbum"]]];
                [self log:[NSString stringWithFormat:@"missing genres: %@", [score objectForKey:@"missingGenre"]]];
                [self log:[NSString stringWithFormat:@"missing years: %@", [score objectForKey:@"missingYear"]]];
                historyStatus = percent >= 80 ? @"OK" : @"WARN";
                historyMessage = [NSString stringWithFormat:@"Tag score complete. Metadata completeness: %ld%%.", (long)percent];
            } else {
                NSError *writeError = nil;
                BOOL wrote = NO;
                if ([self.reportFormat isEqualToString:@"csv"]) {
                    wrote = [IGLibraryDoctorCSVString(tracks) writeToURL:self.reportDestinationURL atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
                } else {
                    NSData *data = [NSJSONSerialization dataWithJSONObject:IGLibraryDoctorJSONObject(tracks) options:NSJSONWritingPrettyPrinted error:&writeError];
                    wrote = data != nil && [data writeToURL:self.reportDestinationURL options:NSDataWritingAtomic error:&writeError];
                }
                if (wrote) {
                    historyMessage = [NSString stringWithFormat:@"Report exported. Tracks: %lu. File: %@", (unsigned long)[tracks count], [self.reportDestinationURL path] ?: @""];
                    [self log:historyMessage];
                } else {
                    historyStatus = @"WARN";
                    historyMessage = [NSString stringWithFormat:@"Could not save report: %@", [writeError localizedDescription] ?: @"Unknown write error"];
                    [self log:historyMessage];
                }
            }
#if !__has_feature(objc_arc)
            [tracks release];
#endif
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

        [self finishDoctorOperationTitle:selectedTitle status:historyStatus message:historyMessage];
    });
}

- (void)dealloc {
#if !__has_feature(objc_arc)
    [_toolPopup release];
    [_runButton release];
    [_progressIndicator release];
    [_statusLabel release];
    [_logView release];
    [_helpSheetWindow release];
    [_compareFolderURL release];
    [_reportDestinationURL release];
    [_reportFormat release];
    [super dealloc];
#endif
}

@end

@interface IGMainWindowController () <NSSplitViewDelegate>
@property (nonatomic, strong) NSSplitView *splitView;
@property (nonatomic, strong) NSView *sidebarContainer;
@property (nonatomic, strong) NSView *contentContainer;
@property (nonatomic, strong) NSView *pageContainer;
@property (nonatomic, strong) NSView *footerContainer;
@property (nonatomic, strong) NSTextField *footerLabel;
@property (nonatomic, strong) NSView *sidebarBackgroundView;
@property (nonatomic, strong) NSMutableArray *sidebarButtons;
@property (nonatomic, strong) NSMutableDictionary *sidebarActivityIndicators;
@property (nonatomic, strong) NSButton *sidebarToggleButton;
@property (nonatomic, strong) NSTextField *libraryStatusLabel;
@property (nonatomic, strong) NSButton *libraryRefreshButton;
@property (nonatomic, strong) NSWindow *firstLaunchSheetWindow;
@property (nonatomic, assign) NSInteger firstLaunchGuideStep;
@property (nonatomic, assign) BOOL firstLaunchGuideMarksSeen;
@property (nonatomic, strong) NSTextField *firstLaunchCategoryLabel;
@property (nonatomic, strong) NSTextField *firstLaunchStepLabel;
@property (nonatomic, strong) NSTextField *firstLaunchTitleLabel;
@property (nonatomic, strong) NSTextField *firstLaunchMessageLabel;
@property (nonatomic, strong) NSTextField *firstLaunchDetailLabel;
@property (nonatomic, strong) NSTextField *firstLaunchHighlightOneLabel;
@property (nonatomic, strong) NSTextField *firstLaunchHighlightTwoLabel;
@property (nonatomic, strong) NSTextField *firstLaunchProgressLabel;
@property (nonatomic, strong) NSButton *firstLaunchBackButton;
@property (nonatomic, strong) NSButton *firstLaunchNextButton;
@property (nonatomic, strong) NSButton *firstLaunchLocalModeCheckbox;
@property (nonatomic, strong) NSWindow *libraryBusySheetWindow;
@property (nonatomic, assign) NSInteger libraryTrackCount;
@property (nonatomic, assign) BOOL libraryStatusKnown;
@property (nonatomic, assign) BOOL libraryStatusReadable;
@property (nonatomic, assign) BOOL refreshingLibraryStatus;
@property (nonatomic, assign) BOOL sidebarCollapsed;
@property (nonatomic, assign) CGFloat expandedSidebarWidth;
@property (nonatomic, assign) NSInteger activeIndex;
@property (nonatomic, strong) NSViewController *activeViewController;
@property (nonatomic, strong) NSMutableDictionary *pagePreferredHeights;
@property (nonatomic, strong) NSMutableDictionary *pagePreferredWidths;
@property (nonatomic, strong) NSMutableSet *preparedPageViews;

@property (nonatomic, strong) IGGeniusViewController *geniusVC;
@property (nonatomic, strong) IGFixerViewController *fixerVC;
@property (nonatomic, strong) IGVideoMetadataViewController *videoMetadataVC;
@property (nonatomic, strong) IGFileFixerViewController *fileFixerVC;
@property (nonatomic, strong) IGIPodConverterViewController *ipodConverterVC;
@property (nonatomic, strong) IGInfoEraserViewController *infoEraserVC;
@property (nonatomic, strong) IGUSBExportViewController *usbExportVC;
@property (nonatomic, strong) IGCoversOptimizerViewController *coversOptimizerVC;
@property (nonatomic, strong) IGDuplicateFinderViewController *duplicateFinderVC;
@property (nonatomic, strong) IGOfflinePlaylistViewController *offlinePlaylistVC;
@property (nonatomic, strong) IGSettingsViewController *settingsVC;
@property (nonatomic, strong) IGOverviewViewController *overviewVC;
@property (nonatomic, strong) IGLibraryDoctorViewController *libraryDoctorVC;
@property (nonatomic, strong) IGRecoveryCenterViewController *recoveryCenterVC;

- (void)layoutApplicationChrome;
- (void)layoutActivePage;
- (void)preparePageViewForEmbedding:(NSView *)view;
- (void)hideEmbeddedFooterLabelsInView:(NSView *)view;
- (void)updateGlobalFooterText;
- (void)updateSidebarActivityIndicators;
@end

@implementation IGMainWindowController

+ (BOOL)globalFooterVisible {
    return ![[NSUserDefaults standardUserDefaults] boolForKey:IGFooterHiddenDefaultsKey];
}

+ (void)setGlobalFooterVisible:(BOOL)visible {
    [[NSUserDefaults standardUserDefaults] setBool:!visible forKey:IGFooterHiddenDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:IGFooterVisibilityDidChangeNotification object:nil];
}

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 540)
                                                   styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setContentView:IGCreateThemedBackgroundView(NSMakeRect(0, 0, 800, 540), IGThemeBackgroundRoleWindow)];
    [window setContentMinSize:NSMakeSize(800, 540)];
    [window center];
    window.title = @"Syncrosa";
    
	    self = [super initWithWindow:window];
#if !__has_feature(objc_arc)
	    [window release];
#endif
	    if (self) {
	        _libraryTrackCount = -1;
	        _libraryStatusKnown = NO;
	        _libraryStatusReadable = NO;
	        _refreshingLibraryStatus = NO;
	        _sidebarCollapsed = NO;
	        _expandedSidebarWidth = IGSidebarDefaultWidth;
		        _activeIndex = -1;
		        _pagePreferredHeights = [[NSMutableDictionary alloc] init];
		        _pagePreferredWidths = [[NSMutableDictionary alloc] init];
		        _preparedPageViews = [[NSMutableSet alloc] init];
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
	    [_pageContainer release];
	    [_footerContainer release];
	    [_footerLabel release];
	    [_sidebarBackgroundView release];
	    [_sidebarButtons release];
	    [_sidebarActivityIndicators release];
	    [_sidebarToggleButton release];
	    [_libraryStatusLabel release];
	    [_libraryRefreshButton release];
	    [_firstLaunchSheetWindow release];
	    [_firstLaunchCategoryLabel release];
	    [_firstLaunchStepLabel release];
	    [_firstLaunchTitleLabel release];
	    [_firstLaunchMessageLabel release];
	    [_firstLaunchDetailLabel release];
	    [_firstLaunchHighlightOneLabel release];
	    [_firstLaunchHighlightTwoLabel release];
	    [_firstLaunchProgressLabel release];
	    [_firstLaunchBackButton release];
	    [_firstLaunchNextButton release];
	    [_firstLaunchLocalModeCheckbox release];
	    [_libraryBusySheetWindow release];
	    [_ipodConverterVC release];
		    [_activeViewController release];
		    [_pagePreferredHeights release];
		    [_pagePreferredWidths release];
		    [_preparedPageViews release];
	    [_geniusVC release];
	    [_fixerVC release];
	    [_videoMetadataVC release];
	    [_fileFixerVC release];
	    [_infoEraserVC release];
	    [_usbExportVC release];
	    [_coversOptimizerVC release];
	    [_duplicateFinderVC release];
	    [_offlinePlaylistVC release];
	    [_settingsVC release];
	    [_overviewVC release];
	    [_libraryDoctorVC release];
	    [_recoveryCenterVC release];
	    [super dealloc];
	#endif
	}

- (void)setupUI {
    NSView *rootView = self.window.contentView;

	    self.splitView = [[[NSSplitView alloc] initWithFrame:NSMakeRect(0.0,
	                                                                   IGGlobalFooterHeight,
	                                                                   NSWidth(rootView.bounds),
	                                                                   NSHeight(rootView.bounds) - IGGlobalFooterHeight)] autorelease];
    self.splitView.vertical = YES;
    self.splitView.dividerStyle = NSSplitViewDividerStyleThin;
    self.splitView.delegate = self;
    
	    self.sidebarContainer = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 180, NSHeight(self.splitView.bounds))] autorelease];
	    self.contentContainer = [[[NSView alloc] initWithFrame:NSMakeRect(180, 0, 620, NSHeight(self.splitView.bounds))] autorelease];
    
    self.sidebarBackgroundView = IGCreateThemedBackgroundView(self.sidebarContainer.bounds, IGThemeBackgroundRoleSidebar);
	    self.sidebarBackgroundView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	    [self.sidebarContainer addSubview:self.sidebarBackgroundView];
    
    [self.splitView addSubview:self.sidebarContainer];
    [self.splitView addSubview:self.contentContainer];
    [self.splitView adjustSubviews];
    
    [rootView addSubview:self.splitView];

    IGInstallThemedContentBackground(self.contentContainer);
	    self.pageContainer = [[[NSView alloc] initWithFrame:self.contentContainer.bounds] autorelease];
	    self.pageContainer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	    [self.contentContainer addSubview:self.pageContainer];

	    NSButton *sidebarToggle = [[NSButton alloc] initWithFrame:NSMakeRect(12, NSHeight(self.contentContainer.bounds) - 38, 30, 28)];
	    sidebarToggle.bezelStyle = NSTexturedRoundedBezelStyle;
	    sidebarToggle.target = self;
	    sidebarToggle.action = @selector(toggleSidebar:);
	    sidebarToggle.autoresizingMask = NSViewMinYMargin;
	    sidebarToggle.font = [NSFont boldSystemFontOfSize:14.0];
	    sidebarToggle.title = @"";
	    IGConfigureIconButton(sidebarToggle, @"menu", @"Hide Sidebar", YES);
	    self.sidebarToggleButton = sidebarToggle;
	    [self.contentContainer addSubview:sidebarToggle positioned:NSWindowAbove relativeTo:nil];
#if !__has_feature(objc_arc)
	    [sidebarToggle release];
#endif

	    self.footerContainer = IGCreateThemedBackgroundView(NSMakeRect(0, 0, NSWidth(rootView.bounds), IGGlobalFooterHeight), IGThemeBackgroundRoleContent);
	    NSBox *footerSeparator = [[[NSBox alloc] initWithFrame:NSMakeRect(0, IGGlobalFooterHeight - 1.0, NSWidth(rootView.bounds), 1.0)] autorelease];
	    footerSeparator.boxType = NSBoxSeparator;
	    footerSeparator.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
	    [self.footerContainer addSubview:footerSeparator];
	    self.footerLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(40, 2, NSWidth(rootView.bounds) - 80, 30)] autorelease];
	    self.footerLabel.font = [NSFont systemFontOfSize:10.0];
	    self.footerLabel.textColor = IGThemeMutedTextColor();
	    self.footerLabel.alignment = NSCenterTextAlignment;
	    self.footerLabel.editable = NO;
	    self.footerLabel.selectable = NO;
	    self.footerLabel.bordered = NO;
	    self.footerLabel.drawsBackground = NO;
	    self.footerLabel.autoresizingMask = NSViewWidthSizable;
	    [self.footerContainer addSubview:self.footerLabel];
	    [rootView addSubview:self.footerContainer];
	    [self updateGlobalFooterText];

    self.sidebarButtons = [NSMutableArray array];
    self.sidebarActivityIndicators = [NSMutableDictionary dictionary];
    [self setupSidebar];
    [self updateButtonStates];
	    [self restoreSidebarState];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(localizationChanged:)
                                                 name:@"IGLanguageChangedNotification"
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(drivesUpdatedNotification:)
                                                 name:@"IGUSBDrivesUpdatedNotification"
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeChanged:)
                                                 name:IGThemeDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(operationActivityChanged:)
                                                 name:IGOperationActivityDidChangeNotification
                                               object:nil];
	    [[NSNotificationCenter defaultCenter] addObserver:self
	                                             selector:@selector(footerVisibilityChanged:)
	                                                 name:IGFooterVisibilityDidChangeNotification
	                                               object:nil];
	    [[NSNotificationCenter defaultCenter] addObserver:self
	                                             selector:@selector(windowDidResize:)
	                                                 name:NSWindowDidResizeNotification
	                                               object:self.window];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(systemAppearanceChanged:)
                                                 name:@"NSApplicationDidChangeEffectiveAppearanceNotification"
                                               object:nil];
    [self layoutApplicationChrome];
    [self applyTheme];
    
    // Initial VC: if API key exists, show Genius Playlist, otherwise Settings
	    NSString *provider = [[NSUserDefaults standardUserDefaults] stringForKey:@"provider"] ?: @"Gemini";
    NSString *apiKey = [[IGKeychainHelper sharedHelper] readStringForAccount:[provider lowercaseString]];
    if (apiKey && apiKey.length > 0) {
        [self switchViewToIndex:IGNavigationItemOverview];
    } else {
        [self switchViewToIndex:IGNavigationItemSettings];
    }

    [self performSelector:@selector(showFirstLaunchSetupIfNeeded) withObject:nil afterDelay:0.45];
}

- (void)themeChanged:(NSNotification *)notification {
    (void)notification;
    [self applyTheme];
}

- (void)systemAppearanceChanged:(NSNotification *)notification {
    (void)notification;
    if ([IGActiveAppearanceModeIdentifier() isEqualToString:@"system"]) {
        [self applyTheme];
    }
}

- (void)applyTheme {
    [self.window setBackgroundColor:IGThemeContentColor()];
    [self.window.contentView setNeedsDisplay:YES];
    [self.sidebarBackgroundView setNeedsDisplay:YES];
    [self.footerContainer setNeedsDisplay:YES];
    self.footerLabel.textColor = IGThemeMutedTextColor();
    self.libraryStatusLabel.textColor = IGThemeMutedTextColor();
    IGApplyThemeToButton(self.libraryRefreshButton, IGThemeButtonRoleSecondary);
    IGApplyThemeToButton(self.sidebarToggleButton, IGThemeButtonRoleSecondary);
    for (NSButton *button in self.sidebarButtons) {
        IGApplyThemeToButton(button, IGThemeButtonRoleSidebar);
    }
    IGApplyThemeToViewHierarchy(self.contentContainer);
    IGApplyThemeToWindow(self.firstLaunchSheetWindow);
    IGApplyThemeToWindow(self.libraryBusySheetWindow);
    IGRefreshThemedViews(self.window.contentView);
    [self.contentContainer setNeedsDisplay:YES];
    [self.sidebarContainer setNeedsDisplay:YES];
}

- (void)updateGlobalFooterText {
    self.footerLabel.stringValue = [[IGLocalizationService sharedService] t:@"footer"] ?: @"";
}

- (NSInteger)navigationIndexForOperationIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:IGOperationActivityUSBExportIdentifier]) return IGNavigationItemUSBExport;
    if ([identifier isEqualToString:IGOperationActivityAIPlaylistIdentifier]) return IGNavigationItemAIPlaylist;
    if ([identifier isEqualToString:IGOperationActivityVideoMetadataIdentifier]) return IGNavigationItemVideoMetadata;
    return -1;
}

- (void)operationActivityChanged:(NSNotification *)notification {
    (void)notification;
    [self updateSidebarActivityIndicators];
}

- (void)updateSidebarActivityIndicators {
    NSString *identifier = [IGOperationActivity sharedActivity].activeIdentifier;
    if ([identifier length] > 0 && [self.sidebarActivityIndicators objectForKey:identifier]) {
        return;
    }

    for (NSProgressIndicator *indicator in [self.sidebarActivityIndicators allValues]) {
        [indicator stopAnimation:nil];
        [indicator removeFromSuperview];
    }
    [self.sidebarActivityIndicators removeAllObjects];
    for (NSButton *button in self.sidebarButtons) {
        button.toolTip = [NSString stringWithFormat:@"Open %@", button.title ?: @"Syncrosa"];
    }

    NSInteger index = [self navigationIndexForOperationIdentifier:identifier];
    if (index < 0 || index >= (NSInteger)[self.sidebarButtons count]) return;

    NSButton *button = [self.sidebarButtons objectAtIndex:index];
    NSProgressIndicator *spinner = [[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(NSWidth(button.bounds) - 18.0,
                                                                                           floor((NSHeight(button.bounds) - 14.0) / 2.0),
                                                                                           14.0,
                                                                                           14.0)] autorelease];
    spinner.style = NSProgressIndicatorSpinningStyle;
    spinner.indeterminate = YES;
    spinner.controlSize = NSSmallControlSize;
    spinner.autoresizingMask = NSViewMinXMargin;
    [button addSubview:spinner];
    [spinner startAnimation:nil];
    [self.sidebarActivityIndicators setObject:spinner forKey:identifier];
    button.toolTip = [NSString stringWithFormat:@"%@ — operation in progress", button.title ?: @"Syncrosa"];
}

- (void)footerVisibilityChanged:(NSNotification *)notification {
    (void)notification;
    [self layoutApplicationChrome];
}

- (void)windowDidResize:(NSNotification *)notification {
    (void)notification;
    [self layoutApplicationChrome];
}

- (void)layoutApplicationChrome {
    NSView *windowContentView = [self.window contentView];
    NSRect bounds = [windowContentView bounds];
    BOOL footerVisible = [[self class] globalFooterVisible];
    CGFloat footerHeight = footerVisible ? IGGlobalFooterHeight : 0.0;

    self.footerContainer.hidden = !footerVisible;
    self.footerContainer.frame = NSMakeRect(0.0, 0.0, NSWidth(bounds), IGGlobalFooterHeight);
    self.splitView.frame = NSMakeRect(0.0,
                                      footerHeight,
                                      NSWidth(bounds),
                                      MAX(0.0, NSHeight(bounds) - footerHeight));
    self.pageContainer.frame = self.contentContainer.bounds;
    [self layoutSidebarControls];
    [self layoutActivePage];
}

- (void)hideEmbeddedFooterLabelsInView:(NSView *)view {
    if (!view) {
        return;
    }
    if ([view isKindOfClass:[NSTextField class]]) {
        NSString *text = [(NSTextField *)view stringValue];
        NSString *globalFooterText = [[IGLocalizationService sharedService] t:@"footer"] ?: @"";
        if (([globalFooterText length] > 0 && [text isEqualToString:globalFooterText]) || IGTextIsEmbeddedLegacyFooter(text)) {
            [view removeFromSuperview];
            return;
        }
    }
    NSArray *children = [[view subviews] copy];
    for (NSView *child in children) {
        [self hideEmbeddedFooterLabelsInView:child];
    }
#if !__has_feature(objc_arc)
    [children release];
#endif
}

- (void)preparePageViewForEmbedding:(NSView *)view {
    if (!view) {
        return;
    }
    NSValue *key = [NSValue valueWithNonretainedObject:view];
    if (![self.preparedPageViews containsObject:key]) {
        CGFloat preferredHeight = MAX(480.0, NSHeight(view.frame));
        CGFloat preferredWidth = MAX(580.0, NSWidth(view.frame));
        [self.pagePreferredHeights setObject:[NSNumber numberWithDouble:preferredHeight] forKey:key];
        [self.pagePreferredWidths setObject:[NSNumber numberWithDouble:preferredWidth] forKey:key];
        [self.preparedPageViews addObject:key];
    }
    [self hideEmbeddedFooterLabelsInView:view];
}

- (void)layoutActivePage {
    if (!self.activeViewController || !self.pageContainer) {
        return;
    }
    NSView *view = self.activeViewController.view;
    NSValue *key = [NSValue valueWithNonretainedObject:view];
    NSNumber *storedHeight = [self.pagePreferredHeights objectForKey:key];
    NSNumber *storedWidth = [self.pagePreferredWidths objectForKey:key];
    CGFloat preferredHeight = storedHeight ? [storedHeight doubleValue] : MAX(480.0, NSHeight(view.frame));
    CGFloat preferredWidth = storedWidth ? [storedWidth doubleValue] : MAX(580.0, NSWidth(view.frame));
    view.frame = IGCenteredLegacyPageFrame(NSMakeSize(preferredWidth, preferredHeight), self.pageContainer.bounds);
}

- (void)restoreSidebarState {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    CGFloat savedWidth = [defaults doubleForKey:IGSidebarWidthDefaultsKey];
    if (savedWidth >= IGSidebarMinimumWidth) {
        self.expandedSidebarWidth = MIN(savedWidth, 250.0);
    }

    [self setSidebarCollapsed:[defaults boolForKey:IGSidebarCollapsedDefaultsKey] persist:NO];
}

- (void)toggleSidebar:(id)sender {
    (void)sender;
    [self setSidebarCollapsed:!self.sidebarCollapsed persist:YES];
}

- (void)setSidebarCollapsed:(BOOL)collapsed persist:(BOOL)persist {
    if (collapsed) {
        CGFloat currentWidth = NSWidth(self.sidebarContainer.frame);
        if (currentWidth >= IGSidebarMinimumWidth) {
            self.expandedSidebarWidth = MIN(currentWidth, 250.0);
        }
        self.sidebarCollapsed = YES;
        self.sidebarContainer.hidden = YES;
        [self.splitView adjustSubviews];
    } else {
        self.sidebarCollapsed = NO;
        self.sidebarContainer.hidden = NO;
        [self.splitView adjustSubviews];
        CGFloat maximumWidth = MAX(IGSidebarMinimumWidth,
                                   NSWidth(self.splitView.bounds) - IGContentMinimumWidth - self.splitView.dividerThickness);
        CGFloat width = MAX(IGSidebarMinimumWidth, MIN(self.expandedSidebarWidth, MIN(250.0, maximumWidth)));
        [self.splitView setPosition:width ofDividerAtIndex:0];
    }

    if (persist) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setBool:self.sidebarCollapsed forKey:IGSidebarCollapsedDefaultsKey];
        [defaults setDouble:self.expandedSidebarWidth forKey:IGSidebarWidthDefaultsKey];
        [defaults synchronize];
    }

    [self layoutSidebarControls];
    [self layoutActivePage];
}

- (void)layoutSidebarControls {
    if (!self.sidebarToggleButton) {
        return;
    }

    CGFloat sidebarWidth = NSWidth(self.sidebarContainer.bounds);
    CGFloat sidebarHeight = NSHeight(self.sidebarContainer.bounds);
    CGFloat contentHeight = NSHeight(self.contentContainer.bounds);
    self.sidebarToggleButton.frame = NSMakeRect(12.0, MAX(6.0, contentHeight - 38.0), 30.0, 28.0);
    self.sidebarToggleButton.toolTip = self.sidebarCollapsed ? @"Show Sidebar" : @"Hide Sidebar";
    self.sidebarToggleButton.title = @"";
    NSImage *toggleImage = IGIconImageNamed(@"menu");
    [toggleImage setSize:NSMakeSize(15.0, 15.0)];
    self.sidebarToggleButton.image = toggleImage;
    [[self.sidebarToggleButton cell] setImagePosition:NSImageOnly];
    [[self.sidebarToggleButton cell] setImageScaling:NSImageScaleProportionallyDown];

    for (NSButton *button in self.sidebarButtons) {
        button.hidden = NO;
    }
    if (!self.sidebarCollapsed && ![self.sidebarContainer isHidden]) {
        CGFloat buttonY = sidebarHeight - 72.0;
        CGFloat buttonWidth = MAX(80.0, sidebarWidth - 30.0);
        for (NSButton *button in self.sidebarButtons) {
            button.frame = NSMakeRect(15.0, buttonY, buttonWidth, 28.0);
            buttonY -= 32.0;
        }
    }

    self.sidebarBackgroundView.frame = self.sidebarContainer.bounds;
    [self.contentContainer addSubview:self.sidebarToggleButton positioned:NSWindowAbove relativeTo:nil];
}

- (void)showFirstLaunchSetupIfNeeded {
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (!version || version.length == 0) {
        version = @"development";
    }

    NSString *seenVersion = [[NSUserDefaults standardUserDefaults] stringForKey:@"syncrosa_first_launch_guide_seen_version"];
    if (![seenVersion isEqualToString:version]) {
        [self showFirstLaunchGuideMarkingSeen:YES];
    }
}

- (void)showFirstLaunchGuideMarkingSeen:(BOOL)markSeen {
    if (self.firstLaunchSheetWindow) {
        [self.firstLaunchSheetWindow makeKeyAndOrderFront:nil];
        return;
    }

    self.firstLaunchGuideStep = 0;
    self.firstLaunchGuideMarksSeen = markSeen;
    NSRect sheetRect = NSMakeRect(0, 0, 680, 430);
    NSWindow *sheet = [[NSWindow alloc] initWithContentRect:sheetRect
                                                  styleMask:NSTitledWindowMask
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    BOOL russian = [[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];
    sheet.title = russian ? @"Первый запуск Syncrosa" : @"Syncrosa First Launch Setup";
    self.firstLaunchSheetWindow = sheet;
#if !__has_feature(objc_arc)
    [sheet release];
#endif

    NSView *content = [self.firstLaunchSheetWindow contentView];
    IGInstallThemedContentBackground(content);

    NSBox *illustrationBox = [[[NSBox alloc] initWithFrame:NSMakeRect(24, 70, 190, 325)] autorelease];
    illustrationBox.title = @"Syncrosa";
    illustrationBox.boxType = NSBoxPrimary;
    [content addSubview:illustrationBox];

    NSImageView *iconView = [[[NSImageView alloc] initWithFrame:NSMakeRect(55, 205, 80, 80)] autorelease];
    iconView.image = [NSApp applicationIconImage];
    iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [illustrationBox addSubview:iconView];

    self.firstLaunchCategoryLabel = IGCreateGuideTextField(@"", NSMakeRect(16, 150, 158, 42),
                                                           [NSFont boldSystemFontOfSize:15], IGThemeAccentColor(), NSCenterTextAlignment);
    [illustrationBox addSubview:self.firstLaunchCategoryLabel];
    NSTextField *caption = IGCreateGuideTextField(russian ? @"Музыка под вашим контролем" : @"Your music, under control",
                                                  NSMakeRect(18, 74, 154, 55), [NSFont systemFontOfSize:11],
                                                  IGThemeMutedTextColor(), NSCenterTextAlignment);
    [illustrationBox addSubview:caption];

    self.firstLaunchStepLabel = IGCreateGuideTextField(@"", NSMakeRect(240, 365, 410, 18),
                                                       [NSFont boldSystemFontOfSize:11], IGThemeAccentColor(), NSLeftTextAlignment);
    self.firstLaunchTitleLabel = IGCreateGuideTextField(@"", NSMakeRect(240, 313, 410, 48),
                                                        [NSFont boldSystemFontOfSize:20], IGThemeTextColor(), NSLeftTextAlignment);
    self.firstLaunchMessageLabel = IGCreateGuideTextField(@"", NSMakeRect(240, 250, 410, 58),
                                                          [NSFont systemFontOfSize:13], IGThemeTextColor(), NSLeftTextAlignment);
    self.firstLaunchDetailLabel = IGCreateGuideTextField(@"", NSMakeRect(240, 190, 410, 56),
                                                         [NSFont systemFontOfSize:11.5], IGThemeMutedTextColor(), NSLeftTextAlignment);
    self.firstLaunchHighlightOneLabel = IGCreateGuideTextField(@"", NSMakeRect(252, 137, 398, 44),
                                                               [NSFont systemFontOfSize:11], IGThemeMutedTextColor(), NSLeftTextAlignment);
    self.firstLaunchHighlightTwoLabel = IGCreateGuideTextField(@"", NSMakeRect(252, 91, 398, 44),
                                                               [NSFont systemFontOfSize:11], IGThemeMutedTextColor(), NSLeftTextAlignment);
    [content addSubview:self.firstLaunchStepLabel];
    [content addSubview:self.firstLaunchTitleLabel];
    [content addSubview:self.firstLaunchMessageLabel];
    [content addSubview:self.firstLaunchDetailLabel];
    [content addSubview:self.firstLaunchHighlightOneLabel];
    [content addSubview:self.firstLaunchHighlightTwoLabel];

    self.firstLaunchLocalModeCheckbox = [[[NSButton alloc] initWithFrame:NSMakeRect(240, 61, 330, 24)] autorelease];
    self.firstLaunchLocalModeCheckbox.buttonType = NSSwitchButton;
    self.firstLaunchLocalModeCheckbox.title = russian ? @"Только локальная обработка" : @"Only Local Mode";
    self.firstLaunchLocalModeCheckbox.target = self;
    self.firstLaunchLocalModeCheckbox.action = @selector(firstLaunchLocalModeChanged:);
    [content addSubview:self.firstLaunchLocalModeCheckbox];

    NSBox *separator = [[[NSBox alloc] initWithFrame:NSMakeRect(0, 54, 680, 1)] autorelease];
    separator.boxType = NSBoxSeparator;
    [content addSubview:separator];

    NSButton *skipButton = [[[NSButton alloc] initWithFrame:NSMakeRect(24, 14, 100, 30)] autorelease];
    skipButton.title = russian ? @"Пропустить" : @"Skip";
    skipButton.bezelStyle = NSRoundedBezelStyle;
    skipButton.target = self;
    skipButton.action = @selector(closeFirstLaunchGuide:);
    IGApplyThemeToButton(skipButton, IGThemeButtonRoleSecondary);
    [content addSubview:skipButton];

    self.firstLaunchProgressLabel = IGCreateGuideTextField(@"", NSMakeRect(270, 20, 90, 18),
                                                           [NSFont systemFontOfSize:11], IGThemeMutedTextColor(), NSCenterTextAlignment);
    [content addSubview:self.firstLaunchProgressLabel];

    self.firstLaunchBackButton = [[[NSButton alloc] initWithFrame:NSMakeRect(430, 14, 100, 30)] autorelease];
    self.firstLaunchBackButton.bezelStyle = NSRoundedBezelStyle;
    self.firstLaunchBackButton.target = self;
    self.firstLaunchBackButton.action = @selector(firstLaunchBackClicked:);
    IGApplyThemeToButton(self.firstLaunchBackButton, IGThemeButtonRoleSecondary);
    [content addSubview:self.firstLaunchBackButton];

    self.firstLaunchNextButton = [[[NSButton alloc] initWithFrame:NSMakeRect(540, 14, 116, 30)] autorelease];
    self.firstLaunchNextButton.bezelStyle = NSRoundedBezelStyle;
    self.firstLaunchNextButton.target = self;
    self.firstLaunchNextButton.action = @selector(firstLaunchNextClicked:);
    IGApplyThemeToButton(self.firstLaunchNextButton, IGThemeButtonRolePrimary);
    [content addSubview:self.firstLaunchNextButton];

    [self updateFirstLaunchGuide];

    [NSApp beginSheet:self.firstLaunchSheetWindow
       modalForWindow:self.window
        modalDelegate:nil
       didEndSelector:NULL
          contextInfo:NULL];
    IGApplyThemeToWindow(self.firstLaunchSheetWindow);
}

- (NSArray *)firstLaunchGuideSteps {
    BOOL russian = [[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];
    if (russian) {
        return @[
            @{@"category": @"Коллекция", @"title": @"Всё для вашей музыки", @"message": @"Syncrosa объединяет работу с медиатекой iTunes, локальными файлами, папками и внешними накопителями.", @"detail": @"Этот тур ничего не изменяет. Он покажет, где находится каждая группа инструментов.", @"one": @"- Исправляйте данные и создавайте плейлисты в iTunes.", @"two": @"- Обрабатывайте папки и музыку для старых Apple-устройств."},
            @{@"category": @"iTunes", @"title": @"Подключите медиатеку", @"message": @"Разрешите автоматизацию iTunes, когда OS X покажет системный запрос, затем проверьте медиатеку.", @"detail": @"Syncrosa читает названия и идентификаторы треков через системную автоматизацию. iTunes не открывается без вашего подтверждения.", @"one": @"- Overview показывает статус и количество треков.", @"two": @"- Музыка не меняется без отдельной команды."},
            @{@"category": @"Плейлисты", @"title": @"AI или полностью офлайн", @"message": @"AI Playlist создаёт подборки через выбранного провайдера, а Offline Playlist работает по локальным правилам.", @"detail": @"Media Fixer экспортирует каталог JSON для внешнего AI и импортирует его выбор обратно как плейлист.", @"one": @"- Подборки по запросу, жанру или настроению.", @"two": @"- Локальная генерация без отправки медиатеки в сеть."},
            @{@"category": @"Метаданные", @"title": @"Исправляйте данные треков", @"message": @"iTunes Media Fixer восстанавливает выбранные поля: название, исполнителя, альбом, жанр, номер трека и текст песни.", @"detail": @"Вы сами отмечаете поля, которые разрешено менять, до запуска процесса.", @"one": @"- Добавление текстов, обложек и корректных тегов.", @"two": @"- Поиск разделённых альбомов и пакетная обработка."},
            @{@"category": @"Файлы", @"title": @"Работайте прямо с папками", @"message": @"Folder Fixer изменяет теги и имена локальных файлов, включая вложенные папки, без обязательного импорта в iTunes.", @"detail": @"Info Eraser отдельно удаляет теги и обложки с подтверждением и backup для восстановления.", @"one": @"- MP3, M4A, FLAC и другие поддерживаемые форматы.", @"two": @"- Сначала тестируйте разрушительные действия на копии."},
            @{@"category": @"Диагностика", @"title": @"Проверяйте здоровье медиатеки", @"message": @"Library Doctor проверяет обложки, теги, повреждённые ссылки и совместимость, а Duplicate Finder разбирает повторы пакетно.", @"detail": @"Tag Score, Link Audit и отчёты JSON/CSV ничего не меняют и подходят для безопасной диагностики.", @"one": @"- Сначала аудит, затем применение изменений.", @"two": @"- История показывает результат каждой операции."},
            @{@"category": @"Устройства", @"title": @"Готовьте музыку для старых Apple-устройств", @"message": @"Covers Optimizer уменьшает artwork под iPod и старые устройства, экономя место без изменения аудиодорожки.", @"detail": @"USB Export копирует плейлист в отдельную папку на накопителе и может создать M3U/M3U8.", @"one": @"- Профили обложек под Classic, Nano и старые iPhone.", @"two": @"- Безопасные имена и готовая структура на флешке."},
            @{@"category": @"Контроль", @"title": @"Безопасность и восстановление", @"message": @"Перед массовыми изменениями создавайте backup. Recovery Center показывает прерванные операции и историю.", @"detail": @"В Settings находятся оформление, язык, AI-провайдер, обновления, HDD Safe Mode и локальный режим.", @"one": @"- Stop завершает текущий безопасный шаг и останавливает задачу.", @"two": @"- Only Local Mode отключает сетевой поиск метаданных."}
        ];
    }
    return @[
        @{@"category": @"Collection", @"title": @"Everything for your music", @"message": @"Syncrosa brings together your iTunes library, local files, folders, and external drives.", @"detail": @"This tour changes nothing. It shows where every group of tools lives.", @"one": @"- Repair details and create playlists in iTunes.", @"two": @"- Process folders and music for older Apple devices."},
        @{@"category": @"iTunes", @"title": @"Connect your library", @"message": @"Allow iTunes automation when OS X asks, then verify that Syncrosa can read your library.", @"detail": @"Syncrosa reads names and track identifiers through system automation. It never opens iTunes without your confirmation.", @"one": @"- Overview shows library status and track count.", @"two": @"- Music is never changed without a separate command."},
        @{@"category": @"Playlists", @"title": @"Use AI or stay fully offline", @"message": @"AI Playlist creates selections through your provider, while Offline Playlist works with local rules.", @"detail": @"Media Fixer exports a catalog JSON for an external AI and imports its selection back as a playlist.", @"one": @"- Build selections by request, genre, or mood.", @"two": @"- Generate locally without sending the library online."},
        @{@"category": @"Metadata", @"title": @"Repair track information", @"message": @"iTunes Media Fixer restores selected fields: title, artist, album, genre, track number, and lyrics.", @"detail": @"You choose exactly which fields may change before the process starts.", @"one": @"- Add lyrics, artwork, and cleaner metadata.", @"two": @"- Find split albums and process tracks in batches."},
        @{@"category": @"Files", @"title": @"Work directly with folders", @"message": @"Folder Fixer changes local file tags and names, including nested folders, without requiring an iTunes import.", @"detail": @"Info Eraser separately removes tags and artwork with confirmation and a recovery backup.", @"one": @"- Supports MP3, M4A, FLAC, and other formats.", @"two": @"- Test destructive tools on a copy first."},
        @{@"category": @"Diagnostics", @"title": @"Inspect library health", @"message": @"Library Doctor checks artwork, tags, broken links, and compatibility. Duplicate Finder handles repeated tracks in batches.", @"detail": @"Tag Score, Link Audit, and JSON/CSV reports are read-only diagnostics.", @"one": @"- Audit first, apply changes second.", @"two": @"- Operation History explains what each task changed."},
        @{@"category": @"Devices", @"title": @"Prepare music for older Apple devices", @"message": @"Covers Optimizer reduces artwork for iPods and older devices to save space without changing audio.", @"detail": @"USB Export copies a playlist into its own folder and can create M3U/M3U8 files.", @"one": @"- Artwork profiles for Classic, Nano, and older iPhones.", @"two": @"- Safe filenames and a ready USB folder structure."},
        @{@"category": @"Control", @"title": @"Safety and recovery", @"message": @"Create backups before bulk changes. Recovery Center shows interrupted operations and history.", @"detail": @"Settings contains appearance, language, AI provider, updates, HDD Safe Mode, and local mode.", @"one": @"- Stop finishes the current safe unit before ending a task.", @"two": @"- Only Local Mode disables online metadata lookup."}
    ];
}

- (void)updateFirstLaunchGuide {
    NSArray *steps = [self firstLaunchGuideSteps];
    if ([steps count] == 0) return;
    self.firstLaunchGuideStep = MAX(0, MIN(self.firstLaunchGuideStep, (NSInteger)[steps count] - 1));
    NSDictionary *step = [steps objectAtIndex:(NSUInteger)self.firstLaunchGuideStep];
    BOOL russian = [[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];
    self.firstLaunchCategoryLabel.stringValue = [step objectForKey:@"category"] ?: @"Syncrosa";
    self.firstLaunchStepLabel.stringValue = [NSString stringWithFormat:russian ? @"ШАГ %ld" : @"STEP %ld", (long)(self.firstLaunchGuideStep + 1)];
    self.firstLaunchTitleLabel.stringValue = [step objectForKey:@"title"] ?: @"";
    self.firstLaunchMessageLabel.stringValue = [step objectForKey:@"message"] ?: @"";
    self.firstLaunchDetailLabel.stringValue = [step objectForKey:@"detail"] ?: @"";
    self.firstLaunchHighlightOneLabel.stringValue = [step objectForKey:@"one"] ?: @"";
    self.firstLaunchHighlightTwoLabel.stringValue = [step objectForKey:@"two"] ?: @"";
    self.firstLaunchProgressLabel.stringValue = [NSString stringWithFormat:@"%ld / %lu", (long)(self.firstLaunchGuideStep + 1), (unsigned long)[steps count]];
    self.firstLaunchBackButton.title = russian ? @"Назад" : @"Back";
    self.firstLaunchBackButton.enabled = self.firstLaunchGuideStep > 0;
    self.firstLaunchNextButton.title = self.firstLaunchGuideStep == (NSInteger)[steps count] - 1
        ? (russian ? @"Начать" : @"Start")
        : (russian ? @"Далее" : @"Continue");
    self.firstLaunchLocalModeCheckbox.hidden = self.firstLaunchGuideStep != (NSInteger)[steps count] - 1;
    self.firstLaunchLocalModeCheckbox.state = [[NSUserDefaults standardUserDefaults] boolForKey:@"only_local_mode"] ? NSOnState : NSOffState;
}

- (void)firstLaunchBackClicked:(id)sender {
    (void)sender;
    if (self.firstLaunchGuideStep > 0) {
        self.firstLaunchGuideStep--;
        [self updateFirstLaunchGuide];
    }
}

- (void)firstLaunchNextClicked:(id)sender {
    (void)sender;
    NSArray *steps = [self firstLaunchGuideSteps];
    if (self.firstLaunchGuideStep >= (NSInteger)[steps count] - 1) {
        [self closeFirstLaunchGuide:nil];
        return;
    }
    self.firstLaunchGuideStep++;
    [self updateFirstLaunchGuide];
}

- (void)firstLaunchLocalModeChanged:(NSButton *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:(sender.state == NSOnState) forKey:@"only_local_mode"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)closeFirstLaunchGuide:(id)sender {
    if (!self.firstLaunchSheetWindow) {
        return;
    }

    if (self.firstLaunchGuideMarksSeen) {
        NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        if (!version || version.length == 0) version = @"development";
        [[NSUserDefaults standardUserDefaults] setObject:version forKey:@"syncrosa_first_launch_guide_seen_version"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }

    [NSApp endSheet:self.firstLaunchSheetWindow];
    [self.firstLaunchSheetWindow orderOut:nil];
    self.firstLaunchSheetWindow = nil;
    self.firstLaunchCategoryLabel = nil;
    self.firstLaunchStepLabel = nil;
    self.firstLaunchTitleLabel = nil;
    self.firstLaunchMessageLabel = nil;
    self.firstLaunchDetailLabel = nil;
    self.firstLaunchHighlightOneLabel = nil;
    self.firstLaunchHighlightTwoLabel = nil;
    self.firstLaunchProgressLabel = nil;
    self.firstLaunchBackButton = nil;
    self.firstLaunchNextButton = nil;
    self.firstLaunchLocalModeCheckbox = nil;
}

- (void)drivesUpdatedNotification:(NSNotification *)notification {
    [self updateButtonStates];
}

- (BOOL)indexRequiresReadableLibrary:(NSInteger)index {
    return IGNavigationItemRequiresReadableLibrary((IGNavigationItem)index);
}

- (BOOL)libraryIsConfirmedEmpty {
    return (self.libraryStatusKnown && self.libraryStatusReadable && self.libraryTrackCount == 0);
}

- (BOOL)libraryIsUnreadable {
    return (self.libraryStatusKnown && !self.libraryStatusReadable);
}

- (BOOL)libraryBlocksTools {
    return [self libraryIsConfirmedEmpty] || [self libraryIsUnreadable];
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

- (void)showUnreadableLibraryAlert {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Could Not Read iTunes"];
    [alert setInformativeText:@"Syncrosa could not read the iTunes library. Open iTunes, wait until it finishes loading, then click Refresh iTunes."];
    [alert runModal];
#if !__has_feature(objc_arc)
    [alert release];
#endif
}

- (NSString *)libraryActionNameForIndex:(NSInteger)index {
    switch (index) {
        case IGNavigationItemAIPlaylist: return @"AI Playlist";
        case IGNavigationItemMediaFixer: return @"iTunes Media Fixer";
        case IGNavigationItemUSBExport: return @"USB Export";
        case IGNavigationItemCoversOptimizer: return @"Covers Optimizer";
        case IGNavigationItemDuplicateFinder: return @"Duplicate Finder";
        case IGNavigationItemOfflinePlaylist: return @"Offline Playlist";
        case IGNavigationItemLibraryDoctor: return @"Library Doctor";
        default: return @"this tool";
    }
}

- (BOOL)confirmOpeningITunesForAction:(NSString *)action {
    if ([[IGiTunesService sharedService] iTunesIsRunning]) {
        return YES;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Open iTunes?"];
    NSString *toolName = [action length] > 0 ? action : @"this tool";
    [alert setInformativeText:[NSString stringWithFormat:@"Syncrosa needs iTunes to read your music library for %@. It will show a waiting screen while the library is checked.", toolName]];
    [alert addButtonWithTitle:@"Open iTunes"];
    [alert addButtonWithTitle:@"Cancel"];
    NSInteger result = [alert runModal];
#if !__has_feature(objc_arc)
    [alert release];
#endif
    return result == NSAlertFirstButtonReturn;
}

- (void)showLibraryBusySheetWithMessage:(NSString *)message {
    if (self.libraryBusySheetWindow) {
        [self dismissLibraryBusySheet];
    }

    NSWindow *sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 430, 150)
                                                  styleMask:NSTitledWindowMask
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    sheet.title = @"Syncrosa";
    self.libraryBusySheetWindow = sheet;
#if !__has_feature(objc_arc)
    [sheet release];
#endif

    IGInstallThemedContentBackground(self.libraryBusySheetWindow.contentView);

    NSProgressIndicator *spinner = [[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(34, 82, 32, 32)] autorelease];
    spinner.style = NSProgressIndicatorSpinningStyle;
    spinner.indeterminate = YES;
    [spinner startAnimation:nil];
    [self.libraryBusySheetWindow.contentView addSubview:spinner];

    NSTextField *title = IGCreateGuideTextField(@"Please Wait", NSMakeRect(80, 94, 310, 22),
                                                [NSFont boldSystemFontOfSize:15],
                                                [NSColor colorWithCalibratedWhite:0.12 alpha:1.0],
                                                NSLeftTextAlignment);
    [self.libraryBusySheetWindow.contentView addSubview:title];

    NSTextField *body = IGCreateGuideTextField(message ?: @"Syncrosa is checking iTunes.",
                                               NSMakeRect(80, 48, 320, 44),
                                               [NSFont systemFontOfSize:12],
                                               [NSColor colorWithCalibratedWhite:0.35 alpha:1.0],
                                               NSLeftTextAlignment);
    [self.libraryBusySheetWindow.contentView addSubview:body];
    IGApplyThemeToWindow(self.libraryBusySheetWindow);

    [NSApp beginSheet:self.libraryBusySheetWindow
       modalForWindow:self.window
        modalDelegate:nil
       didEndSelector:NULL
          contextInfo:NULL];
    [self.window display];
}

- (void)dismissLibraryBusySheet {
    if (!self.libraryBusySheetWindow) {
        return;
    }
    [NSApp endSheet:self.libraryBusySheetWindow];
    [self.libraryBusySheetWindow orderOut:nil];
    self.libraryBusySheetWindow = nil;
}

- (BOOL)refreshLibraryStatusForAction:(NSString *)action completion:(void(^)(void))completionBlock {
    if (self.refreshingLibraryStatus) {
        return NO;
    }

    if (![[IGiTunesService sharedService] iTunesIsRunning]) {
        if (![self confirmOpeningITunesForAction:action]) {
            self.libraryStatusLabel.stringValue = @"iTunes status not checked.";
            [self updateButtonStates];
            return NO;
        }
        [self showLibraryBusySheetWithMessage:@"Opening iTunes and preparing the library check..."];
        if (![[IGiTunesService sharedService] launchITunesForUserActionWithOperation:(action ?: @"library check")]) {
            [self dismissLibraryBusySheet];
            self.libraryStatusLabel.stringValue = @"iTunes did not open.";
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Could Not Open iTunes"];
            [alert setInformativeText:@"Open iTunes manually, then click Refresh iTunes again."];
            [alert runModal];
#if !__has_feature(objc_arc)
            [alert release];
#endif
            [self updateButtonStates];
            return NO;
        }
    } else {
        [self showLibraryBusySheetWithMessage:@"Syncrosa is checking your iTunes library. This can take a moment on older hard drives."];
    }

    void (^completionCopy)(void) = completionBlock ? [completionBlock copy] : nil;
    self.refreshingLibraryStatus = YES;
    self.libraryStatusLabel.stringValue = @"Checking iTunes...";
    self.libraryRefreshButton.enabled = NO;
    [self updateButtonStates];

    [[IGiTunesService sharedService] fetchLibraryTrackCountWithCompletion:^(NSInteger trackCount, NSString *errorMessage) {
        self.refreshingLibraryStatus = NO;
        [self dismissLibraryBusySheet];
        self.libraryTrackCount = trackCount;
        self.libraryStatusReadable = (trackCount >= 0);
        self.libraryStatusKnown = YES;
        self.libraryRefreshButton.enabled = YES;

        if (trackCount == 0) {
            self.libraryStatusLabel.stringValue = @"iTunes library is empty.";
        } else if (trackCount > 0) {
            self.libraryStatusLabel.stringValue = [NSString stringWithFormat:@"iTunes tracks: %ld", (long)trackCount];
        } else {
            self.libraryStatusLabel.stringValue = @"Could not read iTunes.";
            [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"Could not read iTunes library count: %@", errorMessage ?: @""]];
        }

        [self updateButtonStates];

        if ([self libraryBlocksTools] && [self indexRequiresReadableLibrary:self.activeIndex]) {
            [self switchViewToIndex:IGNavigationItemOverview];
        }

        if (completionCopy) {
            completionCopy();
#if !__has_feature(objc_arc)
            [completionCopy release];
#endif
        }
    }];
    return YES;
}

- (BOOL)refreshLibraryStatusWithCompletion:(void(^)(void))completionBlock {
    return [self refreshLibraryStatusForAction:@"refreshing iTunes status" completion:completionBlock];
}

- (NSString *)overviewLibraryStatusText {
    if (self.refreshingLibraryStatus) {
        return @"Checking iTunes...";
    }
    if (!self.libraryStatusKnown) {
        return @"Not checked";
    }
    if (!self.libraryStatusReadable) {
        return @"Unavailable";
    }
    if (self.libraryTrackCount == 0) {
        return @"Empty library";
    }
    return [NSString stringWithFormat:@"%ld tracks", (long)self.libraryTrackCount];
}

- (BOOL)overviewLibraryToolsAvailable {
    return self.libraryStatusKnown && self.libraryStatusReadable && self.libraryTrackCount > 0 && [[IGiTunesService sharedService] iTunesIsRunning];
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
        BOOL disabledByLibraryState = ([self libraryBlocksTools] && [self indexRequiresReadableLibrary:i]);
        if (i == IGNavigationItemAIPlaylist) { // Only Genius Playlist requires an API key
            btn.enabled = hasKey && !disabledByLibraryState && !self.refreshingLibraryStatus;
        } else if (i == IGNavigationItemUSBExport) { // USB Export button
            btn.enabled = !isUSBSearching && !disabledByLibraryState && !self.refreshingLibraryStatus;
        } else if ([self indexRequiresReadableLibrary:i]) {
            btn.enabled = !disabledByLibraryState && !self.refreshingLibraryStatus;
        } else {
            btn.enabled = YES;
        }
        [btn setNeedsDisplay:YES];
    }
    [self.libraryRefreshButton setNeedsDisplay:YES];
}

- (void)setupSidebar {
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    NSString *recoveryTitle = [lang.selectedLanguage isEqualToString:@"ru"] ? @"Центр восстановления" : @"Recovery Center";
    NSArray *titles = @[
        @"Overview",
        [lang t:@"ai_playlist"],
        [lang t:@"media_fixer"],
        [lang.selectedLanguage isEqualToString:@"ru"] ? @"Фильмы и сериалы" : @"Video Metadata",
        [lang t:@"folder_fix"],
        [lang.selectedLanguage isEqualToString:@"ru"] ? @"Конвертер для iPod" : @"iPod Converter",
        [lang t:@"usb_export"],
        [lang t:@"covers_optimizer"],
        [lang t:@"duplicate_finder"],
        [lang t:@"offline_playlist"],
        @"Info Eraser",
        @"Library Doctor",
        recoveryTitle,
        [lang t:@"settings"]
    ];
	    NSArray *icons = @[
	        @"compass",
	        @"star",
	        @"refresh",
	        @"artwork",
	        @"folder",
	        @"device",
	        @"usb",
	        @"artwork",
	        @"search",
	        @"network-off",
	        @"trash",
	        @"doctor",
	        @"restore",
	        @"settings"
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
	        btn.font = [NSFont systemFontOfSize:11.0];
	        NSString *iconName = [icons objectAtIndex:i];
	        if ([iconName length] > 0) {
	            IGConfigureIconButton(btn, iconName, [NSString stringWithFormat:@"Open %@", [titles objectAtIndex:i]], NO);
	        }
        IGApplyThemeToButton(btn, IGThemeButtonRoleSidebar);
	        [self.sidebarContainer addSubview:btn];
	        [self.sidebarButtons addObject:btn];
#if !__has_feature(objc_arc)
	        [btn release];
#endif
	        y -= 32;
	    }

    [self updateSidebarActivityIndicators];

    [self.libraryStatusLabel removeFromSuperview];
    self.libraryStatusLabel = nil;
    [self.libraryRefreshButton removeFromSuperview];
    self.libraryRefreshButton = nil;

    [self layoutSidebarControls];
}

- (void)localizationChanged:(NSNotification *)notification {
    (void)notification;
    [self updateGlobalFooterText];
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
    
    if (index == IGNavigationItemAIPlaylist && !hasKey && !IGDeveloperPreviewAllowsNavigationIndex(index)) {
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
            BOOL started = [self refreshLibraryStatusForAction:[self libraryActionNameForIndex:index] completion:^{
                if ([self libraryIsConfirmedEmpty]) {
                    [self showEmptyLibraryAlert];
                    [self switchViewToIndex:IGNavigationItemOverview];
                } else if ([self libraryIsUnreadable]) {
                    [self showUnreadableLibraryAlert];
                    [self switchViewToIndex:IGNavigationItemOverview];
                } else {
                    [self switchViewToIndex:index];
                }
            }];
            if (!started) {
                [self updateButtonStates];
            }
        }
        return;
    }

    if ([self indexRequiresReadableLibrary:index] && self.libraryStatusKnown && self.libraryStatusReadable && ![[IGiTunesService sharedService] iTunesIsRunning]) {
        self.libraryStatusKnown = NO;
        self.libraryStatusReadable = NO;
        self.libraryTrackCount = -1;
        self.libraryStatusLabel.stringValue = @"iTunes status not checked.";
        [self updateButtonStates];
        [self switchViewToIndex:index];
        return;
    }

	    if ([self indexRequiresReadableLibrary:index] && [self libraryIsConfirmedEmpty]) {
	        [self showEmptyLibraryAlert];
	        return;
	    }

	    if ([self indexRequiresReadableLibrary:index] && [self libraryIsUnreadable]) {
	        [self showUnreadableLibraryAlert];
	        return;
	    }

    @try {

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

	    // Clear only the active page. App chrome stays mounted above it.
	    NSArray *contentSubviews = [self.pageContainer.subviews copy];
	    for (NSView *v in contentSubviews) {
	        [v removeFromSuperview];
	    }
#if !__has_feature(objc_arc)
	    [contentSubviews release];
#endif
    
    NSViewController *targetVC = nil;
    switch (index) {
	        case IGNavigationItemOverview:
	            if (!self.overviewVC) {
	                IGOverviewViewController *vc = [[IGOverviewViewController alloc] init];
	                vc.mainController = self;
	                self.overviewVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            [self.overviewVC refreshOverview];
	            targetVC = self.overviewVC;
	            break;
	        case IGNavigationItemAIPlaylist:
	            if (!self.geniusVC) {
	                IGGeniusViewController *vc = [[IGGeniusViewController alloc] init];
	                self.geniusVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.geniusVC;
	            break;
	        case IGNavigationItemMediaFixer:
	            if (!self.fixerVC) {
	                IGFixerViewController *vc = [[IGFixerViewController alloc] init];
	                self.fixerVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.fixerVC;
	            break;
	        case IGNavigationItemVideoMetadata:
	            if (!self.videoMetadataVC) {
	                IGVideoMetadataViewController *vc = [[IGVideoMetadataViewController alloc] init];
	                self.videoMetadataVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.videoMetadataVC;
	            break;
	        case IGNavigationItemFolderFixer:
	            if (!self.fileFixerVC) {
	                IGFileFixerViewController *vc = [[IGFileFixerViewController alloc] init];
	                self.fileFixerVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.fileFixerVC;
	            break;
	        case IGNavigationItemIPodConverter:
	            if (!self.ipodConverterVC) {
	                IGIPodConverterViewController *vc = [[IGIPodConverterViewController alloc] init];
	                self.ipodConverterVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.ipodConverterVC;
	            break;
	        case IGNavigationItemUSBExport:
	            if (!self.usbExportVC) {
	                IGUSBExportViewController *vc = [[IGUSBExportViewController alloc] init];
	                self.usbExportVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.usbExportVC;
	            break;
	        case IGNavigationItemCoversOptimizer:
	            if (!self.coversOptimizerVC) {
	                IGCoversOptimizerViewController *vc = [[IGCoversOptimizerViewController alloc] init];
	                self.coversOptimizerVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.coversOptimizerVC;
	            break;
	        case IGNavigationItemDuplicateFinder:
	            if (!self.duplicateFinderVC) {
	                IGDuplicateFinderViewController *vc = [[IGDuplicateFinderViewController alloc] init];
	                self.duplicateFinderVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.duplicateFinderVC;
	            break;
	        case IGNavigationItemOfflinePlaylist:
	            if (!self.offlinePlaylistVC) {
	                IGOfflinePlaylistViewController *vc = [[IGOfflinePlaylistViewController alloc] init];
	                self.offlinePlaylistVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.offlinePlaylistVC;
	            break;
	        case IGNavigationItemInfoEraser:
	            if (!self.infoEraserVC) {
	                IGInfoEraserViewController *vc = [[IGInfoEraserViewController alloc] init];
	                self.infoEraserVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.infoEraserVC;
	            break;
	        case IGNavigationItemLibraryDoctor:
	            if (!self.libraryDoctorVC) {
	                IGLibraryDoctorViewController *vc = [[IGLibraryDoctorViewController alloc] init];
	                self.libraryDoctorVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            targetVC = self.libraryDoctorVC;
	            break;
	        case IGNavigationItemRecoveryCenter:
	            if (!self.recoveryCenterVC) {
	                IGRecoveryCenterViewController *vc = [[IGRecoveryCenterViewController alloc] init];
	                self.recoveryCenterVC = vc;
#if !__has_feature(objc_arc)
	                [vc release];
#endif
	            }
	            [self.recoveryCenterVC reloadRecoveryData];
	            targetVC = self.recoveryCenterVC;
	            break;
	        case IGNavigationItemSettings:
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
	        [self preparePageViewForEmbedding:targetVC.view];
	        self.activeViewController = targetVC;
	        [self layoutActivePage];
	        IGInstallThemedContentBackground(targetVC.view);
	        IGApplyThemeToViewHierarchy(targetVC.view);
	        [self.pageContainer addSubview:targetVC.view];
	        [self.contentContainer addSubview:self.sidebarToggleButton positioned:NSWindowAbove relativeTo:nil];
	    }
    } @catch (NSException *exception) {
        [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"Switch view exception index=%ld: %@ - %@", (long)index, exception.name, exception.reason]];
        [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"Switch view stack: %@", exception.callStackSymbols]];
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Syncrosa could not open this tab."];
        [alert setInformativeText:[NSString stringWithFormat:@"The app stayed open and returned to Overview.\n\n%@", exception.reason ?: @"Unknown error."]];
        [alert runModal];
#if !__has_feature(objc_arc)
        [alert release];
#endif
        if (index != IGNavigationItemOverview) {
            [self switchViewToIndex:IGNavigationItemOverview];
        }
    }
}

- (void)windowWillClose:(NSNotification *)notification {
    [NSApp terminate:nil];
}

#pragma mark - SplitView Delegate
- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview {
    (void)splitView;
    return subview == self.sidebarContainer;
}

- (void)splitViewDidResizeSubviews:(NSNotification *)notification {
    (void)notification;
    self.pageContainer.frame = self.contentContainer.bounds;
    if ([self.sidebarContainer isHidden]) {
        self.sidebarCollapsed = YES;
        [self layoutSidebarControls];
        [self layoutActivePage];
        return;
    }
    CGFloat sidebarWidth = NSWidth(self.sidebarContainer.frame);
    self.sidebarCollapsed = NO;
    if (!self.sidebarCollapsed && sidebarWidth >= IGSidebarMinimumWidth) {
        self.expandedSidebarWidth = MIN(sidebarWidth, 250.0);
        [[NSUserDefaults standardUserDefaults] setDouble:self.expandedSidebarWidth forKey:IGSidebarWidthDefaultsKey];
    }
    [self layoutSidebarControls];
    [self layoutActivePage];
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)dividerIndex {
    (void)proposedMax;
    (void)dividerIndex;
    if (self.sidebarCollapsed) return IGSidebarCollapsedWidth;
    return MAX(IGSidebarMinimumWidth,
               MIN(250.0, NSWidth(splitView.bounds) - IGContentMinimumWidth - splitView.dividerThickness));
}
- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)dividerIndex {
    (void)splitView;
    (void)proposedMin;
    (void)dividerIndex;
    return self.sidebarCollapsed ? IGSidebarCollapsedWidth : IGSidebarMinimumWidth;
}

@end
