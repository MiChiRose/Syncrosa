#import "IGLyricsService.h"

@interface IGLyricsService ()
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation IGLyricsService

+ (instancetype)sharedService {
    static IGLyricsService *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 5.0;
        config.timeoutIntervalForResource = 5.0;
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
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
        
        if (!escapedArtist || !escapedTitle) {
            completionBlock(nil);
            return;
        }
        
        NSString *urlString = [NSString stringWithFormat:@"https://api.lyrics.ovh/v1/%@/%@", escapedArtist, escapedTitle];
        NSURL *url = [NSURL URLWithString:urlString];
        
        if (!url) {
            completionBlock(nil);
            return;
        }
        
        NSURLSessionDataTask *task = [self.session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error || !data) {
                completionBlock(nil);
                return;
            }
            
            @try {
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                if (httpResponse.statusCode != 200) {
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
        }];
        [task resume];
    } @catch (NSException *ex) {
        NSLog(@"Exception in lyrics fetch setup: %@", ex);
        completionBlock(nil);
    }
}

@end
