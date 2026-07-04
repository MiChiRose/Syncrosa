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

- (void)dealloc {
#if !__has_feature(objc_arc)
    [_persistentID release];
    [_name release];
    [_artist release];
    [_album release];
    [_genre release];
    [super dealloc];
#endif
}

@end
