#import <Foundation/Foundation.h>

@class IGTrack;

BOOL IGPlaylistJSONPersistentIDLooksSafe(NSString *value);
NSArray *IGPlaylistJSONPersistentIDsFromJSONObject(id json);
NSString *IGPlaylistJSONPlaylistNameFromJSONObject(id json);
NSDictionary *IGPlaylistJSONObjectForTrack(IGTrack *track);
