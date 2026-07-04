#import "IGLyricsService.h"

@interface IGLyricsService ()
@end

static void IGLyricsAddCACertIfAvailable(NSMutableArray *args) {
    NSString *caPath = [[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"];
    if (caPath.length > 0) {
        [args addObjectsFromArray:@[@"--cacert", caPath]];
    }
}

static NSString *IGLyricsTempPath(NSString *extension) {
    NSString *baseName = [NSString stringWithFormat:@"syncrosa-curl-%@", [[NSProcessInfo processInfo] globallyUniqueString]];
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[baseName stringByAppendingPathExtension:extension]];
}

static NSData *IGLyricsRunCurl(NSArray *args, int *statusOut) {
    NSString *stdoutPath = IGLyricsTempPath(@"stdout");
    NSString *stderrPath = IGLyricsTempPath(@"stderr");
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
    } @catch (NSException *exception) {
        NSLog(@"Curl lyrics fetch failed: %@", exception.reason);
        [stdoutHandle closeFile];
        [stderrHandle closeFile];
    }

    [[NSFileManager defaultManager] removeItemAtPath:stdoutPath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:stderrPath error:nil];
    if (statusOut) *statusOut = status;
    return data;
}

@implementation IGLyricsService

+ (instancetype)sharedService {
    static IGLyricsService *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (void)fetchLyricsForArtist:(NSString *)artist
                       title:(NSString *)title
                  completion:(void(^)(NSString *lyrics))completionBlock {
    if (!artist || artist.length == 0 || !title || title.length == 0) {
        completionBlock(nil);
        return;
    }

    @try {
        NSMutableCharacterSet *allowed = [[NSCharacterSet URLPathAllowedCharacterSet] mutableCopy];
        [allowed removeCharactersInString:@"/"];

        NSString *escapedArtist = [artist stringByAddingPercentEncodingWithAllowedCharacters:allowed];
        NSString *escapedTitle = [title stringByAddingPercentEncodingWithAllowedCharacters:allowed];
#if !__has_feature(objc_arc)
        [allowed release];
#endif

        if (!escapedArtist || !escapedTitle) {
            completionBlock(nil);
            return;
        }

        NSString *urlString = [NSString stringWithFormat:@"https://api.lyrics.ovh/v1/%@/%@", escapedArtist, escapedTitle];
        if (!urlString) {
            completionBlock(nil);
            return;
        }

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @try {
                NSMutableArray *args = [NSMutableArray arrayWithArray:@[@"-sSL", @"-m", @"10"]];
                IGLyricsAddCACertIfAvailable(args);
                [args addObject:urlString];

                int status = -1;
                NSData *data = IGLyricsRunCurl(args, &status);
                if (status != 0 || data.length == 0) {
                    completionBlock(nil);
                    return;
                }

                NSError *jsonError = nil;
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                if (jsonError || ![json isKindOfClass:[NSDictionary class]]) {
                    completionBlock(nil);
                    return;
                }

                NSString *lyrics = json[@"lyrics"];
                if ([lyrics isKindOfClass:[NSString class]] && lyrics.length > 0) {
                    completionBlock(lyrics);
                } else {
                    completionBlock(nil);
                }
            } @catch (NSException *ex) {
                NSLog(@"Exception in lyrics parsing: %@", ex);
                completionBlock(nil);
            }
        });
    } @catch (NSException *ex) {
        NSLog(@"Exception in lyrics fetch setup: %@", ex);
        completionBlock(nil);
    }
}

@end
