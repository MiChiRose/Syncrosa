#import "IGFileFixerViewController.h"
#import "IGLocalizationService.h"
#import "IGNotificationView.h"
#import "IGiTunesService.h"
#import "IGLyricsService.h"
#import <AVFoundation/AVFoundation.h>

@interface IGFileFixerViewController ()
@property (nonatomic, strong) NSTextField *folderPathField;
@property (nonatomic, strong) NSButton *selectFolderButton;
@property (nonatomic, strong) NSButton *downloadCoversButton;
@property (nonatomic, strong) NSButton *fixButton;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextView *logView;
@property (nonatomic, strong) NSArray<NSURL *> *foundFiles;
@property (nonatomic, assign) BOOL isProcessing;

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
    helpButton.bezelStyle = NSBezelStyleHelpButton;
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
    
    y -= 45;
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
                                                  styleMask:NSWindowStyleMaskTitled
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

- (void)log:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *line = [NSString stringWithFormat:@"> %@\n", text];
        NSAttributedString *attrLine = [[NSAttributedString alloc] initWithString:line attributes:@{NSForegroundColorAttributeName: [NSColor greenColor]}];
        [self.logView.textStorage appendAttributedString:attrLine];
        [self.logView scrollRangeToVisible:NSMakeRange(self.logView.string.length, 0)];
    });
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
    
    self.foundFiles = matches;
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    self.statusLabel.stringValue = [lang t:@"files_to_process" args:@[@([matches count])]];
    [self log:[NSString stringWithFormat:@"Scanned folder recursively: Found %ld music files.", (long)matches.count]];
    self.fixButton.enabled = (matches.count > 0);
}

- (void)fixClicked:(id)sender {
    if (self.isProcessing) return;
    
    self.isProcessing = YES;
    self.fixButton.enabled = NO;
    self.selectFolderButton.enabled = NO;
    self.downloadCoversButton.enabled = NO;
    
    [self log:@"Starting folder fix process..."];
    self.progressIndicator.maxValue = self.foundFiles.count;
    self.progressIndicator.doubleValue = 0;
    
    [self processFileAtIndex:0];
}

- (void)processFileAtIndex:(NSInteger)index {
    if (index >= self.foundFiles.count) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.isProcessing = NO;
            self.fixButton.enabled = YES;
            self.selectFolderButton.enabled = YES;
            self.downloadCoversButton.enabled = YES;
            self.statusLabel.stringValue = [[IGLocalizationService sharedService] t:@"done"];
            [self log:@"Process finished successfully."];
            
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
    
    [self fixFileAtURL:fileUrl downloadCover:downloadCovers completion:^(BOOL success) {
        if (success) {
            [self log:[NSString stringWithFormat:@"Successfully fixed: %@", fileName]];
        } else {
            [self log:[NSString stringWithFormat:@"Failed to fix: %@", fileName]];
        }
        
        [self processFileAtIndex:index + 1];
    }];
}

#pragma mark - Metadata Fixing Core Logic

- (void)extractMetadataFromFile:(NSURL *)fileURL 
                      completion:(void(^)(NSString *artist, NSString *title, NSData *coverData))completionBlock {
    AVAsset *asset = [AVAsset assetWithURL:fileURL];
    
    [asset loadValuesAsynchronouslyForKeys:@[@"commonMetadata"] completionHandler:^{
        NSError *error = nil;
        AVKeyValueStatus status = [asset statusOfValueForKey:@"commonMetadata" error:&error];
        
        __block NSString *artist = nil;
        __block NSString *title = nil;
        __block NSData *coverData = nil;
        
        if (status == AVKeyValueStatusLoaded) {
            NSArray *items = [asset commonMetadata];
            for (AVMetadataItem *item in items) {
                NSString *key = item.commonKey;
                if ([key isEqualToString:AVMetadataCommonKeyArtist]) {
                    artist = item.stringValue;
                } else if ([key isEqualToString:AVMetadataCommonKeyTitle]) {
                    title = item.stringValue;
                } else if ([key isEqualToString:AVMetadataCommonKeyArtwork]) {
                    if ([item.value isKindOfClass:[NSData class]]) {
                        coverData = (NSData *)item.value;
                    } else if ([item.value isKindOfClass:[NSDictionary class]]) {
                        coverData = [(NSDictionary *)item.value objectForKey:@"data"];
                    }
                }
            }
        }
        
        completionBlock(artist, title, coverData);
    }];
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
    NSString *query = [NSString stringWithFormat:@"%@ %@", title, artist];
    NSString *encodedQuery = [query stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *urlString = [NSString stringWithFormat:@"https://itunes.apple.com/search?term=%@&entity=song&limit=1", encodedQuery];
    NSURL *url = [NSURL URLWithString:urlString];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url 
                                                           completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            NSLog(@"NSURLSession failed (potential TLS error). Trying curl fallback...");
            [self fetchITunesMetadataWithCurl:urlString completion:completionBlock];
            return;
        }
        
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSArray *results = json[@"results"];
        if (results.count > 0) {
            completionBlock(results[0]);
        } else {
            completionBlock(nil);
        }
    }];
    [task resume];
}

- (void)fetchITunesMetadataWithCurl:(NSString *)urlString completion:(void(^)(NSDictionary *result))completionBlock {
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/curl"];
    [task setArguments:@[@"-s", @"-L", urlString]];
    
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    
    @try {
        [task launch];
        [task waitUntilExit];
        
        NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
        if (data.length > 0) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSArray *results = json[@"results"];
            if (results.count > 0) {
                completionBlock(results[0]);
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
    NSURL *url = [NSURL URLWithString:highResUrlStr];
    NSURL *destinationURL = [dirURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.jpg", baseName]];
    
    NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithURL:url 
                                                                     completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (!error && location) {
            NSFileManager *fm = [NSFileManager defaultManager];
            if ([fm fileExistsAtPath:destinationURL.path]) {
                [fm removeItemAtURL:destinationURL error:nil];
            }
            if ([fm moveItemAtURL:location toURL:destinationURL error:nil]) {
                completionBlock(YES);
                return;
            }
        }
        
        [self downloadCoverWithCurl:highResUrlStr destination:destinationURL completion:completionBlock];
    }];
    [task resume];
}

- (void)downloadCoverWithCurl:(NSString *)urlString 
                  destination:(NSURL *)destURL 
                   completion:(void(^)(BOOL success))completionBlock {
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/curl"];
    [task setArguments:@[@"-s", @"-L", @"-o", destURL.path, urlString]];
    
    @try {
        [task launch];
        [task waitUntilExit];
        BOOL success = [[NSFileManager defaultManager] fileExistsAtPath:destURL.path];
        completionBlock(success);
    } @catch (NSException *exception) {
        NSLog(@"Curl cover art download failed: %@", exception.reason);
        completionBlock(NO);
    }
}

- (void)fixFileAtURL:(NSURL *)fileURL downloadCover:(BOOL)downloadCover completion:(void(^)(BOOL success))completionBlock {
    [self extractMetadataFromFile:fileURL completion:^(NSString *artist, NSString *title, NSData *coverData) {
        __block NSString *currentArtist = artist;
        __block NSString *currentTitle = title;
        
        if (currentArtist.length == 0 || currentTitle.length == 0) {
            NSDictionary *parsed = [self parseArtistTitleFromFilename:[fileURL lastPathComponent]];
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
            
            NSString *newName = [NSString stringWithFormat:@"%@ - %@.%@", sanitizedArtist, sanitizedTitle, [fileURL pathExtension]];
            NSURL *newURL = [[fileURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:newName];
            
            NSFileManager *fm = [NSFileManager defaultManager];
            NSError *moveError = nil;
            BOOL renameSuccess = YES;
            
            if (![fileURL.path isEqualToString:newURL.path]) {
                if ([fm fileExistsAtPath:newURL.path]) {
                    [fm removeItemAtURL:newURL error:nil];
                }
                renameSuccess = [fm moveItemAtURL:fileURL toURL:newURL error:&moveError];
            }
            
            if (renameSuccess) {
                // Update iTunes/Music.app via AppleScript if the track exists in iTunes (by checking original path or new path)
                @try {
                    NSMutableArray *updates = [NSMutableArray array];
                    if (self.albumCheckbox.state == NSOnState && result[@"collectionName"]) {
                        [updates addObject:[NSString stringWithFormat:@"set album of t to \"%@\"", [result[@"collectionName"] stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]]];
                    }
                    if (self.titleCheckbox.state == NSOnState && result[@"trackName"]) {
                        [updates addObject:[NSString stringWithFormat:@"set name of t to \"%@\"", [result[@"trackName"] stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]]];
                    }
                    if (self.artistCheckbox.state == NSOnState && result[@"artistName"]) {
                        [updates addObject:[NSString stringWithFormat:@"set artist of t to \"%@\"", [result[@"artistName"] stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]]];
                    }
                    if (self.genreCheckbox.state == NSOnState && result[@"primaryGenreName"]) {
                        [updates addObject:[NSString stringWithFormat:@"set genre of t to \"%@\"", [result[@"primaryGenreName"] stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]]];
                    }
                    if (self.trackNumberCheckbox.state == NSOnState && result[@"trackNumber"]) {
                        [updates addObject:[NSString stringWithFormat:@"set track number of t to %@", result[@"trackNumber"]]];
                    }
                    
                    // Fetch and update lyrics if lyrics checkbox is checked
                    if (self.lyricsCheckbox.state == NSOnState) {
                        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
                        __block NSString *fetchedLyrics = nil;
                        [[IGLyricsService sharedService] fetchLyricsForArtist:finalArtist title:finalTitle completion:^(NSString *lyrics) {
                            fetchedLyrics = lyrics;
                            dispatch_semaphore_signal(sema);
                        }];
                        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
                        
                        if (fetchedLyrics) {
                            [updates addObject:[NSString stringWithFormat:@"set lyrics of t to \"%@\"", [fetchedLyrics stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]]];
                        }
                    }
                    
                    if (updates.count > 0) {
                        // We check both the old path and the new path to find the track in iTunes
                        NSString *updateScript = [NSString stringWithFormat:
                            @"tell application \"iTunes\"\n"
                            "    try\n"
                            "        set t to (some track of library playlist 1 whose location is POSIX file \"%@\")\n"
                            "        %@\n"
                            "    on error\n"
                            "        try\n"
                            "            set t to (some track of library playlist 1 whose location is POSIX file \"%@\")\n"
                            "            %@\n"
                            "        end try\n"
                            "    end try\n"
                            "end tell", fileURL.path, [updates componentsJoinedByString:@"\n"], newURL.path, [updates componentsJoinedByString:@"\n"]];
                        [[IGiTunesService sharedService] runAppleScript:updateScript];
                    }
                } @catch (NSException *ex) {
                    NSLog(@"AppleScript write in Folder Fixer failed: %@", ex);
                }
                
                if (downloadCover && result[@"artworkUrl100"]) {
                    [self downloadCoverArtURL:result[@"artworkUrl100"] 
                                   toDirectory:[newURL URLByDeletingLastPathComponent] 
                                      baseName:[NSString stringWithFormat:@"%@ - %@", sanitizedArtist, sanitizedTitle] 
                                    completion:^(BOOL coverSuccess) {
                        completionBlock(YES);
                    }];
                } else {
                    completionBlock(YES);
                }
            } else {
                NSLog(@"Rename failed: %@", moveError.localizedDescription);
                completionBlock(NO);
            }
        }];
    }];
}

- (NSString *)sanitizeFilename:(NSString *)name {
    NSCharacterSet *invalidCharacters = [NSCharacterSet characterSetWithCharactersInString:@"/\\?%*|\"<>:"];
    NSArray *parts = [name componentsSeparatedByCharactersInSet:invalidCharacters];
    return [parts componentsJoinedByString:@"_"];
}

@end
