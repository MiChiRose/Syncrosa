#import <Foundation/Foundation.h>

@interface IGLocalizationService : NSObject

+ (instancetype)sharedService;

@property (nonatomic, copy) NSString *selectedLanguage;

- (NSString *)t:(NSString *)key;
- (NSString *)t:(NSString *)key args:(NSArray *)args;

@end
