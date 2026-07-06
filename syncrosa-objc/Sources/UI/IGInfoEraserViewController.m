#import "IGInfoEraserViewController.h"
#import "IGNotificationView.h"
#include <stdint.h>

static NSString *IGInfoEraserBackupDirName = @"SyncrosaInfoEraserBackup";
static NSUInteger IGInfoEraserChunkSize = 256 * 1024;

static uint32_t IGInfoEraserReadBE32(NSData *data, NSUInteger offset) {
    const unsigned char *bytes = [data bytes];
    return ((uint32_t)bytes[offset] << 24) | ((uint32_t)bytes[offset + 1] << 16) | ((uint32_t)bytes[offset + 2] << 8) | (uint32_t)bytes[offset + 3];
}

static uint64_t IGInfoEraserReadBE64(NSData *data, NSUInteger offset) {
    const unsigned char *bytes = [data bytes];
    uint64_t value = 0;
    NSUInteger i = 0;
    for (i = 0; i < 8; i++) {
        value = (value << 8) | (uint64_t)bytes[offset + i];
    }
    return value;
}

static void IGInfoEraserWriteBE32(NSMutableData *data, NSUInteger offset, uint32_t value) {
    unsigned char *bytes = [data mutableBytes];
    bytes[offset] = (unsigned char)((value >> 24) & 0xFF);
    bytes[offset + 1] = (unsigned char)((value >> 16) & 0xFF);
    bytes[offset + 2] = (unsigned char)((value >> 8) & 0xFF);
    bytes[offset + 3] = (unsigned char)(value & 0xFF);
}

static void IGInfoEraserWriteBE64(NSMutableData *data, NSUInteger offset, uint64_t value) {
    unsigned char *bytes = [data mutableBytes];
    NSUInteger i = 0;
    for (i = 0; i < 8; i++) {
        NSUInteger shift = (7 - i) * 8;
        bytes[offset + i] = (unsigned char)((value >> shift) & 0xFF);
    }
}

static NSData *IGInfoEraserFreeAtomData(NSUInteger size, NSUInteger headerSize) {
    NSMutableData *data = [NSMutableData dataWithLength:size];
    if (size < 8) return data;
    unsigned char *bytes = [data mutableBytes];
    if (headerSize == 16 && size >= 16) {
        IGInfoEraserWriteBE32(data, 0, 1);
        bytes[4] = 'f'; bytes[5] = 'r'; bytes[6] = 'e'; bytes[7] = 'e';
        IGInfoEraserWriteBE64(data, 8, (uint64_t)size);
    } else {
        IGInfoEraserWriteBE32(data, 0, (uint32_t)size);
        bytes[4] = 'f'; bytes[5] = 'r'; bytes[6] = 'e'; bytes[7] = 'e';
    }
    return data;
}

@interface IGInfoEraserViewController ()
@property (nonatomic, strong) NSTextField *folderPathField;
@property (nonatomic, strong) NSButton *selectFolderButton;
@property (nonatomic, strong) NSButton *backupButton;
@property (nonatomic, strong) NSButton *eraseButton;
@property (nonatomic, strong) NSButton *restoreButton;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextView *logView;
@property (nonatomic, strong) NSURL *selectedFolderURL;
@property (nonatomic, strong) NSArray *foundFiles;
@property (nonatomic, assign) BOOL isProcessing;
@end

@implementation IGInfoEraserViewController

- (void)loadView {
    self.view = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 480)] autorelease];
    [self setupUI];
}

- (void)setupUI {
    CGFloat y = 440;

    NSTextField *titleLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 540, 30)] autorelease];
    titleLabel.stringValue = @"Info Eraser";
    titleLabel.font = [NSFont boldSystemFontOfSize:18];
    titleLabel.editable = NO;
    titleLabel.bordered = NO;
    titleLabel.drawsBackground = NO;
    titleLabel.alignment = NSCenterTextAlignment;
    [self.view addSubview:titleLabel];

    NSButton *helpButton = [[[NSButton alloc] initWithFrame:NSMakeRect(520, y + 2, 25, 25)] autorelease];
    helpButton.title = @"?";
    helpButton.bezelStyle = NSHelpButtonBezelStyle;
    helpButton.target = self;
    helpButton.action = @selector(helpClicked:);
    [self.view addSubview:helpButton];

    y -= 72;
    NSBox *warningBox = [[[NSBox alloc] initWithFrame:NSMakeRect(40, y, 500, 58)] autorelease];
    warningBox.boxType = NSBoxCustom;
    warningBox.borderType = NSLineBorder;
    warningBox.borderColor = [NSColor colorWithCalibratedRed:0.65 green:0.0 blue:0.08 alpha:1.0];
    warningBox.fillColor = [NSColor colorWithCalibratedRed:1.0 green:0.90 blue:0.90 alpha:1.0];
    [self.view addSubview:warningBox];

    NSTextField *warning = [[[NSTextField alloc] initWithFrame:NSMakeRect(50, y + 8, 480, 42)] autorelease];
    warning.stringValue = @"WARNING: this tab permanently removes embedded song information and artwork from local files. Use only on a copied folder or after creating a backup.";
    warning.font = [NSFont boldSystemFontOfSize:11];
    warning.textColor = [NSColor colorWithCalibratedRed:0.55 green:0.0 blue:0.06 alpha:1.0];
    warning.editable = NO;
    warning.bordered = NO;
    warning.drawsBackground = NO;
    warning.alignment = NSCenterTextAlignment;
    [self.view addSubview:warning];

    y -= 42;
    self.folderPathField = [[[NSTextField alloc] initWithFrame:NSMakeRect(40, y, 360, 24)] autorelease];
    self.folderPathField.editable = NO;
    [[self.folderPathField cell] setPlaceholderString:@"No folder selected"];
    [self.view addSubview:self.folderPathField];

    self.selectFolderButton = [[[NSButton alloc] initWithFrame:NSMakeRect(410, y - 2, 130, 30)] autorelease];
    self.selectFolderButton.title = @"Select Folder";
    self.selectFolderButton.bezelStyle = NSRoundedBezelStyle;
    self.selectFolderButton.target = self;
    self.selectFolderButton.action = @selector(selectFolderClicked:);
    [self.view addSubview:self.selectFolderButton];

    y -= 45;
    self.backupButton = [[[NSButton alloc] initWithFrame:NSMakeRect(40, y, 160, 32)] autorelease];
    self.backupButton.title = @"Backup Original Info";
    self.backupButton.bezelStyle = NSRoundedBezelStyle;
    self.backupButton.enabled = NO;
    self.backupButton.target = self;
    self.backupButton.action = @selector(backupClicked:);
    [self.view addSubview:self.backupButton];

    self.eraseButton = [[[NSButton alloc] initWithFrame:NSMakeRect(210, y, 150, 32)] autorelease];
    self.eraseButton.title = @"Erase Info";
    self.eraseButton.bezelStyle = NSTexturedRoundedBezelStyle;
    self.eraseButton.enabled = NO;
    self.eraseButton.target = self;
    self.eraseButton.action = @selector(eraseClicked:);
    [self.view addSubview:self.eraseButton];

    self.restoreButton = [[[NSButton alloc] initWithFrame:NSMakeRect(370, y, 170, 32)] autorelease];
    self.restoreButton.title = @"Restore Original Info";
    self.restoreButton.bezelStyle = NSRoundedBezelStyle;
    self.restoreButton.enabled = NO;
    self.restoreButton.target = self;
    self.restoreButton.action = @selector(restoreClicked:);
    [self.view addSubview:self.restoreButton];

    y -= 35;
    self.progressIndicator = [[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(40, y, 500, 18)] autorelease];
    self.progressIndicator.style = NSProgressIndicatorBarStyle;
    self.progressIndicator.indeterminate = NO;
    self.progressIndicator.minValue = 0;
    [self.view addSubview:self.progressIndicator];

    y -= 130;
    NSScrollView *scrollView = [[[NSScrollView alloc] initWithFrame:NSMakeRect(40, y, 500, 118)] autorelease];
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;
    self.logView = [[[NSTextView alloc] initWithFrame:scrollView.bounds] autorelease];
    self.logView.editable = NO;
    self.logView.backgroundColor = [NSColor blackColor];
    self.logView.textColor = [NSColor greenColor];
    self.logView.font = [NSFont fontWithName:@"Monaco" size:10];
    scrollView.documentView = self.logView;
    [self.view addSubview:scrollView];

    y -= 30;
    self.statusLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(40, y, 500, 20)] autorelease];
    self.statusLabel.stringValue = @"Select a folder to scan local music files.";
    self.statusLabel.editable = NO;
    self.statusLabel.bordered = NO;
    self.statusLabel.drawsBackground = NO;
    self.statusLabel.alignment = NSCenterTextAlignment;
    [self.view addSubview:self.statusLabel];
}

- (void)helpClicked:(id)sender {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:@"Info Eraser Help"];
    [alert setInformativeText:@"Info Eraser works only with the selected local folder and its subfolders. It does not edit iTunes directly.\n\nBackup Original Info creates SyncrosaInfoEraserBackup with manifest.json and sidecar tag files.\n\nErase Info removes MP3 ID3 tags and M4A/MP4/AAC/ALAC metadata atoms without transcoding audio.\n\nRestore Info can restore metadata only from a backup created before erasing."];
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)log:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *line = [NSString stringWithFormat:@"> %@\n", text ?: @""];
        NSAttributedString *attrLine = [[[NSAttributedString alloc] initWithString:line attributes:@{NSForegroundColorAttributeName: [NSColor greenColor]}] autorelease];
        [self.logView.textStorage appendAttributedString:attrLine];
        if (self.logView.textStorage.length > 30000) {
            [self.logView.textStorage deleteCharactersInRange:NSMakeRange(0, self.logView.textStorage.length - 30000)];
        }
        [self.logView scrollRangeToVisible:NSMakeRange(self.logView.textStorage.length, 0)];
    });
}

- (void)clearLogView {
    [self.logView setString:@""];
}

- (void)setControlsBusy:(BOOL)busy {
    self.isProcessing = busy;
    self.selectFolderButton.enabled = !busy;
    BOOL hasFiles = (self.foundFiles.count > 0);
    self.backupButton.enabled = (!busy && hasFiles);
    self.eraseButton.enabled = (!busy && hasFiles);
    self.restoreButton.enabled = (!busy && self.selectedFolderURL != nil);
}

- (void)selectFolderClicked:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:NO];

    if ([panel runModal] == NSOKButton) {
        NSURL *url = [[panel URLs] firstObject];
        self.selectedFolderURL = url;
        self.folderPathField.stringValue = url.path ?: @"";
        [self scanFolder:url];
    }
}

- (void)scanFolder:(NSURL *)url {
    self.statusLabel.stringValue = @"Scanning folder...";
    [self clearLogView];
    [self log:[NSString stringWithFormat:@"Scanning folder recursively: %@", url.path ?: @""]];
    [self setControlsBusy:YES];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSArray *extensions = @[@"mp3", @"m4a", @"mp4", @"aac", @"flac", @"wav", @"aiff", @"alac"];
        NSMutableArray *matches = [NSMutableArray array];
        NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:url includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];

        for (NSURL *fileURL in enumerator) {
            if ([[fileURL lastPathComponent] isEqualToString:IGInfoEraserBackupDirName]) {
                [enumerator skipDescendants];
                continue;
            }
            NSNumber *isDirectory = nil;
            [fileURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
            if ([isDirectory boolValue]) continue;
            if ([extensions containsObject:[[fileURL pathExtension] lowercaseString]]) {
                [matches addObject:fileURL];
            }
        }

        NSArray *result = [[matches sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
            return [a.path localizedStandardCompare:b.path];
        }] copy];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.foundFiles = result;
            NSInteger supportedCount = [self supportedCountInFiles:result];
            self.progressIndicator.maxValue = MAX(result.count, 1);
            self.progressIndicator.doubleValue = 0;
            self.statusLabel.stringValue = [NSString stringWithFormat:@"Found %ld files. Supported for erasing: %ld.", (long)result.count, (long)supportedCount];
            [self log:[NSString stringWithFormat:@"Found %ld music files. Supported for erasing MP3/M4A/MP4/AAC/ALAC: %ld.", (long)result.count, (long)supportedCount]];
            [self setControlsBusy:NO];
#if !__has_feature(objc_arc)
            [result release];
#endif
        });
#if !__has_feature(objc_arc)
        [pool drain];
#endif
    });
}

- (NSInteger)supportedCountInFiles:(NSArray *)files {
    NSInteger count = 0;
    for (NSURL *url in files) {
        if ([self isSupportedInfoExtension:[[url pathExtension] lowercaseString]]) {
            count++;
        }
    }
    return count;
}

- (BOOL)isSupportedInfoExtension:(NSString *)ext {
    return [ext isEqualToString:@"mp3"] || [self isMP4LikeExtension:ext];
}

- (BOOL)isMP4LikeExtension:(NSString *)ext {
    return [ext isEqualToString:@"m4a"] || [ext isEqualToString:@"mp4"] || [ext isEqualToString:@"aac"] || [ext isEqualToString:@"alac"];
}

- (void)backupClicked:(id)sender {
    [self runOperationWithStatus:@"Backing up original info..." block:^NSString *(void (^progress)(NSInteger, NSInteger)) {
        NSString *manifest = nil;
        NSInteger supported = [self backupOriginalInfoWithProgress:progress manifestPath:&manifest];
        return [NSString stringWithFormat:@"Backup saved: %@ (%ld supported files).", manifest ?: @"", (long)supported];
    }];
}

- (void)eraseClicked:(id)sender {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:@"Are you sure?"];
    [alert setInformativeText:@"Syncrosa will permanently remove embedded info from supported files. Continue only if you created a backup or are working on copies."];
    [alert addButtonWithTitle:@"Continue"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSAlert *finalAlert = [[[NSAlert alloc] init] autorelease];
    [finalAlert setMessageText:@"Final Warning"];
    [finalAlert setInformativeText:@"This action cannot be undone without a SyncrosaInfoEraserBackup. Continue?"];
    [finalAlert addButtonWithTitle:@"Erase"];
    [finalAlert addButtonWithTitle:@"Cancel"];
    if ([finalAlert runModal] != NSAlertFirstButtonReturn) return;

    [self runOperationWithStatus:@"Erasing embedded info..." block:^NSString *(void (^progress)(NSInteger, NSInteger)) {
        NSInteger unsupported = 0;
        NSInteger erased = [self eraseInfoWithProgress:progress unsupported:&unsupported];
        return [NSString stringWithFormat:@"Erase finished. Stripped %ld files. Unsupported/skipped: %ld.", (long)erased, (long)unsupported];
    }];
}

- (void)restoreClicked:(id)sender {
    [self runOperationWithStatus:@"Restoring original info..." block:^NSString *(void (^progress)(NSInteger, NSInteger)) {
        NSInteger missing = 0;
        NSInteger restored = [self restoreInfoWithProgress:progress missing:&missing];
        return [NSString stringWithFormat:@"Restore finished. Restored %ld files. Missing files: %ld.", (long)restored, (long)missing];
    }];
}

- (void)runOperationWithStatus:(NSString *)status block:(NSString *(^)(void (^progress)(NSInteger current, NSInteger total)))operation {
    if (!self.selectedFolderURL || self.isProcessing) return;
    NSString *(^operationCopy)(void (^progress)(NSInteger current, NSInteger total)) = [operation copy];
    [self setControlsBusy:YES];
    self.progressIndicator.doubleValue = 0;
    self.progressIndicator.maxValue = MAX(self.foundFiles.count, 1);
    self.statusLabel.stringValue = status;
    [self clearLogView];
    [self log:status];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *message = nil;
        @try {
            message = operationCopy(^(NSInteger current, NSInteger total) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.progressIndicator.maxValue = MAX(total, 1);
                    self.progressIndicator.doubleValue = current;
                });
            });
        } @catch (NSException *exception) {
            message = [NSString stringWithFormat:@"ERROR: %@", exception.reason ?: @""];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusLabel.stringValue = message ?: @"Done";
            [self log:message ?: @"Done"];
            [self setControlsBusy:NO];
            [IGNotificationView showInView:self.view message:message ?: @"Done" isError:[message hasPrefix:@"ERROR:"]];
        });
#if !__has_feature(objc_arc)
        [operationCopy release];
#endif
#if !__has_feature(objc_arc)
        [pool drain];
#endif
    });
}

#pragma mark - Backup / Erase / Restore

- (NSString *)backupDirectoryPath {
    return [self.selectedFolderURL.path stringByAppendingPathComponent:IGInfoEraserBackupDirName];
}

- (NSInteger)backupOriginalInfoWithProgress:(void(^)(NSInteger current, NSInteger total))progress manifestPath:(NSString **)manifestPath {
    NSString *backupDir = [self backupDirectoryPath];
    NSString *tagsDir = [backupDir stringByAppendingPathComponent:@"tags"];
    [[NSFileManager defaultManager] createDirectoryAtPath:tagsDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSMutableArray *items = [NSMutableArray array];
    NSInteger supported = 0;
    NSInteger total = self.foundFiles.count;

    for (NSInteger i = 0; i < total; i++) {
        NSURL *url = self.foundFiles[i];
        NSString *ext = [[url pathExtension] lowercaseString];
        NSString *itemID = [[[NSProcessInfo processInfo] globallyUniqueString] stringByReplacingOccurrencesOfString:@"." withString:@"-"];
        NSMutableDictionary *item = [NSMutableDictionary dictionary];
        [item setObject:itemID forKey:@"id"];
        [item setObject:[self relativePathForURL:url] forKey:@"relativePath"];
        [item setObject:ext ?: @"" forKey:@"extension"];
        BOOL supportedExtension = [self isSupportedInfoExtension:ext];
        [item setObject:[NSNumber numberWithBool:supportedExtension] forKey:@"supported"];
        [item setObject:@"" forKey:@"id3v2File"];
        [item setObject:@"" forKey:@"id3v1File"];
        [item setObject:@0 forKey:@"id3v2Bytes"];
        [item setObject:@0 forKey:@"id3v1Bytes"];
        [item setObject:@"" forKey:@"mp4AtomFile"];
        [item setObject:@0 forKey:@"mp4AtomOffset"];
        [item setObject:@0 forKey:@"mp4AtomBytes"];
        [item setObject:@"" forKey:@"mp4AtomType"];
        if (supportedExtension) {
            supported++;
        }

        if ([ext isEqualToString:@"mp3"]) {
            unsigned long long fileSize = 0;
            NSUInteger id3v2Length = 0;
            NSUInteger id3v1Length = 0;
            [self mp3TagRangesForURL:url id3v2Length:&id3v2Length id3v1Length:&id3v1Length fileSize:&fileSize];
            NSFileHandle *input = [NSFileHandle fileHandleForReadingAtPath:url.path];
            if (input && id3v2Length > 0) {
                [input seekToFileOffset:0];
                NSData *data = [input readDataOfLength:id3v2Length];
                NSString *tagName = [NSString stringWithFormat:@"%@.id3v2", itemID];
                [data writeToFile:[tagsDir stringByAppendingPathComponent:tagName] atomically:YES];
                [item setObject:[@"tags" stringByAppendingPathComponent:tagName] forKey:@"id3v2File"];
                [item setObject:@(id3v2Length) forKey:@"id3v2Bytes"];
            }
            if (input && id3v1Length > 0 && fileSize >= 128) {
                [input seekToFileOffset:fileSize - 128];
                NSData *data = [input readDataOfLength:128];
                NSString *tagName = [NSString stringWithFormat:@"%@.id3v1", itemID];
                [data writeToFile:[tagsDir stringByAppendingPathComponent:tagName] atomically:YES];
                [item setObject:[@"tags" stringByAppendingPathComponent:tagName] forKey:@"id3v1File"];
                [item setObject:@128 forKey:@"id3v1Bytes"];
            }
            [input closeFile];
        } else if ([self isMP4LikeExtension:ext]) {
            NSDictionary *atom = [self mp4MetadataAtomForPath:url.path];
            if (atom) {
                unsigned long long offset = [[atom objectForKey:@"offset"] unsignedLongLongValue];
                NSUInteger size = [[atom objectForKey:@"size"] unsignedIntegerValue];
                NSString *type = [atom objectForKey:@"type"];
                NSData *data = [self readDataFromPath:url.path offset:offset length:size];
                if (data.length == size) {
                    NSString *tagName = [NSString stringWithFormat:@"%@.%@", itemID, type ?: @"ilst"];
                    [data writeToFile:[tagsDir stringByAppendingPathComponent:tagName] atomically:YES];
                    [item setObject:[@"tags" stringByAppendingPathComponent:tagName] forKey:@"mp4AtomFile"];
                    [item setObject:@(offset) forKey:@"mp4AtomOffset"];
                    [item setObject:@(size) forKey:@"mp4AtomBytes"];
                    [item setObject:type ?: @"ilst" forKey:@"mp4AtomType"];
                }
            }
        }

        [items addObject:item];
        if (progress) progress(i + 1, total);
    }

    NSDictionary *manifest = @{
        @"version": @1,
        @"createdAt": @([[NSDate date] timeIntervalSince1970]),
        @"format": @"syncrosa-info-eraser-sidecar-v2",
        @"items": items
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:nil];
    NSString *path = [backupDir stringByAppendingPathComponent:@"manifest.json"];
    [json writeToFile:path atomically:YES];
    if (manifestPath) *manifestPath = path;
    return supported;
}

- (NSInteger)eraseInfoWithProgress:(void(^)(NSInteger current, NSInteger total))progress unsupported:(NSInteger *)unsupportedOut {
    NSInteger erased = 0;
    NSInteger unsupported = 0;
    NSInteger total = self.foundFiles.count;
    for (NSInteger i = 0; i < total; i++) {
        NSURL *url = self.foundFiles[i];
        NSString *ext = [[url pathExtension] lowercaseString];

        if ([ext isEqualToString:@"mp3"]) {
            unsigned long long fileSize = 0;
            NSUInteger id3v2Length = 0;
            NSUInteger id3v1Length = 0;
            [self mp3TagRangesForURL:url id3v2Length:&id3v2Length id3v1Length:&id3v1Length fileSize:&fileSize];
            if (id3v2Length > 0 || id3v1Length > 0) {
                NSString *tempPath = [url.path stringByAppendingFormat:@".syncrosa-strip-%@", [[NSProcessInfo processInfo] globallyUniqueString]];
                if ([self copyFile:url.path toPath:tempPath start:id3v2Length end:fileSize - id3v1Length] &&
                    [self replaceOriginalPath:url.path withTempPath:tempPath]) {
                    erased++;
                }
                [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
            }
        } else if ([self isMP4LikeExtension:ext]) {
            NSDictionary *atom = [self mp4MetadataAtomForPath:url.path];
            if (atom) {
                unsigned long long offset = [[atom objectForKey:@"offset"] unsignedLongLongValue];
                NSUInteger size = [[atom objectForKey:@"size"] unsignedIntegerValue];
                NSUInteger headerSize = [[atom objectForKey:@"headerSize"] unsignedIntegerValue];
                NSData *freeData = IGInfoEraserFreeAtomData(size, headerSize);
                if ([self writeData:freeData toPath:url.path offset:offset]) {
                    erased++;
                }
            }
        } else {
            unsupported++;
        }
        if (progress) progress(i + 1, total);
    }
    if (unsupportedOut) *unsupportedOut = unsupported;
    return erased;
}

- (NSInteger)restoreInfoWithProgress:(void(^)(NSInteger current, NSInteger total))progress missing:(NSInteger *)missingOut {
    NSString *backupDir = [self backupDirectoryPath];
    NSString *manifestPath = [backupDir stringByAppendingPathComponent:@"manifest.json"];
    NSData *json = [NSData dataWithContentsOfFile:manifestPath];
    if (!json) {
        [NSException raise:@"InfoEraser" format:@"Backup manifest not found: %@", manifestPath];
    }
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
    NSArray *items = [manifest objectForKey:@"items"];
    NSInteger restored = 0;
    NSInteger missing = 0;
    NSInteger total = items.count;

    for (NSInteger i = 0; i < total; i++) {
        NSDictionary *item = items[i];
        if (![[item objectForKey:@"supported"] boolValue]) {
            if (progress) progress(i + 1, total);
            continue;
        }
        NSString *relativePath = [item objectForKey:@"relativePath"];
        NSString *path = [self safePathByJoiningBase:self.selectedFolderURL.path relative:relativePath];
        if (path.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            missing++;
            if (progress) progress(i + 1, total);
            continue;
        }

        NSString *ext = [[item objectForKey:@"extension"] lowercaseString];
        if ([ext isEqualToString:@"mp3"]) {
            NSData *id3v2 = [self tagDataFromBackupDir:backupDir relative:[item objectForKey:@"id3v2File"]];
            NSData *id3v1 = [self tagDataFromBackupDir:backupDir relative:[item objectForKey:@"id3v1File"]];
            unsigned long long fileSize = 0;
            NSUInteger id3v2Length = 0;
            NSUInteger id3v1Length = 0;
            [self mp3TagRangesForURL:[NSURL fileURLWithPath:path] id3v2Length:&id3v2Length id3v1Length:&id3v1Length fileSize:&fileSize];

            NSString *bodyPath = [path stringByAppendingFormat:@".syncrosa-body-%@", [[NSProcessInfo processInfo] globallyUniqueString]];
            NSString *finalPath = [path stringByAppendingFormat:@".syncrosa-restore-%@", [[NSProcessInfo processInfo] globallyUniqueString]];
            if (![self copyFile:path toPath:bodyPath start:id3v2Length end:fileSize - id3v1Length]) {
                if (progress) progress(i + 1, total);
                continue;
            }

            [[NSFileManager defaultManager] createFileAtPath:finalPath contents:nil attributes:nil];
            NSFileHandle *output = [NSFileHandle fileHandleForWritingAtPath:finalPath];
            if (id3v2.length > 0) [output writeData:id3v2];
            NSFileHandle *body = [NSFileHandle fileHandleForReadingAtPath:bodyPath];
            NSData *chunk = nil;
            while ((chunk = [body readDataOfLength:IGInfoEraserChunkSize]).length > 0) {
                [output writeData:chunk];
            }
            [body closeFile];
            if (id3v1.length > 0) [output writeData:id3v1];
            [output closeFile];

            if ([self replaceOriginalPath:path withTempPath:finalPath]) {
                restored++;
            }
            [[NSFileManager defaultManager] removeItemAtPath:bodyPath error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:finalPath error:nil];
        } else if ([self isMP4LikeExtension:ext]) {
            NSData *atomData = [self tagDataFromBackupDir:backupDir relative:[item objectForKey:@"mp4AtomFile"]];
            NSUInteger expectedBytes = [[item objectForKey:@"mp4AtomBytes"] unsignedIntegerValue];
            unsigned long long offset = [[item objectForKey:@"mp4AtomOffset"] unsignedLongLongValue];
            if (atomData.length == expectedBytes && expectedBytes > 0 && [self writeData:atomData toPath:path offset:offset]) {
                restored++;
            }
        }
        if (progress) progress(i + 1, total);
    }

    if (missingOut) *missingOut = missing;
    return restored;
}

#pragma mark - MP4 Helpers

- (NSDictionary *)mp4MetadataAtomForPath:(NSString *)path {
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    unsigned long long fileSize = [[attrs objectForKey:NSFileSize] unsignedLongLongValue];
    if (fileSize <= 8) return nil;

    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!handle) return nil;
    NSDictionary *atom = [self findMP4AtomInHandle:handle
                                             start:0
                                               end:fileSize
                                              path:@[@"moov", @"udta", @"meta", @"ilst"]
                                             index:0];
    [handle closeFile];
    return atom;
}

- (NSDictionary *)findMP4AtomInHandle:(NSFileHandle *)handle start:(unsigned long long)start end:(unsigned long long)end path:(NSArray *)path index:(NSUInteger)index {
    unsigned long long cursor = start;
    while (cursor + 8 <= end) {
        NSDictionary *atom = [self readMP4AtomHeaderInHandle:handle offset:cursor parentEnd:end];
        if (!atom) break;

        unsigned long long offset = [[atom objectForKey:@"offset"] unsignedLongLongValue];
        unsigned long long size = [[atom objectForKey:@"size"] unsignedLongLongValue];
        NSUInteger headerSize = [[atom objectForKey:@"headerSize"] unsignedIntegerValue];
        if (size < headerSize || offset + size > end) break;

        NSString *type = [atom objectForKey:@"type"];
        if ([type isEqualToString:[path objectAtIndex:index]]) {
            if (index == path.count - 1) {
                return atom;
            }
            unsigned long long extraHeader = [type isEqualToString:@"meta"] ? 4 : 0;
            unsigned long long childStart = offset + headerSize + extraHeader;
            if (childStart < offset + size) {
                NSDictionary *found = [self findMP4AtomInHandle:handle
                                                          start:childStart
                                                            end:offset + size
                                                           path:path
                                                          index:index + 1];
                if (found) return found;
            }
        }

        cursor += size;
    }
    return nil;
}

- (NSDictionary *)readMP4AtomHeaderInHandle:(NSFileHandle *)handle offset:(unsigned long long)offset parentEnd:(unsigned long long)parentEnd {
    [handle seekToFileOffset:offset];
    NSData *header = [handle readDataOfLength:16];
    if (header.length < 8) return nil;

    uint32_t size32 = IGInfoEraserReadBE32(header, 0);
    NSData *typeData = [header subdataWithRange:NSMakeRange(4, 4)];
    NSString *type = [[[NSString alloc] initWithData:typeData encoding:NSMacOSRomanStringEncoding] autorelease];
    NSUInteger headerSize = 8;
    unsigned long long atomSize = size32;

    if (size32 == 1) {
        if (header.length < 16) return nil;
        atomSize = IGInfoEraserReadBE64(header, 8);
        headerSize = 16;
    } else if (size32 == 0) {
        atomSize = parentEnd - offset;
    }

    if (atomSize < headerSize || type.length == 0) return nil;
    return @{
        @"type": type,
        @"offset": @(offset),
        @"size": @(atomSize),
        @"headerSize": @(headerSize)
    };
}

- (NSData *)readDataFromPath:(NSString *)path offset:(unsigned long long)offset length:(NSUInteger)length {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!handle) return nil;
    [handle seekToFileOffset:offset];
    NSData *data = [handle readDataOfLength:length];
    [handle closeFile];
    return data;
}

- (BOOL)writeData:(NSData *)data toPath:(NSString *)path offset:(unsigned long long)offset {
    if (data.length == 0) return NO;
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) return NO;
    [handle seekToFileOffset:offset];
    [handle writeData:data];
    [handle closeFile];
    return YES;
}

#pragma mark - MP3 Helpers

- (NSUInteger)syncsafeSizeFromHeader:(NSData *)header {
    const unsigned char *bytes = [header bytes];
    return ((bytes[6] & 0x7F) << 21) | ((bytes[7] & 0x7F) << 14) | ((bytes[8] & 0x7F) << 7) | (bytes[9] & 0x7F);
}

- (void)mp3TagRangesForURL:(NSURL *)url id3v2Length:(NSUInteger *)id3v2Length id3v1Length:(NSUInteger *)id3v1Length fileSize:(unsigned long long *)fileSize {
    if (id3v2Length) *id3v2Length = 0;
    if (id3v1Length) *id3v1Length = 0;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:nil];
    unsigned long long size = [[attrs objectForKey:NSFileSize] unsignedLongLongValue];
    if (fileSize) *fileSize = size;

    NSFileHandle *input = [NSFileHandle fileHandleForReadingAtPath:url.path];
    NSData *header = [input readDataOfLength:10];
    if (header.length == 10) {
        const unsigned char *bytes = [header bytes];
        if (bytes[0] == 'I' && bytes[1] == 'D' && bytes[2] == '3') {
            NSUInteger length = 10 + [self syncsafeSizeFromHeader:header];
            if ((bytes[5] & 0x10) != 0) length += 10;
            if (length <= size && id3v2Length) *id3v2Length = length;
        }
    }
    if (size >= 128) {
        [input seekToFileOffset:size - 128];
        NSData *tail = [input readDataOfLength:3];
        if (tail.length == 3) {
            const unsigned char *bytes = [tail bytes];
            if (bytes[0] == 'T' && bytes[1] == 'A' && bytes[2] == 'G' && id3v1Length) {
                *id3v1Length = 128;
            }
        }
    }
    [input closeFile];
}

- (BOOL)copyFile:(NSString *)sourcePath toPath:(NSString *)destPath start:(unsigned long long)start end:(unsigned long long)end {
    if (end <= start) return NO;
    [[NSFileManager defaultManager] createFileAtPath:destPath contents:nil attributes:nil];
    NSFileHandle *input = [NSFileHandle fileHandleForReadingAtPath:sourcePath];
    NSFileHandle *output = [NSFileHandle fileHandleForWritingAtPath:destPath];
    if (!input || !output) return NO;
    [input seekToFileOffset:start];
    unsigned long long remaining = end - start;
    while (remaining > 0) {
        NSUInteger readLength = (NSUInteger)MIN((unsigned long long)IGInfoEraserChunkSize, remaining);
        NSData *chunk = [input readDataOfLength:readLength];
        if (chunk.length == 0) break;
        [output writeData:chunk];
        remaining -= chunk.length;
    }
    [input closeFile];
    [output closeFile];
    if (remaining > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:destPath error:nil];
        return NO;
    }
    return YES;
}

- (BOOL)replaceOriginalPath:(NSString *)originalPath withTempPath:(NSString *)tempPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *backupPath = [originalPath stringByAppendingFormat:@".syncrosa-tmp-%@", [[NSProcessInfo processInfo] globallyUniqueString]];
    NSError *error = nil;
    if (![fm moveItemAtPath:originalPath toPath:backupPath error:&error]) {
        return NO;
    }
    if ([fm moveItemAtPath:tempPath toPath:originalPath error:&error]) {
        [fm removeItemAtPath:backupPath error:nil];
        return YES;
    }
    [fm moveItemAtPath:backupPath toPath:originalPath error:nil];
    return NO;
}

- (NSData *)tagDataFromBackupDir:(NSString *)backupDir relative:(NSString *)relative {
    if (![relative isKindOfClass:[NSString class]] || relative.length == 0) return nil;
    NSString *path = [self safePathByJoiningBase:backupDir relative:relative];
    if (path.length == 0) return nil;
    return [NSData dataWithContentsOfFile:path];
}

- (NSString *)relativePathForURL:(NSURL *)url {
    NSString *base = [self.selectedFolderURL.path stringByStandardizingPath];
    NSString *path = [url.path stringByStandardizingPath];
    NSString *prefix = [base stringByAppendingString:@"/"];
    if ([path hasPrefix:prefix]) {
        return [path substringFromIndex:prefix.length];
    }
    return url.lastPathComponent;
}

- (NSString *)safePathByJoiningBase:(NSString *)base relative:(NSString *)relative {
    if (![relative isKindOfClass:[NSString class]] || relative.length == 0) return nil;
    NSString *candidate = [[base stringByAppendingPathComponent:relative] stringByStandardizingPath];
    NSString *standardBase = [base stringByStandardizingPath];
    NSString *prefix = [standardBase stringByAppendingString:@"/"];
    if ([candidate isEqualToString:standardBase] || [candidate hasPrefix:prefix]) {
        return candidate;
    }
    return nil;
}

@end
