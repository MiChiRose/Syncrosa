#import "IGFixerViewController.h"
#import "IGiTunesService.h"
#import "IGMediaFixerManager.h"
#import "IGLocalizationService.h"
#import "IGNotificationView.h"
#import "IGLogger.h"
#import "IGTrack.h"
#import "IGPlaylistJSONSupport.h"

static NSString *IGFixerAppleScriptLiteral(NSString *value) {
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

@interface IGFixerViewController ()

@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSButton *startButton;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextView *logView;
@property (nonatomic, strong) NSTextField *footerLabel;

@property (nonatomic, strong) NSButton *selectAllCheckbox;
@property (nonatomic, strong) NSButton *albumCheckbox;
@property (nonatomic, strong) NSButton *titleCheckbox;
@property (nonatomic, strong) NSButton *artistCheckbox;
@property (nonatomic, strong) NSButton *genreCheckbox;
@property (nonatomic, strong) NSButton *trackNumberCheckbox;
@property (nonatomic, strong) NSButton *lyricsCheckbox;
@property (nonatomic, strong) NSButton *exportLibraryJSONButton;
@property (nonatomic, strong) NSButton *importLibraryJSONButton;
@property (nonatomic, strong) NSWindow *helpSheetWindow;
@property (nonatomic, assign) BOOL isRunning;

@end

@implementation IGFixerViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 480)];
    [self setupUI];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(localizationChanged:)
                                                 name:@"IGLanguageChangedNotification"
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
#if !__has_feature(objc_arc)
    [super dealloc];
#endif
}

- (void)setupUI {
    CGFloat y = 430;
    
    self.titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 30)];
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
    
    y -= 40;
    self.progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(40, y, 500, 20)];
    self.progressIndicator.style = NSProgressIndicatorBarStyle;
    self.progressIndicator.indeterminate = NO;
    [self.view addSubview:self.progressIndicator];
    
    y -= 25;
    self.statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 20)];
    self.statusLabel.editable = NO;
    self.statusLabel.bordered = NO;
    self.statusLabel.drawsBackground = NO;
    self.statusLabel.alignment = NSCenterTextAlignment;
    [self.view addSubview:self.statusLabel];

    // Selective Tag Checkboxes
    y -= 30;
    self.selectAllCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(40, y, 150, 20)];
    [self.selectAllCheckbox setButtonType:NSSwitchButton];
    self.selectAllCheckbox.target = self;
    self.selectAllCheckbox.action = @selector(selectAllClicked:);
    self.selectAllCheckbox.state = NSOffState;
    [self.view addSubview:self.selectAllCheckbox];
    
    y -= 25;
    self.albumCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(40, y, 140, 20)];
    [self.albumCheckbox setButtonType:NSSwitchButton];
    self.albumCheckbox.state = NSOnState;
    self.albumCheckbox.target = self;
    self.albumCheckbox.action = @selector(tagCheckboxClicked:);
    [self.view addSubview:self.albumCheckbox];
    
    self.titleCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(200, y, 140, 20)];
    [self.titleCheckbox setButtonType:NSSwitchButton];
    self.titleCheckbox.state = NSOnState;
    self.titleCheckbox.target = self;
    self.titleCheckbox.action = @selector(tagCheckboxClicked:);
    [self.view addSubview:self.titleCheckbox];
    
    self.artistCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(360, y, 140, 20)];
    [self.artistCheckbox setButtonType:NSSwitchButton];
    self.artistCheckbox.state = NSOnState;
    self.artistCheckbox.target = self;
    self.artistCheckbox.action = @selector(tagCheckboxClicked:);
    [self.view addSubview:self.artistCheckbox];
    
    y -= 25;
    self.genreCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(40, y, 140, 20)];
    [self.genreCheckbox setButtonType:NSSwitchButton];
    self.genreCheckbox.state = NSOnState;
    self.genreCheckbox.target = self;
    self.genreCheckbox.action = @selector(tagCheckboxClicked:);
    [self.view addSubview:self.genreCheckbox];
    
    self.trackNumberCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(200, y, 140, 20)];
    [self.trackNumberCheckbox setButtonType:NSSwitchButton];
    self.trackNumberCheckbox.state = NSOnState;
    self.trackNumberCheckbox.target = self;
    self.trackNumberCheckbox.action = @selector(tagCheckboxClicked:);
    [self.view addSubview:self.trackNumberCheckbox];
    
    self.lyricsCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(360, y, 140, 20)];
    [self.lyricsCheckbox setButtonType:NSSwitchButton];
    self.lyricsCheckbox.state = NSOffState;
    self.lyricsCheckbox.target = self;
    self.lyricsCheckbox.action = @selector(tagCheckboxClicked:);
    [self.view addSubview:self.lyricsCheckbox];

    y -= 140;
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(40, y, 500, 130)];
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;
    
    self.logView = [[NSTextView alloc] initWithFrame:scrollView.bounds];
    self.logView.editable = NO;
    self.logView.backgroundColor = [NSColor blackColor];
    self.logView.textColor = [NSColor greenColor];
    self.logView.font = [NSFont fontWithName:@"Monaco" size:10];
    
    scrollView.documentView = self.logView;
    [self.view addSubview:scrollView];
    
    y -= 50;
    self.startButton = [[NSButton alloc] initWithFrame:NSMakeRect(190, y, 200, 40)];
    self.startButton.bezelStyle = NSTexturedRoundedBezelStyle;
    self.startButton.target = self;
    self.startButton.action = @selector(startClicked:);
    [self.view addSubview:self.startButton];

    y -= 38;
    self.exportLibraryJSONButton = [[NSButton alloc] initWithFrame:NSMakeRect(80, y, 200, 30)];
    self.exportLibraryJSONButton.bezelStyle = NSRoundedBezelStyle;
    self.exportLibraryJSONButton.target = self;
    self.exportLibraryJSONButton.action = @selector(exportLibraryJSONClicked:);
    [self.view addSubview:self.exportLibraryJSONButton];

    self.importLibraryJSONButton = [[NSButton alloc] initWithFrame:NSMakeRect(300, y, 200, 30)];
    self.importLibraryJSONButton.bezelStyle = NSRoundedBezelStyle;
    self.importLibraryJSONButton.target = self;
    self.importLibraryJSONButton.action = @selector(importLibraryJSONClicked:);
    [self.view addSubview:self.importLibraryJSONButton];

    // Footer
    self.footerLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 15, 540, 30)];
    self.footerLabel.font = [NSFont systemFontOfSize:10];
    self.footerLabel.textColor = [NSColor grayColor];
    self.footerLabel.alignment = NSCenterTextAlignment;
    self.footerLabel.editable = NO;
    self.footerLabel.bordered = NO;
    self.footerLabel.drawsBackground = NO;
    [self.view addSubview:self.footerLabel];
    
    [self updateLocalization];
    [self tagCheckboxClicked:nil];
}

- (void)updateLocalization {
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    
    self.titleLabel.stringValue = [lang t:@"media_fixer"];
    self.startButton.title = [lang t:@"analyze_lib"];
    self.footerLabel.stringValue = [lang t:@"footer"];
    
    self.selectAllCheckbox.title = [lang t:@"select_all"];
    self.albumCheckbox.title = [lang t:@"tag_album"];
    self.titleCheckbox.title = [lang t:@"tag_title"];
    self.artistCheckbox.title = [lang t:@"tag_artist"];
    self.genreCheckbox.title = [lang t:@"tag_genre"];
    self.trackNumberCheckbox.title = [lang t:@"tag_track_number"];
    self.lyricsCheckbox.title = [lang t:@"tag_lyrics"];
    self.exportLibraryJSONButton.title = [lang.selectedLanguage isEqualToString:@"ru"] ? @"Экспорт JSON медиатеки" : @"Export Library JSON";
    self.importLibraryJSONButton.title = [lang.selectedLanguage isEqualToString:@"ru"] ? @"Импорт JSON плейлиста" : @"Import Playlist JSON";
    
    if (self.statusLabel.stringValue.length == 0 ||
        [self.statusLabel.stringValue isEqualToString:@"Ready to scan for metadata issues"] ||
        [self.statusLabel.stringValue isEqualToString:@"Готов к сканированию медиатеки на ошибки."]) {
        self.statusLabel.stringValue = [lang.selectedLanguage isEqualToString:@"ru"] ? 
            @"Готов к сканированию медиатеки на ошибки." : 
            @"Ready to scan for metadata issues";
    }
}

- (void)localizationChanged:(NSNotification *)notification {
    [self updateLocalization];
}

- (void)log:(NSString *)text {
    [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"MediaFixer UI: %@", text ?: @""]];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *line = [NSString stringWithFormat:@"> %@\n", text];
        NSAttributedString *attrLine = [[NSAttributedString alloc] initWithString:line attributes:@{NSForegroundColorAttributeName: [NSColor greenColor]}];
        NSTextStorage *storage = self.logView.textStorage;
        [storage appendAttributedString:attrLine];
        if (storage.length > 30000) {
            [storage deleteCharactersInRange:NSMakeRange(0, storage.length - 30000)];
        }
#if !__has_feature(objc_arc)
        [attrLine release];
#endif
        [self.logView scrollRangeToVisible:NSMakeRange(storage.length, 0)];
    });
}

- (void)clearLogView {
    [self.logView setString:@""];
}

- (void)selectAllClicked:(id)sender {
    NSInteger state = self.selectAllCheckbox.state;
    self.albumCheckbox.state = state;
    self.titleCheckbox.state = state;
    self.artistCheckbox.state = state;
    self.genreCheckbox.state = state;
    self.trackNumberCheckbox.state = state;
    self.lyricsCheckbox.state = state;
    [self updateStartButtonState];
}

- (BOOL)hasSelectedTags {
    return self.albumCheckbox.state == NSOnState ||
           self.titleCheckbox.state == NSOnState ||
           self.artistCheckbox.state == NSOnState ||
           self.genreCheckbox.state == NSOnState ||
           self.trackNumberCheckbox.state == NSOnState ||
           self.lyricsCheckbox.state == NSOnState;
}

- (void)updateStartButtonState {
    self.startButton.enabled = (!self.isRunning && [self hasSelectedTags]);
    self.exportLibraryJSONButton.enabled = !self.isRunning;
    self.importLibraryJSONButton.enabled = !self.isRunning;
}

- (void)tagCheckboxClicked:(id)sender {
    BOOL allChecked = self.albumCheckbox.state == NSOnState &&
                      self.titleCheckbox.state == NSOnState &&
                      self.artistCheckbox.state == NSOnState &&
                      self.genreCheckbox.state == NSOnState &&
                      self.trackNumberCheckbox.state == NSOnState &&
                      self.lyricsCheckbox.state == NSOnState;
    self.selectAllCheckbox.state = allChecked ? NSOnState : NSOffState;
    [self updateStartButtonState];
}

- (void)helpClicked:(id)sender {
    NSString *helpText = @"iTunes Media Fixer Help\n\n"
                          "This utility scans your iTunes/Music library for split albums and missing metadata (Album, Title, Artist, Genre, Track Number, and Lyrics).\n\n"
                          "1. Select All / Individual Tags: Use the checkboxes to choose which metadata tags should be corrected. Only the checked tags will be updated via AppleScript.\n"
                          "2. Library JSON: Export a clean list of your iTunes tracks, give it to an external AI helper, then import a returned JSON selection to create a playlist.\n"
                          "3. Safe Operation: Every single track operation is wrapped in a safe error handling block, ensuring that if any track write fails (due to write permissions, locked files, etc.), the app will skip it and continue without crashing.";
    
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

- (void)showSimpleAlertWithTitle:(NSString *)title message:(NSString *)message {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:title ?: @"Syncrosa"];
    [alert setInformativeText:message ?: @""];
    [alert runModal];
}

- (void)showWaitSheetWithMessage:(NSString *)message {
    if (self.helpSheetWindow) {
        [self closeHelpSheet:nil];
    }

    NSWindow *sheet = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 140)
                                                   styleMask:NSTitledWindowMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES] autorelease];
    sheet.title = @"Syncrosa";

    NSProgressIndicator *spinner = [[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(32, 78, 32, 32)] autorelease];
    spinner.style = NSProgressIndicatorSpinningStyle;
    spinner.indeterminate = YES;
    [spinner startAnimation:nil];
    [sheet.contentView addSubview:spinner];

    NSTextField *label = [[[NSTextField alloc] initWithFrame:NSMakeRect(78, 58, 310, 54)] autorelease];
    label.stringValue = message ?: @"Please wait...";
    label.font = [NSFont systemFontOfSize:12];
    label.editable = NO;
    label.selectable = NO;
    label.bordered = NO;
    label.drawsBackground = NO;
    [[label cell] setWraps:YES];
    [sheet.contentView addSubview:label];

    self.helpSheetWindow = sheet;
    [NSApp beginSheet:self.helpSheetWindow
       modalForWindow:self.view.window
        modalDelegate:nil
       didEndSelector:NULL
          contextInfo:NULL];
    [self.view.window display];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

- (BOOL)prepareITunesForUserAction:(NSString *)action {
    if ([[IGiTunesService sharedService] iTunesIsRunning]) {
        return YES;
    }

    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:@"Open iTunes?"];
    [alert setInformativeText:[NSString stringWithFormat:@"Syncrosa needs iTunes for %@. It will not open iTunes unless you allow it.", action ?: @"this action"]];
    [alert addButtonWithTitle:@"Open iTunes"];
    [alert addButtonWithTitle:@"Cancel"];
    NSInteger result = [alert runModal];
    if (result != NSAlertFirstButtonReturn) {
        self.statusLabel.stringValue = @"iTunes action cancelled.";
        [self log:@"iTunes action cancelled by user."];
        return NO;
    }

    self.statusLabel.stringValue = @"Opening iTunes...";
    [self log:@"Opening iTunes after user confirmation..."];
    [self showWaitSheetWithMessage:@"Opening iTunes. Please wait while Syncrosa prepares the library operation..."];
    if (![[IGiTunesService sharedService] launchITunesForUserActionWithOperation:(action ?: @"media fixer action")]) {
        [self closeHelpSheet:nil];
        self.statusLabel.stringValue = @"Could not open iTunes.";
        [self log:@"Could not open iTunes."];
        [self showSimpleAlertWithTitle:@"Could Not Open iTunes" message:@"Open iTunes manually, then try again."];
        return NO;
    }
    [self closeHelpSheet:nil];
    return YES;
}

- (void)finishLibraryJSONOperationWithStatus:(NSString *)status error:(BOOL)isError {
    self.statusLabel.stringValue = status ?: @"";
    self.isRunning = NO;
    [self.progressIndicator stopAnimation:nil];
    self.progressIndicator.indeterminate = NO;
    [self updateStartButtonState];
    if ([status length] > 0) {
        [IGNotificationView showInView:self.view message:status isError:isError];
    }
}

- (NSString *)promptForPlaylistNameWithDefault:(NSString *)defaultName {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:@"Name Playlist"];
    [alert setInformativeText:@"Enter a name for the iTunes playlist Syncrosa should create from this JSON selection."];
    [alert addButtonWithTitle:@"Create"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *field = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)] autorelease];
    field.stringValue = ([defaultName length] > 0) ? defaultName : @"AI Playlist";
    [alert setAccessoryView:field];

    NSInteger response = [alert runModal];
    if (response != NSAlertFirstButtonReturn) {
        return @"";
    }
    NSString *name = [field.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return ([name length] > 0) ? name : @"";
}

- (BOOL)confirmPlaylistImportWithRequestedCount:(NSUInteger)requestedCount matchedCount:(NSUInteger)matchedCount missingCount:(NSUInteger)missingCount {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:@"Create iTunes Playlist?"];
    [alert setInformativeText:[NSString stringWithFormat:
                               @"Syncrosa found %lu matching tracks from %lu requested IDs.\n\n%lu IDs were not found in this iTunes library.\n\nIf a playlist with the same name already exists, Syncrosa will replace its contents.",
                               (unsigned long)matchedCount,
                               (unsigned long)requestedCount,
                               (unsigned long)missingCount]];
    [alert addButtonWithTitle:@"Continue"];
    [alert addButtonWithTitle:@"Cancel"];
    return [alert runModal] == NSAlertFirstButtonReturn;
}

- (void)exportLibraryJSONClicked:(id)sender {
    if (self.isRunning) {
        return;
    }

    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setAllowedFileTypes:[NSArray arrayWithObject:@"json"]];
    [panel setNameFieldStringValue:@"Syncrosa-iTunes-Library.json"];
    [panel setTitle:@"Export iTunes Library JSON"];
    if ([panel runModal] != NSFileHandlingPanelOKButton) {
        return;
    }

    NSURL *destinationURL = [panel URL];
    if (!destinationURL) {
        return;
    }
    if (![self prepareITunesForUserAction:@"exporting the iTunes library JSON"]) {
        return;
    }

    [self clearLogView];
    self.isRunning = YES;
    [self updateStartButtonState];
    self.statusLabel.stringValue = @"Checking iTunes library...";
    self.progressIndicator.indeterminate = YES;
    [self.progressIndicator startAnimation:nil];
    [self log:@"Preparing full-library JSON export..."];

    [[IGiTunesService sharedService] fetchLibraryTrackCountWithCompletion:^(NSInteger trackCount, NSString *errorMessage) {
        if (trackCount < 0) {
            NSString *message = errorMessage ?: @"Could not read iTunes library.";
            [self log:message];
            [self finishLibraryJSONOperationWithStatus:message error:YES];
            return;
        }
        if (trackCount == 0) {
            NSString *message = @"iTunes has no tracks to export.";
            [self log:message];
            [self finishLibraryJSONOperationWithStatus:message error:YES];
            return;
        }

        self.progressIndicator.indeterminate = NO;
        self.progressIndicator.maxValue = trackCount;
        self.progressIndicator.doubleValue = 0;
        self.statusLabel.stringValue = @"Exporting library track list...";

        [[IGiTunesService sharedService] fetchAllTracksWithProgress:^(NSInteger current, NSInteger total) {
            self.progressIndicator.maxValue = total;
            self.progressIndicator.doubleValue = current;
            self.statusLabel.stringValue = [NSString stringWithFormat:@"Exporting %ld / %ld tracks...", (long)current, (long)total];
        } completion:^(NSArray *tracks) {
            if ([tracks count] == 0) {
                NSString *message = @"No readable iTunes tracks were returned.";
                [self log:message];
                [self finishLibraryJSONOperationWithStatus:message error:YES];
                return;
            }

            NSMutableArray *jsonTracks = [NSMutableArray arrayWithCapacity:[tracks count]];
            for (IGTrack *track in tracks) {
                if ([track isKindOfClass:[IGTrack class]] && [track.persistentID length] > 0) {
                    [jsonTracks addObject:IGPlaylistJSONObjectForTrack(track)];
                }
            }

            NSDictionary *manifest = [NSDictionary dictionaryWithObjectsAndKeys:
                                      @"syncrosa-itunes-library-v1", @"schema",
                                      @"Syncrosa", @"app",
                                      ([[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] ?: @""), @"appVersion",
                                      [NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]], @"exportedAt",
                                      [NSNumber numberWithUnsignedInteger:[jsonTracks count]], @"trackCount",
                                      @"Ask an external AI agent to return JSON with either {\"playlistName\":\"Name\",\"persistentIDs\":[\"...\"]} or {\"playlistName\":\"Name\",\"tracks\":[{\"persistentID\":\"...\"}]}.", @"instructions",
                                      jsonTracks, @"tracks",
                                      nil];

            NSError *jsonError = nil;
            NSData *data = [NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:&jsonError];
            if (![data isKindOfClass:[NSData class]]) {
                NSString *message = [NSString stringWithFormat:@"Could not prepare JSON: %@", [jsonError localizedDescription] ?: @"unknown error"];
                [self log:message];
                [self finishLibraryJSONOperationWithStatus:message error:YES];
                return;
            }

            NSError *writeError = nil;
            BOOL wrote = [data writeToURL:destinationURL options:NSDataWritingAtomic error:&writeError];
            if (!wrote) {
                NSString *message = [NSString stringWithFormat:@"Could not save JSON: %@", [writeError localizedDescription] ?: @"unknown error"];
                [self log:message];
                [self finishLibraryJSONOperationWithStatus:message error:YES];
                return;
            }

            NSString *message = [NSString stringWithFormat:@"Exported %lu tracks to JSON.", (unsigned long)[jsonTracks count]];
            [self log:message];
            [self finishLibraryJSONOperationWithStatus:message error:NO];
        }];
    }];
}

- (void)importLibraryJSONClicked:(id)sender {
    if (self.isRunning) {
        return;
    }

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setAllowedFileTypes:[NSArray arrayWithObject:@"json"]];
    [panel setAllowsMultipleSelection:NO];
    [panel setCanChooseDirectories:NO];
    [panel setTitle:@"Import Playlist JSON"];
    if ([panel runModal] != NSFileHandlingPanelOKButton) {
        return;
    }

    NSURL *sourceURL = [panel URL];
    if (!sourceURL) {
        return;
    }

    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:[sourceURL path] error:nil];
    unsigned long long fileSize = [[attrs objectForKey:NSFileSize] unsignedLongLongValue];
    if (fileSize > (10ULL * 1024ULL * 1024ULL)) {
        [self showSimpleAlertWithTitle:@"Import JSON" message:@"This JSON file is too large for the legacy importer."];
        return;
    }

    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfURL:sourceURL options:0 error:&readError];
    if (![data isKindOfClass:[NSData class]] || [data length] == 0) {
        [self showSimpleAlertWithTitle:@"Import JSON" message:[NSString stringWithFormat:@"Could not read JSON: %@", [readError localizedDescription] ?: @"unknown error"]];
        return;
    }

    NSError *jsonError = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (!json) {
        [self showSimpleAlertWithTitle:@"Import JSON" message:[NSString stringWithFormat:@"Could not parse JSON: %@", [jsonError localizedDescription] ?: @"unknown error"]];
        return;
    }
    NSArray *requestedIDs = IGPlaylistJSONPersistentIDsFromJSONObject(json);
    if ([requestedIDs count] == 0) {
        [self showSimpleAlertWithTitle:@"Import JSON" message:@"This file does not contain readable iTunes persistent IDs."];
        return;
    }
    if ([requestedIDs count] > 10000) {
        [self showSimpleAlertWithTitle:@"Import JSON" message:@"This JSON selection is too large. Please import no more than 10,000 track IDs at once."];
        return;
    }
    if (![self prepareITunesForUserAction:@"creating a playlist from JSON"]) {
        return;
    }

    NSString *suggestedName = IGPlaylistJSONPlaylistNameFromJSONObject(json);
    [self clearLogView];
    self.isRunning = YES;
    [self updateStartButtonState];
    self.statusLabel.stringValue = @"Checking JSON tracks against iTunes...";
    self.progressIndicator.indeterminate = YES;
    [self.progressIndicator startAnimation:nil];
    [self log:[NSString stringWithFormat:@"Import JSON contains %lu requested track IDs.", (unsigned long)[requestedIDs count]]];

    [[IGiTunesService sharedService] fetchAllTracksWithProgress:^(NSInteger current, NSInteger total) {
        self.progressIndicator.indeterminate = NO;
        self.progressIndicator.maxValue = total;
        self.progressIndicator.doubleValue = current;
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Checking %ld / %ld iTunes tracks...", (long)current, (long)total];
    } completion:^(NSArray *tracks) {
        if ([tracks count] == 0) {
            NSString *message = @"No readable iTunes tracks were returned.";
            [self log:message];
            [self finishLibraryJSONOperationWithStatus:message error:YES];
            return;
        }

        NSMutableSet *availableIDs = [NSMutableSet setWithCapacity:[tracks count]];
        for (IGTrack *track in tracks) {
            if ([track isKindOfClass:[IGTrack class]] && [track.persistentID length] > 0) {
                [availableIDs addObject:[[track.persistentID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString]];
            }
        }

        NSMutableArray *matchedIDs = [NSMutableArray array];
        for (NSString *pid in requestedIDs) {
            if ([availableIDs containsObject:pid]) {
                [matchedIDs addObject:pid];
            }
        }

        NSUInteger missingCount = [requestedIDs count] >= [matchedIDs count] ? ([requestedIDs count] - [matchedIDs count]) : 0;
        [self log:[NSString stringWithFormat:@"Matched %lu IDs, missing %lu.", (unsigned long)[matchedIDs count], (unsigned long)missingCount]];
        if ([matchedIDs count] == 0) {
            NSString *message = @"None of the JSON tracks were found in this iTunes library.";
            [self finishLibraryJSONOperationWithStatus:message error:YES];
            [self showSimpleAlertWithTitle:@"Import JSON" message:message];
            return;
        }

        if (![self confirmPlaylistImportWithRequestedCount:[requestedIDs count] matchedCount:[matchedIDs count] missingCount:missingCount]) {
            [self finishLibraryJSONOperationWithStatus:@"Playlist import cancelled." error:NO];
            return;
        }

        NSString *playlistName = [self promptForPlaylistNameWithDefault:suggestedName];
        if ([playlistName length] == 0) {
            [self finishLibraryJSONOperationWithStatus:@"Playlist import cancelled." error:NO];
            return;
        }

        self.statusLabel.stringValue = @"Creating iTunes playlist...";
        self.progressIndicator.indeterminate = YES;
        [self.progressIndicator startAnimation:nil];
        [self log:[NSString stringWithFormat:@"Creating playlist '%@' from JSON selection...", playlistName]];

        [[IGiTunesService sharedService] createPlaylistWithName:playlistName persistentIDs:matchedIDs completion:^(NSInteger addedCount) {
            NSString *message = [NSString stringWithFormat:@"Created playlist '%@' with %ld tracks.", playlistName, (long)addedCount];
            if (addedCount <= 0) {
                message = @"iTunes did not add any tracks to the playlist.";
            }
            [self log:message];
            [self finishLibraryJSONOperationWithStatus:message error:(addedCount <= 0)];
        }];
    }];
}

- (void)startClicked:(id)sender {
    if (![self hasSelectedTags]) {
        return;
    }
    if (![self prepareITunesForUserAction:@"iTunes Media Fixer"]) {
        return;
    }
    [self clearLogView];
    [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"MediaFixer start options album=%ld title=%ld artist=%ld genre=%ld trackNumber=%ld lyrics=%ld",
                                  (long)self.albumCheckbox.state,
                                  (long)self.titleCheckbox.state,
                                  (long)self.artistCheckbox.state,
                                  (long)self.genreCheckbox.state,
                                  (long)self.trackNumberCheckbox.state,
                                  (long)self.lyricsCheckbox.state]];

    self.isRunning = YES;
    [self updateStartButtonState];
    self.statusLabel.stringValue = @"Checking iTunes library...";

    [[IGiTunesService sharedService] fetchLibraryTrackCountWithCompletion:^(NSInteger trackCount, NSString *errorMessage) {
        if (trackCount < 0) {
            self.statusLabel.stringValue = errorMessage ?: @"Could not read iTunes library.";
            [self log:self.statusLabel.stringValue];
            self.isRunning = NO;
            [self updateStartButtonState];
            [IGNotificationView showInView:self.view message:self.statusLabel.stringValue isError:YES];
            return;
        }
        if (trackCount == 0) {
            self.statusLabel.stringValue = @"iTunes has no tracks. There is no metadata to update.";
            [self log:self.statusLabel.stringValue];
            self.isRunning = NO;
            [self updateStartButtonState];
            [IGNotificationView showInView:self.view message:self.statusLabel.stringValue isError:YES];
            return;
        }

        [self log:@"Phase 1: Scanning for split albums..."];
        self.statusLabel.stringValue = @"Scanning for merge candidates...";
        self.progressIndicator.indeterminate = YES;
        [self.progressIndicator startAnimation:nil];

        [[IGMediaFixerManager sharedManager] getMergeCandidatesWithCompletion:^(NSArray *candidates) {
            if (candidates.count > 0) {
                [self log:[NSString stringWithFormat:@"Found %ld split albums to merge.", (long)candidates.count]];
                [self runMergePhase:candidates];
            } else {
                [self log:@"No split albums found. Proceeding to metadata check."];
                [self runMetadataPhase];
            }
        }];
    }];
}

- (void)runMergePhase:(NSArray *)candidates {
    self.progressIndicator.indeterminate = NO;
    self.progressIndicator.maxValue = candidates.count;
    self.progressIndicator.doubleValue = 0;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __block NSInteger processed = 0;
        IGiTunesService *service = [IGiTunesService sharedService];

        for (NSDictionary *item in candidates) {
            NSString *main = item[@"main"];
            NSArray *targets = item[@"targets"];
            NSString *mainLiteral = IGFixerAppleScriptLiteral(main);

            dispatch_async(dispatch_get_main_queue(), ^{
                self.statusLabel.stringValue = [NSString stringWithFormat:@"Merging: %@", main];
            });

            for (NSDictionary *t in targets) {
                @try {
                    NSString *pid = t[@"pid"];
                    NSString *script = [NSString stringWithFormat:@"tell application \"iTunes\" to set album of (some track of library playlist 1 whose persistent ID is %@) to %@", IGFixerAppleScriptLiteral(pid), mainLiteral];
                    [service runAppleScriptNamed:@"mediaFixer.mergeAlbum" source:script];
                } @catch (NSException *ex) {
                    NSLog(@"Error merging split album: %@", ex);
                }
            }

            processed++;
            dispatch_async(dispatch_get_main_queue(), ^{
                self.progressIndicator.doubleValue = processed;
            });
            [self log:[NSString stringWithFormat:@"Merged variants into: %@", main]];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self log:@"Merge phase complete."];
            [self runMetadataPhase];
        });
    });
}

- (void)runMetadataPhase {
    [self log:@"Phase 2: Fetching missing metadata..."];
    
    NSDictionary *options = @{
        @"album": @(self.albumCheckbox.state == NSOnState),
        @"title": @(self.titleCheckbox.state == NSOnState),
        @"artist": @(self.artistCheckbox.state == NSOnState),
        @"genre": @(self.genreCheckbox.state == NSOnState),
        @"trackNumber": @(self.trackNumberCheckbox.state == NSOnState),
        @"lyrics": @(self.lyricsCheckbox.state == NSOnState)
    };
    
    [[IGMediaFixerManager sharedManager] runMetadataFixWithOptions:options progress:^(NSInteger current, NSInteger total) {
        self.progressIndicator.maxValue = total;
        self.progressIndicator.doubleValue = current;
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Processing track %ld of %ld...", (long)current, (long)total];
    } completion:^{
        self.statusLabel.stringValue = [[IGLocalizationService sharedService] t:@"done"];
        [self log:@"All metadata tasks finished."];
        self.isRunning = NO;
        [self updateStartButtonState];
        [self.progressIndicator stopAnimation:nil];
        self.progressIndicator.indeterminate = NO;
        self.progressIndicator.doubleValue = self.progressIndicator.maxValue;
        
        [IGNotificationView showInView:self.view message:[[IGLocalizationService sharedService] t:@"done"] isError:NO];
    }];
}

@end
