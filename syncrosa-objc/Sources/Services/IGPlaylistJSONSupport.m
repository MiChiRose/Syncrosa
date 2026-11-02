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

    NSArray *directKeys = [NSArray arrayWithObjects:@"persistentIDs", @"persistentIds", @"trackIDs", @"trackIds", @"selectedPersistentIDs", @"selectedTrackIDs", nil];
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
                if (![pid isKindOfClass:[NSString class]] || [pid length] == 0) {
                    pid = [(NSDictionary *)item objectForKey:@"persistentId"];
                }
                if (![pid isKindOfClass:[NSString class]] || [pid length] == 0) {
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

NSString *IGPlaylistJSONAgentInstructions(void)
{
    return @"This file contains the entire readable music catalog, not a random sample. Ask the user for a mood, occasion and track count, then choose from all tracks. Return ONLY one JSON object in the selectionExample format: playlistName and an ordered trackIDs array. Copy each 16-character ID exactly from tracks; do not invent IDs, repeat tracks, return the catalog, or add Markdown. Select no more tracks than the catalog contains. Any free assistant or the user's own paid agent can read this file; no Syncrosa API key is required for export or import.";
}

NSString *IGPlaylistJSONSelectionValidationError(id json, NSSet *availableIDs)
{
    // Earlier Cocoa exports allowed a plain array of IDs or track objects.
    // Normalize it before applying the same whole-selection validation.
    if ([json isKindOfClass:[NSArray class]]) {
        json = [NSDictionary dictionaryWithObject:json forKey:@"tracks"];
    }
    if (![json isKindOfClass:[NSDictionary class]]) {
        return @"The AI reply must contain a playlist selection object or an array of track IDs.";
    }
    id schema = [(NSDictionary *)json objectForKey:@"schema"];
    if (schema && ![schema isKindOfClass:[NSString class]]) {
        return @"The selection schema must be a string. The playlist was not changed.";
    }
    NSString *normalizedSchema = [(NSString *)schema lowercaseString];
    if (normalizedSchema &&
        ([normalizedSchema rangeOfString:@"library"].location != NSNotFound ||
         [normalizedSchema rangeOfString:@"manifest"].location != NSNotFound)) {
        return @"This is a library export. Choose the selection JSON returned by your AI assistant.";
    }

    NSMutableArray *rawIDs = [NSMutableArray array];
    NSArray *keys = [NSArray arrayWithObjects:@"persistentIDs", @"persistentIds", @"trackIDs", @"trackIds", @"selectedPersistentIDs", @"selectedTrackIDs", nil];
    for (NSString *key in keys) {
        id values = [(NSDictionary *)json objectForKey:key];
        if (!values) continue;
        if (![values isKindOfClass:[NSArray class]]) return @"The track ID fields must be JSON arrays.";
        [rawIDs addObjectsFromArray:values];
    }
    id tracks = [(NSDictionary *)json objectForKey:@"tracks"];
    if (tracks) {
        if (![tracks isKindOfClass:[NSArray class]]) return @"The tracks field must be a JSON array.";
        for (id track in tracks) {
            id value = track;
            if ([track isKindOfClass:[NSDictionary class]]) {
                value = [(NSDictionary *)track objectForKey:@"persistentID"] ?: [(NSDictionary *)track objectForKey:@"persistentId"] ?: [(NSDictionary *)track objectForKey:@"id"];
            }
            if (![value isKindOfClass:[NSString class]]) return @"Every selected track must contain a valid ID.";
            [rawIDs addObject:value];
        }
    }
    if ([rawIDs count] == 0) return @"The selection does not contain any track IDs.";
    for (id value in rawIDs) {
        if (![value isKindOfClass:[NSString class]]) return @"Every track ID must be a 16-character hexadecimal string.";
        NSString *normalized = [[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
        if ([normalized length] != 16 || !IGPlaylistJSONPersistentIDLooksSafe(normalized)) {
            return @"Every track ID must be a 16-character hexadecimal string. The playlist was not changed.";
        }
        if (availableIDs && ![availableIDs containsObject:normalized]) {
            return @"Some selected IDs are not in this iTunes library. Refresh the export and selection. The playlist was not changed.";
        }
    }
    return nil;
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
            [NSNumber numberWithUnsignedLongLong:track.fileSizeBytes], @"fileSizeBytes",
            [NSByteCountFormatter stringFromByteCount:(long long)track.fileSizeBytes
                                           countStyle:NSByteCountFormatterCountStyleFile], @"fileSize",
            nil];
}
