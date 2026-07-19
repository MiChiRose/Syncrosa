#import "IGPlaylistJSONSupport.h"
#import "IGTrack.h"

static id IGPlaylistJSONStringValue(NSString *value)
{
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

BOOL IGPlaylistJSONPersistentIDLooksSafe(NSString *value)
{
    if (![value isKindOfClass:[NSString class]]) {
        return NO;
    }

    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed length] < 4 || [trimmed length] > 32) {
        return NO;
    }

    NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    return [[trimmed stringByTrimmingCharactersInSet:hex] length] == 0;
}

static void IGPlaylistJSONAddPersistentID(NSMutableArray *ids, NSMutableSet *seen, NSString *value)
{
    NSString *trimmed = [value isKindOfClass:[NSString class]] ? [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : nil;
    if (!IGPlaylistJSONPersistentIDLooksSafe(trimmed)) {
        return;
    }

    NSString *normalized = [trimmed uppercaseString];
    if (![seen containsObject:normalized]) {
        [seen addObject:normalized];
        [ids addObject:normalized];
    }
}

NSArray *IGPlaylistJSONPersistentIDsFromJSONObject(id json)
{
    NSMutableArray *ids = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    id root = json;
    if ([root isKindOfClass:[NSArray class]]) {
        root = [NSDictionary dictionaryWithObject:root forKey:@"tracks"];
    }
    if (![root isKindOfClass:[NSDictionary class]]) {
        return ids;
    }

    NSArray *directKeys = [NSArray arrayWithObjects:@"persistentIDs", @"persistentIds", @"trackIDs", @"trackIds", @"selectedPersistentIDs", nil];
    for (NSString *key in directKeys) {
        id list = [(NSDictionary *)root objectForKey:key];
        if ([list isKindOfClass:[NSArray class]]) {
            for (id value in (NSArray *)list) {
                IGPlaylistJSONAddPersistentID(ids, seen, [value isKindOfClass:[NSString class]] ? value : nil);
            }
        }
    }

    id tracks = [(NSDictionary *)root objectForKey:@"tracks"];
    if ([tracks isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)tracks) {
            if ([item isKindOfClass:[NSDictionary class]]) {
                NSString *pid = [(NSDictionary *)item objectForKey:@"persistentID"];
                if ([pid length] == 0) {
                    pid = [(NSDictionary *)item objectForKey:@"persistentId"];
                }
                if ([pid length] == 0) {
                    pid = [(NSDictionary *)item objectForKey:@"id"];
                }
                IGPlaylistJSONAddPersistentID(ids, seen, pid);
            } else if ([item isKindOfClass:[NSString class]]) {
                IGPlaylistJSONAddPersistentID(ids, seen, item);
            }
        }
    }
    return ids;
}

NSString *IGPlaylistJSONPlaylistNameFromJSONObject(id json)
{
    if (![json isKindOfClass:[NSDictionary class]]) {
        return @"";
    }

    NSArray *keys = [NSArray arrayWithObjects:@"playlistName", @"playlist_name", @"name", nil];
    for (NSString *key in keys) {
        NSString *value = [(NSDictionary *)json objectForKey:key];
        if ([value isKindOfClass:[NSString class]]) {
            NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([trimmed length] > 0) {
                return trimmed;
            }
        }
    }
    return @"";
}

NSDictionary *IGPlaylistJSONObjectForTrack(IGTrack *track)
{
    NSString *persistentID = IGPlaylistJSONStringValue(track.persistentID);
    NSString *title = IGPlaylistJSONStringValue(track.name);
    NSString *artist = IGPlaylistJSONStringValue(track.artist);
    NSString *album = IGPlaylistJSONStringValue(track.album);
    NSString *genre = IGPlaylistJSONStringValue(track.genre);
    return [NSDictionary dictionaryWithObjectsAndKeys:
            persistentID, @"persistentID",
            persistentID, @"id",
            title, @"title",
            title, @"name",
            artist, @"artist",
            album, @"album",
            genre, @"genre",
            [NSNumber numberWithInteger:track.year], @"year",
            nil];
}
