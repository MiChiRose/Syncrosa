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
    NSAppleScript *script = [[NSAppleScript alloc] initWithSource:source];
    NSDictionary *error = nil;
    NSAppleEventDescriptor *descriptor = [script executeAndReturnError:&error];
    if (error) {
        NSLog(@"AppleScript Error: %@", error);
        return nil;
    }
    return [descriptor stringValue];
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

// Stubs for metadata fixer - will implement details if needed
- (void)getMergeCandidatesWithCompletion:(void(^)(NSArray *candidates))completionBlock {
    // Logic from media_fixer.py to be ported here
    if (completionBlock) completionBlock(@[]);
}

- (void)runMetadataFixWithProgress:(void(^)(NSInteger current, NSInteger total))progressBlock 
                        completion:(void(^)(void))completionBlock {
    // Logic from media_fixer.py to be ported here
    if (completionBlock) completionBlock();
}

@end
