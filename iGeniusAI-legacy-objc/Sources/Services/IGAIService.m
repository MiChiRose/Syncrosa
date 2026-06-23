#import "IGAIService.h"
#import "IGLogger.h"

@interface IGAIService () <NSURLSessionDelegate>
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation IGAIService

+ (instancetype)sharedService {
    static IGAIService *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
        sharedInstance.provider = @"Gemini";
        sharedInstance.model = @"google/gemini-2.0-flash-exp:free";
        
        // Initialize session with self as delegate to handle legacy SSL issues
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        sharedInstance.session = [NSURLSession sessionWithConfiguration:config 
                                                               delegate:sharedInstance 
                                                          delegateQueue:[NSOperationQueue mainQueue]];
    });
    return sharedInstance;
}

#pragma mark - NSURLSessionDelegate (Secure SSL Support)

- (void)URLSession:(NSURLSession *)session 
              task:(NSURLSessionTask *)task 
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge 
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    
    NSString *host = challenge.protectionSpace.host;
    NSArray *trustedHosts = @[@"generativelanguage.googleapis.com", @"api.groq.com", @"openrouter.ai", @"itunes.apple.com"];
    
    BOOL isTrusted = NO;
    for (NSString *h in trustedHosts) {
        if ([host rangeOfString:h].location != NSNotFound) {
            isTrusted = YES;
            break;
        }
    }

    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        if (isTrusted) {
            // For older macOS, we still might need to help it with the trust if root certs are expired,
            // but we only do this for our known AI providers.
            completionHandler(NSURLSessionAuthChallengeUseCredential, [[NSURLCredential alloc] initWithTrust:challenge.protectionSpace.serverTrust]);
        } else {
            // Default handling for other hosts (more secure)
            completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
        }
    } else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}

#pragma mark - Network Helper with Curl Fallback

- (void)makeRequestToURL:(NSURL *)url 
                  method:(NSString *)method 
                 headers:(NSDictionary *)headers 
                    body:(NSData *)body 
              completion:(void(^)(NSData *data, NSError *error))completionBlock {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method;
    [request addValue:@"iTunesGeniusAI/1.0 (macOS)" forHTTPHeaderField:@"User-Agent"];
    for (NSString *key in headers) {
        [request addValue:headers[key] forHTTPHeaderField:key];
    }
    if (body) {
        request.HTTPBody = body;
        [request addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }
    
    [[self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error && data) {
            completionBlock(data, nil);
            return;
        }
        
        // Fallback to curl on network error (likely SSL/TLS failure on 10.9)
        [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"NSURLSession failed: %@. Falling back to curl...", error.localizedDescription]];
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSTask *task = [[NSTask alloc] init];
            [task setLaunchPath:@"/usr/bin/curl"];
            
            NSMutableArray *args = [NSMutableArray arrayWithArray:@[@"-sSL", @"-m", @"60"]];
            [args addObjectsFromArray:@[@"-H", @"User-Agent: iTunesGeniusAI/1.0 (macOS)"]];
            
            for (NSString *key in headers) {
                [args addObjectsFromArray:@[@"-H", [NSString stringWithFormat:@"%@: %@", key, headers[key]]]];
            }
            
            NSString *tmpFile = nil;
            if (body) {
                [args addObjectsFromArray:@[@"-H", @"Content-Type: application/json"]];
                tmpFile = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
                [body writeToFile:tmpFile atomically:YES];
                [args addObjectsFromArray:@[@"-d", [NSString stringWithFormat:@"@%@", tmpFile]]];
            }
            
            [args addObject:url.absoluteString];
            [task setArguments:args];
            
            NSPipe *pipe = [NSPipe pipe];
            [task setStandardOutput:pipe];
            
            @try {
                [task launch];
                [task waitUntilExit];
                
                if (tmpFile) {
                    [[NSFileManager defaultManager] removeItemAtPath:tmpFile error:nil];
                }
                
                NSData *curlData = [[pipe fileHandleForReading] readDataToEndOfFile];
                if ([task terminationStatus] == 0 && curlData.length > 0) {
                    completionBlock(curlData, nil);
                } else {
                    NSString *errDesc = [NSString stringWithFormat:@"Curl failed with status %d", [task terminationStatus]];
                    completionBlock(nil, [NSError errorWithDomain:@"IGCurlError" code:[task terminationStatus] userInfo:@{NSLocalizedDescriptionKey: errDesc}]);
                }
            } @catch (NSException *exception) {
                if (tmpFile) {
                    [[NSFileManager defaultManager] removeItemAtPath:tmpFile error:nil];
                }
                completionBlock(nil, [NSError errorWithDomain:@"IGCurlException" code:-1 userInfo:@{NSLocalizedDescriptionKey: exception.reason}]);
            }
        });
    }] resume];
}

- (void)fetchOpenRouterModelsWithCompletion:(void(^)(NSArray *models))completionBlock {
    NSURL *url = [NSURL URLWithString:@"https://openrouter.ai/api/v1/models"];
    NSDictionary *headers = @{
        @"HTTP-Referer": @"https://github.com/MiChiRose/iGeniusAI",
        @"X-Title": @"iGeniusAI-Legacy"
    };
    
    [self makeRequestToURL:url method:@"GET" headers:headers body:nil completion:^(NSData *data, NSError *error) {
        if (data && !error) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSArray *dataArray = json[@"data"];
            NSMutableArray *freeModels = [NSMutableArray array];
            for (NSDictionary *m in dataArray) {
                NSString *modelID = m[@"id"];
                if ([modelID rangeOfString:@":free"].location != NSNotFound) {
                    [freeModels addObject:modelID];
                }
            }
            [freeModels sortUsingSelector:@selector(compare:)];
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(freeModels);
            });
        } else {
            [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"Sync failed: %@", error.localizedDescription]];
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(nil);
            });
        }
    }];
}

- (void)validateAPIKeyWithCompletion:(void(^)(BOOL success, NSString *errorMsg))completionBlock {
    if (!self.apiKey || self.apiKey.length == 0) {
        completionBlock(NO, @"API Key is empty");
        return;
    }
    
    NSURL *url = nil;
    NSDictionary *bodyDict = nil;
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    
    if ([self.provider isEqualToString:@"Groq"]) {
        url = [NSURL URLWithString:@"https://api.groq.com/openai/v1/chat/completions"];
        bodyDict = @{
            @"model": self.model,
            @"messages": @[@{@"role": @"user", @"content": @"Say 'OK'"}],
            @"max_tokens": @10
        };
        headers[@"Authorization"] = [NSString stringWithFormat:@"Bearer %@", self.apiKey];
    } else if ([self.provider isEqualToString:@"OpenRouter"]) {
        url = [NSURL URLWithString:@"https://openrouter.ai/api/v1/chat/completions"];
        bodyDict = @{
            @"model": self.model,
            @"messages": @[@{@"role": @"user", @"content": @"Say 'OK'"}],
            @"max_tokens": @10
        };
        headers[@"Authorization"] = [NSString stringWithFormat:@"Bearer %@", self.apiKey];
        headers[@"HTTP-Referer"] = @"https://github.com/MiChiRose/iGeniusAI";
        headers[@"X-Title"] = @"iGeniusAI-Legacy";
    } else {
        // Gemini
        NSString *urlStr = [NSString stringWithFormat:@"https://generativelanguage.googleapis.com/v1beta/models/%@:generateContent?key=%@", self.model, self.apiKey];
        url = [NSURL URLWithString:urlStr];
        bodyDict = @{
            @"contents": @[@{@"parts": @[@{@"text": @"Say 'OK'"}]}],
            @"generationConfig": @{@"maxOutputTokens": @10}
        };
    }
    
    NSData *body = [NSJSONSerialization dataWithJSONObject:bodyDict options:0 error:nil];
    
    [self makeRequestToURL:url method:@"POST" headers:headers body:body completion:^(NSData *data, NSError *error) {
        if (error || !data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(NO, error ? error.localizedDescription : @"Unknown network error");
            });
            return;
        }
        
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        BOOL success = NO;
        if ([self.provider isEqualToString:@"Gemini"]) {
            success = (json[@"candidates"] != nil);
        } else {
            success = (json[@"choices"] != nil);
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock(success, success ? @"OK" : @"Invalid Response");
        });
    }];
}

- (void)generatePlaylistWithPrompt:(NSString *)prompt 
                             count:(NSInteger)count 
                     librarySample:(NSArray *)sample 
                        completion:(void(^)(NSArray *suggestedIDs))completionBlock {
    
    NSString *libraryText = [sample componentsJoinedByString:@"\\n"];
    NSString *systemPrompt = [NSString stringWithFormat:
        @"You are an expert DJ AI.\n"
        "Create a playlist from the provided library.\n"
        "Event/Mood requested: %@\n"
        "Target Track Count: %ld\n\n"
        "Library format: PersistentID|Artist|Title|Genre|Year\n"
        "%@\n\n"
        "CRITICAL RULES:\n"
        "1. Select exactly %ld tracks. If you cannot find perfect matches, select the closest alternatives based on artist style or genre to ensure you reach the target count.\n"
        "2. You MUST return ONLY the 16-character hexadecimal PersistentID for each selected track.\n"
        "3. DO NOT return track titles or artist names. Only the IDs (the first part of each line).\n"
        "4. Your ENTIRE output MUST BE ONLY a single, flat JSON array of these ID strings.\n"
        "5. DO NOT add explanations, notes, or markdown.\n"
        "CORRECT OUTPUT FORMAT: [\"A1B2C3D4E5F67890\", \"0987654321ABCDEF\"]", 
        prompt, (long)count, libraryText, (long)count];

    NSURL *url = nil;
    NSDictionary *bodyDict = nil;
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    
    if ([self.provider isEqualToString:@"Groq"] || [self.provider isEqualToString:@"OpenRouter"]) {
        url = [NSURL URLWithString:[self.provider isEqualToString:@"Groq"] ? @"https://api.groq.com/openai/v1/chat/completions" : @"https://openrouter.ai/api/v1/chat/completions"];
        bodyDict = @{
            @"model": self.model,
            @"messages": @[
                @{@"role": @"system", @"content": @"You are a strict data API. You MUST output ONLY a valid JSON array of strings."},
                @{@"role": @"user", @"content": systemPrompt}
            ],
            @"temperature": @0.3
        };
        headers[@"Authorization"] = [NSString stringWithFormat:@"Bearer %@", self.apiKey];
        if ([self.provider isEqualToString:@"OpenRouter"]) {
            headers[@"HTTP-Referer"] = @"https://github.com/MiChiRose/iGeniusAI";
            headers[@"X-Title"] = @"iGeniusAI-Legacy";
        }
    } else {
        // Gemini
        NSString *urlStr = [NSString stringWithFormat:@"https://generativelanguage.googleapis.com/v1beta/models/%@:generateContent?key=%@", self.model, self.apiKey];
        url = [NSURL URLWithString:urlStr];
        bodyDict = @{
            @"contents": @[@{@"parts": @[@{@"text": systemPrompt}]}]
        };
    }

    NSData *body = [NSJSONSerialization dataWithJSONObject:bodyDict options:0 error:nil];
    
    [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"Sending request to %@ (Model: %@)", self.provider, self.model]];

    [self makeRequestToURL:url method:@"POST" headers:headers body:body completion:^(NSData *data, NSError *error) {
        if (!data || error) {
            [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"Network Error: %@", error ? error.localizedDescription : @"Empty data"]];
            [[IGLogger sharedLogger] saveLogToDesktopWithRawResponse:nil];
            dispatch_async(dispatch_get_main_queue(), ^{ completionBlock(nil); });
            return;
        }
        
        NSString *rawText = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *text = @"";
        
        if ([self.provider isEqualToString:@"Gemini"]) {
            NSArray *candidates = json[@"candidates"];
            if (candidates.count > 0) {
                text = candidates[0][@"content"][@"parts"][0][@"text"];
            }
        } else {
            NSArray *choices = json[@"choices"];
            if (choices.count > 0) {
                text = choices[0][@"message"][@"content"];
            }
        }
        
        if (text.length == 0) {
            [[IGLogger sharedLogger] log:@"Error: AI returned empty response or invalid format."];
            [[IGLogger sharedLogger] saveLogToDesktopWithRawResponse:rawText];
        }

        // Use Regex to extract 16-char hex IDs
        NSError *regError = nil;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"([a-fA-F0-9]{16})" options:0 error:&regError];
        NSArray *matches = [regex matchesInString:text options:0 range:NSMakeRange(0, text.length)];
        
        NSMutableArray *ids = [NSMutableArray array];
        for (NSTextCheckingResult *match in matches) {
            NSString *matchStr = [text substringWithRange:[match rangeAtIndex:1]];
            if (![ids containsObject:matchStr]) {
                [ids addObject:matchStr];
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (ids.count > count) {
                completionBlock([ids subarrayWithRange:NSMakeRange(0, count)]);
            } else {
                completionBlock(ids);
            }
        });
    }];
}
@end
