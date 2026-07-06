#import "IGFileFixerViewController.h"
#import "IGLocalizationService.h"
#import "IGNotificationView.h"
#import "IGiTunesService.h"
#import "IGLyricsService.h"
#import <objc/message.h>

static NSString *IGFileFixerJSONString(id value) {
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

static NSNumber *IGFileFixerJSONNumber(id value) {
    return [value respondsToSelector:@selector(integerValue)] ? value : @(0);
}

static void IGFileFixerAddCACertIfAvailable(NSMutableArray *args) {
    NSString *caPath = [[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"];
    if (caPath.length > 0) {
        [args addObjectsFromArray:@[@"--cacert", caPath]];
    }
}

static NSString *IGFileFixerAppleScriptLiteral(NSString *value) {
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

static NSString *IGFileFixerTempPath(NSString *extension) {
    NSString *baseName = [NSString stringWithFormat:@"syncrosa-curl-%@", [[NSProcessInfo processInfo] globallyUniqueString]];
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[baseName stringByAppendingPathExtension:extension]];
}

static NSData *IGFileFixerRunCurl(NSArray *args, int *statusOut) {
    NSString *stdoutPath = IGFileFixerTempPath(@"stdout");
    NSString *stderrPath = IGFileFixerTempPath(@"stderr");
    NSDictionary *attrs = @{NSFilePosixPermissions: [NSNumber numberWithUnsignedLong:0600]};
    [[NSFileManager defaultManager] createFileAtPath:stdoutPath contents:nil attributes:attrs];
    [[NSFileManager defaultManager] createFileAtPath:stderrPath contents:nil attributes:attrs];

    NSFileHandle *stdoutHandle = [NSFileHandle fileHandleForWritingAtPath:stdoutPath];
    NSFileHandle *stderrHandle = [NSFileHandle fileHandleForWritingAtPath:stderrPath];
    int status = -1;
    NSData *data = nil;

    @try {
        NSTask *task = [[[NSTask alloc] init] autorelease];
        [task setLaunchPath:@"/usr/bin/curl"];
        [task setArguments:args];
        [task setStandardOutput:stdoutHandle];
        [task setStandardError:stderrHandle];
        [task launch];
        [task waitUntilExit];
        status = [task terminationStatus];
        [stdoutHandle closeFile];
        [stderrHandle closeFile];
        data = [NSData dataWithContentsOfFile:stdoutPath];
    } @catch (NSException *exception) {
        NSLog(@"Curl in Folder Fixer failed: %@", exception.reason);
        [stdoutHandle closeFile];
        [stderrHandle closeFile];
    }

    [[NSFileManager defaultManager] removeItemAtPath:stdoutPath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:stderrPath error:nil];
    if (statusOut) *statusOut = status;
    return data;
}

static void IGFileFixerRecordHistory(NSString *tool, NSString *title, NSString *status, NSString *message, NSInteger affectedCount) {
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
        @"tool": tool ?: @"",
        @"title": title ?: @"",
        @"status": status ?: @"",
        @"message": message ?: @"",
        @"createdAt": @([[NSDate date] timeIntervalSince1970]),
        @"affectedCount": @(affectedCount),
        @"backupPath": @""
    };
    [entries insertObject:entry atIndex:0];
    while (entries.count > 250) {
        [entries removeLastObject];
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:entries options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:path atomically:YES];
}

@interface IGFileFixerViewController ()
@property (nonatomic, strong) NSTextField *folderPathField;
@property (nonatomic, strong) NSButton *selectFolderButton;
@property (nonatomic, strong) NSButton *downloadCoversButton;
@property (nonatomic, strong) NSButton *cleanFilenamesButton;
@property (nonatomic, strong) NSButton *fixButton;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextView *logView;
@property (nonatomic, strong) NSArray *foundFiles;
@property (nonatomic, assign) BOOL isProcessing;
@property (nonatomic, assign) BOOL underscoreNormalizationEnabledForRun;
@property (nonatomic, assign) NSInteger folderFixSuccessCount;
@property (nonatomic, assign) NSInteger folderFixFailureCount;

@property (nonatomic, strong) NSButton *selectAllCheckbox;
@property (nonatomic, strong) NSButton *albumCheckbox;
@property (nonatomic, strong) NSButton *titleCheckbox;
@property (nonatomic, strong) NSButton *artistCheckbox;
@property (nonatomic, strong) NSButton *genreCheckbox;
@property (nonatomic, strong) NSButton *trackNumberCheckbox;
@property (nonatomic, strong) NSButton *lyricsCheckbox;
@property (nonatomic, strong) NSWindow *helpSheetWindow;
@end

@implementation IGFileFixerViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 480)];
    [self setupUI];
}

- (void)setupUI {
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    CGFloat y = 440;

    NSTextField *titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 30)];
    titleLabel.stringValue = [lang t:@"file_fixing"];
    titleLabel.font = [NSFont boldSystemFontOfSize:18];
    titleLabel.editable = NO;
    titleLabel.bordered = NO;
    titleLabel.drawsBackground = NO;
    titleLabel.alignment = NSCenterTextAlignment;
    [self.view addSubview:titleLabel];

    NSButton *helpButton = [[NSButton alloc] initWithFrame:NSMakeRect(520, y, 25, 25)];
    helpButton.bezelStyle = NSHelpButtonBezelStyle;
    helpButton.title = @"";
    helpButton.target = self;
    helpButton.action = @selector(helpClicked:);
    [self.view addSubview:helpButton];

    y -= 35;
    NSTextField *instrLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(40, y, 500, 35)];
    instrLabel.stringValue = [lang t:@"file_instr"];
    instrLabel.font = [NSFont systemFontOfSize:11];
    instrLabel.textColor = [NSColor grayColor];
    instrLabel.editable = NO;
    instrLabel.bordered = NO;
    instrLabel.drawsBackground = NO;
    instrLabel.alignment = NSCenterTextAlignment;
    [self.view addSubview:instrLabel];

    y -= 35;
    self.folderPathField = [[NSTextField alloc] initWithFrame:NSMakeRect(40, y, 360, 24)];
    self.folderPathField.editable = NO;
    [[self.folderPathField cell] setPlaceholderString:[lang t:@"no_folder"]];
    [self.view addSubview:self.folderPathField];

    self.selectFolderButton = [[NSButton alloc] initWithFrame:NSMakeRect(410, y-2, 130, 30)];
    self.selectFolderButton.title = [lang t:@"select_folder"];
    self.selectFolderButton.bezelStyle = NSRoundedBezelStyle;
    self.selectFolderButton.target = self;
    self.selectFolderButton.action = @selector(selectFolderClicked:);
    [self.view addSubview:self.selectFolderButton];

    // Grid of Checkboxes
    y -= 30;
    self.selectAllCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(40, y, 150, 20)];
    [self.selectAllCheckbox setButtonType:NSSwitchButton];
    self.selectAllCheckbox.title = [lang t:@"select_all"];
    self.selectAllCheckbox.target = self;
    self.selectAllCheckbox.action = @selector(selectAllClicked:);
    self.selectAllCheckbox.state = NSOnState;
    [self.view addSubview:self.selectAllCheckbox];

    y -= 25;
    self.albumCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(40, y, 140, 20)];
    [self.albumCheckbox setButtonType:NSSwitchButton];
    self.albumCheckbox.title = [lang t:@"tag_album"];
    self.albumCheckbox.state = NSOnState;
    [self.view addSubview:self.albumCheckbox];

    self.titleCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(200, y, 140, 20)];
    [self.titleCheckbox setButtonType:NSSwitchButton];
    self.titleCheckbox.title = [lang t:@"tag_title"];
    self.titleCheckbox.state = NSOnState;
    [self.view addSubview:self.titleCheckbox];

    self.artistCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(360, y, 140, 20)];
    [self.artistCheckbox setButtonType:NSSwitchButton];
    self.artistCheckbox.title = [lang t:@"tag_artist"];
    self.artistCheckbox.state = NSOnState;
    [self.view addSubview:self.artistCheckbox];

    y -= 25;
    self.genreCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(40, y, 140, 20)];
    [self.genreCheckbox setButtonType:NSSwitchButton];
    self.genreCheckbox.title = [lang t:@"tag_genre"];
    self.genreCheckbox.state = NSOnState;
    [self.view addSubview:self.genreCheckbox];

    self.trackNumberCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(200, y, 140, 20)];
    [self.trackNumberCheckbox setButtonType:NSSwitchButton];
    self.trackNumberCheckbox.title = [lang t:@"tag_track_number"];
    self.trackNumberCheckbox.state = NSOnState;
    [self.view addSubview:self.trackNumberCheckbox];

    self.lyricsCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(360, y, 140, 20)];
    [self.lyricsCheckbox setButtonType:NSSwitchButton];
    self.lyricsCheckbox.title = [lang t:@"tag_lyrics"];
    self.lyricsCheckbox.state = NSOnState;
    [self.view addSubview:self.lyricsCheckbox];

    y -= 28;
    self.downloadCoversButton = [[NSButton alloc] initWithFrame:NSMakeRect(190, y, 200, 20)];
    [self.downloadCoversButton setButtonType:NSSwitchButton];
    self.downloadCoversButton.title = @"Download Album Covers";
    self.downloadCoversButton.state = NSOnState;
    [self.view addSubview:self.downloadCoversButton];

    y -= 24;
    self.cleanFilenamesButton = [[NSButton alloc] initWithFrame:NSMakeRect(190, y - 4, 200, 30)];
    self.cleanFilenamesButton.title = @"Clean Filenames";
    self.cleanFilenamesButton.bezelStyle = NSRoundedBezelStyle;
    self.cleanFilenamesButton.enabled = NO;
    self.cleanFilenamesButton.target = self;
    self.cleanFilenamesButton.action = @selector(cleanFilenamesClicked:);
    [self.view addSubview:self.cleanFilenamesButton];

    y -= 42;
    self.fixButton = [[NSButton alloc] initWithFrame:NSMakeRect(190, y, 200, 40)];
    self.fixButton.title = [lang t:@"fix_all"];
    self.fixButton.bezelStyle = NSTexturedRoundedBezelStyle;
    self.fixButton.enabled = NO;
    self.fixButton.target = self;
    self.fixButton.action = @selector(fixClicked:);
    [self.view addSubview:self.fixButton];

    y -= 25;
    self.progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(40, y, 500, 20)];
    self.progressIndicator.style = NSProgressIndicatorBarStyle;
    self.progressIndicator.indeterminate = NO;
    [self.view addSubview:self.progressIndicator];

    y -= 110;
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(40, y, 500, 105)];
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
    self.statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(40, y, 500, 20)];
    self.statusLabel.stringValue = [lang t:@"ready"];
    self.statusLabel.editable = NO;
    self.statusLabel.bordered = NO;
    self.statusLabel.drawsBackground = NO;
    self.statusLabel.alignment = NSCenterTextAlignment;
    [self.view addSubview:self.statusLabel];

    // Footer
    NSTextField *footer = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 10, 540, 35)];
    footer.stringValue = [lang t:@"footer"];
    footer.font = [NSFont systemFontOfSize:10];
    footer.textColor = [NSColor grayColor];
    footer.alignment = NSCenterTextAlignment;
    footer.editable = NO;
    footer.bordered = NO;
    footer.drawsBackground = NO;
    [self.view addSubview:footer];
}

- (void)selectAllClicked:(id)sender {
    NSInteger state = self.selectAllCheckbox.state;
    self.albumCheckbox.state = state;
    self.titleCheckbox.state = state;
    self.artistCheckbox.state = state;
    self.genreCheckbox.state = state;
    self.trackNumberCheckbox.state = state;
    self.lyricsCheckbox.state = state;
}

- (void)helpClicked:(id)sender {
    NSString *helpText = @"Folder Media Fixer Help\n\n"
                          "This utility scans a local directory for music files and performs the following actions:\n\n"
                          "1. Standard Rename: Renames music files on your disk to the standard format 'Artist - Title' using metadata parsed from filenames or the iTunes API.\n"
                          "2. iTunes Tag Sync: If the file is part of your iTunes/Music library, it runs an AppleScript to sync only the checked tags (Album, Title, Artist, Genre, Track Number, and Lyrics).\n"
                          "3. Cover Art: Downloads the album cover as a separate JPEG file in the same directory if 'Download Album Covers' is checked.\n\n"
                          "Every individual track write operation is wrapped in a safe block. If a write fails or the track is not present in iTunes/Music, it will skip without interrupting the overall process.";

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

- (void)log:(NSString *)text {
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
    self.fixButton.enabled = NO;
    self.statusLabel.stringValue = @"Scanning folder...";
    [self clearLogView];
    [self log:[NSString stringWithFormat:@"Scanning folder recursively: %@", url.path ?: @""]];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *extensions = @[@"mp3", @"m4a", @"wav", @"flac", @"alac", @"aiff"];
        NSMutableArray *matches = [NSMutableArray array];

        NSDirectoryEnumerator *enumerator = [fm enumeratorAtURL:url
                                     includingPropertiesForKeys:nil
                                                        options:NSDirectoryEnumerationSkipsHiddenFiles
                                                   errorHandler:nil];

        for (NSURL *fileUrl in enumerator) {
            NSNumber *isDirectory = nil;
            [fileUrl getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
            if ([isDirectory boolValue]) continue;

            if ([extensions containsObject:[[fileUrl pathExtension] lowercaseString]]) {
                [matches addObject:fileUrl];
            }
        }

        NSArray *result = [matches copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.foundFiles = result;
            IGLocalizationService *lang = [IGLocalizationService sharedService];
            self.statusLabel.stringValue = [lang t:@"files_to_process" args:@[@([result count])]];
            [self log:[NSString stringWithFormat:@"Scanned folder recursively: Found %ld music files.", (long)result.count]];
            self.fixButton.enabled = (result.count > 0);
            self.cleanFilenamesButton.enabled = (result.count > 0);
#if !__has_feature(objc_arc)
            [result release];
#endif
        });
#if !__has_feature(objc_arc)
        [pool drain];
#endif
    });
}

- (void)fixClicked:(id)sender {
    if (self.isProcessing) return;

    self.isProcessing = YES;
    self.underscoreNormalizationEnabledForRun = NO;
    self.folderFixSuccessCount = 0;
    self.folderFixFailureCount = 0;
    self.fixButton.enabled = NO;
    self.selectFolderButton.enabled = NO;
    self.downloadCoversButton.enabled = NO;
    self.cleanFilenamesButton.enabled = NO;

    [self clearLogView];
    [self log:@"Starting folder fix process..."];
    self.progressIndicator.maxValue = self.foundFiles.count;
    self.progressIndicator.doubleValue = 0;

    [self processFileAtIndex:0];
}

- (void)cleanFilenamesClicked:(id)sender {
    if (self.isProcessing || self.foundFiles.count == 0) return;

    self.isProcessing = YES;
    self.fixButton.enabled = NO;
    self.cleanFilenamesButton.enabled = NO;
    self.selectFolderButton.enabled = NO;
    self.downloadCoversButton.enabled = NO;

    [self clearLogView];
    [self log:@"Starting filename cleaner..."];
    self.statusLabel.stringValue = @"Cleaning filenames...";
    self.progressIndicator.maxValue = self.foundFiles.count;
    self.progressIndicator.doubleValue = 0;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSMutableArray *updatedFiles = [NSMutableArray arrayWithCapacity:self.foundFiles.count];
        __block BOOL failed = NO;
        __block NSInteger renamed = 0;
        NSInteger currentIndex = 0;

        for (NSURL *fileURL in self.foundFiles) {
            if (failed) break;
            currentIndex++;
            dispatch_async(dispatch_get_main_queue(), ^{
                self.progressIndicator.doubleValue = currentIndex;
                [self log:[NSString stringWithFormat:@"Checking: %@", fileURL.lastPathComponent ?: @""]];
            });

            NSError *error = nil;
            NSURL *newURL = [self URLByReplacingUnderscoresInFilenameForURL:fileURL error:&error];
            if (!newURL) {
                failed = YES;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self log:[NSString stringWithFormat:@"ERROR: %@", error.localizedDescription ?: @"Could not rename file."]];
                });
                break;
            }

            if (![newURL.path isEqualToString:fileURL.path]) {
                renamed++;
            }
            [updatedFiles addObject:newURL];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self log:[NSString stringWithFormat:@"OK: %@", newURL.lastPathComponent ?: @""]];
            });
        }

        if (failed && currentIndex > 0 && currentIndex - 1 < self.foundFiles.count) {
            NSInteger remainingIndex = currentIndex - 1;
            while (remainingIndex < self.foundFiles.count) {
                [updatedFiles addObject:[self.foundFiles objectAtIndex:remainingIndex]];
                remainingIndex++;
            }
        }

        NSArray *finalFiles = [updatedFiles copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.foundFiles = finalFiles;
            self.isProcessing = NO;
            self.fixButton.enabled = (self.foundFiles.count > 0);
            self.cleanFilenamesButton.enabled = (self.foundFiles.count > 0);
            self.selectFolderButton.enabled = YES;
            self.downloadCoversButton.enabled = YES;
            self.statusLabel.stringValue = failed ? @"Filename Cleaner stopped after an error." : [NSString stringWithFormat:@"Filename Cleaner finished. Renamed: %ld.", (long)renamed];
            [self log:self.statusLabel.stringValue];
            IGFileFixerRecordHistory(@"Filename Cleaner", @"Clean Filenames", failed ? @"FAIL" : @"OK", self.statusLabel.stringValue, renamed);
#if !__has_feature(objc_arc)
            [finalFiles release];
#endif
        });
#if !__has_feature(objc_arc)
        [pool drain];
#endif
    });
}

- (void)processFileAtIndex:(NSInteger)index {
    if (index >= self.foundFiles.count) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.isProcessing = NO;
            self.fixButton.enabled = YES;
            self.selectFolderButton.enabled = YES;
            self.downloadCoversButton.enabled = YES;
            self.cleanFilenamesButton.enabled = (self.foundFiles.count > 0);
            NSString *historyStatus = self.folderFixFailureCount > 0 ? @"WARN" : @"OK";
            NSString *historyMessage = self.folderFixFailureCount > 0 ?
                [NSString stringWithFormat:@"Process finished with %ld failed files and %ld successful files.", (long)self.folderFixFailureCount, (long)self.folderFixSuccessCount] :
                @"Process finished successfully.";
            self.statusLabel.stringValue = [[IGLocalizationService sharedService] t:@"done"];
            [self log:historyMessage];
            IGFileFixerRecordHistory(@"Folder Fixer", @"Fix Folder Metadata", historyStatus, historyMessage, self.folderFixSuccessCount);

            [IGNotificationView showInView:self.view message:[[IGLocalizationService sharedService] t:@"done"] isError:NO];
        });
        return;
    }

    NSURL *fileUrl = self.foundFiles[index];
    NSString *fileName = [fileUrl lastPathComponent];

    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Fixing: %@", fileName];
        [self log:[NSString stringWithFormat:@"Processing: %@", fileName]];
        self.progressIndicator.doubleValue = index + 1;
    });

    BOOL downloadCovers = (self.downloadCoversButton.state == NSOnState);
    BOOL updateAlbum = (self.albumCheckbox.state == NSOnState);
    BOOL updateTitle = (self.titleCheckbox.state == NSOnState);
    BOOL updateArtist = (self.artistCheckbox.state == NSOnState);
    BOOL updateGenre = (self.genreCheckbox.state == NSOnState);
    BOOL updateTrackNumber = (self.trackNumberCheckbox.state == NSOnState);
    BOOL updateLyrics = (self.lyricsCheckbox.state == NSOnState);
    BOOL normalizeUnderscores = self.underscoreNormalizationEnabledForRun;
    if (updateLyrics && [[NSUserDefaults standardUserDefaults] boolForKey:@"only_local_mode"]) {
        updateLyrics = NO;
        [self log:@"Only Local Mode enabled: skipping lyrics request."];
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self fixFileAtURL:fileUrl
             downloadCover:downloadCovers
       normalizeUnderscores:normalizeUnderscores
               updateAlbum:updateAlbum
               updateTitle:updateTitle
              updateArtist:updateArtist
               updateGenre:updateGenre
         updateTrackNumber:updateTrackNumber
              updateLyrics:updateLyrics
                completion:^(BOOL success, BOOL underscoreNormalizationFailed) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (underscoreNormalizationFailed) {
                    self.underscoreNormalizationEnabledForRun = NO;
                    [self log:@"Underscore replacement stopped after a safe failure. Other Folder Fixer actions will continue."];
                }
                if (success) {
                    self.folderFixSuccessCount++;
                    [self log:[NSString stringWithFormat:@"Successfully fixed: %@", fileName]];
                } else {
                    self.folderFixFailureCount++;
                    [self log:[NSString stringWithFormat:@"Failed to fix: %@", fileName]];
                }

                [self processFileAtIndex:index + 1];
            });
        }];
    });
}

#pragma mark - Metadata Fixing Core Logic

- (void)extractMetadataFromFile:(NSURL *)fileURL
                      completion:(void(^)(NSString *artist, NSString *title, NSData *coverData))completionBlock {
    static BOOL attemptedAVFoundationLoad = NO;
    static BOOL avFoundationAvailable = NO;
    if (!attemptedAVFoundationLoad) {
        attemptedAVFoundationLoad = YES;
        NSBundle *bundle = [NSBundle bundleWithPath:@"/System/Library/Frameworks/AVFoundation.framework"];
        avFoundationAvailable = ([bundle isLoaded] || [bundle load]);
    }

    Class assetClass = NSClassFromString(@"AVAsset");
    if (!avFoundationAvailable || !assetClass) {
        completionBlock(nil, nil, nil);
        return;
    }

    typedef id (*IGAssetWithURLMessageSend)(id, SEL, NSURL *);
    id asset = ((IGAssetWithURLMessageSend)objc_msgSend)(assetClass, @selector(assetWithURL:), fileURL);
    if (!asset || ![asset respondsToSelector:@selector(loadValuesAsynchronouslyForKeys:completionHandler:)]) {
        completionBlock(nil, nil, nil);
        return;
    }

    typedef void (*IGLoadValuesMessageSend)(id, SEL, NSArray *, void (^)(void));
    ((IGLoadValuesMessageSend)objc_msgSend)(asset, @selector(loadValuesAsynchronouslyForKeys:completionHandler:), @[@"commonMetadata"], ^{
        NSError *error = nil;
        NSInteger status = 0;
        if ([asset respondsToSelector:@selector(statusOfValueForKey:error:)]) {
            typedef NSInteger (*IGStatusMessageSend)(id, SEL, NSString *, NSError **);
            status = ((IGStatusMessageSend)objc_msgSend)(asset, @selector(statusOfValueForKey:error:), @"commonMetadata", &error);
        }

        __block NSString *artist = nil;
        __block NSString *title = nil;
        __block NSData *coverData = nil;

        if (status == 2) {
            NSArray *items = nil;
            @try {
                items = [asset valueForKey:@"commonMetadata"];
            } @catch (NSException *exception) {
                items = nil;
            }

            for (id item in items) {
                NSString *key = nil;
                id value = nil;
                NSString *stringValue = nil;
                @try {
                    key = [item valueForKey:@"commonKey"];
                    value = [item valueForKey:@"value"];
                    stringValue = [item valueForKey:@"stringValue"];
                } @catch (NSException *exception) {
                    continue;
                }

                if ([key isEqualToString:@"artist"]) {
                    artist = stringValue;
                } else if ([key isEqualToString:@"title"]) {
                    title = stringValue;
                } else if ([key isEqualToString:@"artwork"]) {
                    if ([value isKindOfClass:[NSData class]]) {
                        coverData = (NSData *)value;
                    } else if ([value isKindOfClass:[NSDictionary class]]) {
                        coverData = [(NSDictionary *)value objectForKey:@"data"];
                    }
                }
            }
        }

        completionBlock(artist, title, coverData);
    });
}

- (NSDictionary *)parseArtistTitleFromFilename:(NSString *)filename {
    NSString *cleanName = [filename stringByDeletingPathExtension];
    NSArray *parts = [cleanName componentsSeparatedByString:@" - "];

    if (parts.count >= 2) {
        return @{
            @"artist": [parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]],
            @"title": [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
        };
    }

    parts = [cleanName componentsSeparatedByString:@"-"];
    if (parts.count >= 2) {
        return @{
            @"artist": [parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]],
            @"title": [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
        };
    }

    return @{
        @"artist": @"",
        @"title": cleanName
    };
}

- (void)fetchITunesMetadataForTitle:(NSString *)title
                             artist:(NSString *)artist
                         completion:(void(^)(NSDictionary *result))completionBlock {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"only_local_mode"]) {
        [self log:@"Only Local Mode enabled: skipping iTunes Search metadata request."];
        completionBlock(nil);
        return;
    }

    NSString *query = [NSString stringWithFormat:@"%@ %@", title, artist];
    NSString *encodedQuery = [query stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *urlString = [NSString stringWithFormat:@"https://itunes.apple.com/search?term=%@&entity=song&limit=1", encodedQuery];

    [self fetchITunesMetadataWithCurl:urlString completion:completionBlock];
}

- (void)fetchITunesMetadataWithCurl:(NSString *)urlString completion:(void(^)(NSDictionary *result))completionBlock {
    NSMutableArray *args = [NSMutableArray arrayWithArray:@[@"-s", @"-L", @"-f", @"-m", @"20"]];
    IGFileFixerAddCACertIfAvailable(args);
    [args addObject:urlString];

    @try {
        int status = -1;
        NSData *data = IGFileFixerRunCurl(args, &status);
        if (status == 0 && data.length > 0) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSArray *results = json[@"results"];
            if (results.count > 0) {
                NSDictionary *raw = results[0];
                completionBlock(@{
                    @"artistName": IGFileFixerJSONString(raw[@"artistName"]),
                    @"trackName": IGFileFixerJSONString(raw[@"trackName"]),
                    @"collectionName": IGFileFixerJSONString(raw[@"collectionName"]),
                    @"primaryGenreName": IGFileFixerJSONString(raw[@"primaryGenreName"]),
                    @"artworkUrl100": IGFileFixerJSONString(raw[@"artworkUrl100"]),
                    @"trackNumber": IGFileFixerJSONNumber(raw[@"trackNumber"])
                });
                return;
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"Curl iTunes fetch failed: %@", exception.reason);
    }
    completionBlock(nil);
}

- (void)downloadCoverArtURL:(NSString *)urlStr
                  toDirectory:(NSURL *)dirURL
                      baseName:(NSString *)baseName
                    completion:(void(^)(BOOL success))completionBlock {
    NSString *highResUrlStr = [urlStr stringByReplacingOccurrencesOfString:@"100x100bb" withString:@"600x600bb"];
    highResUrlStr = [highResUrlStr stringByReplacingOccurrencesOfString:@"100x100" withString:@"600x600"];
    NSURL *destinationURL = [dirURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.jpg", baseName]];

    [self downloadCoverWithCurl:highResUrlStr destination:destinationURL completion:completionBlock];
}

- (void)downloadCoverWithCurl:(NSString *)urlString
                  destination:(NSURL *)destURL
                   completion:(void(^)(BOOL success))completionBlock {
    NSTask *task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath:@"/usr/bin/curl"];
    NSMutableArray *args = [NSMutableArray arrayWithArray:@[@"-s", @"-L", @"-f", @"-m", @"30"]];
    IGFileFixerAddCACertIfAvailable(args);
    [args addObjectsFromArray:@[@"-o", destURL.path, urlString]];
    [task setArguments:args];

    @try {
        [task launch];
        [task waitUntilExit];
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:destURL.path error:nil];
        BOOL success = (attrs != nil && [[attrs objectForKey:NSFileSize] unsignedLongLongValue] > 0);
        completionBlock(success);
    } @catch (NSException *exception) {
        NSLog(@"Curl cover art download failed: %@", exception.reason);
        completionBlock(NO);
    }
}

- (NSURL *)uniqueDestinationURLForURL:(NSURL *)url excludingURL:(NSURL *)originalURL {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:url.path] || [url.path isEqualToString:originalURL.path]) {
        return url;
    }

    NSURL *dirURL = [url URLByDeletingLastPathComponent];
    NSString *ext = [url pathExtension];
    NSString *base = [[url lastPathComponent] stringByDeletingPathExtension];

    for (NSInteger suffix = 2; suffix < 10000; suffix++) {
        NSString *candidateName = ext.length > 0 ?
            [NSString stringWithFormat:@"%@ - %ld.%@", base, (long)suffix, ext] :
            [NSString stringWithFormat:@"%@ - %ld", base, (long)suffix];
        NSURL *candidateURL = [dirURL URLByAppendingPathComponent:candidateName];
        if (![fm fileExistsAtPath:candidateURL.path]) {
            return candidateURL;
        }
    }

    return nil;
}

- (void)fixFileAtURL:(NSURL *)fileURL
       downloadCover:(BOOL)downloadCover
 normalizeUnderscores:(BOOL)normalizeUnderscores
         updateAlbum:(BOOL)updateAlbum
         updateTitle:(BOOL)updateTitle
        updateArtist:(BOOL)updateArtist
         updateGenre:(BOOL)updateGenre
   updateTrackNumber:(BOOL)updateTrackNumber
        updateLyrics:(BOOL)updateLyrics
          completion:(void(^)(BOOL success, BOOL underscoreNormalizationFailed))completionBlock {
    __block NSURL *workingURL = fileURL;
    __block BOOL underscoreNormalizationFailed = NO;

    if (normalizeUnderscores) {
        NSError *normalizeError = nil;
        NSURL *normalizedURL = [self URLByReplacingUnderscoresInFilenameForURL:fileURL error:&normalizeError];
        if (normalizedURL) {
            workingURL = normalizedURL;
        } else {
            underscoreNormalizationFailed = YES;
            workingURL = fileURL;
        }
    }

    [self extractMetadataFromFile:workingURL completion:^(NSString *artist, NSString *title, NSData *coverData) {
        __block NSString *currentArtist = artist;
        __block NSString *currentTitle = title;

        if (currentArtist.length == 0 || currentTitle.length == 0) {
            NSDictionary *parsed = [self parseArtistTitleFromFilename:[workingURL lastPathComponent]];
            if (currentArtist.length == 0) currentArtist = parsed[@"artist"];
            if (currentTitle.length == 0) currentTitle = parsed[@"title"];
        }

        if (currentArtist.length == 0) currentArtist = @"Unknown Artist";
        if (currentTitle.length == 0) currentTitle = @"Unknown Title";

        [self fetchITunesMetadataForTitle:currentTitle artist:currentArtist completion:^(NSDictionary *result) {
            NSString *finalArtist = result[@"artistName"] ?: currentArtist;
            NSString *finalTitle = result[@"trackName"] ?: currentTitle;

            NSString *sanitizedArtist = [self sanitizeFilename:finalArtist];
            NSString *sanitizedTitle = [self sanitizeFilename:finalTitle];

            NSString *newName = [NSString stringWithFormat:@"%@ - %@.%@", sanitizedArtist, sanitizedTitle, [workingURL pathExtension]];
            NSURL *newURL = [[workingURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:newName];
            newURL = [self uniqueDestinationURLForURL:newURL excludingURL:workingURL];
            if (!newURL) {
                NSLog(@"Could not find a safe destination filename for %@", workingURL.path);
                completionBlock(NO, underscoreNormalizationFailed);
                return;
            }

            NSFileManager *fm = [NSFileManager defaultManager];
            NSError *moveError = nil;
            BOOL renameSuccess = YES;

            if (![workingURL.path isEqualToString:newURL.path]) {
                renameSuccess = [fm moveItemAtURL:workingURL toURL:newURL error:&moveError];
            }

            if (renameSuccess) {
                // Update iTunes/Music.app via AppleScript if the track exists in iTunes (by checking original path or new path)
                @try {
                    NSMutableArray *updates = [NSMutableArray array];
                    if (updateAlbum && [result[@"collectionName"] length] > 0) {
                        [updates addObject:[NSString stringWithFormat:@"set album of t to %@", IGFileFixerAppleScriptLiteral(result[@"collectionName"])]];
                    }
                    if (updateTitle && [result[@"trackName"] length] > 0) {
                        [updates addObject:[NSString stringWithFormat:@"set name of t to %@", IGFileFixerAppleScriptLiteral(result[@"trackName"])]];
                    }
                    if (updateArtist && [result[@"artistName"] length] > 0) {
                        [updates addObject:[NSString stringWithFormat:@"set artist of t to %@", IGFileFixerAppleScriptLiteral(result[@"artistName"])]];
                    }
                    if (updateGenre && [result[@"primaryGenreName"] length] > 0) {
                        [updates addObject:[NSString stringWithFormat:@"set genre of t to %@", IGFileFixerAppleScriptLiteral(result[@"primaryGenreName"])]];
                    }
                    if (updateTrackNumber && [result[@"trackNumber"] integerValue] > 0) {
                        [updates addObject:[NSString stringWithFormat:@"set track number of t to %@", result[@"trackNumber"]]];
                    }

                    // Fetch and update lyrics if lyrics checkbox is checked
                    if (updateLyrics) {
                        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
                        __block NSString *fetchedLyrics = nil;
                        [[IGLyricsService sharedService] fetchLyricsForArtist:finalArtist title:finalTitle completion:^(NSString *lyrics) {
#if !__has_feature(objc_arc)
                            fetchedLyrics = [lyrics copy];
#else
                            fetchedLyrics = lyrics;
#endif
                            dispatch_semaphore_signal(sema);
                        }];
                        long waitResult = dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(35 * NSEC_PER_SEC)));
                        if (waitResult != 0) {
                            NSLog(@"Lyrics timeout for %@ - %@", finalArtist, finalTitle);
                        }

                        if (fetchedLyrics) {
                            [updates addObject:[NSString stringWithFormat:@"set lyrics of t to %@", IGFileFixerAppleScriptLiteral(fetchedLyrics)]];
                        }
#if !__has_feature(objc_arc)
                        [fetchedLyrics release];
#endif
#if !OS_OBJECT_USE_OBJC
                        if (waitResult == 0) {
                            dispatch_release(sema);
                        }
#endif
                    }

                    if (updates.count > 0) {
                        // We check both the old path and the new path to find the track in iTunes
                        NSString *updateScript = [NSString stringWithFormat:
                            @"tell application \"iTunes\"\n"
                            "    try\n"
                            "        set t to (some track of library playlist 1 whose location is POSIX file %@)\n"
                            "        %@\n"
                            "    on error\n"
                            "        try\n"
                            "            set t to (some track of library playlist 1 whose location is POSIX file %@)\n"
                            "            %@\n"
                            "        end try\n"
                            "    end try\n"
                            "end tell",
                            IGFileFixerAppleScriptLiteral(workingURL.path),
                            [updates componentsJoinedByString:@"\n"],
                            IGFileFixerAppleScriptLiteral(newURL.path),
                            [updates componentsJoinedByString:@"\n"]];
                        [[IGiTunesService sharedService] runAppleScriptNamed:@"folderFixer.updateTrack" source:updateScript];
                    }
                } @catch (NSException *ex) {
                    NSLog(@"AppleScript write in Folder Fixer failed: %@", ex);
                }

                if (downloadCover && result[@"artworkUrl100"]) {
                    [self downloadCoverArtURL:result[@"artworkUrl100"]
                                   toDirectory:[newURL URLByDeletingLastPathComponent]
                                      baseName:[NSString stringWithFormat:@"%@ - %@", sanitizedArtist, sanitizedTitle]
                                    completion:^(BOOL coverSuccess) {
                        completionBlock(YES, underscoreNormalizationFailed);
                    }];
                } else {
                    completionBlock(YES, underscoreNormalizationFailed);
                }
            } else {
                NSLog(@"Rename failed: %@", moveError.localizedDescription);
                completionBlock(NO, underscoreNormalizationFailed);
            }
        }];
    }];
}

- (NSString *)sanitizeFilename:(NSString *)name {
    NSCharacterSet *invalidCharacters = [NSCharacterSet characterSetWithCharactersInString:@"/\\?%*|\"<>:"];
    NSArray *parts = [name componentsSeparatedByCharactersInSet:invalidCharacters];
    return [parts componentsJoinedByString:@"_"];
}

- (NSString *)filenameByReplacingUnderscoresWithSpaces:(NSString *)filename {
    NSMutableString *normalized = [[filename stringByReplacingOccurrencesOfString:@"_" withString:@" "] mutableCopy];
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSArray *parts = [normalized componentsSeparatedByCharactersInSet:whitespace];
    NSMutableArray *nonEmpty = [NSMutableArray array];
    for (NSString *part in parts) {
        if (part.length > 0) {
            [nonEmpty addObject:part];
        }
    }
    NSString *result = [nonEmpty componentsJoinedByString:@" "];
#if !__has_feature(objc_arc)
    [normalized release];
#endif
    return result;
}

- (NSURL *)URLByReplacingUnderscoresInFilenameForURL:(NSURL *)fileURL error:(NSError **)error {
    NSString *baseName = [[fileURL lastPathComponent] stringByDeletingPathExtension];
    NSUInteger underscoreCount = 0;
    NSUInteger pos = 0;
    while (pos < baseName.length) {
        unichar ch = [baseName characterAtIndex:pos];
        if (ch == '_') underscoreCount++;
        pos++;
    }
    if (underscoreCount < 2 &&
        [baseName rangeOfString:@"_-_"].location == NSNotFound &&
        [baseName rangeOfString:@"__"].location == NSNotFound) {
        return fileURL;
    }

    NSString *normalizedBase = [self filenameByReplacingUnderscoresWithSpaces:baseName];
    if (normalizedBase.length == 0 || [normalizedBase isEqualToString:baseName]) {
        return fileURL;
    }

    NSString *ext = [fileURL pathExtension];
    NSString *newName = ext.length > 0 ?
        [NSString stringWithFormat:@"%@.%@", normalizedBase, ext] :
        normalizedBase;
    NSURL *desiredURL = [[fileURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:newName];
    NSURL *destinationURL = [self uniqueDestinationURLForURL:desiredURL excludingURL:fileURL];
    if (!destinationURL) {
        return nil;
    }
    if ([destinationURL.path isEqualToString:fileURL.path]) {
        return fileURL;
    }

    if ([[NSFileManager defaultManager] moveItemAtURL:fileURL toURL:destinationURL error:error]) {
        return destinationURL;
    }
    return nil;
}

@end
