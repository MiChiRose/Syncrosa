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
#import "IGTheme.h"

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
    self.statusLabel.textColor = IGThemeMutedTextColor();
    self.statusLabel.editable = NO;
    self.statusLabel.bordered = NO;
    self.statusLabel.drawsBackground = NO;
    self.statusLabel.alignment = NSCenterTextAlignment;
    IGSetTextFieldLineBreakMode(self.statusLabel, NSLineBreakByWordWrapping);
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
    wizard.title = @"Show First Launch Guide";
    wizard.bezelStyle = NSRoundedBezelStyle;
    wizard.target = self;
    wizard.action = @selector(wizardClicked:);
    [self.view addSubview:wizard];
}

- (void)refreshClicked:(id)sender {
    self.statusLabel.stringValue = @"Checking iTunes...";
    BOOL started = [self.mainController refreshLibraryStatusWithCompletion:^{
        self.statusLabel.stringValue = @"iTunes status refreshed. Use the sidebar status for the current track count.";
    }];
    if (!started) {
        self.statusLabel.stringValue = @"iTunes check cancelled.";
    }
}

- (void)openDoctorClicked:(id)sender {
    [self.mainController switchViewToIndex:9];
}

- (void)wizardClicked:(id)sender {
    [(id)self.mainController showFirstLaunchGuideMarkingSeen:NO];
}

@end

@interface IGLibraryDoctorViewController : NSViewController
@property (nonatomic, strong) NSArray *toolButtons;
@property (nonatomic, strong) NSButton *runButton;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextView *logView;
@property (nonatomic, strong) NSWindow *helpSheetWindow;
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, assign) NSInteger selectedToolIndex;
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

    NSArray *tabTitles = @[@"Restore", @"Covers", @"Library", @"iPod", @"Broken"];
    NSMutableArray *buttons = [NSMutableArray arrayWithCapacity:[tabTitles count]];
    self.selectedToolIndex = 1;
    for (NSInteger i = 0; i < (NSInteger)[tabTitles count]; i++) {
        NSButton *tabButton = [[[NSButton alloc] initWithFrame:NSMakeRect(40 + (i * 100), 382, 96, 28)] autorelease];
        tabButton.title = [tabTitles objectAtIndex:i];
        tabButton.font = [NSFont systemFontOfSize:12];
        tabButton.bezelStyle = NSTexturedRoundedBezelStyle;
        [tabButton setButtonType:NSPushOnPushOffButton];
        IGApplyThemeToButton(tabButton, IGThemeButtonRoleTab);
        tabButton.tag = i;
        tabButton.target = self;
        tabButton.action = @selector(doctorToolChanged:);
        [self.view addSubview:tabButton];
        [buttons addObject:tabButton];
    }
    self.toolButtons = buttons;
    [self updateDoctorToolButtons];

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
        @"Audit formats and filenames for older iPods.",
        @"Find missing or unreadable local files."
    ];
}

- (void)updateDoctorToolButtons {
    for (NSButton *button in self.toolButtons) {
        BOOL selected = (button.tag == self.selectedToolIndex);
        button.state = selected ? NSOnState : NSOffState;
        button.font = selected ? [NSFont boldSystemFontOfSize:12] : [NSFont systemFontOfSize:12];
        IGApplyThemeToButton(button, IGThemeButtonRoleTab);
        [button setNeedsDisplay:YES];
    }
}

- (void)doctorToolChanged:(id)sender {
    if ([sender isKindOfClass:[NSButton class]]) {
        self.selectedToolIndex = [(NSButton *)sender tag];
    }
    [self updateDoctorToolButtons];
    NSInteger selected = self.selectedToolIndex;
    NSArray *descriptions = [self toolDescriptions];
    if (selected >= 0 && selected < (NSInteger)descriptions.count) {
        self.statusLabel.stringValue = [descriptions objectAtIndex:selected];
    }
}

- (void)helpClicked:(id)sender {
    NSString *helpText = @"Library Doctor Help\n\n"
                         "Use this page for quick health checks before running library tools.\n\n"
                         "Restore: points you to the Covers Optimizer restore flow.\n"
                         "Covers: counts tracks with embedded cover artwork.\n"
                         "Library: verifies that iTunes can be read.\n"
                         "iPod: reports formats, long names, missing files, and large files.\n"
                         "Broken: lists missing or unreadable file references.";

    NSWindow *sheet = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 260)
                                                   styleMask:NSTitledWindowMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES] autorelease];
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(20, 60, 380, 180)] autorelease];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;

    NSTextView *textView = [[[NSTextView alloc] initWithFrame:scroll.bounds] autorelease];
    textView.editable = NO;
    textView.string = helpText;
    textView.font = [NSFont systemFontOfSize:12];
    scroll.documentView = textView;
    [sheet.contentView addSubview:scroll];

    NSButton *closeButton = [[[NSButton alloc] initWithFrame:NSMakeRect(160, 15, 100, 30)] autorelease];
    closeButton.title = @"OK";
    closeButton.bezelStyle = NSRoundedBezelStyle;
    closeButton.target = self;
    closeButton.action = @selector(closeHelpSheet:);
    [sheet.contentView addSubview:closeButton];

    IGApplyThemeToWindow(sheet);
    self.helpSheetWindow = sheet;
    if ([self.view.window respondsToSelector:@selector(beginSheet:completionHandler:)]) {
        [self.view.window beginSheet:sheet completionHandler:nil];
    } else {
        [NSApp beginSheet:sheet modalForWindow:self.view.window modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
    }
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

- (void)runClicked:(id)sender {
    if (self.isRunning) return;
    self.isRunning = YES;
    self.runButton.enabled = NO;
    self.progressIndicator.doubleValue = 0;
    [self clearLog];

    NSInteger selected = self.selectedToolIndex;
    NSArray *titles = @[@"Cover Restore", @"Cover Audit", @"Library Audit", @"iPod Report", @"Broken Tracks"];
    NSString *selectedTitle = (selected >= 0 && selected < (NSInteger)titles.count) ? [titles objectAtIndex:selected] : @"Library Audit";
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
        } else if (selected == 3 || selected == 4) {
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
            if (selected == 3) {
                NSArray *supported = @[@"mp3", @"m4a", @"mp4", @"aac", @"wav", @"aiff", @"aif"];
                NSInteger unsupported = 0;
                NSInteger missing = 0;
                NSInteger longNames = 0;
                NSInteger hugeFiles = 0;
                unsigned long long totalBytes = 0;
                NSFileManager *fm = [NSFileManager defaultManager];
                for (NSDictionary *track in refs) {
                    NSString *path = [track objectForKey:@"path"] ?: @"";
                    NSString *ext = [[path pathExtension] lowercaseString];
                    unsigned long long size = [[track objectForKey:@"size"] unsignedLongLongValue];
                    totalBytes += size;
                    if (path.length == 0 || ![fm fileExistsAtPath:path] || ![fm isReadableFileAtPath:path]) {
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
                }
                NSString *sizeStr = [NSByteCountFormatter stringFromByteCount:(long long)totalBytes countStyle:NSByteCountFormatterCountStyleFile];
                [self log:[NSString stringWithFormat:@"file tracks scanned: %ld", (long)refs.count]];
                [self log:[NSString stringWithFormat:@"total local size: %@", sizeStr]];
                [self log:[NSString stringWithFormat:@"unsupported format warnings: %ld", (long)unsupported]];
                [self log:[NSString stringWithFormat:@"missing/unreadable files: %ld", (long)missing]];
                [self log:[NSString stringWithFormat:@"long filenames (>80 chars): %ld", (long)longNames]];
                [self log:[NSString stringWithFormat:@"large files (>100 MB): %ld", (long)hugeFiles]];
                NSInteger warnings = unsupported + missing + longNames + hugeFiles;
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
            self.statusLabel.stringValue = historyMessage;
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
@property (nonatomic, strong) NSView *sidebarBackgroundView;
@property (nonatomic, strong) NSMutableArray *sidebarButtons;
@property (nonatomic, strong) NSTextField *libraryStatusLabel;
@property (nonatomic, strong) NSButton *libraryRefreshButton;
@property (nonatomic, strong) NSWindow *firstLaunchSheetWindow;
@property (nonatomic, strong) NSWindow *libraryBusySheetWindow;
@property (nonatomic, assign) NSInteger libraryTrackCount;
@property (nonatomic, assign) BOOL libraryStatusKnown;
@property (nonatomic, assign) BOOL libraryStatusReadable;
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
    [window setContentView:IGCreateThemedBackgroundView(NSMakeRect(0, 0, 800, 500), IGThemeBackgroundRoleWindow)];
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
	    [_sidebarBackgroundView release];
	    [_sidebarButtons release];
	    [_libraryStatusLabel release];
	    [_libraryRefreshButton release];
	    [_firstLaunchSheetWindow release];
	    [_libraryBusySheetWindow release];
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
    
    self.sidebarBackgroundView = IGCreateThemedBackgroundView(self.sidebarContainer.bounds, IGThemeBackgroundRoleSidebar);
	    [self.sidebarContainer addSubview:self.sidebarBackgroundView];
    
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
                                             selector:@selector(themeChanged:)
                                                 name:IGThemeDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(systemAppearanceChanged:)
                                                 name:@"NSApplicationDidChangeEffectiveAppearanceNotification"
                                               object:nil];
    [self applyTheme];
    
    // Initial VC: if API key exists, show Genius Playlist, otherwise Settings
	    NSString *provider = [[NSUserDefaults standardUserDefaults] stringForKey:@"provider"] ?: @"Gemini";
    NSString *apiKey = [[IGKeychainHelper sharedHelper] readStringForAccount:[provider lowercaseString]];
    if (apiKey && apiKey.length > 0) {
        [self switchViewToIndex:0];
    } else {
        [self switchViewToIndex:10];
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
    self.libraryStatusLabel.textColor = IGThemeMutedTextColor();
    IGApplyThemeToButton(self.libraryRefreshButton, IGThemeButtonRoleSecondary);
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

    NSRect sheetRect = NSMakeRect(0, 0, 560, 380);
    NSWindow *sheet = [[NSWindow alloc] initWithContentRect:sheetRect
                                                  styleMask:NSTitledWindowMask
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    sheet.title = @"Syncrosa First Launch Guide";
    self.firstLaunchSheetWindow = sheet;
#if !__has_feature(objc_arc)
    [sheet release];
#endif

    NSView *content = [self.firstLaunchSheetWindow contentView];
    IGInstallThemedContentBackground(content);
    NSImageView *iconView = [[[NSImageView alloc] initWithFrame:NSMakeRect(28, 288, 64, 64)] autorelease];
    iconView.image = [NSApp applicationIconImage];
    iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [content addSubview:iconView];

    NSTextField *title = IGCreateGuideTextField(@"Before You Start", NSMakeRect(110, 322, 410, 26),
                                                [NSFont boldSystemFontOfSize:18],
                                                [NSColor colorWithCalibratedWhite:0.10 alpha:1.0],
                                                NSLeftTextAlignment);
    [content addSubview:title];

    NSTextField *subtitle = IGCreateGuideTextField(@"A quick setup guide for old iTunes libraries and slower Macs.", NSMakeRect(110, 292, 410, 40),
                                                   [NSFont systemFontOfSize:12],
                                                   [NSColor colorWithCalibratedWhite:0.35 alpha:1.0],
                                                   NSLeftTextAlignment);
    [content addSubview:subtitle];

    NSArray *stepTitles = @[
        @"1. Allow iTunes automation",
        @"2. Start from Overview",
        @"3. Work on copies for destructive tools",
        @"4. Use Only Local Mode when needed"
    ];
    NSArray *stepBodies = @[
        @"If OS X asks for permission, allow Syncrosa to control iTunes so it can read tracks and playlists.",
        @"Overview checks whether the iTunes library is readable before library tools are enabled.",
        @"Info Eraser and direct file fixing can rewrite files. Test them on copies before touching the only copy of a folder.",
        @"In Settings, Only Local Mode skips online metadata lookups and keeps older HDD Macs calmer."
    ];

    CGFloat y = 250.0;
    for (NSInteger i = 0; i < [stepTitles count]; i++) {
        NSTextField *stepTitle = IGCreateGuideTextField([stepTitles objectAtIndex:i], NSMakeRect(42, y, 475, 20),
                                                        [NSFont boldSystemFontOfSize:12],
                                                        [NSColor colorWithCalibratedWhite:0.15 alpha:1.0],
                                                        NSLeftTextAlignment);
        [content addSubview:stepTitle];

        NSTextField *stepBody = IGCreateGuideTextField([stepBodies objectAtIndex:i], NSMakeRect(58, y - 34, 460, 34),
                                                       [NSFont systemFontOfSize:11],
                                                       [NSColor colorWithCalibratedWhite:0.35 alpha:1.0],
                                                       NSLeftTextAlignment);
        [content addSubview:stepBody];
        y -= 54.0;
    }

    NSButton *okButton = [[[NSButton alloc] initWithFrame:NSMakeRect(425, 16, 105, 32)] autorelease];
    okButton.title = @"Got It";
    okButton.bezelStyle = NSRoundedBezelStyle;
    okButton.target = self;
    okButton.action = @selector(closeFirstLaunchGuide:);
    IGApplyThemeToButton(okButton, IGThemeButtonRolePrimary);
    [content addSubview:okButton];

    if (markSeen) {
        NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        if (!version || version.length == 0) {
            version = @"development";
        }
        [[NSUserDefaults standardUserDefaults] setObject:version forKey:@"syncrosa_first_launch_guide_seen_version"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }

    [NSApp beginSheet:self.firstLaunchSheetWindow
       modalForWindow:self.window
        modalDelegate:nil
       didEndSelector:NULL
          contextInfo:NULL];
    IGApplyThemeToWindow(self.firstLaunchSheetWindow);
}

- (void)closeFirstLaunchGuide:(id)sender {
    if (!self.firstLaunchSheetWindow) {
        return;
    }

    [NSApp endSheet:self.firstLaunchSheetWindow];
    [self.firstLaunchSheetWindow orderOut:nil];
    self.firstLaunchSheetWindow = nil;
}

- (void)drivesUpdatedNotification:(NSNotification *)notification {
    [self updateButtonStates];
}

- (BOOL)indexRequiresReadableLibrary:(NSInteger)index {
    return (index == 1 || index == 2 || index == 4 || index == 5 || index == 6 || index == 7 || index == 9);
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
        case 1: return @"AI Playlist";
        case 2: return @"iTunes Media Fixer";
        case 4: return @"USB Export";
        case 5: return @"Covers Optimizer";
        case 6: return @"Duplicate Finder";
        case 7: return @"Offline Playlist";
        case 9: return @"Library Doctor";
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
            [self switchViewToIndex:0];
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
        if (i == 1) { // Only Genius Playlist requires an API key
            btn.enabled = hasKey && !disabledByLibraryState && !self.refreshingLibraryStatus;
        } else if (i == 4) { // USB Export button
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
        IGApplyThemeToButton(btn, IGThemeButtonRoleSidebar);
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
        statusLabel.textColor = IGThemeMutedTextColor();
        statusLabel.alignment = NSCenterTextAlignment;
        IGSetTextFieldLineBreakMode(statusLabel, NSLineBreakByWordWrapping);
        statusLabel.stringValue = @"iTunes status not checked.";
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
        IGApplyThemeToButton(refreshButton, IGThemeButtonRoleSecondary);
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
            BOOL started = [self refreshLibraryStatusForAction:[self libraryActionNameForIndex:index] completion:^{
                if ([self libraryIsConfirmedEmpty]) {
                    [self showEmptyLibraryAlert];
                    [self switchViewToIndex:0];
                } else if ([self libraryIsUnreadable]) {
                    [self showUnreadableLibraryAlert];
                    [self switchViewToIndex:0];
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
	        IGInstallThemedContentBackground(targetVC.view);
	        IGApplyThemeToViewHierarchy(targetVC.view);
	        [self.contentContainer addSubview:targetVC.view];
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
        if (index != 0) {
            [self switchViewToIndex:0];
        }
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
