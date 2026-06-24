#import <Foundation/Foundation.h>

@interface IGTrack : NSObject

@property (nonatomic, copy) NSString *persistentID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSString *album;
@property (nonatomic, copy) NSString *genre;
@property (nonatomic, assign) NSInteger year;

- (instancetype)initWithPersistentID:(NSString *)pid 
                                name:(NSString *)name 
                              artist:(NSString *)artist 
                               album:(NSString *)album 
                               genre:(NSString *)genre 
                                year:(NSInteger)year;

@end
