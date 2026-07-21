#import "IGCoversOptimizerViewController.h"
#import "IGLocalizationService.h"
#import "IGiTunesService.h"
#import "IGLogger.h"
#import "IGTheme.h"

static NSString *IGCoverAppleScriptLiteral(NSString *value) {
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

static NSString *IGCoverAppleScriptListLiteral(NSArray *values) {
    NSMutableArray *parts = [NSMutableArray arrayWithCapacity:values.count];
    for (id value in values) {
        [parts addObject:IGCoverAppleScriptLiteral([value isKindOfClass:[NSString class]] ? value : @"")];
    }
    return [NSString stringWithFormat:@"{%@}", [parts componentsJoinedByString:@", "]];
}

static void IGTrimLogTextView(NSTextView *textView, NSUInteger maxCharacters) {
    NSTextStorage *storage = textView.textStorage;
    if (storage.length <= maxCharacters) return;
    NSUInteger extra = storage.length - maxCharacters;
    [storage deleteCharactersInRange:NSMakeRange(0, extra)];
}

static void IGCoversHDDSafePause(void) {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"hdd_safe_mode"]) {
        [NSThread sleepForTimeInterval:0.01];
    }
}

static NSString *IGCoversSupportDir(void) {
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *base = dirs.count > 0 ? [dirs objectAtIndex:0] : NSHomeDirectory();
    NSString *dir = [base stringByAppendingPathComponent:@"Syncrosa"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSString *IGCoversBeginActiveOperation(NSString *title, NSString *message, NSInteger affectedCount, NSString *backupPath) {
    NSString *identifier = [[NSProcessInfo processInfo] globallyUniqueString];
    NSDictionary *marker = @{
        @"id": identifier,
        @"tool": @"Covers Optimizer",
        @"title": title ?: @"",
        @"message": message ?: @"",
        @"startedAt": @([[NSDate date] timeIntervalSince1970]),
        @"affectedCount": @(affectedCount),
        @"backupPath": backupPath ?: @""
    };
    NSString *path = [IGCoversSupportDir() stringByAppendingPathComponent:@"active-operation.plist"];
    [marker writeToFile:path atomically:YES];
    return identifier;
}

static void IGCoversFinishActiveOperation(NSString *identifier) {
    NSString *path = [IGCoversSupportDir() stringByAppendingPathComponent:@"active-operation.plist"];
    NSDictionary *marker = [NSDictionary dictionaryWithContentsOfFile:path];
    if (!identifier || [[marker objectForKey:@"id"] isEqualToString:identifier]) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
}

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
@property (nonatomic, assign) NSInteger lastResolvedLibraryTrackCount;
@property (nonatomic, strong) NSWindow *helpSheetWindow;
@property (nonatomic, strong) NSString *activeOperationID;

@end

@implementation IGCoversOptimizerViewController

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
    self.restoreButton.enabled = [self hasCoverBackup];
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
    self.logView.backgroundColor = IGThemePanelInsetColor();
    self.logView.textColor = IGThemeAccentColor();
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
    [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"Covers: %@", message ?: @""]];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm:ss";
        NSString *stamp = [formatter stringFromDate:[NSDate date]];
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", stamp, message];

        NSTextStorage *storage = self.logView.textStorage;
        [storage beginEditing];
        NSAttributedString *attrLine = [[NSAttributedString alloc] initWithString:line attributes:@{
            NSForegroundColorAttributeName: IGThemeAccentColor(),
            NSFontAttributeName: [NSFont fontWithName:@"Monaco" size:10]
        }];
        [storage appendAttributedString:attrLine];
        IGTrimLogTextView(self.logView, 30000);
#if !__has_feature(objc_arc)
        [attrLine release];
        [formatter release];
#endif
        [storage endEditing];
        [self.logView scrollRangeToVisible:NSMakeRange(storage.length, 0)];
    });
}

// Helpers
- (NSString *)appName {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:@"/Applications/iTunes.app"] ||
        [fm fileExistsAtPath:@"/System/Applications/iTunes.app"]) {
        return @"iTunes";
    }
    if ([fm fileExistsAtPath:@"/System/Applications/Music.app"]) {
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
    return [[IGiTunesService sharedService] runAppleScriptNamed:@"covers.generic" source:source];
}

- (NSInteger)libraryTrackCount {
    NSString *script = [NSString stringWithFormat:
        @"on recordCandidate(labelText, countText, playlistName, modeText)\n"
        "    return \"COUNT\" & tab & labelText & tab & countText & tab & playlistName & tab & modeText & linefeed\n"
        "end recordCandidate\n"
        @"set out to \"\"\n"
        @"tell application \"%@\"\n"
        "    set bestCount to 0\n"
        "    set bestName to \"\"\n"
        "    set bestMode to \"none\"\n"
        "    try\n"
        "        set c to count of every track\n"
        "        set out to out & my recordCandidate(\"every track\", c as text, \"application\", \"app_tracks\")\n"
        "        if c > bestCount then\n"
        "            set bestCount to c\n"
        "            set bestName to \"application\"\n"
        "            set bestMode to \"app_tracks\"\n"
        "        end if\n"
        "    on error errMsg number errNum\n"
        "        set out to out & \"ERROR\" & tab & \"every track\" & tab & (errNum as text) & tab & errMsg & linefeed\n"
        "    end try\n"
        "    try\n"
        "        set c to count of every track of library playlist 1\n"
        "        set out to out & my recordCandidate(\"library playlist 1 tracks\", c as text, name of library playlist 1 as text, \"library_tracks\")\n"
        "        if c > bestCount then\n"
        "            set bestCount to c\n"
        "            set bestName to name of library playlist 1 as text\n"
        "            set bestMode to \"library_tracks\"\n"
        "        end if\n"
        "    on error errMsg number errNum\n"
        "        set out to out & \"ERROR\" & tab & \"library playlist 1 tracks\" & tab & (errNum as text) & tab & errMsg & linefeed\n"
        "    end try\n"
        "    try\n"
        "        set c to count of every file track of library playlist 1\n"
        "        set out to out & my recordCandidate(\"library playlist 1 file tracks\", c as text, name of library playlist 1 as text, \"library_file_tracks\")\n"
        "        if c > bestCount then\n"
        "            set bestCount to c\n"
        "            set bestName to name of library playlist 1 as text\n"
        "            set bestMode to \"library_file_tracks\"\n"
        "        end if\n"
        "    on error errMsg number errNum\n"
        "        set out to out & \"ERROR\" & tab & \"library playlist 1 file tracks\" & tab & (errNum as text) & tab & errMsg & linefeed\n"
        "    end try\n"
        "    try\n"
        "        repeat with s in sources\n"
        "            repeat with p in playlists of s\n"
        "                set plName to \"\"\n"
        "                try\n"
        "                    set plName to (name of s as text) & \"/\" & (name of p as text)\n"
        "                end try\n"
        "                try\n"
        "                    set c to count of file tracks of p\n"
        "                    set out to out & my recordCandidate(\"playlist file tracks\", c as text, plName, \"playlist_file_tracks\")\n"
        "                    if c > bestCount then\n"
        "                        set bestCount to c\n"
        "                        set bestName to plName\n"
        "                        set bestMode to \"playlist_file_tracks\"\n"
        "                    end if\n"
        "                end try\n"
        "                try\n"
        "                    set c to count of tracks of p\n"
        "                    set out to out & my recordCandidate(\"playlist tracks\", c as text, plName, \"playlist_tracks\")\n"
        "                    if c > bestCount then\n"
        "                        set bestCount to c\n"
        "                        set bestName to plName\n"
        "                        set bestMode to \"playlist_tracks\"\n"
        "                    end if\n"
        "                end try\n"
        "            end repeat\n"
        "        end repeat\n"
        "    on error errMsg number errNum\n"
        "        set out to out & \"ERROR\" & tab & \"sources playlists\" & tab & (errNum as text) & tab & errMsg & linefeed\n"
        "    end try\n"
        "end tell\n"
        "return \"BEST\" & tab & (bestCount as text) & tab & bestName & tab & bestMode & linefeed & out", [self appName]];

    NSString *raw = [[IGiTunesService sharedService] runAppleScriptNamed:@"covers.resolveLibrary" source:script];
    NSInteger count = -1;
    BOOL hasSuccessfulCountProbe = NO;
    BOOL hasReadError = NO;
    if (raw.length > 0) {
        NSArray *lines = [raw componentsSeparatedByString:@"\n"];
        if (lines.count > 0) {
            NSArray *parts = [[lines objectAtIndex:0] componentsSeparatedByString:@"\t"];
            if (parts.count >= 4 && [[parts objectAtIndex:0] isEqualToString:@"BEST"]) {
                count = [[parts objectAtIndex:1] integerValue];
                [self log:[NSString stringWithFormat:@"Resolved iTunes library: %@ tracks via %@ (%@).",
                           [parts objectAtIndex:1],
                           [parts objectAtIndex:3],
                           [parts objectAtIndex:2]]];
            }
        }
        for (NSUInteger idx = 1; idx < lines.count; idx++) {
            NSString *line = [lines objectAtIndex:idx];
            if (line.length == 0) continue;
            NSArray *lineParts = [line componentsSeparatedByString:@"\t"];
            if (lineParts.count > 0 && [[lineParts objectAtIndex:0] isEqualToString:@"COUNT"]) {
                hasSuccessfulCountProbe = YES;
            } else if (lineParts.count > 0 && [[lineParts objectAtIndex:0] isEqualToString:@"ERROR"]) {
                hasReadError = YES;
            }
        }
    }
    if (count == 0 && hasReadError && !hasSuccessfulCountProbe) {
        count = -1;
    }
    self.lastResolvedLibraryTrackCount = count;
    if (count == 0) {
        [self log:@"iTunes library is readable, but it has 0 tracks. Covers operation stopped before changing files."];
    } else if (count < 0) {
        [self log:@"Could not resolve a non-empty iTunes library playlist. Try syncing the library cache from Settings and run the operation again."];
    }
    return count;
}

- (NSString *)emptyCoverScanMessage {
    NSString *appName = [self appName];
    if (self.lastResolvedLibraryTrackCount == 0) {
        return [NSString stringWithFormat:@"%@ library has no tracks. There is no cover artwork to process.", appName];
    }
    return [NSString stringWithFormat:@"Could not read %@ library tracks. Covers operation stopped before changing files.", appName];
}

- (NSMutableDictionary *)loadManifest {
    NSString *path = [self manifestPath];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data) {
        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (dict) {
            NSMutableDictionary *mutableDict = [dict mutableCopy];
#if !__has_feature(objc_arc)
            return [mutableDict autorelease];
#else
            return mutableDict;
#endif
        }
    }
    NSMutableDictionary *defaultManifest = [@{@"manifest_version": @1, @"backups": [NSMutableDictionary dictionary]} mutableCopy];
#if !__has_feature(objc_arc)
    return [defaultManifest autorelease];
#else
    return defaultManifest;
#endif
}

- (BOOL)hasCoverBackup {
    NSDictionary *manifest = [self loadManifest];
    NSDictionary *backups = manifest[@"backups"];
    return [backups isKindOfClass:[NSDictionary class]] && backups.count > 0;
}

- (void)saveManifest:(NSDictionary *)manifest {
    NSString *path = [self manifestPath];
    NSData *data = [NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:path atomically:YES];
}

- (void)updateManifestWithPID:(NSString *)pid title:(NSString *)title artist:(NSString *)artist ext:(NSString *)ext width:(NSInteger)w height:(NSInteger)h {
    NSMutableDictionary *manifest = [self loadManifest];
    NSMutableDictionary *backups = [manifest[@"backups"] mutableCopy];
    BOOL ownsBackups = (backups != nil);
    if (!backups) {
        backups = [NSMutableDictionary dictionary];
    }

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
#if !__has_feature(objc_arc)
    if (ownsBackups) {
        [backups release];
    }
    [formatter release];
#endif
}

- (NSArray *)getTracksWithCovers {
    return [self getTracksWithCoversWithProgress:nil];
}

- (NSArray *)getTracksWithCoversWithProgress:(void(^)(NSInteger current, NSInteger total))progressBlock {
    NSInteger total = [self libraryTrackCount];
    if (total <= 0) return @[];

    NSMutableArray *list = [NSMutableArray array];
    NSInteger chunkSize = 100;
    NSString *appName = [self appName];

    for (NSInteger start = 1; start <= total; start += chunkSize) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSInteger end = MIN(start + chunkSize - 1, total);
        NSString *script = [NSString stringWithFormat:
        @"on replaceText(theText, oldText, newText)\n"
        "    set AppleScript's text item delimiters to oldText\n"
        "    set textItems to every text item of theText\n"
        "    set AppleScript's text item delimiters to newText\n"
        "    set newString to textItems as text\n"
        "    set AppleScript's text item delimiters to \"\"\n"
        "    return newString\n"
        "end replaceText\n"
        "on textValue(v)\n"
        "    try\n"
        "        if v is missing value then return \"\"\n"
        "        set s to v as text\n"
        "        set s to my replaceText(s, tab, \" \")\n"
        "        set s to my replaceText(s, linefeed, \" \")\n"
        "        set s to my replaceText(s, return, \" \")\n"
        "        return s\n"
        "    on error\n"
        "        return \"\"\n"
        "    end try\n"
        "end textValue\n"
        "on considerCandidate(candidateCount, candidatePlaylist, candidateMode, candidateName, currentBestCount, currentBestPlaylist, currentBestMode, currentBestName)\n"
        "    if candidateCount > currentBestCount then\n"
        "        return {candidateCount, candidatePlaylist, candidateMode, candidateName}\n"
        "    end if\n"
        "    return {currentBestCount, currentBestPlaylist, currentBestMode, currentBestName}\n"
        "end considerCandidate\n"
        @"set out to \"\"\n"
        "set startIndex to %ld\n"
        "set endIndex to %ld\n"
        "tell application \"%@\"\n"
        "    set bestCount to 0\n"
        "    set bestPlaylist to missing value\n"
        "    set bestMode to \"none\"\n"
        "    set bestName to \"\"\n"
        "    try\n"
        "        set c to count of every track\n"
        "        if c > bestCount then\n"
        "            set bestCount to c\n"
        "            set bestMode to \"app_tracks\"\n"
        "            set bestName to \"application\"\n"
        "        end if\n"
        "    end try\n"
        "    try\n"
        "        set c to count of every track of library playlist 1\n"
        "        if c > bestCount then\n"
        "            set bestCount to c\n"
        "            set bestPlaylist to library playlist 1\n"
        "            set bestMode to \"playlist_tracks\"\n"
        "            set bestName to name of library playlist 1 as text\n"
        "        end if\n"
        "    end try\n"
        "    try\n"
        "        set c to count of every file track of library playlist 1\n"
        "        if c > bestCount then\n"
        "            set bestCount to c\n"
        "            set bestPlaylist to library playlist 1\n"
        "            set bestMode to \"playlist_file_tracks\"\n"
        "            set bestName to name of library playlist 1 as text\n"
        "        end if\n"
        "    end try\n"
        "    try\n"
        "        repeat with s in sources\n"
        "            repeat with p in playlists of s\n"
        "                set plName to \"\"\n"
        "                try\n"
        "                    set plName to (name of s as text) & \"/\" & (name of p as text)\n"
        "                end try\n"
        "                try\n"
        "                    set c to count of file tracks of p\n"
        "                    if c > bestCount then\n"
        "                        set bestCount to c\n"
        "                        set bestPlaylist to p\n"
        "                        set bestMode to \"playlist_file_tracks\"\n"
        "                        set bestName to plName\n"
        "                    end if\n"
        "                end try\n"
        "                try\n"
        "                    set c to count of tracks of p\n"
        "                    if c > bestCount then\n"
        "                        set bestCount to c\n"
        "                        set bestPlaylist to p\n"
        "                        set bestMode to \"playlist_tracks\"\n"
        "                        set bestName to plName\n"
        "                    end if\n"
        "                end try\n"
        "            end repeat\n"
        "        end repeat\n"
        "    end try\n"
        "    if bestCount <= 0 then return \"RESOLVED\" & tab & \"0\" & tab & bestMode & tab & bestName & linefeed\n"
        "    if endIndex > bestCount then set endIndex to bestCount\n"
        "    set out to out & \"RESOLVED\" & tab & (bestCount as text) & tab & bestMode & tab & bestName & linefeed\n"
        "    try\n"
        "        if bestMode is \"app_tracks\" then\n"
        "            set trks to (tracks startIndex thru endIndex)\n"
        "        else if bestMode is \"playlist_file_tracks\" then\n"
        "            set trks to (file tracks startIndex thru endIndex of bestPlaylist)\n"
        "        else\n"
        "            set trks to (tracks startIndex thru endIndex of bestPlaylist)\n"
        "        end if\n"
        "        repeat with t in trks\n"
        "            try\n"
        "                set pid to my textValue(persistent ID of t)\n"
        "                if pid is not \"\" then\n"
        "                    set nm to my textValue(name of t)\n"
        "                    set artName to my textValue(artist of t)\n"
        "                    try\n"
        "                        set aw to artwork 1 of t\n"
        "                        set hasCover to \"YES\"\n"
        "                    on error\n"
        "                        set hasCover to \"NO\"\n"
        "                    end try\n"
        "                    set out to out & pid & tab & nm & tab & artName & tab & hasCover & linefeed\n"
        "                end if\n"
        "            end try\n"
        "        end repeat\n"
        "    on error errMsg number errNum\n"
        "        set out to out & \"ERROR\" & tab & (errNum as text) & tab & errMsg & linefeed\n"
        "    end try\n"
        "end tell\n"
        "return out", (long)start, (long)end, appName];

        NSString *res = [[IGiTunesService sharedService] runAppleScriptNamed:@"covers.scanChunk" source:script];
        NSInteger parsedRows = 0;
        if (res.length > 0) {
            NSArray *lines = [res componentsSeparatedByString:@"\n"];
            for (NSString *line in lines) {
                if (line.length == 0) continue;

                NSArray *parts = [line componentsSeparatedByString:@"\t"];
                if (parts.count > 0 && ([[parts objectAtIndex:0] isEqualToString:@"RESOLVED"] || [[parts objectAtIndex:0] isEqualToString:@"ERROR"])) {
                    continue;
                }
                if (parts.count >= 3 && [parts[0] length] > 0) {
                    NSString *hasCover = parts.count >= 4 ? parts[3] : @"UNKNOWN";
                    NSDictionary *trackInfo = @{
                        @"pid": parts[0],
                        @"title": parts[1],
                        @"artist": parts[2],
                        @"hasCover": hasCover
                    };
                    [list addObject:trackInfo];
                    parsedRows++;
                }
            }
        }
        [self log:[NSString stringWithFormat:@"Scanned iTunes chunk %ld-%ld, parsed %ld tracks.", (long)start, (long)end, (long)parsedRows]];

        if (progressBlock) {
            dispatch_async(dispatch_get_main_queue(), ^{
                progressBlock(end, total);
            });
        }
#if !__has_feature(objc_arc)
        [pool drain];
#endif
    }
    return list;
}

- (NSInteger)backupCoversForTracks:(NSArray *)tracks progress:(void(^)(NSInteger current, NSInteger total))progressBlock {
    if (tracks.count == 0) return 0;

    NSString *backupFolder = [self backupFolderPath];
    NSMutableDictionary *trackByPID = [NSMutableDictionary dictionaryWithCapacity:tracks.count];
    NSMutableDictionary *manifest = [self loadManifest];
    NSMutableDictionary *backups = [manifest[@"backups"] mutableCopy];
    BOOL ownsBackups = (backups != nil);
    if (!backups) {
        backups = [NSMutableDictionary dictionary];
    }
    manifest[@"backups"] = backups;

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";

    for (NSDictionary *track in tracks) {
        NSString *pid = track[@"pid"];
        if (pid.length > 0) {
            trackByPID[pid] = track;
        }
    }

    NSInteger successCount = 0;
    NSInteger chunkSize = 50;
    NSInteger total = tracks.count;

    for (NSInteger start = 0; start < total; start += chunkSize) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSInteger length = MIN(chunkSize, total - start);
        NSArray *chunk = [tracks subarrayWithRange:NSMakeRange(start, length)];
        NSMutableArray *pids = [NSMutableArray arrayWithCapacity:chunk.count];

        for (NSDictionary *track in chunk) {
            NSString *pid = track[@"pid"];
            if (pid.length > 0) {
                NSDictionary *existing = backups[pid];
                NSString *existingExt = existing[@"original_format"] ?: @"jpg";
                NSString *existingPath = [[backupFolder stringByAppendingPathComponent:pid] stringByAppendingPathExtension:existingExt];
                if (existing && [[NSFileManager defaultManager] fileExistsAtPath:existingPath]) {
                    successCount++;
                    continue;
                }
                [pids addObject:pid];
            }
        }

        if (pids.count == 0) {
            [self log:[NSString stringWithFormat:@"Backed up covers chunk %ld-%ld: already had backups.",
                       (long)(start + 1),
                       (long)(start + length)]];
            if (progressBlock) progressBlock(start + length, total);
#if !__has_feature(objc_arc)
            [pool drain];
#endif
            continue;
        }

        NSString *script = [NSString stringWithFormat:
            @"on writeArtwork(imageData, destPath)\n"
            "    set fileRef to missing value\n"
            "    try\n"
            "        set destFile to POSIX file destPath\n"
            "        set fileRef to open for access destFile with write permission\n"
            "        set eof fileRef to 0\n"
            "        write imageData to fileRef\n"
            "        close access fileRef\n"
            "    on error errMsg number errNum\n"
            "        try\n"
            "            if fileRef is not missing value then close access fileRef\n"
            "        end try\n"
            "        error errMsg number errNum\n"
            "    end try\n"
            "end writeArtwork\n"
            "set backupFolder to %@\n"
            "set pidList to %@\n"
            "set out to \"\"\n"
            "with timeout of 600 seconds\n"
            "tell application \"%@\"\n"
            "    repeat with pidItem in pidList\n"
            "        set pidText to (contents of pidItem) as text\n"
            "        set stageText to \"start\"\n"
            "        try\n"
            "            set stageText to \"resolve track\"\n"
            "            set t to (some track of library playlist 1 whose persistent ID is pidText)\n"
            "            if not (exists artwork 1 of t) then\n"
            "                set out to out & \"NO_ARTWORK\" & tab & pidText & linefeed\n"
            "            else\n"
            "                set stageText to \"read artwork\"\n"
            "                set aw to artwork 1 of t\n"
            "                tell aw\n"
            "                    try\n"
            "                        set imageData to raw data\n"
            "                    on error\n"
            "                        set imageData to data\n"
            "                    end try\n"
            "                    set fmtText to \"\"\n"
            "                    try\n"
            "                        set fmtText to format as text\n"
            "                    end try\n"
            "                    set ext to \"jpg\"\n"
            "                    if fmtText contains \"PNG\" or fmtText contains \"png\" then set ext to \"png\"\n"
            "                    if fmtText contains \"JPEG\" or fmtText contains \"jpeg\" or fmtText contains \"JPG\" or fmtText contains \"jpg\" then set ext to \"jpg\"\n"
            "                    set w to 0\n"
            "                    set h to 0\n"
            "                    try\n"
            "                        set w to width as integer\n"
            "                    end try\n"
            "                    try\n"
            "                        set h to height as integer\n"
            "                    end try\n"
            "                end tell\n"
            "                set stageText to \"write file\"\n"
            "                set destPath to backupFolder & \"/\" & pidText & \".\" & ext\n"
            "                my writeArtwork(imageData, destPath)\n"
            "                set out to out & \"OK\" & tab & pidText & tab & ext & tab & (w as text) & tab & (h as text) & linefeed\n"
            "            end if\n"
            "        on error errMsg number errNum\n"
            "            set out to out & \"ERROR\" & tab & pidText & tab & stageText & tab & (errNum as text) & tab & errMsg & linefeed\n"
            "        end try\n"
            "    end repeat\n"
            "end tell\n"
            "end timeout\n"
            "return out",
            IGCoverAppleScriptLiteral(backupFolder),
            IGCoverAppleScriptListLiteral(pids),
            [self appName]];

        NSString *res = [[IGiTunesService sharedService] runAppleScriptNamed:@"covers.backupBatch" source:script];
        NSInteger chunkSaved = 0;
        NSInteger chunkErrors = 0;

        if (res.length > 0) {
            NSArray *lines = [res componentsSeparatedByString:@"\n"];
            for (NSString *line in lines) {
                if (line.length == 0) continue;

                NSArray *parts = [line componentsSeparatedByString:@"\t"];
                if (parts.count >= 5 && [parts[0] isEqualToString:@"OK"]) {
                    NSString *pid = parts[1];
                    NSString *rawExt = parts[2];
                    NSString *ext = rawExt.length > 0 ? rawExt : @"jpg";
                    NSInteger w = [parts[3] integerValue];
                    NSInteger h = [parts[4] integerValue];
                    NSString *savedPath = [[backupFolder stringByAppendingPathComponent:pid] stringByAppendingPathExtension:ext];
                    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:savedPath error:nil];

                    unsigned long long fileSize = [[attrs objectForKey:NSFileSize] unsignedLongLongValue];
                    if (fileSize == 0) {
                        chunkErrors++;
                        [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"Covers batch backup wrote empty file pid=%@ path=%@", pid ?: @"", savedPath ?: @""]];
                        continue;
                    }

                    if (w <= 0 || h <= 0) {
                        NSImage *image = [[NSImage alloc] initWithContentsOfFile:savedPath];
                        if (image) {
                            w = (NSInteger)image.size.width;
                            h = (NSInteger)image.size.height;
#if !__has_feature(objc_arc)
                            [image release];
#endif
                        }
                    }

                    NSDictionary *track = trackByPID[pid];
                    NSString *dateStr = [formatter stringFromDate:[NSDate date]];
                    backups[pid] = @{
                        @"title": track[@"title"] ?: @"",
                        @"artist": track[@"artist"] ?: @"",
                        @"original_format": ext ?: @"jpg",
                        @"original_width": @(w),
                        @"original_height": @(h),
                        @"backup_date": dateStr ?: @""
                    };
                    successCount++;
                    chunkSaved++;
                } else if (parts.count >= 2) {
                    chunkErrors++;
                    [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"Covers batch backup result: %@", line]];
                }
            }
        }

        [self log:[NSString stringWithFormat:@"Backed up covers chunk %ld-%ld: saved %ld, errors %ld.",
                   (long)(start + 1),
                   (long)(start + length),
                   (long)chunkSaved,
                   (long)chunkErrors]];

        if (progressBlock) {
            progressBlock(start + length, total);
        }
        if (chunkSaved > 0) {
            [self saveManifest:manifest];
        }
        IGCoversHDDSafePause();
#if !__has_feature(objc_arc)
        [pool drain];
#endif
    }

    [self saveManifest:manifest];
#if !__has_feature(objc_arc)
    if (ownsBackups) {
        [backups release];
    }
    [formatter release];
#endif

    return successCount;
}

- (BOOL)backupCoverForPID:(NSString *)pid title:(NSString *)title artist:(NSString *)artist {
    if (pid.length == 0) return NO;
    NSDictionary *track = @{
        @"pid": pid,
        @"title": title ?: @"",
        @"artist": artist ?: @"",
        @"hasCover": @"YES"
    };
    return [self backupCoversForTracks:@[track] progress:nil] > 0;
}

- (NSData *)resizeImageAtPath:(NSString *)sourcePath targetSize:(CGFloat)targetSize {
    if (![NSThread isMainThread]) {
        __block NSData *result = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{
#if !__has_feature(objc_arc)
            result = [[self resizeImageAtPath:sourcePath targetSize:targetSize] retain];
#else
            result = [self resizeImageAtPath:sourcePath targetSize:targetSize];
#endif
        });
#if !__has_feature(objc_arc)
        return [result autorelease];
#else
        return result;
#endif
    }

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

    NSData *jpegData = [rep representationUsingType:NSJPEGFileType properties:@{NSImageCompressionFactor: @0.85}];
#if !__has_feature(objc_arc)
    [rep release];
    [image release];
#endif
    return jpegData;
}

- (BOOL)setTrackArtworkForPID:(NSString *)pid imagePath:(NSString *)imagePath {
    NSString *script = [NSString stringWithFormat:
        @"on readArtworkFile(imagePath)\n"
        "    set fileAlias to (POSIX file imagePath) as alias\n"
        "    return read fileAlias as picture\n"
        "end readArtworkFile\n"
        "set pidText to %@\n"
        "set imagePath to %@\n"
        "set imgData to my readArtworkFile(imagePath)\n"
        "with timeout of 180 seconds\n"
        @"tell application \"%@\"\n"
        "    try\n"
        "        set t to (some track of library playlist 1 whose persistent ID is pidText)\n"
        "        try\n"
        "            set data of artwork 1 of t to imgData\n"
        "        on error\n"
        "            make new artwork at t with properties {data:imgData}\n"
        "        end try\n"
        "        return \"SUCCESS\"\n"
        "    on error errMsg number errNum\n"
        "        return \"ERROR: \" & errNum & \" - \" & errMsg\n"
        "    end try\n"
        "end tell\n"
        "end timeout",
        IGCoverAppleScriptLiteral(pid),
        IGCoverAppleScriptLiteral(imagePath),
        [self appName]];

    NSString *res = [[IGiTunesService sharedService] runAppleScriptNamed:@"covers.setArtwork" source:script];
    return [res isEqualToString:@"SUCCESS"];
}

- (BOOL)optimizeCoverForPID:(NSString *)pid targetSize:(NSInteger)targetSize {
    NSDictionary *manifest = [self loadManifest];
    return [self optimizeCoverForPID:pid targetSize:targetSize manifest:manifest];
}

- (BOOL)optimizeCoverForPID:(NSString *)pid targetSize:(NSInteger)targetSize manifest:(NSDictionary *)manifest {
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

    NSString *tempName = [NSString stringWithFormat:@"syncrosa-cover-%@-%@.jpg", pid ?: @"track", [[NSProcessInfo processInfo] globallyUniqueString]];
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:tempName];
    if (![resized writeToFile:tempPath atomically:YES]) {
        return NO;
    }

    BOOL success = [self setTrackArtworkForPID:pid imagePath:tempPath];
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
    return success;
}

- (BOOL)restoreCoverForPID:(NSString *)pid {
    NSDictionary *manifest = [self loadManifest];
    return [self restoreCoverForPID:pid manifest:manifest];
}

- (BOOL)restoreCoverForPID:(NSString *)pid manifest:(NSDictionary *)manifest {
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
    if (self.isProcessing) {
        [self log:@"Ignored Backup click because another Covers operation is already running."];
        return;
    }
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    self.isProcessing = YES;
    self.progressIndicator.indeterminate = YES;
    [self.progressIndicator setDoubleValue:0];
    [self.progressIndicator startAnimation:nil];
    self.statusLabel.stringValue = @"Scanning iTunes library for covers...";
    [self.logView setString:@""];
    [self log:[lang t:@"log_backup_started"]];
    [self log:@"If iTunes is closed, open it first or use Refresh iTunes when Syncrosa asks for permission."];
    self.activeOperationID = IGCoversBeginActiveOperation(@"Backup Original Covers",
                                                         @"Cover backup was interrupted while scanning iTunes artwork.",
                                                         0,
                                                         [self backupFolderPath]);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *tracks = [self getTracksWithCoversWithProgress:^(NSInteger current, NSInteger total) {
            self.statusLabel.stringValue = [NSString stringWithFormat:@"Scanning tracks %ld of %ld...", (long)current, (long)total];
        }];
        if (tracks.count == 0) {
            NSString *message = [self emptyCoverScanMessage];
            [self log:message];
            dispatch_async(dispatch_get_main_queue(), ^{
                IGCoversFinishActiveOperation(self.activeOperationID);
                self.activeOperationID = nil;
                self.isProcessing = NO;
                self.progressIndicator.indeterminate = NO;
                self.progressIndicator.doubleValue = 0;
                self.statusLabel.stringValue = message;
            });
            return;
        }

        NSInteger artworkHintCount = 0;
        for (NSDictionary *track in tracks) {
            if ([track[@"hasCover"] isEqualToString:@"YES"]) {
                artworkHintCount++;
            }
        }
        [self log:[NSString stringWithFormat:@"iTunes returned %ld tracks; AppleScript sees artwork on %ld of them.", (long)tracks.count, (long)artworkHintCount]];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressIndicator.indeterminate = NO;
            [self.progressIndicator setMaxValue:tracks.count];
            [self.progressIndicator setDoubleValue:0];
        });

        NSInteger successCount = [self backupCoversForTracks:tracks progress:^(NSInteger current, NSInteger total) {
            NSString *status = [NSString stringWithFormat:@"Backing up covers %ld of %ld...", (long)current, (long)total];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.statusLabel.stringValue = status;
                [self.progressIndicator setDoubleValue:current];
            });
        }];

        if (successCount == 0) {
            [self log:@"No cover files were written. iTunes may expose cached artwork visually without embeddable artwork data in the track files."];
        }
        [self log:[lang t:@"log_backup_finished" args:@[@(successCount)]]];
        dispatch_async(dispatch_get_main_queue(), ^{
            IGCoversFinishActiveOperation(self.activeOperationID);
            self.activeOperationID = nil;
            self.isProcessing = NO;
            self.statusLabel.stringValue = @"";
        });
    });
}

- (void)optimizeClicked:(NSButton *)sender {
    if (self.isProcessing) {
        [self log:@"Ignored Optimize click because another Covers operation is already running."];
        return;
    }
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
    self.progressIndicator.indeterminate = YES;
    [self.progressIndicator setDoubleValue:0];
    [self.progressIndicator startAnimation:nil];
    self.statusLabel.stringValue = @"Scanning iTunes library for covers...";
    [self.logView setString:@""];

    NSInteger index = [self.devicePopup indexOfSelectedItem];
    NSInteger targetSize = 300;
    if (index == 1) targetSize = 600;
    else if (index == 2) targetSize = 1000;

    [self log:[lang t:@"log_optimize_started" args:@[@(targetSize)]]];
    self.activeOperationID = IGCoversBeginActiveOperation(@"Optimize Covers",
                                                         @"Cover optimization was interrupted. Check the backup manifest before continuing.",
                                                         0,
                                                         [self backupFolderPath]);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *tracks = [self getTracksWithCoversWithProgress:^(NSInteger current, NSInteger total) {
            self.statusLabel.stringValue = [NSString stringWithFormat:@"Scanning tracks %ld of %ld...", (long)current, (long)total];
        }];
        if (tracks.count == 0) {
            NSString *message = [self emptyCoverScanMessage];
            [self log:message];
            dispatch_async(dispatch_get_main_queue(), ^{
                IGCoversFinishActiveOperation(self.activeOperationID);
                self.activeOperationID = nil;
                self.isProcessing = NO;
                self.progressIndicator.indeterminate = NO;
                self.progressIndicator.doubleValue = 0;
                self.statusLabel.stringValue = message;
            });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressIndicator.indeterminate = NO;
            [self.progressIndicator setMaxValue:tracks.count];
            [self.progressIndicator setDoubleValue:0];
        });

        NSInteger backupCount = [self backupCoversForTracks:tracks progress:^(NSInteger current, NSInteger total) {
            NSString *status = [NSString stringWithFormat:@"Backing up originals %ld of %ld...", (long)current, (long)total];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.statusLabel.stringValue = status;
                [self.progressIndicator setDoubleValue:current];
            });
        }];
        [self log:[NSString stringWithFormat:@"Backup pass before optimization saved/updated %ld covers.", (long)backupCount]];

        NSInteger successCount = 0;
        NSDictionary *manifest = [self loadManifest];
        for (NSInteger i = 0; i < tracks.count; i++) {
            NSDictionary *t = tracks[i];
            NSString *status = [NSString stringWithFormat:@"%@ - %@", t[@"artist"], t[@"title"]];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.statusLabel.stringValue = status;
                [self.progressIndicator setDoubleValue:i + 1];
            });

            if ([self optimizeCoverForPID:t[@"pid"] targetSize:targetSize manifest:manifest]) {
                successCount++;
                [self log:[NSString stringWithFormat:@"Optimized: %@", t[@"title"]]];
            } else {
                [self log:[lang t:@"error_processing" args:@[t[@"title"]]]];
            }
            IGCoversHDDSafePause();
        }

        [self log:[lang t:@"log_optimize_finished" args:@[@(successCount)]]];
        dispatch_async(dispatch_get_main_queue(), ^{
            IGCoversFinishActiveOperation(self.activeOperationID);
            self.activeOperationID = nil;
            self.isProcessing = NO;
            self.statusLabel.stringValue = @"";
        });
    });
}

- (void)restoreClicked:(NSButton *)sender {
    if (self.isProcessing) {
        [self log:@"Ignored Restore click because another Covers operation is already running."];
        return;
    }
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    self.isProcessing = YES;
    self.progressIndicator.indeterminate = YES;
    [self.progressIndicator setDoubleValue:0];
    [self.progressIndicator startAnimation:nil];
    self.statusLabel.stringValue = @"Scanning iTunes library for covers...";
    [self.logView setString:@""];
    [self log:[lang t:@"log_restore_started"]];
    self.activeOperationID = IGCoversBeginActiveOperation(@"Restore Original Covers",
                                                         @"Cover restore was interrupted. Check Operation History and the backup manifest.",
                                                         0,
                                                         [self backupFolderPath]);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *tracks = [self getTracksWithCoversWithProgress:^(NSInteger current, NSInteger total) {
            self.statusLabel.stringValue = [NSString stringWithFormat:@"Scanning tracks %ld of %ld...", (long)current, (long)total];
        }];
        if (tracks.count == 0) {
            NSString *message = [self emptyCoverScanMessage];
            [self log:message];
            dispatch_async(dispatch_get_main_queue(), ^{
                IGCoversFinishActiveOperation(self.activeOperationID);
                self.activeOperationID = nil;
                self.isProcessing = NO;
                self.progressIndicator.indeterminate = NO;
                self.progressIndicator.doubleValue = 0;
                self.statusLabel.stringValue = message;
            });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressIndicator.indeterminate = NO;
            [self.progressIndicator setMaxValue:tracks.count];
            [self.progressIndicator setDoubleValue:0];
        });

        NSInteger successCount = 0;
        NSDictionary *manifest = [self loadManifest];
        for (NSInteger i = 0; i < tracks.count; i++) {
            NSDictionary *t = tracks[i];
            NSString *status = [NSString stringWithFormat:@"%@ - %@", t[@"artist"], t[@"title"]];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.statusLabel.stringValue = status;
                [self.progressIndicator setDoubleValue:i + 1];
            });

            if ([self restoreCoverForPID:t[@"pid"] manifest:manifest]) {
                successCount++;
                [self log:[NSString stringWithFormat:@"Restored: %@", t[@"title"]]];
            }
            IGCoversHDDSafePause();
        }

        [self log:[lang t:@"log_restore_finished" args:@[@(successCount)]]];
        dispatch_async(dispatch_get_main_queue(), ^{
            IGCoversFinishActiveOperation(self.activeOperationID);
            self.activeOperationID = nil;
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
        [self.restoreButton setEnabled:(!isProcessing && [self hasCoverBackup])];
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

    IGApplyThemeToWindow(sheet);
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

@end
