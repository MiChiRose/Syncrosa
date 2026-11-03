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
    [self fetchLyricsForArtist:artist title:title errorCompletion:^(NSString *lyrics, NSString *errorMessage) {
        if (completionBlock) completionBlock(lyrics);
    }];
}

- (void)fetchLyricsForArtist:(NSString *)artist
                       title:(NSString *)title
             errorCompletion:(void(^)(NSString *lyrics, NSString *errorMessage))completionBlock {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *errorMessage = nil;
        NSString *lyrics = [self lyricsForArtist:artist title:title errorMessage:&errorMessage];
        if (completionBlock) completionBlock(lyrics, errorMessage);
    });
}

- (NSString *)lyricsForArtist:(NSString *)artist title:(NSString *)title errorMessage:(NSString **)errorMessage {
    if (errorMessage) *errorMessage = nil;
    if ([artist length] == 0 || [title length] == 0 || [[NSUserDefaults standardUserDefaults] boolForKey:@"only_local_mode"]) return nil;
    @try {
        NSMutableCharacterSet *allowed = [[[NSCharacterSet alphanumericCharacterSet] mutableCopy] autorelease];
        [allowed addCharactersInString:@"-._~"];
        NSString *escapedArtist = [artist stringByAddingPercentEncodingWithAllowedCharacters:allowed];
        NSString *escapedTitle = [title stringByAddingPercentEncodingWithAllowedCharacters:allowed];
        if (!escapedArtist || !escapedTitle) {
            if (errorMessage) *errorMessage = @"Could not prepare the lyrics request.";
            return nil;
        }
        NSString *urlString = [NSString stringWithFormat:@"https://api.lyrics.ovh/v1/%@/%@", escapedArtist, escapedTitle];
        NSMutableArray *args = [NSMutableArray arrayWithArray:@[@"-sSL", @"-m", @"10", @"--write-out", @"\n%{http_code}"]];
        IGLyricsAddCACertIfAvailable(args);
        [args addObject:urlString];
        int status = -1;
        NSData *data = IGLyricsRunCurl(args, &status);
        if (status != 0 || [data length] == 0) {
            if (errorMessage) *errorMessage = @"Lyrics request failed or timed out.";
            return nil;
        }
        NSString *response = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
        NSRange separator = [response rangeOfString:@"\n" options:NSBackwardsSearch];
        if (!response || separator.location == NSNotFound) {
            if (errorMessage) *errorMessage = @"Lyrics service returned an invalid response.";
            return nil;
        }
        NSInteger httpStatus = [[response substringFromIndex:NSMaxRange(separator)] integerValue];
        if (httpStatus == 404) return nil;
        if (httpStatus < 200 || httpStatus >= 300) {
            if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Lyrics service returned HTTP %ld.", (long)httpStatus];
            return nil;
        }
        NSData *body = [[response substringToIndex:separator.location] dataUsingEncoding:NSUTF8StringEncoding];
        id json = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
        if (![json isKindOfClass:[NSDictionary class]] || ![[json objectForKey:@"lyrics"] isKindOfClass:[NSString class]]) {
            if (errorMessage) *errorMessage = @"Lyrics service returned an invalid response.";
            return nil;
        }
        NSString *lyrics = [json objectForKey:@"lyrics"];
        return [[lyrics stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0 ? lyrics : nil;
    } @catch (NSException *exception) {
        if (errorMessage) *errorMessage = @"Lyrics request could not be completed.";
        return nil;
    }
}

@end
