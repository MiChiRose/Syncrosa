#import "IGTrack.h"

@implementation IGTrack

- (instancetype)initWithPersistentID:(NSString *)pid 
                                name:(NSString *)name 
                              artist:(NSString *)artist 
                               album:(NSString *)album 
                               genre:(NSString *)genre 
                                year:(NSInteger)year {
    self = [super init];
    if (self) {
        _persistentID = [pid copy];
        _name = [name copy];
        _artist = [artist copy];
        _album = [album copy];
        _genre = [genre copy];
        _year = year;
    }
    return self;
}

@end
