#import "IGOperationActivity.h"
#import <CommonCrypto/CommonDigest.h>
#import <math.h>

NSString * const IGOperationActivityDidChangeNotification = @"IGOperationActivityDidChangeNotification";
NSString * const IGOperationRecoveryDidChangeNotification = @"IGOperationRecoveryDidChangeNotification";
NSString * const IGOperationActivityUSBExportIdentifier = @"usb-export";
NSString * const IGOperationActivityAIPlaylistIdentifier = @"ai-playlist";
NSString * const IGOperationActivityVideoMetadataIdentifier = @"video-metadata";

static NSError *IGRecoveryError(NSString *message) {
    return [NSError errorWithDomain:@"SyncrosaRecovery" code:1 userInfo:@{NSLocalizedDescriptionKey: message ?: @"Recovery information could not be processed."}];
}

static NSString *IGRecoveryRecordName(NSString *identifier) {
    NSData *bytes = [identifier dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256([bytes bytes], (CC_LONG)[bytes length], digest);
    NSMutableString *name = [NSMutableString string];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) [name appendFormat:@"%02x", digest[index]];
    return [name stringByAppendingPathExtension:@"plist"];
}

static NSDictionary *IGRecoveryNormalizedMarker(id value) {
    if (![value isKindOfClass:[NSDictionary class]]) return nil;
    NSString *identifier = value[@"id"];
    if (![identifier isKindOfClass:[NSString class]] || [identifier length] == 0 || [identifier length] > 512) return nil;
    for (NSString *key in @[@"tool", @"title", @"message"]) {
        if (![value[key] isKindOfClass:[NSString class]] || [value[key] length] > 100000) return nil;
    }
    id rawCount = value[@"affectedCount"];
    if (![rawCount isKindOfClass:[NSNumber class]] || [rawCount integerValue] < 0) return nil;
    id rawDate = value[@"startedAt"];
    NSNumber *timestamp = nil;
    if ([rawDate isKindOfClass:[NSNumber class]] && isfinite([rawDate doubleValue]) && [rawDate doubleValue] >= 0) timestamp = rawDate;
    else if ([rawDate isKindOfClass:[NSString class]]) {
        NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
        formatter.locale = [[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease];
        formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
        NSDate *date = [formatter dateFromString:rawDate];
        if (date) timestamp = @([date timeIntervalSince1970]);
    }
    if (!timestamp) return nil;
    NSString *backup = [value[@"backupPath"] isKindOfClass:[NSString class]] ? value[@"backupPath"] : @"";
    return @{@"id": identifier, @"tool": value[@"tool"], @"title": value[@"title"], @"message": value[@"message"],
             @"startedAt": timestamp, @"affectedCount": @([rawCount integerValue]), @"backupPath": backup};
}

@interface IGOperationActivity ()
@property (nonatomic, readwrite, copy) NSString *activeIdentifier;
@property (nonatomic, readwrite, assign) double progress;
@property (nonatomic, copy) NSString *recoveryRoot;
@property (nonatomic, retain) NSMutableDictionary *storedRecoveryMarkers;
@property (nonatomic, retain) NSMutableSet *runningRecoveryIDs;
@property (nonatomic, retain) NSMutableArray *recoveryLoadWarnings;
@property (nonatomic, retain) NSMutableArray *recoveryWriteWarnings;
@end

@implementation IGOperationActivity

+ (instancetype)sharedActivity {
    static IGOperationActivity *activity = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ activity = [[self alloc] init]; });
    return activity;
}

- (id)init {
    NSArray *directories = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *base = [directories count] > 0 ? directories[0] : NSHomeDirectory();
    return [self initWithRecoveryDirectory:[base stringByAppendingPathComponent:@"Syncrosa"]];
}

- (id)initWithRecoveryDirectory:(NSString *)directory {
    self = [super init];
    if (self) {
        self.recoveryRoot = directory;
        self.storedRecoveryMarkers = [NSMutableDictionary dictionary];
        self.runningRecoveryIDs = [NSMutableSet set];
        self.recoveryLoadWarnings = [NSMutableArray array];
        self.recoveryWriteWarnings = [NSMutableArray array];
        [self reloadRecoveryMarkers];
    }
    return self;
}

- (NSString *)recoveryRecordsDirectory {
    return [[self.recoveryRoot stringByAppendingPathComponent:@"Recovery Operations"] stringByAppendingPathComponent:@"Cocoa"];
}

- (NSString *)recoveryRecordPath:(NSString *)identifier {
    return [[self recoveryRecordsDirectory] stringByAppendingPathComponent:IGRecoveryRecordName(identifier)];
}

- (BOOL)requireRecoveryDirectory:(NSString *)directory error:(NSError **)error {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:directory error:error];
    if (attributes && [attributes[NSFileType] isEqualToString:NSFileTypeDirectory]) return YES;
    if (error && !*error) *error = IGRecoveryError(@"The recovery location is not a regular directory.");
    return NO;
}

- (NSData *)readRecoveryDataAtPath:(NSString *)path error:(NSError **)error {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:error];
    if (![attributes[NSFileType] isEqualToString:NSFileTypeRegular] || [attributes[NSFileSize] unsignedLongLongValue] > 1024ULL * 1024ULL) {
        if (error) *error = IGRecoveryError(@"The recovery record is invalid or unreadable.");
        return nil;
    }
    return [NSData dataWithContentsOfFile:path options:0 error:error];
}

- (NSDictionary *)readRecoveryRecordAtPath:(NSString *)path error:(NSError **)error {
    NSData *data = [self readRecoveryDataAtPath:path error:error];
    if (!data) return nil;
    id record = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:error];
    if (![record isKindOfClass:[NSDictionary class]] || ![record[@"schemaVersion"] isEqual:@1]) {
        if (error) *error = IGRecoveryError(@"The recovery record has an unsupported format.");
        return nil;
    }
    NSDictionary *marker = IGRecoveryNormalizedMarker(record[@"marker"]);
    if (!marker || ![[path lastPathComponent] isEqualToString:IGRecoveryRecordName(marker[@"id"])]) {
        if (error) *error = IGRecoveryError(@"The recovery record identifier does not match its file.");
        return nil;
    }
    return marker;
}

- (BOOL)persistRecoveryMarker:(NSDictionary *)marker error:(NSError **)error {
    NSFileManager *manager = [NSFileManager defaultManager];
    if (![manager createDirectoryAtPath:self.recoveryRoot withIntermediateDirectories:YES attributes:nil error:error] ||
        ![self requireRecoveryDirectory:self.recoveryRoot error:error]) return NO;
    NSString *parent = [self.recoveryRoot stringByAppendingPathComponent:@"Recovery Operations"];
    for (NSString *directory in @[parent, [self recoveryRecordsDirectory]]) {
        if (![manager fileExistsAtPath:directory] && ![manager createDirectoryAtPath:directory withIntermediateDirectories:NO attributes:nil error:error]) return NO;
        if (![self requireRecoveryDirectory:directory error:error]) return NO;
    }
    NSString *path = [self recoveryRecordPath:marker[@"id"]];
    if ([manager fileExistsAtPath:path]) {
        NSDictionary *existing = [self readRecoveryRecordAtPath:path error:error];
        if ([existing isEqualToDictionary:marker]) return YES;
        if (error && !*error) *error = IGRecoveryError(@"Recovery information changed while it was being processed.");
        return NO;
    }
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:@{@"schemaVersion": @1, @"marker": marker} format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    return data && [data writeToFile:path options:NSDataWritingAtomic error:error];
}

- (void)addRecoveryWriteWarning:(NSError *)error {
    NSString *message = [error localizedDescription] ?: @"Recovery information could not be saved.";
    if (![self.recoveryWriteWarnings containsObject:message]) [self.recoveryWriteWarnings addObject:message];
    if ([self.recoveryWriteWarnings count] > 25) [self.recoveryWriteWarnings removeObjectAtIndex:0];
}

- (NSArray *)recoveryMarkers {
    @synchronized(self) {
        NSMutableArray *markers = [NSMutableArray array];
        for (NSString *identifier in self.storedRecoveryMarkers) {
            if (![self.runningRecoveryIDs containsObject:identifier]) [markers addObject:self.storedRecoveryMarkers[identifier]];
        }
        [markers sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            NSComparisonResult result = [right[@"startedAt"] compare:left[@"startedAt"]];
            return result == NSOrderedSame ? [left[@"id"] compare:right[@"id"]] : result;
        }];
        return [[[NSArray alloc] initWithArray:markers] autorelease];
    }
}

- (NSArray *)recoveryWarnings {
    @synchronized(self) {
        NSMutableArray *warnings = [NSMutableArray arrayWithArray:self.recoveryLoadWarnings];
        for (NSString *warning in self.recoveryWriteWarnings) if (![warnings containsObject:warning]) [warnings addObject:warning];
        return [[[NSArray alloc] initWithArray:warnings] autorelease];
    }
}

- (void)migrateLegacyRecoveryFile:(NSString *)name propertyList:(BOOL)propertyList {
    NSString *path = [self.recoveryRoot stringByAppendingPathComponent:name];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return;
    NSError *error = nil;
    NSData *data = [self requireRecoveryDirectory:self.recoveryRoot error:&error] ? [self readRecoveryDataAtPath:path error:&error] : nil;
    id decoded = data ? (propertyList ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&error] : [NSJSONSerialization JSONObjectWithData:data options:0 error:&error]) : nil;
    NSDictionary *marker = IGRecoveryNormalizedMarker(decoded);
    if (!marker || ![self persistRecoveryMarker:marker error:&error]) {
        [self.recoveryLoadWarnings addObject:[NSString stringWithFormat:@"Previous recovery file %@ could not be migrated; it was preserved.", name]];
        return;
    }
    self.storedRecoveryMarkers[marker[@"id"]] = marker;
    NSData *current = [self readRecoveryDataAtPath:path error:&error];
    if (![current isEqualToData:data] || ![[NSFileManager defaultManager] removeItemAtPath:path error:&error]) {
        [self.recoveryLoadWarnings addObject:[NSString stringWithFormat:@"Previous recovery file %@ changed or could not be cleared; it was preserved.", name]];
    }
}

- (void)reloadRecoveryMarkers {
    @synchronized(self) {
        [self.recoveryLoadWarnings removeAllObjects];
        NSMutableDictionary *loaded = [NSMutableDictionary dictionary];
        NSString *directory = [self recoveryRecordsDirectory];
        NSFileManager *manager = [NSFileManager defaultManager];
        if ([manager fileExistsAtPath:directory]) {
            NSError *directoryError = nil;
            BOOL safeHierarchy = [self requireRecoveryDirectory:self.recoveryRoot error:&directoryError] &&
                [self requireRecoveryDirectory:[self.recoveryRoot stringByAppendingPathComponent:@"Recovery Operations"] error:&directoryError] &&
                [self requireRecoveryDirectory:directory error:&directoryError];
            NSArray *files = safeHierarchy ? [manager contentsOfDirectoryAtPath:directory error:&directoryError] : nil;
            if (!files) [self.recoveryLoadWarnings addObject:@"Recovery records could not be loaded; existing files were preserved."];
            for (NSString *name in files) {
                if (![[name pathExtension] isEqualToString:@"plist"]) continue;
                NSError *error = nil;
                NSDictionary *marker = [self readRecoveryRecordAtPath:[directory stringByAppendingPathComponent:name] error:&error];
                if (marker) loaded[marker[@"id"]] = marker;
                else [self.recoveryLoadWarnings addObject:[NSString stringWithFormat:@"Recovery record %@ could not be read; it was preserved.", name]];
            }
        }
        for (NSString *identifier in self.runningRecoveryIDs) {
            if (self.storedRecoveryMarkers[identifier]) loaded[identifier] = self.storedRecoveryMarkers[identifier];
        }
        self.storedRecoveryMarkers = loaded;
        [self migrateLegacyRecoveryFile:@"active-operation.plist" propertyList:YES];
        [self migrateLegacyRecoveryFile:@"active-operation.json" propertyList:NO];
    }
}

- (BOOL)saveRecoveryMarker:(NSDictionary *)marker error:(NSError **)error {
    BOOL saved = NO;
    @synchronized(self) {
        NSError *failure = nil;
        NSDictionary *normalized = IGRecoveryNormalizedMarker(marker);
        if (normalized) {
            saved = [self persistRecoveryMarker:normalized error:&failure];
            self.storedRecoveryMarkers[normalized[@"id"]] = normalized;
            [self.runningRecoveryIDs addObject:normalized[@"id"]];
        } else failure = IGRecoveryError(@"The recovery marker is invalid.");
        if (!saved) {
            if (error) *error = failure;
            [self addRecoveryWriteWarning:failure];
        }
    }
    [self postRecoveryChange];
    return saved;
}

- (BOOL)removeRecoveryMarker:(NSString *)identifier error:(NSError **)error {
    if (!identifier || !self.storedRecoveryMarkers[identifier]) return YES;
    NSString *path = [self recoveryRecordPath:identifier];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (![self requireRecoveryDirectory:self.recoveryRoot error:error] ||
            ![self requireRecoveryDirectory:[self.recoveryRoot stringByAppendingPathComponent:@"Recovery Operations"] error:error] ||
            ![self requireRecoveryDirectory:[self recoveryRecordsDirectory] error:error]) return NO;
        NSDictionary *marker = [self readRecoveryRecordAtPath:path error:error];
        if (!marker || ![marker[@"id"] isEqualToString:identifier] || ![[NSFileManager defaultManager] removeItemAtPath:path error:error]) return NO;
    }
    [self.storedRecoveryMarkers removeObjectForKey:identifier];
    return YES;
}

- (BOOL)finishRecoveryMarkerWithIdentifier:(NSString *)identifier error:(NSError **)error {
    BOOL removed = NO;
    @synchronized(self) {
        NSError *failure = nil;
        if (identifier) [self.runningRecoveryIDs removeObject:identifier];
        removed = [self removeRecoveryMarker:identifier error:&failure];
        if (!removed) {
            if (error) *error = failure;
            [self addRecoveryWriteWarning:failure];
        }
    }
    [self postRecoveryChange];
    return removed;
}

- (BOOL)clearRecoveryMarkerWithIdentifier:(NSString *)identifier error:(NSError **)error {
    BOOL removed = NO;
    @synchronized(self) {
        NSError *failure = nil;
        if ([self.runningRecoveryIDs containsObject:identifier]) failure = IGRecoveryError(@"A running operation cannot be removed from recovery.");
        else removed = [self removeRecoveryMarker:identifier error:&failure];
        if (!removed) {
            if (error) *error = failure;
            [self addRecoveryWriteWarning:failure];
        }
    }
    [self postRecoveryChange];
    return removed;
}

- (BOOL)beginOperationWithIdentifier:(NSString *)identifier {
    @synchronized(self) {
        if ([identifier length] == 0 || [self.activeIdentifier length] > 0) return NO;
        self.activeIdentifier = identifier;
        self.progress = 0.0;
    }
    [self postChange];
    return YES;
}

- (void)updateProgress:(double)progress forIdentifier:(NSString *)identifier {
    @synchronized(self) {
        if (![self.activeIdentifier isEqualToString:identifier]) return;
        self.progress = MIN(1.0, MAX(0.0, progress));
    }
    [self postChange];
}

- (void)finishOperationWithIdentifier:(NSString *)identifier {
    @synchronized(self) {
        if (![self.activeIdentifier isEqualToString:identifier]) return;
        self.activeIdentifier = nil;
        self.progress = 0.0;
    }
    [self postChange];
}

- (BOOL)isOperationActiveWithIdentifier:(NSString *)identifier {
    @synchronized(self) { return [self.activeIdentifier isEqualToString:identifier]; }
}

- (void)postRecoveryChange {
    if ([NSThread isMainThread]) [[NSNotificationCenter defaultCenter] postNotificationName:IGOperationRecoveryDidChangeNotification object:self];
    else dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:IGOperationRecoveryDidChangeNotification object:self]; });
}

- (void)postChange {
    void (^postBlock)(void) = ^{
        NSDictionary *info = @{ @"identifier": self.activeIdentifier ?: @"", @"progress": @(self.progress) };
        [[NSNotificationCenter defaultCenter] postNotificationName:IGOperationActivityDidChangeNotification object:self userInfo:info];
    };
    if ([NSThread isMainThread]) postBlock();
    else dispatch_async(dispatch_get_main_queue(), postBlock);
}

- (void)dealloc {
#if !__has_feature(objc_arc)
    [_activeIdentifier release];
    [_recoveryRoot release];
    [_storedRecoveryMarkers release];
    [_runningRecoveryIDs release];
    [_recoveryLoadWarnings release];
    [_recoveryWriteWarnings release];
    [super dealloc];
#endif
}

@end
