#import "IGiTunesService.h"
#import "IGLogger.h"
#import <Cocoa/Cocoa.h>

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

static BOOL IGApplicationIsRunning(NSString *appName) {
    if (appName.length == 0) return NO;

    NSArray *runningApps = [[NSWorkspace sharedWorkspace] launchedApplications];
    for (NSDictionary *appInfo in runningApps) {
        NSString *runningName = [appInfo objectForKey:@"NSApplicationName"];
        if ([runningName isEqualToString:appName]) {
            return YES;
        }
    }
    return NO;
}

+ (instancetype)sharedService {
    static IGiTunesService *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (BOOL)ensureApplicationReady:(NSString *)appName forOperation:(NSString *)operation timeout:(NSTimeInterval)timeout {
    if (appName.length == 0) return YES;

    BOOL wasRunning = IGApplicationIsRunning(appName);
    if (!wasRunning) {
        [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"AppleScript '%@' needs %@; launching application.", operation ?: @"", appName]];
        BOOL launched = [[NSWorkspace sharedWorkspace] launchApplication:appName];
        [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"Launch request for %@ returned %@.", appName, launched ? @"YES" : @"NO"]];
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

- (NSString *)runAppleScript:(NSString *)source {
    return [self runAppleScriptNamed:@"generic" source:source];
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
            stderrText = [NSString stringWithFormat:@"%@ is not ready for AppleScript operation %@", targetAppName, name ?: @""];
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
        NSString *countStr = [self runAppleScriptNamed:@"library.fetchAll.count" source:@"tell application \"iTunes\" to count every track of library playlist 1"];
        NSInteger total = [countStr integerValue];
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
                "            set out to out & pid & tab & art & tab & nm & tab & alb & tab & gen & tab & yr & linefeed\n"
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
                        if (parts.count >= 6) {
                            IGTrack *track = [[IGTrack alloc] initWithPersistentID:parts[0]
                                                                              name:parts[2]
                                                                            artist:parts[1]
                                                                             album:parts[3]
                                                                             genre:parts[4]
                                                                              year:[parts[5] integerValue]];
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
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *idsString = IGAppleScriptListLiteral(pids);
        NSString *playlistLiteral = IGAppleScriptLiteral(name);
        
        NSString *scriptSource = [NSString stringWithFormat:
            @"tell application \"iTunes\"\n"
            "    set plName to %@\n"
            "    if not (exists user playlist plName) then\n"
            "        make new user playlist with properties {name:plName}\n"
            "    end if\n"
            "    set pl to user playlist plName\n"
            "    delete every track of pl\n"
            "    \n"
            "    set addedCount to 0\n"
            "    set idList to %@\n"
            "    \n"
            "    repeat with tid in idList\n"
            "        set tidText to (contents of tid) as text\n"
            "        try\n"
            "            set trk to (some track of library playlist 1 whose persistent ID is tidText)\n"
            "            duplicate trk to pl\n"
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

@end
