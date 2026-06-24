#import "IGMediaFixerManager.h"
#import "IGiTunesService.h"

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
                    @"yr": releaseDate ? [releaseDate substringToIndex:4] : @""
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
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        IGiTunesService *service = [IGiTunesService sharedService];
        NSString *countStr = [service runAppleScript:@"tell application \"iTunes\" to count every track of library playlist 1"];
        NSInteger total = [countStr integerValue];
        
        for (NSInteger i = 1; i <= total; i++) {
            NSString *getScript = [NSString stringWithFormat:
                @"tell application \"iTunes\"\n"
                "    try\n"
                "        set t to track %ld of library playlist 1\n"
                "        set alb to album of t\n"
                "        if alb is \"\" or alb is \"Unknown Album\" or alb is missing value then\n"
                "            return (persistent ID of t) & \"|\" & (artist of t) & \"|\" & (name of t)\n"
                "        end if\n"
                "    \n    end try\n"
                "end tell\n"
                "return \"SKIP\"", (long)i];
            
            NSString *trackRaw = [service runAppleScript:getScript];
            if ([trackRaw isEqualToString:@"SKIP"] || [trackRaw rangeOfString:@"|"].location == NSNotFound) {
                if (progressBlock) {
                    dispatch_async(dispatch_get_main_queue(), ^{ progressBlock(i, total); });
                }
                continue;
            }

            NSArray *parts = [trackRaw componentsSeparatedByString:@"|"];
            if (parts.count < 3) continue;
            
            NSString *pid = parts[0];
            NSString *artist = parts[1];
            NSString *title = parts[2];

            dispatch_semaphore_t sema = dispatch_semaphore_create(0);
            [self fetchAppleMetadataForArtist:artist title:title completion:^(NSDictionary *info) {
                if (info) {
                    NSMutableArray *updates = [NSMutableArray array];
                    if (info[@"alb"]) [updates addObject:[NSString stringWithFormat:@"set album of t to \"%@\"", [info[@"alb"] stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]]];
                    if (info[@"yr"]) [updates addObject:[NSString stringWithFormat:@"set year of t to %@", info[@"yr"]]];
                    if (info[@"gen"]) [updates addObject:[NSString stringWithFormat:@"set genre of t to \"%@\"", [info[@"gen"] stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]]];
                    
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
                }
                dispatch_semaphore_signal(sema);
            }];
            dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

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
