#import "IGCoversOptimizerViewController.h"
#import "IGLocalizationService.h"

@interface IGCoversOptimizerViewController ()

@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *selectLabel;
@property (nonatomic, strong) NSPopUpButton *devicePopup;
@property (nonatomic, strong) NSButton *backupButton;
@property (nonatomic, strong) NSButton *optimizeButton;
@property (nonatomic, strong) NSButton *restoreButton;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextView *logView;

@property (nonatomic, assign) BOOL isProcessing;
@property (nonatomic, strong) NSWindow *helpSheetWindow;

@end

@implementation IGCoversOptimizerViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 480)];
    [self setupUI];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(localizationChanged:)
                                                 name:@"IGLanguageChangedNotification"
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupUI {
    IGLocalizationService *lang = [IGLocalizationService sharedService];
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
    
    y -= 45;
    self.selectLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(40, y + 2, 180, 20)];
    self.selectLabel.editable = NO;
    self.selectLabel.bordered = NO;
    self.selectLabel.drawsBackground = NO;
    [self.view addSubview:self.selectLabel];
    
    self.devicePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(230, y, 310, 26) pullsDown:NO];
    [self.devicePopup addItemsWithTitles:@[
        @"iPod Classic / Nano / Vintage (300x300)",
        @"iPhone 4s / 6 / iOS 5-6 (600x600)",
        @"Modern iOS / High-Res (1000x1000)"
    ]];
    [self.view addSubview:self.devicePopup];
    
    y -= 45;
    CGFloat btnW = 160;
    self.backupButton = [[NSButton alloc] initWithFrame:NSMakeRect(40, y, btnW, 32)];
    self.backupButton.bezelStyle = NSTexturedRoundedBezelStyle;
    self.backupButton.target = self;
    self.backupButton.action = @selector(backupClicked:);
    [self.view addSubview:self.backupButton];
    
    self.optimizeButton = [[NSButton alloc] initWithFrame:NSMakeRect(210, y, btnW, 32)];
    self.optimizeButton.bezelStyle = NSTexturedRoundedBezelStyle;
    self.optimizeButton.target = self;
    self.optimizeButton.action = @selector(optimizeClicked:);
    [self.view addSubview:self.optimizeButton];
    
    self.restoreButton = [[NSButton alloc] initWithFrame:NSMakeRect(380, y, btnW, 32)];
    self.restoreButton.bezelStyle = NSTexturedRoundedBezelStyle;
    self.restoreButton.target = self;
    self.restoreButton.action = @selector(restoreClicked:);
    [self.view addSubview:self.restoreButton];
    
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
    self.statusLabel.font = [NSFont labelFontOfSize:11];
    [self.view addSubview:self.statusLabel];
    
    y -= 175;
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(40, y, 500, 160)];
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;
    
    self.logView = [[NSTextView alloc] initWithFrame:scrollView.bounds];
    self.logView.editable = NO;
    self.logView.backgroundColor = [NSColor blackColor];
    self.logView.textColor = [NSColor greenColor];
    self.logView.font = [NSFont fontWithName:@"Monaco" size:10];
    
    scrollView.documentView = self.logView;
    [self.view addSubview:scrollView];
    
    [self updateLocalization];
}

- (void)localizationChanged:(NSNotification *)notification {
    [self updateLocalization];
}

- (void)updateLocalization {
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    self.titleLabel.stringValue = [lang t:@"covers_optimizer"];
    self.selectLabel.stringValue = [lang t:@"select_device"];
    self.backupButton.title = [lang t:@"btn_backup_covers"];
    self.optimizeButton.title = [lang t:@"btn_optimize_covers"];
    self.restoreButton.title = [lang t:@"btn_restore_covers"];
}

- (void)log:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm:ss";
        NSString *stamp = [formatter stringFromDate:[NSDate date]];
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", stamp, message];
        
        NSTextStorage *storage = self.logView.textStorage;
        [storage beginEditing];
        [storage appendAttributedString:[[NSAttributedString alloc] initWithString:line attributes:@{
            NSForegroundColorAttributeName: [NSColor greenColor],
            NSFontAttributeName: [NSFont fontWithName:@"Monaco" size:10]
        }]];
        [storage endEditing];
        [self.logView scrollRangeToVisible:NSMakeRange(storage.length, 0)];
    });
}

// Helpers
- (NSString *)appName {
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/System/Applications/Music.app"]) {
        return @"Music";
    }
    return @"iTunes";
}

- (NSString *)backupFolderPath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docs = [paths firstObject];
    NSString *folder = [docs stringByAppendingPathComponent:@"AlbumCovers"];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    return folder;
}

- (NSString *)manifestPath {
    return [[self.backupFolderPath stringByAppendingPathComponent:@"manifest.json"] stringByStandardizingPath];
}

- (NSString *)runAppleScript:(NSString *)source {
    NSAppleScript *script = [[NSAppleScript alloc] initWithSource:source];
    NSDictionary *error = nil;
    NSAppleEventDescriptor *desc = [script executeAndReturnError:&error];
    if (error) {
        NSLog(@"AppleScript Error: %@", error);
        return nil;
    }
    return [desc stringValue];
}

- (NSMutableDictionary *)loadManifest {
    NSString *path = [self manifestPath];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data) {
        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (dict) {
            return [dict mutableCopy];
        }
    }
    return [@{@"manifest_version": @1, @"backups": [NSMutableDictionary dictionary]} mutableCopy];
}

- (void)saveManifest:(NSDictionary *)manifest {
    NSString *path = [self manifestPath];
    NSData *data = [NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:path atomically:YES];
}

- (void)updateManifestWithPID:(NSString *)pid title:(NSString *)title artist:(NSString *)artist ext:(NSString *)ext width:(NSInteger)w height:(NSInteger)h {
    NSMutableDictionary *manifest = [self loadManifest];
    NSMutableDictionary *backups = [manifest[@"backups"] mutableCopy] ?: [NSMutableDictionary dictionary];
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";
    NSString *dateStr = [formatter stringFromDate:[NSDate date]];
    
    backups[pid] = @{
        @"title": title ?: @"",
        @"artist": artist ?: @"",
        @"original_format": ext ?: @"jpg",
        @"original_width": @(w),
        @"original_height": @(h),
        @"backup_date": dateStr
    };
    manifest[@"backups"] = backups;
    [self saveManifest:manifest];
}

- (NSArray *)getTracksWithCovers {
    NSString *script = [NSString stringWithFormat:
        @"set out to \"\"\n"
        "tell application \"%@\"\n"
        "    try\n"
        "        set trks to every track of library playlist 1\n"
        "        repeat with t in trks\n"
        "            try\n"
        "                if exists artwork 1 of t then\n"
        "                    set pid to persistent ID of t\n"
        "                    set nm to name of t\n"
        "                    set art to artist of t\n"
        "                    set out to out & pid & \"|\" & nm & \"|\" & art & \"\\n\"\n"
        "                end if\n"
        "            end try\n"
        "        end repeat\n"
        "    end try\n"
        "end tell\n"
        "return out", [self appName]];
    
    NSString *res = [self runAppleScript:script];
    if (!res || res.length == 0) return @[];
    
    NSMutableArray *list = [NSMutableArray array];
    NSArray *lines = [res componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        if ([line containsString:@"|"]) {
            NSArray *parts = [line componentsSeparatedByString:@"|"];
            if (parts.count >= 3) {
                [list addObject:@{@"pid": parts[0], @"title": parts[1], @"artist": parts[2]}];
            }
        }
    }
    return list;
}

- (BOOL)backupCoverForPID:(NSString *)pid title:(NSString *)title artist:(NSString *)artist {
    NSString *backupFolder = [self backupFolderPath];
    NSString *escPath = [[backupFolder stringByAppendingPathComponent:pid] stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    escPath = [escPath stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    
    NSString *script = [NSString stringWithFormat:
        @"tell application \"%@\"\n"
        "    try\n"
        "        set t to (some track whose persistent ID is \"%@\")\n"
        "        if exists artwork 1 of t then\n"
        "            tell artwork 1 of t\n"
        "                set rawData to raw data\n"
        "                if format is JPEG picture then\n"
        "                    set ext to \"jpg\"\n"
        "                else\n"
        "                    set ext to \"png\"\n"
        "                end if\n"
        "                set w to width\n"
        "                set h to height\n"
        "            end tell\n"
        "            set destFile to POSIX file (\"%@.\" & ext)\n"
        "            set fileRef to open for access destFile with write permission\n"
        "            set eof fileRef to 0\n"
        "            write rawData to fileRef starting at 0\n"
        "            close access fileRef\n"
        "            return ext & \"|\" & w & \"|\" & h\n"
        "        else\n"
        "            return \"NO_ARTWORK\"\n"
        "        end if\n"
        "    on error errMsg number errNum\n"
        "        try\n"
        "            close access fileRef\n"
        "        end try\n"
        "        return \"ERROR: \" & errNum & \" - \" & errMsg\n"
        "    end try\n"
        "end tell", [self appName], pid, escPath];
    
    NSString *res = [self runAppleScript:script];
    if (!res || [res isEqualToString:@"NO_ARTWORK"] || [res hasPrefix:@"ERROR"]) {
        return NO;
    }
    
    NSArray *parts = [res componentsSeparatedByString:@"|"];
    if (parts.count >= 3) {
        NSString *ext = parts[0];
        NSInteger w = [parts[1] integerValue];
        NSInteger h = [parts[2] integerValue];
        [self updateManifestWithPID:pid title:title artist:artist ext:ext width:w height:h];
        return YES;
    }
    return NO;
}

- (NSData *)resizeImageAtPath:(NSString *)sourcePath targetSize:(CGFloat)targetSize {
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:sourcePath];
    if (!image) return nil;
    
    NSSize originalSize = image.size;
    NSSize newSize = originalSize;
    
    if (originalSize.width > originalSize.height) {
        if (originalSize.width > targetSize) {
            newSize = NSMakeSize(targetSize, (originalSize.height * targetSize) / originalSize.width);
        }
    } else {
        if (originalSize.height > targetSize) {
            newSize = NSMakeSize((originalSize.width * targetSize) / originalSize.height, targetSize);
        }
    }
    
    NSRect targetRect = NSMakeRect(0, 0, newSize.width, newSize.height);
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                   pixelsWide:newSize.width
                                                                   pixelsHigh:newSize.height
                                                                bitsPerSample:8
                                                                samplesPerPixel:4
                                                                       hasAlpha:YES
                                                                       isPlanar:NO
                                                                 colorSpaceName:NSCalibratedRGBColorSpace
                                                                    bytesPerRow:0
                                                                   bitsPerPixel:0];
    rep.size = newSize;
    
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    [image drawInRect:targetRect fromRect:NSZeroRect operation:NSCompositeCopy fraction:1.0];
    [NSGraphicsContext restoreGraphicsState];
    
    return [rep representationUsingType:NSJPEGFileType properties:@{NSImageCompressionFactor: @0.85}];
}

- (BOOL)setTrackArtworkForPID:(NSString *)pid imagePath:(NSString *)imagePath {
    NSString *escPath = [imagePath stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    escPath = [escPath stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    
    NSString *script = [NSString stringWithFormat:
        @"tell application \"%@\"\n"
        "    try\n"
        "        set t to (some track whose persistent ID is \"%@\")\n"
        "        set fileAlias to (POSIX file \"%@\") as alias\n"
        "        set imgData to read fileAlias as picture\n"
        "        tell t\n"
        "            delete every artwork\n"
        "            set data of artwork 1 to imgData\n"
        "        end tell\n"
        "        return \"SUCCESS\"\n"
        "    on error errMsg number errNum\n"
        "        return \"ERROR: \" & errNum & \" - \" & errMsg\n"
        "    end try\n"
        "end tell", [self appName], pid, escPath];
    
    NSString *res = [self runAppleScript:script];
    return [res isEqualToString:@"SUCCESS"];
}

- (BOOL)optimizeCoverForPID:(NSString *)pid targetSize:(NSInteger)targetSize {
    NSDictionary *manifest = [self loadManifest];
    NSDictionary *backups = manifest[@"backups"];
    NSDictionary *info = backups[pid];
    if (!info) return NO;
    
    NSString *ext = info[@"original_format"] ?: @"jpg";
    NSString *origPath = [[[self backupFolderPath] stringByAppendingPathComponent:pid] stringByAppendingPathExtension:ext];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:origPath]) {
        return NO;
    }
    
    NSInteger origW = [info[@"original_width"] integerValue];
    NSInteger origH = [info[@"original_height"] integerValue];
    if (origW <= targetSize && origH <= targetSize) {
        return [self setTrackArtworkForPID:pid imagePath:origPath];
    }
    
    NSData *resized = [self resizeImageAtPath:origPath targetSize:targetSize];
    if (!resized) return NO;
    
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_temp.jpg", pid]];
    [resized writeToFile:tempPath atomically:YES];
    
    BOOL success = [self setTrackArtworkForPID:pid imagePath:tempPath];
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
    return success;
}

- (BOOL)restoreCoverForPID:(NSString *)pid {
    NSDictionary *manifest = [self loadManifest];
    NSDictionary *backups = manifest[@"backups"];
    NSDictionary *info = backups[pid];
    if (!info) return NO;
    
    NSString *ext = info[@"original_format"] ?: @"jpg";
    NSString *origPath = [[[self backupFolderPath] stringByAppendingPathComponent:pid] stringByAppendingPathExtension:ext];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:origPath]) {
        return NO;
    }
    
    return [self setTrackArtworkForPID:pid imagePath:origPath];
}

// Action handlers
- (void)backupClicked:(NSButton *)sender {
    self.isProcessing = YES;
    [self.progressIndicator setDoubleValue:0];
    [self.logView setString:@""];
    [self log:[[IGLocalizationService sharedService] t:@"log_backup_started"]];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *tracks = [self getTracksWithCovers];
        if (tracks.count == 0) {
            [self log:[[IGLocalizationService sharedService] t:@"no_covers_found"]];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.isProcessing = NO;
            });
            return;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.progressIndicator setMaxValue:tracks.count];
        });
        
        NSInteger successCount = 0;
        for (NSInteger i = 0; i < tracks.count; i++) {
            NSDictionary *t = tracks[i];
            NSString *status = [NSString stringWithFormat:@"%@ - %@", t[@"artist"], t[@"title"]];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.statusLabel.stringValue = status;
                [self.progressIndicator setDoubleValue:i + 1];
            });
            
            if ([self backupCoverForPID:t[@"pid"] title:t[@"title"] artist:t[@"artist"]]) {
                successCount++;
            }
        }
        
        [self log:[[IGLocalizationService sharedService] t:@"log_backup_finished" args:@[@(successCount)]]];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.isProcessing = NO;
            self.statusLabel.stringValue = @"";
        });
    });
}

- (void)optimizeClicked:(NSButton *)sender {
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:[lang t:@"confirm_backup_title"]];
    [alert setInformativeText:[lang t:@"confirm_backup_msg"]];
    [alert addButtonWithTitle:[lang t:@"confirm_yes"]];
    [alert addButtonWithTitle:[lang t:@"confirm_no"]];
    
    if ([alert runModal] != NSAlertFirstButtonReturn) {
        return;
    }
    
    self.isProcessing = YES;
    [self.progressIndicator setDoubleValue:0];
    [self.logView setString:@""];
    
    NSInteger index = [self.devicePopup indexOfSelectedItem];
    NSInteger targetSize = 300;
    if (index == 1) targetSize = 600;
    else if (index == 2) targetSize = 1000;
    
    [self log:[lang t:@"log_optimize_started" args:@[@(targetSize)]]];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *tracks = [self getTracksWithCovers];
        if (tracks.count == 0) {
            [self log:[lang t:@"no_covers_found"]];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.isProcessing = NO;
            });
            return;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.progressIndicator setMaxValue:tracks.count];
        });
        
        NSInteger successCount = 0;
        for (NSInteger i = 0; i < tracks.count; i++) {
            NSDictionary *t = tracks[i];
            NSString *status = [NSString stringWithFormat:@"%@ - %@", t[@"artist"], t[@"title"]];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.statusLabel.stringValue = status;
                [self.progressIndicator setDoubleValue:i + 1];
            });
            
            // Backup first if not backed up
            [self backupCoverForPID:t[@"pid"] title:t[@"title"] artist:t[@"artist"]];
            
            if ([self optimizeCoverForPID:t[@"pid"] targetSize:targetSize]) {
                successCount++;
                [self log:[NSString stringWithFormat:@"Optimized: %@", t[@"title"]]];
            } else {
                [self log:[lang t:@"error_processing" args:@[t[@"title"]]]];
            }
        }
        
        [self log:[lang t:@"log_optimize_finished" args:@[@(successCount)]]];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.isProcessing = NO;
            self.statusLabel.stringValue = @"";
        });
    });
}

- (void)restoreClicked:(NSButton *)sender {
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    self.isProcessing = YES;
    [self.progressIndicator setDoubleValue:0];
    [self.logView setString:@""];
    [self log:[lang t:@"log_restore_started"]];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *tracks = [self getTracksWithCovers];
        if (tracks.count == 0) {
            [self log:[lang t:@"no_covers_found"]];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.isProcessing = NO;
            });
            return;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.progressIndicator setMaxValue:tracks.count];
        });
        
        NSInteger successCount = 0;
        for (NSInteger i = 0; i < tracks.count; i++) {
            NSDictionary *t = tracks[i];
            NSString *status = [NSString stringWithFormat:@"%@ - %@", t[@"artist"], t[@"title"]];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.statusLabel.stringValue = status;
                [self.progressIndicator setDoubleValue:i + 1];
            });
            
            if ([self restoreCoverForPID:t[@"pid"]]) {
                successCount++;
                [self log:[NSString stringWithFormat:@"Restored: %@", t[@"title"]]];
            }
        }
        
        [self log:[lang t:@"log_restore_finished" args:@[@(successCount)]]];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.isProcessing = NO;
            self.statusLabel.stringValue = @"";
        });
    });
}

- (void)setIsProcessing:(BOOL)isProcessing {
    _isProcessing = isProcessing;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.devicePopup setEnabled:!isProcessing];
        [self.backupButton setEnabled:!isProcessing];
        [self.optimizeButton setEnabled:!isProcessing];
        [self.restoreButton setEnabled:!isProcessing];
        if (isProcessing) {
            [self.progressIndicator startAnimation:nil];
        } else {
            [self.progressIndicator stopAnimation:nil];
        }
    });
}

- (void)helpClicked:(id)sender {
    NSString *helpText = @"Covers Optimizer Help\n\n"
                          "This utility optimizes album artwork sizes in your iTunes/Music library to save storage space (crucial for older iPods/devices):\n\n"
                          "1. Target Device: Choose the target iPod or device (e.g. iPod Classic, Nano) to use tailored size rules.\n"
                          "2. Backup: Extracts and saves a copy of all current artwork to your Documents folder before optimization.\n"
                          "3. Optimize: Resizes large high-resolution artwork to optimal dimensions (e.g., 600x600 or smaller) and updates them in your iTunes library.\n"
                          "4. Restore: Restores the original high-resolution artwork from the backup folder.";
    
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
    [self.view.window beginSheet:sheet completionHandler:nil];
}

- (void)closeHelpSheet:(id)sender {
    if (self.helpSheetWindow) {
        [self.view.window endSheet:self.helpSheetWindow];
        [self.helpSheetWindow orderOut:nil];
        self.helpSheetWindow = nil;
    }
}

@end
