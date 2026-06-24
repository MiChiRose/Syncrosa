#import "IGiTunesService.h"

@implementation IGiTunesService

+ (instancetype)sharedService {
    static IGiTunesService *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (NSString *)runAppleScript:(NSString *)source {
    __block NSString *result = nil;
    if ([NSThread isMainThread]) {
        NSAppleScript *script = [[NSAppleScript alloc] initWithSource:source];
        NSDictionary *error = nil;
        NSAppleEventDescriptor *descriptor = [script executeAndReturnError:&error];
        if (error) {
            NSLog(@"AppleScript Error: %@", error);
        }
        result = [descriptor stringValue];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            NSAppleScript *script = [[NSAppleScript alloc] initWithSource:source];
            NSDictionary *error = nil;
            NSAppleEventDescriptor *descriptor = [script executeAndReturnError:&error];
            if (error) {
                NSLog(@"AppleScript Error: %@", error);
            }
            result = [descriptor stringValue];
        });
    }
    return result;
}

- (void)fetchAllTracksWithProgress:(void(^)(NSInteger current, NSInteger total))progressBlock 
                        completion:(void(^)(NSArray *tracks))completionBlock {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *countStr = [self runAppleScript:@"tell application \"iTunes\" to count every track"];
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
                @"set out to \"\"\n"
                "tell application \"iTunes\"\n"
                "    set trks to (tracks %ld thru %ld of library playlist 1)\n"
                "    repeat with t in trks\n"
                "        try\n"
                "            set pid to persistent ID of t\n"
                "            set art to artist of t\n"
                "            set nm to name of t\n"
                "            set alb to album of t\n"
                "            set gen to genre of t\n"
                "            set yr to year of t\n"
                "            set out to out & pid & \"|\" & art & \"|\" & nm & \"|\" & alb & \"|\" & gen & \"|\" & yr & \"\\n\"\n"
                "        end try\n"
                "    end repeat\n"
                "end tell\n"
                "return out", (long)i, (long)end];

            NSString *result = [self runAppleScript:scriptSource];
            if (result) {
                NSArray *lines = [result componentsSeparatedByString:@"\n"];
                for (NSString *line in lines) {
                    if ([line rangeOfString:@"|"].location != NSNotFound) {
                        NSArray *parts = [line componentsSeparatedByString:@"|"];
                        if (parts.count >= 6) {
                            IGTrack *track = [[IGTrack alloc] initWithPersistentID:parts[0]
                                                                              name:parts[2]
                                                                            artist:parts[1]
                                                                             album:parts[3]
                                                                             genre:parts[4]
                                                                              year:[parts[5] integerValue]];
                            [allTracks addObject:track];
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
        NSString *idsString = [NSString stringWithFormat:@"{\"%@\"}", [pids componentsJoinedByString:@"\", \""]];
        NSString *escapedName = [name stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
        
        NSString *scriptSource = [NSString stringWithFormat:
            @"tell application \"iTunes\"\n"
            "    set plName to \"%@\"\n"
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
            "        try\n"
            "            set trk to (some track of library playlist 1 whose persistent ID is tid)\n"
            "            duplicate trk to pl\n"
            "            set addedCount to addedCount + 1\n"
            "        end try\n"
            "    end repeat\n"
            "    return addedCount as string\n"
            "end tell", escapedName, idsString];

        NSString *result = [self runAppleScript:scriptSource];
        NSInteger count = [result integerValue];

        dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock(count);
        });
    });
}

- (void)fetchPlaylistsWithCompletion:(void(^)(NSArray<NSDictionary *> *playlists))completionBlock {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *script = 
            @"tell application \"iTunes\"\n"
            "    set output to \"\"\n"
            "    try\n"
            "        set plist to (every user playlist whose special kind is none)\n"
            "        repeat with pl in plist\n"
            "            set plName to name of pl\n"
            "            set plCount to count of tracks of pl\n"
            "            set output to output & plName & \"|\" & plCount & \"\\n\"\n"
            "        end repeat\n"
            "    end try\n"
            "    return output\n"
            "end tell";
            
        NSString *rawResult = [self runAppleScript:script];
        NSMutableArray *playlists = [NSMutableArray array];
        
        if (rawResult && rawResult.length > 0) {
            NSArray *lines = [rawResult componentsSeparatedByString:@"\n"];
            for (NSString *line in lines) {
                if (line.length == 0) continue;
                NSArray *parts = [line componentsSeparatedByString:@"|"];
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
                    completion:(void(^)(NSArray<NSDictionary *> *tracks))completionBlock {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *escapedName = [playlistName stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
        NSString *script = [NSString stringWithFormat:
            @"tell application \"iTunes\"\n"
            "    set output to \"\"\n"
            "    try\n"
            "        set pl to user playlist \"%@\"\n"
            "        set trks to every file track of pl\n"
            "        repeat with t in trks\n"
            "            try\n"
            "                set loc to location of t\n"
            "                if loc is not missing value then\n"
            "                    set trackPath to POSIX path of loc\n"
            "                    set trackName to name of t\n"
            "                    set trackArtist to artist of t\n"
            "                    set trackSize to size of t\n"
            "                    set output to output & trackName & \"|\" & trackArtist & \"|\" & trackPath & \"|\" & trackSize & \"\\n\"\n"
            "                end if\n"
            "            end try\n"
            "        end repeat\n"
            "    end try\n"
            "    return output\n"
            "end tell", escapedName];
            
        NSString *rawResult = [self runAppleScript:script];
        NSMutableArray *tracks = [NSMutableArray array];
        
        if (rawResult && rawResult.length > 0) {
            NSArray *lines = [rawResult componentsSeparatedByString:@"\n"];
            for (NSString *line in lines) {
                if (line.length == 0) continue;
                NSArray *parts = [line componentsSeparatedByString:@"|"];
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
