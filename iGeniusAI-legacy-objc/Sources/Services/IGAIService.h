#import <Foundation/Foundation.h>

@interface IGAIService : NSObject

+ (instancetype)sharedService;

@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, copy) NSString *provider; // "Gemini", "OpenRouter", "Groq"
@property (nonatomic, copy) NSString *model;

- (void)fetchOpenRouterModelsWithCompletion:(void(^)(NSArray *models))completionBlock;

- (void)validateAPIKeyWithCompletion:(void(^)(BOOL success, NSString *errorMsg))completionBlock;

- (void)generatePlaylistWithPrompt:(NSString *)prompt 
                             count:(NSInteger)count 
                     librarySample:(NSArray *)sample 
                        completion:(void(^)(NSArray *suggestedIDs))completionBlock;

@end
