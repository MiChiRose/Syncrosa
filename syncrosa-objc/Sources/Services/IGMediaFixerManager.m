#import "IGMediaFixerManager.h"
#import "IGiTunesService.h"
#import "IGLyricsService.h"

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
    return [[words filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]] componentsJoinedByString:@" "];
}

- (void)fetchAppleMetadataForArtist:(NSString *)artist title:(NSString *)title completion:(void(^)(NSDictionary *info))completionBlock {
    NSString *cleanTitle = title;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"[\\(\\[].*?[\\)\\]]" options:0 error:nil];
    cleanTitle = [regex stringByReplacingMatchesInString:title options:0 range:NSMakeRange(0, title.length) withTemplate:@""];
    cleanTitle = [cleanTitle stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

    NSString *searchTerm = [NSString stringWithFormat:@"%@ %@", artist, cleanTitle];
    NSString *encodedTerm = [searchTerm stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://itunes.apple.com/search?term=%@&media=music&limit=1", encodedTerm]];

    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data && !error) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSArray *results = json[@"results"];
            if (results.count > 0) {
                NSDictionary *res = results[0];
                NSString *releaseDate = res[@"releaseDate"];
                completionBlock(@{
                    @"alb": res[@"collectionName"] ?: @"",
                    @"gen": res[@"primaryGenreName"] ?: @"",
                    @"yr": releaseDate ? [releaseDate substringToIndex:4] : @"",
                    @"title": res[@"trackName"] ?: @"",
                    @"art": res[@"artistName"] ?: @"",
                    @"trackNumber": res[@"trackNumber"] ?: @(0)
                });
                return;
            }
        }
        completionBlock(nil);
    }] resume];
}

- (void)getMergeCandidatesWithCompletion:(void(^)(NSArray *candidates))completionBlock {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        IGiTunesService *service = [IGiTunesService sharedService];
        NSString *script = @"set out to \"\"\ntell application \"iTunes\"\nset trks to every track of library playlist 1\nrepeat with t in trks\ntry\nset out to out & (persistent ID of t) & \"|\" & (artist of t) & \"|\" & (album of t) & \"\\n\"\nend try\nend repeat\nend tell\nreturn out";
        NSString *raw = [service runAppleScript:script];
        if (!raw) {
            dispatch_async(dispatch_get_main_queue(), ^{ completionBlock(@[]); });
            return;
        }

        NSMutableDictionary *groups = [NSMutableDictionary dictionary];
        NSArray *lines = [raw componentsSeparatedByString:@"\n"];
        
        for (NSString *line in lines) {
            NSArray *parts = [line componentsSeparatedByString:@"|"];
            if (parts.count < 3) continue;
            
            NSString *pid = parts[0];
            NSString *artist = parts[1];
            NSString *album = parts[2];
            
            if (album.length == 0) continue;
            
            NSString *key = [NSString stringWithFormat:@"%@|%@", [artist lowercaseString], [self normalizeText:album]];
            if (!groups[key]) groups[key] = [NSMutableArray array];
            [groups[key] addObject:@{@"pid": pid, @"alb": album}];
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
        }

        dispatch_async(dispatch_get_main_queue(), ^{
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
        IGiTunesService *service = [IGiTunesService sharedService];
        NSString *countStr = [service runAppleScript:@"tell application \"iTunes\" to count every track of library playlist 1"];
        NSInteger total = [countStr integerValue];
        
        BOOL fixAlbum = [options[@"album"] boolValue];
        BOOL fixTitle = [options[@"title"] boolValue];
        BOOL fixArtist = [options[@"artist"] boolValue];
        BOOL fixGenre = [options[@"genre"] boolValue];
        BOOL fixTrackNumber = [options[@"trackNumber"] boolValue];
        BOOL fixLyrics = [options[@"lyrics"] boolValue];
        
        for (NSInteger i = 1; i <= total; i++) {
            @try {
                // Get the current values of the track
                NSString *getScript = [NSString stringWithFormat:
                    @"tell application \"iTunes\"\n"
                    "    try\n"
                    "        set t to track %ld of library playlist 1\n"
                    "        set pid to persistent ID of t\n"
                    "        set nm to name of t\n"
                    "        set art to artist of t\n"
                    "        set alb to album of t\n"
                    "        set gen to genre of t\n"
                    "        set trk to track number of t\n"
                    "        set hasLyrics to \"YES\"\n"
                    "        try\n"
                    "            if lyrics of t is \"\" or lyrics of t is missing value then\n"
                    "                set hasLyrics to \"NO\"\n"
                    "            end if\n"
                    "        on error\n"
                    "            set hasLyrics to \"NO\"\n"
                    "        end try\n"
                    "        return pid & \"|\" & nm & \"|\" & art & \"|\" & alb & \"|\" & gen & \"|\" & trk & \"|\" & hasLyrics\n"
                    "    on error\n"
                    "        return \"SKIP\"\n"
                    "    end try\n"
                    "end tell", (long)i];
                
                NSString *trackRaw = [service runAppleScript:getScript];
                if (!trackRaw || [trackRaw isEqualToString:@"SKIP"] || [trackRaw rangeOfString:@"|"].location == NSNotFound) {
                    if (progressBlock) {
                        dispatch_async(dispatch_get_main_queue(), ^{ progressBlock(i, total); });
                    }
                    continue;
                }

                NSArray *parts = [trackRaw componentsSeparatedByString:@"|"];
                if (parts.count < 7) continue;
                
                NSString *pid = parts[0];
                NSString *name = parts[1];
                NSString *artist = parts[2];
                NSString *album = parts[3];
                NSString *genre = parts[4];
                NSString *trackNumStr = parts[5];
                NSString *hasLyricsStr = parts[6];
                
                // Let's decide if this track needs fixing
                BOOL needsFix = NO;
                if (fixTitle && (name.length == 0 || [name isEqualToString:@"Unknown Title"])) needsFix = YES;
                if (fixArtist && (artist.length == 0 || [artist isEqualToString:@"Unknown Artist"])) needsFix = YES;
                if (fixAlbum && (album.length == 0 || [album isEqualToString:@"Unknown Album"] || [album isEqualToString:@"missing value"])) needsFix = YES;
                if (fixGenre && (genre.length == 0 || [genre isEqualToString:@"Unknown Genre"])) needsFix = YES;
                if (fixTrackNumber && ([trackNumStr integerValue] == 0)) needsFix = YES;
                if (fixLyrics && [hasLyricsStr isEqualToString:@"NO"]) needsFix = YES;
                
                if (!needsFix) {
                    if (progressBlock) {
                        dispatch_async(dispatch_get_main_queue(), ^{ progressBlock(i, total); });
                    }
                    continue;
                }
                
                dispatch_semaphore_t sema = dispatch_semaphore_create(0);
                
                __block NSDictionary *fetchedInfo = nil;
                // Fetch iTunes metadata if any music tag is needed
                if (fixAlbum || fixTitle || fixArtist || fixGenre || fixTrackNumber) {
                    NSString *searchArtist = artist.length > 0 ? artist : @"";
                    NSString *searchTitle = name.length > 0 ? name : @"";
                    
                    [self fetchAppleMetadataForArtist:searchArtist title:searchTitle completion:^(NSDictionary *info) {
                        fetchedInfo = info;
                        dispatch_semaphore_signal(sema);
                    }];
                    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
                }
                
                __block NSString *fetchedLyrics = nil;
                if (fixLyrics) {
                    NSString *lyricsArtist = artist.length > 0 ? artist : (fetchedInfo[@"art"] ?: @"");
                    NSString *lyricsTitle = name.length > 0 ? name : (fetchedInfo[@"title"] ?: @"");
                    
                    [[IGLyricsService sharedService] fetchLyricsForArtist:lyricsArtist title:lyricsTitle completion:^(NSString *lyrics) {
                        fetchedLyrics = lyrics;
                        dispatch_semaphore_signal(sema);
                    }];
                    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
                }
                
                // Construct updates
                NSMutableArray *updates = [NSMutableArray array];
                if (fixAlbum && fetchedInfo[@"alb"] && (album.length == 0 || [album isEqualToString:@"Unknown Album"] || [album isEqualToString:@"missing value"])) {
                    [updates addObject:[NSString stringWithFormat:@"set album of t to \"%@\"", [fetchedInfo[@"alb"] stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]]];
                }
                if (fixGenre && fetchedInfo[@"gen"] && (genre.length == 0 || [genre isEqualToString:@"Unknown Genre"])) {
                    [updates addObject:[NSString stringWithFormat:@"set genre of t to \"%@\"", [fetchedInfo[@"gen"] stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]]];
                }
                if (fixTrackNumber && fetchedInfo[@"trackNumber"] && [trackNumStr integerValue] == 0) {
                    [updates addObject:[NSString stringWithFormat:@"set track number of t to %@", fetchedInfo[@"trackNumber"]]];
                }
                if (fixTitle && fetchedInfo[@"title"] && (name.length == 0 || [name isEqualToString:@"Unknown Title"])) {
                    [updates addObject:[NSString stringWithFormat:@"set name of t to \"%@\"", [fetchedInfo[@"title"] stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]]];
                }
                if (fixArtist && fetchedInfo[@"art"] && (artist.length == 0 || [artist isEqualToString:@"Unknown Artist"])) {
                    [updates addObject:[NSString stringWithFormat:@"set artist of t to \"%@\"", [fetchedInfo[@"art"] stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]]];
                }
                if (fixLyrics && fetchedLyrics) {
                    [updates addObject:[NSString stringWithFormat:@"set lyrics of t to \"%@\"", [fetchedLyrics stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]]];
                }
                
                if (updates.count > 0) {
                    NSString *updateScript = [NSString stringWithFormat:
                        @"tell application \"iTunes\"\n"
                        "    try\n"
                        "        set t to (some track whose persistent ID is \"%@\")\n"
                        "        %@\n"
                        "    end try\n"
                        "end tell", pid, [updates componentsJoinedByString:@"\n"]];
                    [service runAppleScript:updateScript];
                }
            } @catch (NSException *exception) {
                NSLog(@"Exception caught processing track %ld: %@", (long)i, exception);
            }
            
            if (progressBlock) {
                dispatch_async(dispatch_get_main_queue(), ^{ progressBlock(i, total); });
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock();
        });
    });
}

@end
