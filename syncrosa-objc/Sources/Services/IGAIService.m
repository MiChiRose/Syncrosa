#import "IGAIService.h"
#import "IGLogger.h"

@interface IGAIService ()
@end

static NSString *IGAITempPath(NSString *extension) {
    NSString *baseName = [NSString stringWithFormat:@"syncrosa-curl-%@", [[NSProcessInfo processInfo] globallyUniqueString]];
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[baseName stringByAppendingPathExtension:extension]];
}

static BOOL IGAICreatePrivateFile(NSString *path) {
    NSDictionary *attrs = @{NSFilePosixPermissions: [NSNumber numberWithUnsignedLong:0600]};
    return [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:attrs];
}

static NSString *IGAICurlConfigQuote(NSString *value) {
    NSString *source = value ? value : @"";
    NSMutableString *escaped = [[source mutableCopy] autorelease];
    [escaped replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:0 range:NSMakeRange(0, escaped.length)];
    return escaped;
}

static BOOL IGAIWritePrivateData(NSData *data, NSString *path) {
    if (!IGAICreatePrivateFile(path)) return NO;
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) return NO;
    [handle writeData:data ? data : [NSData data]];
    [handle closeFile];
    return YES;
}

NSString *IGAICurlExecutablePath(void) {
    NSString *bundled = [[NSBundle mainBundle] pathForResource:@"curl" ofType:nil inDirectory:@"LegacyCurl"];
    NSArray *candidates = @[
        bundled ?: @"",
        @"/opt/local/bin/curl",
        @"/usr/local/bin/curl",
        @"/opt/homebrew/bin/curl",
        @"/usr/bin/curl"
    ];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *path in candidates) {
        if (path.length > 0 && [fileManager isExecutableFileAtPath:path]) {
            return path;
        }
    }
    return @"/usr/bin/curl";
}

NSString *IGAIUserFacingNetworkErrorMessage(NSError *error) {
    if ([[error domain] isEqualToString:@"IGCurlError"] && [error code] == 35) {
        return @"Secure connection failed. This Mac could not negotiate modern TLS with the AI provider.";
    }
    if ([[error domain] isEqualToString:NSURLErrorDomain]) {
        return @"Could not connect to the AI provider. Check the network connection and try again.";
    }
    return @"Could not connect to the AI provider. Try again in a moment.";
}

@implementation IGAIService

+ (instancetype)sharedService {
    static IGAIService *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
        sharedInstance.provider = @"Gemini";
        sharedInstance.model = @"google/gemini-2.0-flash-exp:free";
    });
    return sharedInstance;
}

#pragma mark - Network Helper

- (void)makeRequestToURL:(NSURL *)url
                  method:(NSString *)method
                 headers:(NSDictionary *)headers
                    body:(NSData *)body
              completion:(void(^)(NSData *data, NSError *error))completionBlock {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSTask *task = [[[NSTask alloc] init] autorelease];
        NSString *curlPath = IGAICurlExecutablePath();
        [task setLaunchPath:curlPath];
        NSString *bundledLibPath = [[[curlPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"lib"] stringByStandardizingPath];
        BOOL bundledRuntime = [curlPath rangeOfString:@"/Contents/Resources/LegacyCurl/"].location != NSNotFound;
        if (bundledRuntime && [[NSFileManager defaultManager] fileExistsAtPath:bundledLibPath]) {
            NSMutableDictionary *environment = [NSMutableDictionary dictionaryWithDictionary:[[NSProcessInfo processInfo] environment]];
            [environment setObject:bundledLibPath forKey:@"DYLD_LIBRARY_PATH"];
            [task setEnvironment:environment];
        }
        [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"AI request transport: %@", curlPath]];

        NSString *requestMethod = method.length > 0 ? method : @"GET";
        NSMutableString *curlConfig = [NSMutableString string];
        [curlConfig appendString:@"silent\n"];
        [curlConfig appendString:@"show-error\n"];
        [curlConfig appendString:@"location\n"];
        [curlConfig appendString:@"max-time = \"60\"\n"];
        [curlConfig appendFormat:@"request = \"%@\"\n", IGAICurlConfigQuote(requestMethod)];
        [curlConfig appendFormat:@"url = \"%@\"\n", IGAICurlConfigQuote(url.absoluteString)];
        NSString *caPath = [[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"];
        if (caPath.length > 0) {
            [curlConfig appendFormat:@"cacert = \"%@\"\n", IGAICurlConfigQuote(caPath)];
        }
        [curlConfig appendString:@"header = \"User-Agent: Syncrosa/1.0 (macOS)\"\n"];
        BOOL hasContentType = NO;
        for (NSString *key in headers) {
            NSString *value = headers[key];
            if ([[key lowercaseString] isEqualToString:@"content-type"]) {
                hasContentType = YES;
            }
            [curlConfig appendFormat:@"header = \"%@: %@\"\n", IGAICurlConfigQuote(key), IGAICurlConfigQuote(value)];
        }

        NSString *tmpFile = nil;
        if (body) {
            if (!hasContentType) {
                [curlConfig appendString:@"header = \"Content-Type: application/json\"\n"];
            }

            tmpFile = IGAITempPath(@"json");
            if (!IGAIWritePrivateData(body, tmpFile)) {
                NSString *errDesc = @"Failed to write temporary request body";
                NSError *writeError = [NSError errorWithDomain:@"IGCurlError" code:-2 userInfo:@{NSLocalizedDescriptionKey: errDesc}];
                completionBlock(nil, writeError);
                return;
            }
            [curlConfig appendFormat:@"data-binary = \"@%@\"\n", IGAICurlConfigQuote(tmpFile)];
        }

        NSString *configPath = IGAITempPath(@"conf");
        NSData *configData = [curlConfig dataUsingEncoding:NSUTF8StringEncoding];
        if (!IGAIWritePrivateData(configData, configPath)) {
            if (tmpFile) {
                [[NSFileManager defaultManager] removeItemAtPath:tmpFile error:nil];
            }
            NSString *errDesc = @"Failed to write temporary curl config";
            NSError *writeError = [NSError errorWithDomain:@"IGCurlError" code:-3 userInfo:@{NSLocalizedDescriptionKey: errDesc}];
            completionBlock(nil, writeError);
            return;
        }

        NSMutableArray *args = [NSMutableArray arrayWithArray:@[@"-q", @"-K", configPath]];
        [task setArguments:args];

        NSString *stdoutPath = IGAITempPath(@"stdout");
        NSString *stderrPath = IGAITempPath(@"stderr");
        IGAICreatePrivateFile(stdoutPath);
        IGAICreatePrivateFile(stderrPath);
        NSFileHandle *stdoutHandle = [NSFileHandle fileHandleForWritingAtPath:stdoutPath];
        NSFileHandle *stderrHandle = [NSFileHandle fileHandleForWritingAtPath:stderrPath];
        [task setStandardOutput:stdoutHandle];
        [task setStandardError:stderrHandle];

        @try {
            [task launch];
            [task waitUntilExit];
            [stdoutHandle closeFile];
            [stderrHandle closeFile];

            NSData *curlData = [NSData dataWithContentsOfFile:stdoutPath];
            NSData *stderrData = [NSData dataWithContentsOfFile:stderrPath];
            NSString *stderrText = @"";
            if (stderrData.length > 0) {
                NSString *decoded = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding];
                stderrText = decoded ?: @"";
#if !__has_feature(objc_arc)
                [decoded autorelease];
#endif
            }
            if (tmpFile) {
                [[NSFileManager defaultManager] removeItemAtPath:tmpFile error:nil];
            }
            [[NSFileManager defaultManager] removeItemAtPath:configPath error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:stdoutPath error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:stderrPath error:nil];

            if ([task terminationStatus] == 0 && curlData.length > 0) {
                completionBlock(curlData, nil);
            } else {
                NSString *errDesc = stderrText.length > 0 ?
                    [NSString stringWithFormat:@"Curl failed with status %d: %@", [task terminationStatus], stderrText] :
                    [NSString stringWithFormat:@"Curl failed with status %d", [task terminationStatus]];
                NSError *curlError = [NSError errorWithDomain:@"IGCurlError" code:[task terminationStatus] userInfo:@{NSLocalizedDescriptionKey: errDesc}];
                completionBlock(nil, curlError);
            }
        } @catch (NSException *exception) {
            [stdoutHandle closeFile];
            [stderrHandle closeFile];
            if (tmpFile) {
                [[NSFileManager defaultManager] removeItemAtPath:tmpFile error:nil];
            }
            [[NSFileManager defaultManager] removeItemAtPath:configPath error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:stdoutPath error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:stderrPath error:nil];
            NSString *reason = exception.reason ?: @"Curl exception";
            NSError *curlException = [NSError errorWithDomain:@"IGCurlException" code:-1 userInfo:@{NSLocalizedDescriptionKey: reason}];
            completionBlock(nil, curlException);
        }
    });
}

- (void)fetchOpenRouterModelsWithCompletion:(void(^)(NSArray *models))completionBlock {
    [self fetchOpenRouterModelsWithDetailedCompletion:^(NSArray *models, NSError *error) {
        (void)error;
        completionBlock(models);
    }];
}

- (void)fetchOpenRouterModelsWithDetailedCompletion:(void(^)(NSArray *models, NSError *error))completionBlock {
    NSURL *url = [NSURL URLWithString:@"https://openrouter.ai/api/v1/models"];
    NSDictionary *headers = @{
        @"HTTP-Referer": @"https://github.com/MiChiRose/Syncrosa",
        @"X-Title": @"Syncrosa-Legacy"
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
                completionBlock(freeModels, nil);
            });
        } else {
            [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"Sync failed: %@", error.localizedDescription]];
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(nil, error);
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

    BOOL isGroq = ([self.provider caseInsensitiveCompare:@"Groq"] == NSOrderedSame);
    BOOL isOpenRouter = ([self.provider caseInsensitiveCompare:@"OpenRouter"] == NSOrderedSame);
    BOOL isGemini = ([self.provider caseInsensitiveCompare:@"Gemini"] == NSOrderedSame);

    if (isGroq) {
        url = [NSURL URLWithString:@"https://api.groq.com/openai/v1/chat/completions"];
        bodyDict = @{
            @"model": self.model,
            @"messages": @[@{@"role": @"user", @"content": @"Say 'OK'"}],
            @"max_tokens": @10
        };
        headers[@"Authorization"] = [NSString stringWithFormat:@"Bearer %@", self.apiKey];
    } else if (isOpenRouter) {
        url = [NSURL URLWithString:@"https://openrouter.ai/api/v1/chat/completions"];
        bodyDict = @{
            @"model": self.model,
            @"messages": @[@{@"role": @"user", @"content": @"Say 'OK'"}],
            @"max_tokens": @10
        };
        headers[@"Authorization"] = [NSString stringWithFormat:@"Bearer %@", self.apiKey];
        headers[@"HTTP-Referer"] = @"https://github.com/MiChiRose/Syncrosa";
        headers[@"X-Title"] = @"Syncrosa-Legacy";
    } else {
        // Gemini
        NSString *urlStr = [NSString stringWithFormat:@"https://generativelanguage.googleapis.com/v1beta/models/%@:generateContent", self.model];
        url = [NSURL URLWithString:urlStr];
        headers[@"x-goog-api-key"] = self.apiKey;
        bodyDict = @{
            @"contents": @[@{@"parts": @[@{@"text": @"Say 'OK'"}]}],
            @"generationConfig": @{@"maxOutputTokens": @10}
        };
    }

    NSData *body = [NSJSONSerialization dataWithJSONObject:bodyDict options:0 error:nil];

    [self makeRequestToURL:url method:@"POST" headers:headers body:body completion:^(NSData *data, NSError *error) {
        if (error || !data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(NO, error ? IGAIUserFacingNetworkErrorMessage(error) : @"Unknown network error");
            });
            return;
        }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        BOOL success = NO;
        if (isGemini || (!isGroq && !isOpenRouter)) {
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

    BOOL isGroq = ([self.provider caseInsensitiveCompare:@"Groq"] == NSOrderedSame);
    BOOL isOpenRouter = ([self.provider caseInsensitiveCompare:@"OpenRouter"] == NSOrderedSame);
    BOOL isGemini = ([self.provider caseInsensitiveCompare:@"Gemini"] == NSOrderedSame);

    if (isGroq || isOpenRouter) {
        url = [NSURL URLWithString:isGroq ? @"https://api.groq.com/openai/v1/chat/completions" : @"https://openrouter.ai/api/v1/chat/completions"];
        bodyDict = @{
            @"model": self.model,
            @"messages": @[
                @{@"role": @"system", @"content": @"You are a strict data API. You MUST output ONLY a valid JSON array of strings."},
                @{@"role": @"user", @"content": systemPrompt}
            ],
            @"temperature": @0.3
        };
        headers[@"Authorization"] = [NSString stringWithFormat:@"Bearer %@", self.apiKey];
        if (isOpenRouter) {
            headers[@"HTTP-Referer"] = @"https://github.com/MiChiRose/Syncrosa";
            headers[@"X-Title"] = @"Syncrosa-Legacy";
        }
    } else {
        // Gemini
        NSString *urlStr = [NSString stringWithFormat:@"https://generativelanguage.googleapis.com/v1beta/models/%@:generateContent", self.model];
        url = [NSURL URLWithString:urlStr];
        headers[@"x-goog-api-key"] = self.apiKey;
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
#if !__has_feature(objc_arc)
        [rawText autorelease];
#endif
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *text = @"";

        if (isGemini || (!isGroq && !isOpenRouter)) {
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
