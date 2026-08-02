#import "IGiTunesService.h"
#import "IGLogger.h"
#import <Cocoa/Cocoa.h>
#import <signal.h>
#import <errno.h>

@implementation IGiTunesService

static NSString *IGStringFromTaskData(NSData *data) {
    if (!data || data.length == 0) return @"";

    NSString *value = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if (!value) {
        value = [[[NSString alloc] initWithData:data encoding:NSMacOSRomanStringEncoding] autorelease];
    }
    if (!value) {
        value = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    }
    return value ?: @"";
}

static NSString *IGTrimmedScriptResult(NSString *value) {
    if (!value) return @"";
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
}

static NSString *IGAppleScriptLiteral(NSString *value) {
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

static NSString *IGAppleScriptListLiteral(NSArray *values) {
    NSMutableArray *parts = [NSMutableArray arrayWithCapacity:values.count];
    for (id value in values) {
        [parts addObject:IGAppleScriptLiteral([value isKindOfClass:[NSString class]] ? value : @"")];
    }
    return [NSString stringWithFormat:@"{%@}", [parts componentsJoinedByString:@", "]];
}

static NSString *IGTargetApplicationNameForScript(NSString *source) {
    if ([source rangeOfString:@"tell application \"iTunes\""].location != NSNotFound) {
        return @"iTunes";
    }
    if ([source rangeOfString:@"tell application \"Music\""].location != NSNotFound) {
        return @"Music";
    }
    return nil;
}

static BOOL IGProcessIsRunningWithPGrep(NSString *processName) {
    if (processName.length == 0) {
        return NO;
    }

    @try {
        NSTask *task = [[[NSTask alloc] init] autorelease];
        [task setLaunchPath:@"/usr/bin/pgrep"];
        [task setArguments:@[@"-x", processName]];
        [task setStandardOutput:[NSPipe pipe]];
        [task setStandardError:[NSPipe pipe]];
        [task launch];
        [task waitUntilExit];
        return [task terminationStatus] == 0;
    } @catch (NSException *exception) {
        [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"pgrep running check failed for %@: %@",
                                      processName,
                                      exception.reason ?: @"unknown error"]];
        return NO;
    }
}

static BOOL IGApplicationIsRunning(NSString *appName) {
    if (appName.length == 0) return NO;

    NSArray *runningApps = [[NSWorkspace sharedWorkspace] launchedApplications];
    for (NSDictionary *appInfo in runningApps) {
        NSString *runningName = [appInfo objectForKey:@"NSApplicationName"];
        if ([runningName isEqualToString:appName]) {
            NSNumber *pidNumber = [appInfo objectForKey:@"NSApplicationProcessIdentifier"];
            pid_t pid = [pidNumber respondsToSelector:@selector(intValue)] ? (pid_t)[pidNumber intValue] : 0;
            if (pid > 0) {
                errno = 0;
                return (kill(pid, 0) == 0 || errno == EPERM);
            }
            return YES;
        }
    }

    BOOL runningByProcessName = IGProcessIsRunningWithPGrep(appName);
    if (runningByProcessName) {
        [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"NSWorkspace did not list %@, but pgrep confirmed it is running.", appName]];
    }
    return runningByProcessName;
}

+ (instancetype)sharedService {
    static IGiTunesService *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (BOOL)iTunesIsRunning {
    return IGApplicationIsRunning(@"iTunes");
}

- (BOOL)launchITunesForUserActionWithOperation:(NSString *)operation {
    [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"User approved iTunes launch for %@.", operation ?: @"iTunes operation"]];
    BOOL launched = [[NSWorkspace sharedWorkspace] launchApplication:@"iTunes"];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:12.0];
    while (!IGApplicationIsRunning(@"iTunes") && [deadline timeIntervalSinceNow] > 0.0) {
        [NSThread sleepForTimeInterval:0.20];
    }
    BOOL running = IGApplicationIsRunning(@"iTunes");
    [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"User-approved iTunes launch result launched=%@ running=%@.",
                                  launched ? @"YES" : @"NO",
                                  running ? @"YES" : @"NO"]];
    return running;
}

- (NSString *)persistentIDForFilePath:(NSString *)filePath
                         errorMessage:(NSString **)errorMessage {
    if (errorMessage) {
        *errorMessage = nil;
    }
    if (![self iTunesIsRunning]) {
        if (errorMessage) {
            *errorMessage = @"iTunes is not running.";
        }
        return nil;
    }

    NSString *script = [NSString stringWithFormat:
        @"set sourcePath to %@\n"
        "set sourceAlias to POSIX file sourcePath as alias\n"
        "tell application \"iTunes\"\n"
        "    try\n"
        "        set t to some file track of library playlist 1 whose location is sourceAlias\n"
        "        return \"OK\" & tab & (persistent ID of t as text)\n"
        "    on error\n"
        "        repeat with t in every file track of library playlist 1\n"
        "            try\n"
        "                if (POSIX path of (location of t as alias)) is sourcePath then\n"
        "                    return \"OK\" & tab & (persistent ID of t as text)\n"
        "                end if\n"
        "            end try\n"
        "        end repeat\n"
        "    end try\n"
        "    return \"ERROR\" & tab & \"The selected file is not referenced by an iTunes track.\"\n"
        "end tell", IGAppleScriptLiteral(filePath)];

    NSString *result = [self runAppleScriptNamed:@"ipodConverter.findTrack" source:script];
    NSArray *parts = [result componentsSeparatedByString:@"\t"];
    if ([parts count] >= 2 && [[parts objectAtIndex:0] isEqualToString:@"OK"]) {
        return [parts objectAtIndex:1];
    }
    if (errorMessage) {
        *errorMessage = [parts count] >= 2 ? [parts objectAtIndex:1] : @"Could not find the selected track in iTunes.";
    }
    return nil;
}

- (BOOL)reapplyMetadataForPersistentID:(NSString *)persistentID
                          errorMessage:(NSString **)errorMessage {
    if (errorMessage) {
        *errorMessage = nil;
    }
    if ([persistentID length] == 0) {
        if (errorMessage) {
            *errorMessage = @"The iTunes track identifier is missing.";
        }
        return NO;
    }

    NSString *script = [NSString stringWithFormat:
        @"tell application \"iTunes\"\n"
        "    try\n"
        "        set t to some file track of library playlist 1 whose persistent ID is %@\n"
        "        set savedName to name of t\n"
        "        set savedArtist to artist of t\n"
        "        set savedAlbum to album of t\n"
        "        set savedAlbumArtist to album artist of t\n"
        "        set savedComposer to composer of t\n"
        "        set savedGenre to genre of t\n"
        "        set savedYear to year of t\n"
        "        set savedTrackNumber to track number of t\n"
        "        set savedTrackCount to track count of t\n"
        "        set savedDiscNumber to disc number of t\n"
        "        set savedDiscCount to disc count of t\n"
        "        set savedComment to comment of t\n"
        "        set savedGrouping to grouping of t\n"
        "        set savedArtwork to missing value\n"
        "        try\n"
        "            if (count of artworks of t) > 0 then set savedArtwork to data of artwork 1 of t\n"
        "        end try\n"
        "        refresh t\n"
        "        set name of t to savedName\n"
        "        set artist of t to savedArtist\n"
        "        set album of t to savedAlbum\n"
        "        set album artist of t to savedAlbumArtist\n"
        "        set composer of t to savedComposer\n"
        "        set genre of t to savedGenre\n"
        "        set year of t to savedYear\n"
        "        set track number of t to savedTrackNumber\n"
        "        set track count of t to savedTrackCount\n"
        "        set disc number of t to savedDiscNumber\n"
        "        set disc count of t to savedDiscCount\n"
        "        set comment of t to savedComment\n"
        "        set grouping of t to savedGrouping\n"
        "        if savedArtwork is not missing value then\n"
        "            if (count of artworks of t) is 0 then\n"
        "                make new artwork at t with properties {data:savedArtwork}\n"
        "            else\n"
        "                set data of artwork 1 of t to savedArtwork\n"
        "            end if\n"
        "        end if\n"
        "        return \"OK\"\n"
        "    on error errMsg number errNum\n"
        "        return \"ERROR\" & tab & (errNum as text) & \" \" & errMsg\n"
        "    end try\n"
        "end tell", IGAppleScriptLiteral(persistentID)];

    NSString *result = [self runAppleScriptNamed:@"ipodConverter.reapplyMetadata" source:script];
    if ([result isEqualToString:@"OK"]) {
        return YES;
    }
    if (errorMessage) {
        NSArray *parts = [result componentsSeparatedByString:@"\t"];
        *errorMessage = [parts count] >= 2 ? [parts objectAtIndex:1] : @"iTunes could not reapply the track metadata.";
    }
    return NO;
}

- (BOOL)ensureApplicationReady:(NSString *)appName forOperation:(NSString *)operation timeout:(NSTimeInterval)timeout {
    if (appName.length == 0) return YES;

    BOOL wasRunning = IGApplicationIsRunning(appName);
    if (!wasRunning) {
        [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"AppleScript '%@' needs %@, but automatic app launch is disabled.", operation ?: @"", appName]];
        return NO;
    }

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!IGApplicationIsRunning(appName) && [deadline timeIntervalSinceNow] > 0.0) {
        [NSThread sleepForTimeInterval:0.25];
    }

    if (!IGApplicationIsRunning(appName)) {
        [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"%@ did not become visible to NSWorkspace within %.0fs.", appName, timeout]];
        return NO;
    }

    // Old iTunes may report as running before its AppleEvent server is ready.
    if (!wasRunning) {
        [NSThread sleepForTimeInterval:1.5];
    }
    return YES;
}

- (NSInteger)readLibraryTrackCountSyncWithErrorMessage:(NSString **)errorMessage {
    if (errorMessage) {
        *errorMessage = nil;
    }

    if (![self iTunesIsRunning]) {
        if (errorMessage) {
            *errorMessage = @"iTunes is not running. Open iTunes or allow Syncrosa to open it when asked.";
        }
        return -1;
    }

    NSString *script =
        @"tell application \"iTunes\"\n"
        "    set trackCount to -1\n"
        "    set fileTrackCount to -1\n"
        "    set lastError to \"\"\n"
        "    try\n"
        "        set trackCount to count every track of library playlist 1\n"
        "    on error errMsg number errNum\n"
        "        set lastError to (errNum as text) & \" \" & errMsg\n"
        "    end try\n"
        "    try\n"
        "        set fileTrackCount to count every file track of library playlist 1\n"
        "    on error errMsg number errNum\n"
        "        if lastError is \"\" then set lastError to (errNum as text) & \" \" & errMsg\n"
        "    end try\n"
        "    if trackCount < 0 and fileTrackCount < 0 then\n"
        "        return \"ERROR\" & tab & lastError\n"
        "    end if\n"
        "    if fileTrackCount > trackCount then set trackCount to fileTrackCount\n"
        "    return \"OK\" & tab & (trackCount as text)\n"
        "end tell";

    NSString *raw = [self runAppleScriptNamed:@"library.count" source:script];
    NSArray *parts = raw.length > 0 ? [raw componentsSeparatedByString:@"\t"] : nil;
    if (parts.count >= 2 && [[parts objectAtIndex:0] isEqualToString:@"OK"]) {
        return [[parts objectAtIndex:1] integerValue];
    }

    NSString *simpleScript =
        @"tell application \"iTunes\"\n"
        "    try\n"
        "        return \"OK\" & tab & ((count of every track of library playlist 1) as text)\n"
        "    on error errMsg number errNum\n"
        "        return \"ERROR\" & tab & ((errNum as text) & \" \" & errMsg)\n"
        "    end try\n"
        "end tell";
    NSString *simpleRaw = [self runAppleScriptNamed:@"library.count.simpleFallback" source:simpleScript];
    NSArray *simpleParts = simpleRaw.length > 0 ? [simpleRaw componentsSeparatedByString:@"\t"] : nil;
    if (simpleParts.count >= 2 && [[simpleParts objectAtIndex:0] isEqualToString:@"OK"]) {
        return [[simpleParts objectAtIndex:1] integerValue];
    }

    if (errorMessage) {
        if (simpleParts.count >= 2 && [[simpleParts objectAtIndex:0] isEqualToString:@"ERROR"]) {
            *errorMessage = [simpleParts objectAtIndex:1];
        } else if (parts.count >= 2 && [[parts objectAtIndex:0] isEqualToString:@"ERROR"]) {
            *errorMessage = [parts objectAtIndex:1];
        } else {
            *errorMessage = @"Could not read iTunes library.";
        }
    }
    return -1;
}

- (NSString *)runAppleScript:(NSString *)source {
    return [self runAppleScriptNamed:@"generic" source:source];
}

- (void)fetchLibraryTrackCountWithCompletion:(void(^)(NSInteger trackCount, NSString *errorMessage))completionBlock {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *errorMessage = nil;
        NSInteger count = [self readLibraryTrackCountSyncWithErrorMessage:&errorMessage];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completionBlock) {
                completionBlock(count, errorMessage);
            }
        });
    });
}

- (NSString *)runAppleScriptNamed:(NSString *)name source:(NSString *)source {
    if (![source isKindOfClass:[NSString class]] || source.length == 0) {
        return @"";
    }

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *baseName = [NSString stringWithFormat:@"syncrosa-%@", [[NSProcessInfo processInfo] globallyUniqueString]];
    NSString *scriptPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[baseName stringByAppendingPathExtension:@"applescript"]];
    NSString *stdoutPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[baseName stringByAppendingPathExtension:@"stdout"]];
    NSString *stderrPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[baseName stringByAppendingPathExtension:@"stderr"]];
    NSString *result = nil;
    NSString *stdoutText = @"";
    NSString *stderrText = @"";
    int terminationStatus = -1;
    BOOL timedOut = NO;
    NSDate *started = [NSDate date];
    NSString *targetAppName = IGTargetApplicationNameForScript(source);
    NSTimeInterval taskTimeout = targetAppName.length > 0 ? 120.0 : 45.0;
    if ([name rangeOfString:@"covers.backupBatch"].location != NSNotFound) {
        taskTimeout = 600.0;
    }

    @synchronized ([IGiTunesService class]) {
    @try {
        if (targetAppName.length > 0 && ![self ensureApplicationReady:targetAppName forOperation:name timeout:90.0]) {
            stderrText = [NSString stringWithFormat:@"%@ is not running. Syncrosa did not launch it automatically.", targetAppName];
            result = [@"" copy];
        } else if (![source writeToFile:scriptPath atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
            stderrText = [NSString stringWithFormat:@"Failed to write temp AppleScript: %@", scriptPath];
            result = [@"" copy];
        } else {
            NSTask *task = [[[NSTask alloc] init] autorelease];
            [task setLaunchPath:@"/usr/bin/osascript"];
            [task setArguments:@[scriptPath]];

            [[NSFileManager defaultManager] createFileAtPath:stdoutPath contents:nil attributes:nil];
            [[NSFileManager defaultManager] createFileAtPath:stderrPath contents:nil attributes:nil];
            NSFileHandle *outHandle = [NSFileHandle fileHandleForWritingAtPath:stdoutPath];
            NSFileHandle *errHandle = [NSFileHandle fileHandleForWritingAtPath:stderrPath];
            [task setStandardOutput:outHandle];
            [task setStandardError:errHandle];

            [task launch];
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:taskTimeout];
            while ([task isRunning] && [deadline timeIntervalSinceNow] > 0.0) {
                [NSThread sleepForTimeInterval:0.05];
            }
            if ([task isRunning]) {
                timedOut = YES;
                [task terminate];
            }
            [task waitUntilExit];
            terminationStatus = [task terminationStatus];
            [outHandle closeFile];
            [errHandle closeFile];

            NSData *outData = [NSData dataWithContentsOfFile:stdoutPath];
            NSData *errData = [NSData dataWithContentsOfFile:stderrPath];
            stdoutText = IGStringFromTaskData(outData);
            stderrText = IGStringFromTaskData(errData);

            if (terminationStatus != 0 && stderrText.length > 0) {
                NSLog(@"AppleScript Error: %@", stderrText);
            }

            result = [IGTrimmedScriptResult(stdoutText) copy];
        }
    } @catch (NSException *exception) {
        NSLog(@"AppleScript exception: %@", exception.reason);
        stderrText = [NSString stringWithFormat:@"NSException: %@ - %@", exception.name, exception.reason];
    } @finally {
        [[IGLogger sharedLogger] logAppleScriptWithName:name
                                                 source:source
                                                 stdout:stdoutText
                                                 stderr:stderrText
                                      terminationStatus:terminationStatus
                                            elapsedTime:[[NSDate date] timeIntervalSinceDate:started]
                                               timedOut:timedOut];
        [[NSFileManager defaultManager] removeItemAtPath:scriptPath error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:stdoutPath error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:stderrPath error:nil];
    }
    }

    if (!result) {
        result = [@"" copy];
    }
    [pool drain];
    return [result autorelease];
}

- (void)writeStartupDiagnostics {
    if (![IGLogger desktopDiagnosticsEnabled]) {
        return;
    }
    [[IGLogger sharedLogger] log:@"Startup iTunes diagnostics begin"];

    NSArray *runningApps = [[NSWorkspace sharedWorkspace] launchedApplications];
    NSMutableArray *runningNames = [NSMutableArray array];
    for (NSDictionary *appInfo in runningApps) {
        NSString *appName = [appInfo objectForKey:@"NSApplicationName"];
        if (appName.length > 0) {
            [runningNames addObject:appName];
        }
    }
    [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"Running apps include iTunes=%@ Music=%@",
                                  [runningNames containsObject:@"iTunes"] ? @"YES" : @"NO",
                                  [runningNames containsObject:@"Music"] ? @"YES" : @"NO"]];

    if (![runningNames containsObject:@"iTunes"]) {
        [[IGLogger sharedLogger] log:@"Startup iTunes diagnostics deferred because iTunes is not running. The next iTunes operation will launch it and log AppleScript results."];
        return;
    }

    NSString *script =
        @"set out to \"\"\n"
        "tell application \"iTunes\"\n"
        "    try\n"
        "        set out to out & \"app_name=\" & (name as text) & linefeed\n"
        "    on error errMsg number errNum\n"
        "        set out to out & \"app_name_ERROR=\" & (errNum as text) & \" \" & errMsg & linefeed\n"
        "    end try\n"
        "    try\n"
        "        set out to out & \"version=\" & (version as text) & linefeed\n"
        "    on error errMsg number errNum\n"
        "        set out to out & \"version_ERROR=\" & (errNum as text) & \" \" & errMsg & linefeed\n"
        "    end try\n"
        "    try\n"
        "        set out to out & \"count_every_track=\" & ((count of every track) as text) & linefeed\n"
        "    on error errMsg number errNum\n"
        "        set out to out & \"count_every_track_ERROR=\" & (errNum as text) & \" \" & errMsg & linefeed\n"
        "    end try\n"
        "    try\n"
        "        set out to out & \"count_every_file_track=\" & ((count of every file track) as text) & linefeed\n"
        "    on error errMsg number errNum\n"
        "        set out to out & \"count_every_file_track_ERROR=\" & (errNum as text) & \" \" & errMsg & linefeed\n"
        "    end try\n"
        "    try\n"
        "        set out to out & \"count_library_playlist_1_tracks=\" & ((count of every track of library playlist 1) as text) & linefeed\n"
        "    on error errMsg number errNum\n"
        "        set out to out & \"count_library_playlist_1_tracks_ERROR=\" & (errNum as text) & \" \" & errMsg & linefeed\n"
        "    end try\n"
        "    try\n"
        "        set out to out & \"count_library_playlist_1_file_tracks=\" & ((count of every file track of library playlist 1) as text) & linefeed\n"
        "    on error errMsg number errNum\n"
        "        set out to out & \"count_library_playlist_1_file_tracks_ERROR=\" & (errNum as text) & \" \" & errMsg & linefeed\n"
        "    end try\n"
        "    try\n"
        "        set out to out & \"sources_count=\" & ((count of every source) as text) & linefeed\n"
        "        repeat with s in every source\n"
        "            set srcName to \"\"\n"
        "            set srcKind to \"\"\n"
        "            try\n"
        "                set srcName to name of s as text\n"
        "            end try\n"
        "            try\n"
        "                set srcKind to kind of s as text\n"
        "            end try\n"
        "            set out to out & \"SOURCE\" & tab & srcName & tab & srcKind & tab & ((count of playlists of s) as text) & linefeed\n"
        "            set playlistIndex to 0\n"
        "            repeat with p in playlists of s\n"
        "                set playlistIndex to playlistIndex + 1\n"
        "                if playlistIndex > 60 then exit repeat\n"
        "                set plName to \"\"\n"
        "                set plClass to \"\"\n"
        "                set plSpecial to \"\"\n"
        "                set plCount to \"ERR\"\n"
        "                set plFileCount to \"ERR\"\n"
        "                try\n"
        "                    set plName to name of p as text\n"
        "                end try\n"
        "                try\n"
        "                    set plClass to class of p as text\n"
        "                end try\n"
        "                try\n"
        "                    set plSpecial to special kind of p as text\n"
        "                end try\n"
        "                try\n"
        "                    set plCount to (count of tracks of p) as text\n"
        "                end try\n"
        "                try\n"
        "                    set plFileCount to (count of file tracks of p) as text\n"
        "                end try\n"
        "                set out to out & \"PLAYLIST\" & tab & srcName & tab & plName & tab & plClass & tab & plSpecial & tab & plCount & tab & plFileCount & linefeed\n"
        "            end repeat\n"
        "        end repeat\n"
        "    on error errMsg number errNum\n"
        "        set out to out & \"sources_ERROR=\" & (errNum as text) & \" \" & errMsg & linefeed\n"
        "    end try\n"
        "end tell\n"
        "return out";

    NSString *result = [self runAppleScriptNamed:@"startup.itunes.map" source:script];
    [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"Startup iTunes diagnostics result length=%lu", (unsigned long)result.length]];
}

- (void)fetchAllTracksWithProgress:(void(^)(NSInteger current, NSInteger total))progressBlock 
                        completion:(void(^)(NSArray *tracks))completionBlock {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *errorMessage = nil;
        NSInteger total = [self readLibraryTrackCountSyncWithErrorMessage:&errorMessage];
        if (total <= 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(@[]);
            });
            return;
        }

        NSMutableArray *allTracks = [NSMutableArray array];
        NSInteger chunkSize = 200;

        for (NSInteger i = 1; i <= total; i += chunkSize) {
            NSInteger end = MIN(i + chunkSize - 1, total);
            NSString *scriptSource = [NSString stringWithFormat:
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
                "set out to \"\"\n"
                "tell application \"iTunes\"\n"
                "    set trks to (tracks %ld thru %ld of library playlist 1)\n"
                "    repeat with t in trks\n"
                "        try\n"
                "            set pid to my textValue(persistent ID of t)\n"
                "            set art to my textValue(artist of t)\n"
                "            set nm to my textValue(name of t)\n"
                "            set alb to my textValue(album of t)\n"
                "            set gen to my textValue(genre of t)\n"
                "            set yr to year of t\n"
                "            set sz to 0\n"
                "            try\n"
                "                set sz to size of t\n"
                "            end try\n"
                "            set out to out & pid & tab & art & tab & nm & tab & alb & tab & gen & tab & yr & tab & sz & linefeed\n"
                "        end try\n"
                "    end repeat\n"
                "end tell\n"
                "return out", (long)i, (long)end];

            NSString *result = [self runAppleScriptNamed:@"library.fetchAll.chunk" source:scriptSource];
            if (result) {
                NSArray *lines = [result componentsSeparatedByString:@"\n"];
                for (NSString *line in lines) {
                    if ([line rangeOfString:@"\t"].location != NSNotFound) {
                        NSArray *parts = [line componentsSeparatedByString:@"\t"];
                        if (parts.count >= 7) {
                            IGTrack *track = [[IGTrack alloc] initWithPersistentID:parts[0]
                                                                              name:parts[2]
                                                                            artist:parts[1]
                                                                             album:parts[3]
                                                                             genre:parts[4]
                                                                              year:[parts[5] integerValue]];
                            track.fileSizeBytes = (unsigned long long)[parts[6] longLongValue];
                            [allTracks addObject:track];
#if !__has_feature(objc_arc)
                            [track release];
#endif
                        }
                    }
                }
            }

            if (progressBlock) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    progressBlock(end, total);
                });
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock(allTracks);
        });
    });
}

- (void)createPlaylistWithName:(NSString *)name 
                 persistentIDs:(NSArray *)pids 
                    completion:(void(^)(NSInteger addedCount))completionBlock {
    if (pids.count == 0) {
        if (completionBlock) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(0);
            });
        }
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *idsString = IGAppleScriptListLiteral(pids);
        NSString *playlistLiteral = IGAppleScriptLiteral(name);
        
        NSString *scriptSource = [NSString stringWithFormat:
            @"tell application \"iTunes\"\n"
            "    set plName to %@\n"
            "    set addedCount to 0\n"
            "    set idList to %@\n"
            "    set tracksToAdd to {}\n"
            "    \n"
            "    repeat with tid in idList\n"
            "        set tidText to (contents of tid) as text\n"
            "        try\n"
            "            set trk to (some track of library playlist 1 whose persistent ID is tidText)\n"
            "            set end of tracksToAdd to trk\n"
            "        end try\n"
            "    end repeat\n"
            "    \n"
            "    if (count of tracksToAdd) is 0 then return \"0\"\n"
            "    \n"
            "    if not (exists user playlist plName) then\n"
            "        make new user playlist with properties {name:plName}\n"
            "    end if\n"
            "    set pl to user playlist plName\n"
            "    delete every track of pl\n"
            "    \n"
            "    repeat with trk in tracksToAdd\n"
            "        try\n"
            "            duplicate (contents of trk) to pl\n"
            "            set addedCount to addedCount + 1\n"
            "        end try\n"
            "    end repeat\n"
            "    return addedCount as string\n"
            "end tell", playlistLiteral, idsString];

        NSString *result = [self runAppleScriptNamed:@"playlist.create" source:scriptSource];
        NSInteger count = [result integerValue];

        dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock(count);
        });
    });
}

- (void)importFilePaths:(NSArray *)paths
         asPlaylistName:(NSString *)playlistName
          clearPlaylist:(BOOL)clearPlaylist
             completion:(void(^)(NSInteger addedCount, NSArray *errors))completionBlock {
    if (paths.count == 0 || playlistName.length == 0) {
        if (completionBlock) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(0, @[@"No files to import."]);
            });
        }
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray *cleanPaths = [NSMutableArray arrayWithCapacity:paths.count];
        for (id value in paths) {
            if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
                [cleanPaths addObject:value];
            }
        }

        NSString *pathList = IGAppleScriptListLiteral(cleanPaths);
        NSString *playlistLiteral = IGAppleScriptLiteral(playlistName);
        NSString *clearLine = clearPlaylist ? @"    delete every track of pl\n" : @"";
        NSString *scriptSource = [NSString stringWithFormat:
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
            "        set s to v as text\n"
            "        set s to my replaceText(s, tab, \" \")\n"
            "        set s to my replaceText(s, linefeed, \" \")\n"
            "        set s to my replaceText(s, return, \" \")\n"
            "        return s\n"
            "    on error\n"
            "        return \"\"\n"
            "    end try\n"
            "end textValue\n"
            @"tell application \"iTunes\"\n"
            "    set plName to %@\n"
            "    set fileList to %@\n"
            "    set addedCount to 0\n"
            "    set errorText to \"\"\n"
            "    if not (exists user playlist plName) then\n"
            "        make new user playlist with properties {name:plName}\n"
            "    end if\n"
            "    set pl to user playlist plName\n"
            "%@"
            "    repeat with filePath in fileList\n"
            "        set filePathText to (contents of filePath) as text\n"
            "        try\n"
            "            set importedTrack to add (POSIX file filePathText)\n"
            "            try\n"
            "                duplicate importedTrack to pl\n"
            "                set addedCount to addedCount + 1\n"
            "            on error\n"
            "                try\n"
            "                    duplicate item 1 of importedTrack to pl\n"
            "                    set addedCount to addedCount + 1\n"
            "                on error errMsg\n"
            "                    set errorText to errorText & my textValue(filePathText) & \": \" & my textValue(errMsg) & linefeed\n"
            "                end try\n"
            "            end try\n"
            "        on error errMsg\n"
            "            set errorText to errorText & my textValue(filePathText) & \": \" & my textValue(errMsg) & linefeed\n"
            "        end try\n"
            "    end repeat\n"
            "    return (addedCount as text) & tab & errorText\n"
            "end tell", playlistLiteral, pathList, clearLine];

        NSString *result = [self runAppleScriptNamed:@"folder.importPlaylist.batch" source:scriptSource];
        NSArray *parts = result.length > 0 ? [result componentsSeparatedByString:@"\t"] : @[];
        NSInteger imported = parts.count > 0 ? [[parts objectAtIndex:0] integerValue] : 0;
        NSMutableArray *errors = [NSMutableArray array];
        if (parts.count > 1) {
            NSArray *lines = [[parts objectAtIndex:1] componentsSeparatedByString:@"\n"];
            for (NSString *line in lines) {
                NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (trimmed.length > 0) {
                    [errors addObject:trimmed];
                }
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completionBlock) {
                completionBlock(imported, errors);
            }
        });
    });
}

- (void)fetchPlaylistsWithCompletion:(void(^)(NSArray *playlists))completionBlock {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *script = 
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
            @"tell application \"iTunes\"\n"
            "    set output to \"\"\n"
            "    try\n"
                "        set plist to (every user playlist whose special kind is none)\n"
                "        repeat with pl in plist\n"
            "            set plName to my textValue(name of pl)\n"
            "            set plCount to count of tracks of pl\n"
            "            set output to output & plName & tab & plCount & linefeed\n"
            "        end repeat\n"
            "    end try\n"
            "    return output\n"
            "end tell";
            
        NSString *rawResult = [self runAppleScriptNamed:@"playlist.fetchList" source:script];
        NSMutableArray *playlists = [NSMutableArray array];
        
        if (rawResult && rawResult.length > 0) {
            NSArray *lines = [rawResult componentsSeparatedByString:@"\n"];
            for (NSString *line in lines) {
                if (line.length == 0) continue;
                NSArray *parts = [line componentsSeparatedByString:@"\t"];
                if (parts.count >= 2) {
                    NSString *name = parts[0];
                    NSInteger count = [parts[1] integerValue];
                    [playlists addObject:@{
                        @"name": name,
                        @"trackCount": @(count)
                    }];
                }
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock(playlists);
        });
    });
}

- (void)fetchTracksForPlaylist:(NSString *)playlistName 
                    completion:(void(^)(NSArray *tracks))completionBlock {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
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
            @"tell application \"iTunes\"\n"
            "    set output to \"\"\n"
            "    try\n"
            "        set pl to user playlist %@\n"
            "        set trks to every file track of pl\n"
            "        repeat with t in trks\n"
            "            try\n"
            "                set loc to location of t\n"
            "                if loc is not missing value then\n"
            "                    set trackPath to POSIX path of loc\n"
            "                    set trackName to my textValue(name of t)\n"
            "                    set trackArtist to my textValue(artist of t)\n"
            "                    set trackSize to size of t\n"
            "                    set output to output & trackName & tab & trackArtist & tab & my textValue(trackPath) & tab & trackSize & linefeed\n"
            "                end if\n"
            "            end try\n"
            "        end repeat\n"
            "    end try\n"
            "    return output\n"
            "end tell", IGAppleScriptLiteral(playlistName)];

        NSString *rawResult = [self runAppleScriptNamed:@"playlist.fetchTracks" source:script];
        NSMutableArray *tracks = [NSMutableArray array];
        
        if (rawResult && rawResult.length > 0) {
            NSArray *lines = [rawResult componentsSeparatedByString:@"\n"];
            for (NSString *line in lines) {
                if (line.length == 0) continue;
                NSArray *parts = [line componentsSeparatedByString:@"\t"];
                if (parts.count >= 4) {
                    [tracks addObject:@{
                        @"name": parts[0],
                        @"artist": parts[1],
                        @"path": parts[2],
                        @"size": @([parts[3] longLongValue])
                    }];
                }
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock(tracks);
        });
    });
}

- (void)fetchLibraryFileTrackReferencesWithCompletion:(void(^)(NSArray *tracks))completionBlock {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *handler =
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
            "end textValue\n";

        NSString *countScript =
            @"tell application \"iTunes\"\n"
            "    try\n"
            "        return (count of every file track of library playlist 1) as text\n"
            "    on error\n"
            "        return \"0\"\n"
            "    end try\n"
            "end tell";

        NSInteger total = [[self runAppleScriptNamed:@"library.fileTrackReferences.count" source:countScript] integerValue];
        NSMutableArray *tracks = [NSMutableArray array];
        NSInteger chunkSize = 200;

        for (NSInteger start = 1; start <= total; start += chunkSize) {
            NSInteger end = MIN(start + chunkSize - 1, total);
            NSString *script = [NSString stringWithFormat:
            @"%@"
            "tell application \"iTunes\"\n"
            "    set output to \"\"\n"
            "    try\n"
            "        set trks to every file track of library playlist 1\n"
            "        repeat with trackIndex from %ld to %ld\n"
            "            if trackIndex is greater than (count of trks) then exit repeat\n"
            "            set t to item trackIndex of trks\n"
            "            set pid to \"\"\n"
            "            set nm to \"\"\n"
            "            set art to \"\"\n"
            "            set pth to \"\"\n"
            "            set sz to \"0\"\n"
            "            set knd to \"\"\n"
            "            try\n"
            "                set pid to persistent ID of t as text\n"
            "            end try\n"
            "            try\n"
            "                set nm to name of t as text\n"
            "            end try\n"
            "            try\n"
            "                set art to artist of t as text\n"
            "            end try\n"
            "            try\n"
            "                set knd to kind of t as text\n"
            "            end try\n"
            "            try\n"
            "                set sz to size of t as text\n"
            "            end try\n"
            "            try\n"
            "                set loc to location of t\n"
            "                if loc is not missing value then set pth to POSIX path of loc\n"
            "            end try\n"
            "            set output to output & my textValue(pid) & tab & my textValue(nm) & tab & my textValue(art) & tab & my textValue(pth) & tab & sz & tab & my textValue(knd) & linefeed\n"
            "        end repeat\n"
            "    end try\n"
            "    return output\n"
            "end tell", handler, (long)start, (long)end];

            NSString *rawResult = [self runAppleScriptNamed:@"library.fileTrackReferences.chunk" source:script];
            NSArray *lines = rawResult.length > 0 ? [rawResult componentsSeparatedByString:@"\n"] : @[];
            for (NSString *line in lines) {
                if ([line rangeOfString:@"\t"].location == NSNotFound) continue;
                NSArray *parts = [line componentsSeparatedByString:@"\t"];
                if (parts.count >= 6) {
                    [tracks addObject:@{
                        @"persistentID": [parts objectAtIndex:0],
                        @"name": [parts objectAtIndex:1],
                        @"artist": [parts objectAtIndex:2],
                        @"path": [parts objectAtIndex:3],
                        @"size": @([[parts objectAtIndex:4] longLongValue]),
                        @"kind": [parts objectAtIndex:5]
                    }];
                }
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completionBlock) {
                completionBlock(tracks);
            }
        });
    });
}

- (void)fetchVideoTracksWithCompletion:(void(^)(NSArray *tracks, NSString *errorMessage))completionBlock {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *script =
            @"on cleanText(v)\n"
             "    try\n"
             "        if v is missing value then return \"\"\n"
             "        set s to v as text\n"
             "        set AppleScript's text item delimiters to tab\n"
             "        set s to text items of s\n"
             "        set AppleScript's text item delimiters to \" \"\n"
             "        set s to s as text\n"
             "        set AppleScript's text item delimiters to \"\"\n"
             "        set AppleScript's text item delimiters to linefeed\n"
             "        set s to text items of s\n"
             "        set AppleScript's text item delimiters to \" \"\n"
             "        set s to s as text\n"
             "        set AppleScript's text item delimiters to \"\"\n"
             "        return s\n"
             "    on error\n"
             "        return \"\"\n"
             "    end try\n"
             "end cleanText\n"
             "set out to \"\"\n"
             "tell application \"iTunes\"\n"
             "    try\n"
             "        repeat with t in every file track of library playlist 1\n"
             "            try\n"
             "                set vk to video kind of t\n"
             "                if vk is movie or vk is TV show then\n"
             "                    if vk is movie then\n"
             "                        set vkText to \"Movie\"\n"
             "                    else\n"
             "                        set vkText to \"TV Show\"\n"
             "                    end if\n"
             "                    set artFlag to \"0\"\n"
             "                    if (count of artworks of t) > 0 then set artFlag to \"1\"\n"
             "                    set out to out & my cleanText(persistent ID of t) & tab & vkText & tab & my cleanText(name of t) & tab & my cleanText(show of t) & tab & (season number of t as text) & tab & (episode number of t as text) & tab & my cleanText(genre of t) & tab & (year of t as text) & tab & my cleanText(description of t) & tab & my cleanText(long description of t) & tab & my cleanText(artist of t) & tab & artFlag & linefeed\n"
             "                end if\n"
             "            end try\n"
             "        end repeat\n"
             "        return out\n"
             "    on error errMsg number errNum\n"
             "        return \"ERROR\" & tab & (errNum as text) & \" \" & errMsg\n"
             "    end try\n"
             "end tell";

        NSString *raw = [self runAppleScriptNamed:@"videoMetadata.fetch" source:script];
        NSMutableArray *tracks = [NSMutableArray array];
        NSString *errorMessage = nil;
        if ([raw hasPrefix:@"ERROR\t"]) {
            NSArray *parts = [raw componentsSeparatedByString:@"\t"];
            errorMessage = [parts count] > 1 ? [parts objectAtIndex:1] : @"Could not read video metadata from iTunes.";
        } else {
            for (NSString *line in [raw componentsSeparatedByString:@"\n"]) {
                NSArray *parts = [line componentsSeparatedByString:@"\t"];
                if ([parts count] < 12 || [[parts objectAtIndex:0] length] == 0) continue;
                [tracks addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                   [parts objectAtIndex:0], @"persistentID",
                                   [parts objectAtIndex:1], @"videoKind",
                                   [parts objectAtIndex:2], @"name",
                                   [parts objectAtIndex:3], @"show",
                                   [NSNumber numberWithInteger:[[parts objectAtIndex:4] integerValue]], @"seasonNumber",
                                   [NSNumber numberWithInteger:[[parts objectAtIndex:5] integerValue]], @"episodeNumber",
                                   [parts objectAtIndex:6], @"genre",
                                   [NSNumber numberWithInteger:[[parts objectAtIndex:7] integerValue]], @"year",
                                   [parts objectAtIndex:8], @"description",
                                   [parts objectAtIndex:9], @"longDescription",
                                   [parts objectAtIndex:10], @"director",
                                   [NSNumber numberWithBool:[[parts objectAtIndex:11] boolValue]], @"hasArtwork",
                                   nil]];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completionBlock) completionBlock(tracks, errorMessage);
        });
    });
}

- (void)updateVideoTrackWithPersistentID:(NSString *)persistentID
                                metadata:(NSDictionary *)metadata
                              artworkURL:(NSURL *)artworkURL
                              completion:(void(^)(BOOL success, NSString *errorMessage))completionBlock {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if ([persistentID length] == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (completionBlock) completionBlock(NO, @"The video track identifier is missing."); });
            return;
        }

        NSString *videoKind = [[metadata objectForKey:@"videoKind"] isEqualToString:@"TV Show"] ? @"TV show" : @"movie";
        NSInteger season = MAX((NSInteger)0, [[metadata objectForKey:@"seasonNumber"] integerValue]);
        NSInteger episode = MAX((NSInteger)0, [[metadata objectForKey:@"episodeNumber"] integerValue]);
        NSInteger year = MAX((NSInteger)0, [[metadata objectForKey:@"year"] integerValue]);
        NSString *artworkLines = @"";
        if ([artworkURL isFileURL] && [[[NSFileManager defaultManager] attributesOfItemAtPath:[artworkURL path] error:nil] count] > 0) {
            artworkLines = [NSString stringWithFormat:
                @"        set artworkFile to POSIX file %@\n"
                 "        set artworkData to read artworkFile as picture\n"
                 "        if (count of artworks of t) is 0 then\n"
                 "            make new artwork at t with properties {data:artworkData}\n"
                 "        else\n"
                 "            set data of artwork 1 of t to artworkData\n"
                 "        end if\n", IGAppleScriptLiteral([artworkURL path])];
        }

        NSString *script = [NSString stringWithFormat:
            @"tell application \"iTunes\"\n"
             "    try\n"
             "        set t to some file track of library playlist 1 whose persistent ID is %@\n"
             "        set name of t to %@\n"
             "        set video kind of t to %@\n"
             "        set show of t to %@\n"
             "        set season number of t to %ld\n"
             "        set episode number of t to %ld\n"
             "        set genre of t to %@\n"
             "        set year of t to %ld\n"
             "        set artist of t to %@\n"
             "        set description of t to %@\n"
             "        set long description of t to %@\n"
             "%@"
             "        return \"OK\"\n"
             "    on error errMsg number errNum\n"
             "        return \"ERROR\" & tab & (errNum as text) & \" \" & errMsg\n"
             "    end try\n"
             "end tell",
             IGAppleScriptLiteral(persistentID),
             IGAppleScriptLiteral([metadata objectForKey:@"name"]),
             videoKind,
             IGAppleScriptLiteral([metadata objectForKey:@"show"]),
             (long)season,
             (long)episode,
             IGAppleScriptLiteral([metadata objectForKey:@"genre"]),
             (long)year,
             IGAppleScriptLiteral([metadata objectForKey:@"director"]),
             IGAppleScriptLiteral([metadata objectForKey:@"description"]),
             IGAppleScriptLiteral([metadata objectForKey:@"description"]),
             artworkLines];

        NSString *raw = [self runAppleScriptNamed:@"videoMetadata.update" source:script];
        BOOL success = [raw isEqualToString:@"OK"];
        NSString *errorMessage = nil;
        if (!success) {
            NSArray *parts = [raw componentsSeparatedByString:@"\t"];
            errorMessage = [parts count] > 1 ? [parts objectAtIndex:1] : @"iTunes could not update this video track.";
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completionBlock) completionBlock(success, errorMessage);
        });
    });
}

@end
