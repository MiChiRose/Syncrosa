#import "IGMediaFixerManager.h"
#import "IGiTunesService.h"
#import "IGLyricsService.h"
#import "IGLogger.h"

static NSString *IGMediaJSONString(id value) {
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

static NSNumber *IGMediaJSONNumber(id value) {
    return [value respondsToSelector:@selector(integerValue)] ? value : @(0);
}

static NSString *IGMediaAppleScriptLiteral(id value) {
    if (![value isKindOfClass:[NSString class]]) {
        return @"";
    }

    NSMutableString *escaped = [value mutableCopy];
    [escaped replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\r\n" withString:@"\n" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\r" withString:@"\n" options:0 range:NSMakeRange(0, escaped.length)];
    NSString *result = [escaped copy];
#if !__has_feature(objc_arc)
    [escaped release];
    return [result autorelease];
#else
    return result;
#endif
}

static void IGMediaAddCACertIfAvailable(NSMutableArray *args) {
    NSString *caPath = [[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"];
    if (caPath.length > 0) {
        [args addObjectsFromArray:@[@"--cacert", caPath]];
    }
}

static NSString *IGMediaTempPath(NSString *extension) {
    NSString *baseName = [NSString stringWithFormat:@"syncrosa-curl-%@", [[NSProcessInfo processInfo] globallyUniqueString]];
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[baseName stringByAppendingPathExtension:extension]];
}

static NSData *IGMediaRunCurl(NSArray *args, int *statusOut) {
    NSString *stdoutPath = IGMediaTempPath(@"stdout");
    NSString *stderrPath = IGMediaTempPath(@"stderr");
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
        if (status != 0) {
            NSData *stderrData = [NSData dataWithContentsOfFile:stderrPath];
            NSString *stderrText = @"";
            if (stderrData.length > 0) {
                NSString *decoded = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding];
                stderrText = decoded ?: @"";
#if !__has_feature(objc_arc)
                [decoded autorelease];
#endif
            }
            if (stderrText.length > 0) {
                NSLog(@"Curl Apple metadata failed with status %d: %@", status, stderrText);
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"Curl Apple metadata fetch failed: %@", exception.reason);
        [stdoutHandle closeFile];
        [stderrHandle closeFile];
    }

    [[NSFileManager defaultManager] removeItemAtPath:stdoutPath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:stderrPath error:nil];
    if (statusOut) *statusOut = status;
    return data;
}

@implementation IGMediaFixerManager

+ (instancetype)sharedManager {
    static IGMediaFixerManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (NSString *)normalizeText:(NSString *)text {
    if (!text || text.length == 0) return @"";

    NSMutableString *mutableString = [text mutableCopy];
    CFStringTransform((__bridge CFMutableStringRef)mutableString, NULL, kCFStringTransformToLatin, NO);
    CFStringTransform((__bridge CFMutableStringRef)mutableString, NULL, kCFStringTransformStripDiacritics, NO);

    NSString *clean = [[mutableString lowercaseString] stringByReplacingOccurrencesOfString:@"[^a-z0-9\\s]" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, mutableString.length)];
    NSArray *words = [clean componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *normalized = [[words filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]] componentsJoinedByString:@" "];
#if !__has_feature(objc_arc)
    [mutableString release];
#endif
    return normalized;
}

- (void)fetchAppleMetadataForArtist:(NSString *)artist title:(NSString *)title completion:(void(^)(NSDictionary *info))completionBlock {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"only_local_mode"]) {
        [[IGLogger sharedLogger] log:@"Only Local Mode enabled: skipping Apple metadata request."];
        completionBlock(nil);
        return;
    }

    NSString *cleanTitle = title;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"[\\(\\[].*?[\\)\\]]" options:0 error:nil];
    cleanTitle = [regex stringByReplacingMatchesInString:title options:0 range:NSMakeRange(0, title.length) withTemplate:@""];
    cleanTitle = [cleanTitle stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

    NSString *searchTerm = [NSString stringWithFormat:@"%@ %@", artist, cleanTitle];
    NSString *encodedTerm = [searchTerm stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *urlString = [NSString stringWithFormat:@"https://itunes.apple.com/search?term=%@&media=music&limit=1", encodedTerm];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @try {
            NSMutableArray *args = [NSMutableArray arrayWithArray:@[@"-sSL", @"-m", @"20"]];
            IGMediaAddCACertIfAvailable(args);
            [args addObject:urlString];

            int status = -1;
            NSData *data = IGMediaRunCurl(args, &status);
            if (status == 0 && data.length > 0) {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                NSArray *results = json[@"results"];
                if (results.count > 0) {
                    NSDictionary *res = results[0];
                    NSString *releaseDate = IGMediaJSONString(res[@"releaseDate"]);
                    NSString *year = releaseDate.length >= 4 ? [releaseDate substringToIndex:4] : @"";
                    completionBlock(@{
                        @"alb": IGMediaJSONString(res[@"collectionName"]),
                        @"gen": IGMediaJSONString(res[@"primaryGenreName"]),
                        @"yr": year,
                        @"title": IGMediaJSONString(res[@"trackName"]),
                        @"art": IGMediaJSONString(res[@"artistName"]),
                        @"trackNumber": IGMediaJSONNumber(res[@"trackNumber"])
                    });
                    return;
                }
            }
        } @catch (NSException *exception) {
            NSLog(@"Curl Apple metadata fetch failed: %@", exception.reason);
        }
        completionBlock(nil);
    });
}

- (void)getMergeCandidatesWithCompletion:(void(^)(NSArray *candidates))completionBlock {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [[IGLogger sharedLogger] log:@"MediaFixer manager: merge candidate scan started"];
        IGiTunesService *service = [IGiTunesService sharedService];
        NSString *countStr = [service runAppleScriptNamed:@"mediaFixer.merge.count" source:@"tell application \"iTunes\" to count every track of library playlist 1"];
        NSInteger total = [countStr integerValue];
        [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"MediaFixer manager: merge candidate total=%ld raw=%@", (long)total, countStr ?: @""]];
        if (total <= 0) {
            dispatch_async(dispatch_get_main_queue(), ^{ completionBlock(@[]); });
            return;
        }

        NSMutableDictionary *groups = [NSMutableDictionary dictionary];
        NSInteger chunkSize = 150;

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
                "set out to \"\"\n"
                "tell application \"iTunes\"\n"
                "    set trks to tracks %ld thru %ld of library playlist 1\n"
                "    repeat with t in trks\n"
                "        try\n"
                "            set out to out & my textValue(persistent ID of t) & tab & my textValue(artist of t) & tab & my textValue(album of t) & linefeed\n"
                "        end try\n"
                "    end repeat\n"
                "end tell\n"
                "return out", (long)start, (long)end];

            NSString *raw = [service runAppleScriptNamed:@"mediaFixer.merge.chunk" source:script];
            NSArray *lines = [raw componentsSeparatedByString:@"\n"];
            NSInteger parsedRows = 0;

            for (NSString *line in lines) {
                if (line.length == 0) continue;

                NSArray *parts = [line componentsSeparatedByString:@"\t"];
                if (parts.count < 3) continue;

                NSString *pid = parts[0];
                NSString *artist = parts[1];
                NSString *album = parts[2];

                if (pid.length == 0 || album.length == 0) continue;

                NSString *key = [NSString stringWithFormat:@"%@|%@", [artist lowercaseString], [self normalizeText:album]];
                if (!groups[key]) groups[key] = [NSMutableArray array];
                [groups[key] addObject:@{@"pid": pid, @"alb": album}];
                parsedRows++;
            }
            [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"MediaFixer manager: merge chunk %ld-%ld parsed=%ld", (long)start, (long)end, (long)parsedRows]];
#if !__has_feature(objc_arc)
            [pool drain];
#endif
        }

        NSMutableArray *toFix = [NSMutableArray array];
        for (NSString *key in groups) {
            NSArray *tracks = groups[key];
            NSMutableSet *variants = [NSMutableSet set];
            NSCountedSet *counts = [[NSCountedSet alloc] init];

            for (NSDictionary *t in tracks) {
                [variants addObject:t[@"alb"]];
                [counts addObject:t[@"alb"]];
            }

            if (variants.count > 1) {
                NSString *mainVariant = nil;
                NSUInteger maxCount = 0;
                for (NSString *v in variants) {
                    if ([counts countForObject:v] > maxCount) {
                        maxCount = [counts countForObject:v];
                        mainVariant = v;
                    }
                }

                NSMutableArray *targets = [NSMutableArray array];
                for (NSDictionary *t in tracks) {
                    if (![t[@"alb"] isEqualToString:mainVariant]) {
                        [targets addObject:t];
                    }
                }
                [toFix addObject:@{@"main": mainVariant, @"targets": targets}];
            }
#if !__has_feature(objc_arc)
            [counts release];
#endif
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"MediaFixer manager: merge candidates=%ld", (long)toFix.count]];
            completionBlock(toFix);
        });
    });
}

- (void)runMetadataFixWithProgress:(void(^)(NSInteger current, NSInteger total))progressBlock
                        completion:(void(^)(void))completionBlock {
    NSDictionary *allOptions = @{
        @"album": @(YES),
        @"title": @(YES),
        @"artist": @(YES),
        @"genre": @(YES),
        @"trackNumber": @(YES),
        @"lyrics": @(YES)
    };
    [self runMetadataFixWithOptions:allOptions progress:progressBlock completion:completionBlock];
}

- (void)runMetadataFixWithOptions:(NSDictionary *)options
                         progress:(void(^)(NSInteger current, NSInteger total))progressBlock
                       completion:(void(^)(void))completionBlock {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"MediaFixer manager: metadata scan started options=%@", options]];
        IGiTunesService *service = [IGiTunesService sharedService];
        NSString *countStr = [service runAppleScriptNamed:@"mediaFixer.metadata.count" source:@"tell application \"iTunes\" to count every track of library playlist 1"];
        NSInteger total = [countStr integerValue];
        [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"MediaFixer manager: metadata total=%ld raw=%@", (long)total, countStr ?: @""]];

        BOOL fixAlbum = [options[@"album"] boolValue];
        BOOL fixTitle = [options[@"title"] boolValue];
        BOOL fixArtist = [options[@"artist"] boolValue];
        BOOL fixGenre = [options[@"genre"] boolValue];
        BOOL fixTrackNumber = [options[@"trackNumber"] boolValue];
        BOOL fixLyrics = [options[@"lyrics"] boolValue];
        if (fixLyrics && [[NSUserDefaults standardUserDefaults] boolForKey:@"only_local_mode"]) {
            fixLyrics = NO;
            [[IGLogger sharedLogger] log:@"Only Local Mode enabled: skipping lyrics requests."];
        }

        void (^reportProgress)(NSInteger) = ^(NSInteger current) {
            if (progressBlock) {
                dispatch_async(dispatch_get_main_queue(), ^{ progressBlock(current, total); });
            }
        };

        NSInteger chunkSize = 150;
        for (NSInteger start = 1; start <= total; start += chunkSize) {
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            NSInteger end = MIN(start + chunkSize - 1, total);
            NSString *chunkScript = [NSString stringWithFormat:
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
                "on numberValue(v)\n"
                "    try\n"
                "        if v is missing value then return \"0\"\n"
                "        return (v as integer) as text\n"
                "    on error\n"
                "        return \"0\"\n"
                "    end try\n"
                "end numberValue\n"
                "set out to \"\"\n"
                "tell application \"iTunes\"\n"
                "    set trks to tracks %ld thru %ld of library playlist 1\n"
                "    repeat with t in trks\n"
                "        try\n"
                "            set pid to my textValue(persistent ID of t)\n"
                "            set nm to my textValue(name of t)\n"
                "            set art to my textValue(artist of t)\n"
                "            set alb to my textValue(album of t)\n"
                "            set gen to my textValue(genre of t)\n"
                "            set trk to my numberValue(track number of t)\n"
                "            set hasLyrics to \"YES\"\n"
                "            try\n"
                "                if lyrics of t is \"\" or lyrics of t is missing value then set hasLyrics to \"NO\"\n"
                "            on error\n"
                "                set hasLyrics to \"NO\"\n"
                "            end try\n"
                "            set out to out & pid & tab & nm & tab & art & tab & alb & tab & gen & tab & trk & tab & hasLyrics & linefeed\n"
                "        on error\n"
                "            set out to out & \"SKIP\" & linefeed\n"
                "        end try\n"
                "    end repeat\n"
                "end tell\n"
                "return out", (long)start, (long)end];

            NSString *chunkRaw = [service runAppleScriptNamed:@"mediaFixer.metadata.chunk" source:chunkScript];
            NSArray *lines = [chunkRaw componentsSeparatedByString:@"\n"];
            NSInteger seenRows = 0;
            NSInteger parsedRows = 0;
            NSInteger updatedRows = 0;

            for (NSString *rawLine in lines) {
                NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
                if (line.length == 0) continue;

                NSInteger currentIndex = MIN(start + seenRows, total);
                seenRows++;
                __block NSDictionary *fetchedInfo = nil;
                __block NSString *fetchedLyrics = nil;

                @try {
                    if ([line isEqualToString:@"SKIP"] || [line rangeOfString:@"\t"].location == NSNotFound) {
                        reportProgress(currentIndex);
                        continue;
                    }

                    NSArray *parts = [line componentsSeparatedByString:@"\t"];
                    if (parts.count < 7) {
                        reportProgress(currentIndex);
                        continue;
                    }

                    NSString *pid = parts[0];
                    NSString *name = parts[1];
                    NSString *artist = parts[2];
                    NSString *album = parts[3];
                    NSString *genre = parts[4];
                    NSString *trackNumStr = parts[5];
                    NSString *hasLyricsStr = parts[6];
                    parsedRows++;

                    BOOL needsFix = NO;
                    if (fixTitle && (name.length == 0 || [name isEqualToString:@"Unknown Title"])) needsFix = YES;
                    if (fixArtist && (artist.length == 0 || [artist isEqualToString:@"Unknown Artist"])) needsFix = YES;
                    if (fixAlbum && (album.length == 0 || [album isEqualToString:@"Unknown Album"] || [album isEqualToString:@"missing value"])) needsFix = YES;
                    if (fixGenre && (genre.length == 0 || [genre isEqualToString:@"Unknown Genre"])) needsFix = YES;
                    if (fixTrackNumber && ([trackNumStr integerValue] == 0)) needsFix = YES;
                    if (fixLyrics && [hasLyricsStr isEqualToString:@"NO"]) needsFix = YES;

                    if (!needsFix) {
                        reportProgress(currentIndex);
                        continue;
                    }

                    if (fixAlbum || fixTitle || fixArtist || fixGenre || fixTrackNumber) {
                        dispatch_semaphore_t metadataSema = dispatch_semaphore_create(0);
                        NSString *searchArtist = artist.length > 0 ? artist : @"";
                        NSString *searchTitle = name.length > 0 ? name : @"";

                        [self fetchAppleMetadataForArtist:searchArtist title:searchTitle completion:^(NSDictionary *info) {
#if !__has_feature(objc_arc)
                            fetchedInfo = [info retain];
#else
                            fetchedInfo = info;
#endif
                            dispatch_semaphore_signal(metadataSema);
                        }];
                        long waitResult = dispatch_semaphore_wait(metadataSema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(35 * NSEC_PER_SEC)));
                        if (waitResult != 0) {
                            [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"MediaFixer manager: Apple metadata timeout pid=%@ title=%@", pid ?: @"", name ?: @""]];
                        }
#if !OS_OBJECT_USE_OBJC
                        if (waitResult == 0) {
                            dispatch_release(metadataSema);
                        }
#endif
                    }

                    if (fixLyrics) {
                        dispatch_semaphore_t lyricsSema = dispatch_semaphore_create(0);
                        NSString *lyricsArtist = artist.length > 0 ? artist : (fetchedInfo[@"art"] ?: @"");
                        NSString *lyricsTitle = name.length > 0 ? name : (fetchedInfo[@"title"] ?: @"");

                        [[IGLyricsService sharedService] fetchLyricsForArtist:lyricsArtist title:lyricsTitle completion:^(NSString *lyrics) {
#if !__has_feature(objc_arc)
                            fetchedLyrics = [lyrics copy];
#else
                            fetchedLyrics = lyrics;
#endif
                            dispatch_semaphore_signal(lyricsSema);
                        }];
                        long waitResult = dispatch_semaphore_wait(lyricsSema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(35 * NSEC_PER_SEC)));
                        if (waitResult != 0) {
                            [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"MediaFixer manager: lyrics timeout pid=%@ title=%@", pid ?: @"", name ?: @""]];
                        }
#if !OS_OBJECT_USE_OBJC
                        if (waitResult == 0) {
                            dispatch_release(lyricsSema);
                        }
#endif
                    }

                    NSMutableArray *updates = [NSMutableArray array];
                    NSString *newAlbum = IGMediaJSONString(fetchedInfo[@"alb"]);
                    NSString *newGenre = IGMediaJSONString(fetchedInfo[@"gen"]);
                    NSString *newTitle = IGMediaJSONString(fetchedInfo[@"title"]);
                    NSString *newArtist = IGMediaJSONString(fetchedInfo[@"art"]);
                    NSNumber *newTrackNumber = IGMediaJSONNumber(fetchedInfo[@"trackNumber"]);

                    if (fixAlbum && newAlbum.length > 0 && (album.length == 0 || [album isEqualToString:@"Unknown Album"] || [album isEqualToString:@"missing value"])) {
                        [updates addObject:[NSString stringWithFormat:@"set album of t to \"%@\"", IGMediaAppleScriptLiteral(newAlbum)]];
                    }
                    if (fixGenre && newGenre.length > 0 && (genre.length == 0 || [genre isEqualToString:@"Unknown Genre"])) {
                        [updates addObject:[NSString stringWithFormat:@"set genre of t to \"%@\"", IGMediaAppleScriptLiteral(newGenre)]];
                    }
                    if (fixTrackNumber && [newTrackNumber integerValue] > 0 && [trackNumStr integerValue] == 0) {
                        [updates addObject:[NSString stringWithFormat:@"set track number of t to %@", newTrackNumber]];
                    }
                    if (fixTitle && newTitle.length > 0 && (name.length == 0 || [name isEqualToString:@"Unknown Title"])) {
                        [updates addObject:[NSString stringWithFormat:@"set name of t to \"%@\"", IGMediaAppleScriptLiteral(newTitle)]];
                    }
                    if (fixArtist && newArtist.length > 0 && (artist.length == 0 || [artist isEqualToString:@"Unknown Artist"])) {
                        [updates addObject:[NSString stringWithFormat:@"set artist of t to \"%@\"", IGMediaAppleScriptLiteral(newArtist)]];
                    }
                    if (fixLyrics && fetchedLyrics) {
                        [updates addObject:[NSString stringWithFormat:@"set lyrics of t to \"%@\"", IGMediaAppleScriptLiteral(fetchedLyrics)]];
                    }

                    if (updates.count > 0) {
                        NSString *updateScript = [NSString stringWithFormat:
                            @"tell application \"iTunes\"\n"
                            "    try\n"
                            "        set t to (some track of library playlist 1 whose persistent ID is \"%@\")\n"
                            "        %@\n"
                            "    end try\n"
                            "end tell", pid, [updates componentsJoinedByString:@"\n"]];
                        [service runAppleScriptNamed:@"mediaFixer.metadata.updateTrack" source:updateScript];
                        updatedRows++;
                    }
                } @catch (NSException *exception) {
                    [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"MediaFixer manager: exception processing track %ld: %@", (long)currentIndex, exception]];
                    NSLog(@"Exception caught processing track %ld: %@", (long)currentIndex, exception);
                }

#if !__has_feature(objc_arc)
                [fetchedInfo release];
                [fetchedLyrics release];
#endif
                reportProgress(currentIndex);
            }

            if (seenRows == 0) {
                reportProgress(end);
            }
            [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"MediaFixer manager: metadata chunk %ld-%ld parsed=%ld updated=%ld",
                                          (long)start, (long)end, (long)parsedRows, (long)updatedRows]];
#if !__has_feature(objc_arc)
            [pool drain];
#endif
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [[IGLogger sharedLogger] log:@"MediaFixer manager: metadata scan completed"];
            completionBlock();
        });
    });
}

@end
