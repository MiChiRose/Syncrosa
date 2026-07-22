#import "IGLibraryDoctorSupport.h"
#import "IGTrack.h"

static BOOL IGDoctorTextHasValue(NSString *value)
{
    if (![value isKindOfClass:[NSString class]]) {
        return NO;
    }
    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [trimmed length] > 0;
}

static NSString *IGDoctorCSVField(id value)
{
    NSString *text = value ? [value description] : @"";
    text = [text stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""];
    return [NSString stringWithFormat:@"\"%@\"", text];
}

static NSString *IGDoctorNormalizedPath(NSString *path)
{
    if (![path isKindOfClass:[NSString class]] || [path length] == 0) {
        return @"";
    }
    return [[[path stringByStandardizingPath] stringByResolvingSymlinksInPath] lowercaseString];
}

NSDictionary *IGLibraryDoctorTagScore(NSArray *tracks)
{
    NSInteger total = 0;
    NSInteger titleCount = 0;
    NSInteger artistCount = 0;
    NSInteger albumCount = 0;
    NSInteger genreCount = 0;
    NSInteger yearCount = 0;

    for (id value in tracks) {
        if (![value isKindOfClass:[IGTrack class]]) {
            continue;
        }
        IGTrack *track = (IGTrack *)value;
        total++;
        if (IGDoctorTextHasValue(track.name)) titleCount++;
        if (IGDoctorTextHasValue(track.artist)) artistCount++;
        if (IGDoctorTextHasValue(track.album)) albumCount++;
        if (IGDoctorTextHasValue(track.genre)) genreCount++;
        if (track.year > 0) yearCount++;
    }

    NSInteger available = titleCount + artistCount + albumCount + genreCount + yearCount;
    NSInteger possible = total * 5;
    NSInteger percent = possible > 0 ? (available * 100 + possible / 2) / possible : 0;
    return @{
        @"trackCount": @(total),
        @"completenessPercent": @(percent),
        @"missingTitle": @(total - titleCount),
        @"missingArtist": @(total - artistCount),
        @"missingAlbum": @(total - albumCount),
        @"missingGenre": @(total - genreCount),
        @"missingYear": @(total - yearCount)
    };
}

NSDictionary *IGLibraryDoctorJSONObject(NSArray *tracks)
{
    NSMutableArray *rows = [NSMutableArray array];
    for (id value in tracks) {
        if (![value isKindOfClass:[IGTrack class]]) {
            continue;
        }
        IGTrack *track = (IGTrack *)value;
        [rows addObject:@{
            @"persistentID": track.persistentID ?: @"",
            @"title": track.name ?: @"",
            @"artist": track.artist ?: @"",
            @"album": track.album ?: @"",
            @"genre": track.genre ?: @"",
            @"year": @(track.year)
        }];
    }
    return @{
        @"schemaVersion": @1,
        @"generatedAt": @([[NSDate date] timeIntervalSince1970]),
        @"summary": IGLibraryDoctorTagScore(tracks),
        @"tracks": rows
    };
}

NSString *IGLibraryDoctorCSVString(NSArray *tracks)
{
    NSMutableString *csv = [NSMutableString stringWithString:@"persistentID,title,artist,album,genre,year\r\n"];
    for (id value in tracks) {
        if (![value isKindOfClass:[IGTrack class]]) {
            continue;
        }
        IGTrack *track = (IGTrack *)value;
        NSArray *fields = @[
            track.persistentID ?: @"",
            track.name ?: @"",
            track.artist ?: @"",
            track.album ?: @"",
            track.genre ?: @"",
            @(track.year)
        ];
        NSMutableArray *escaped = [NSMutableArray arrayWithCapacity:[fields count]];
        for (id field in fields) {
            [escaped addObject:IGDoctorCSVField(field)];
        }
        [csv appendFormat:@"%@\r\n", [escaped componentsJoinedByString:@","]];
    }
    return csv;
}

NSArray *IGLibraryDoctorAudioFilePathsAtURL(NSURL *directoryURL)
{
    if (![directoryURL isFileURL]) {
        return @[];
    }
    NSSet *extensions = [NSSet setWithObjects:@"mp3", @"m4a", @"mp4", @"aac", @"wav", @"aiff", @"aif", @"alac", @"flac", nil];
    NSMutableArray *paths = [NSMutableArray array];
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:[directoryURL path]];
    NSString *relativePath = nil;
    while ((relativePath = [enumerator nextObject])) {
        if (![extensions containsObject:[[relativePath pathExtension] lowercaseString]]) {
            continue;
        }
        [paths addObject:[[directoryURL path] stringByAppendingPathComponent:relativePath]];
    }
    return paths;
}

NSDictionary *IGLibraryDoctorLinkAudit(NSArray *libraryReferences, NSArray *folderFilePaths)
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSMutableSet *libraryPaths = [NSMutableSet set];
    NSMutableArray *missingReferences = [NSMutableArray array];
    for (NSDictionary *reference in libraryReferences) {
        if (![reference isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *path = [reference objectForKey:@"path"];
        NSString *normalized = IGDoctorNormalizedPath(path);
        if ([normalized length] > 0) {
            [libraryPaths addObject:normalized];
        }
        if ([path length] == 0 || ![fileManager fileExistsAtPath:path] || ![fileManager isReadableFileAtPath:path]) {
            [missingReferences addObject:reference];
        }
    }

    NSMutableArray *unlinkedFiles = [NSMutableArray array];
    for (NSString *path in folderFilePaths) {
        if (![libraryPaths containsObject:IGDoctorNormalizedPath(path)]) {
            [unlinkedFiles addObject:path ?: @""];
        }
    }
    return @{
        @"libraryReferenceCount": @([libraryReferences count]),
        @"folderFileCount": @([folderFilePaths count]),
        @"missingReferenceCount": @([missingReferences count]),
        @"unlinkedFileCount": @([unlinkedFiles count]),
        @"missingReferences": missingReferences,
        @"unlinkedFiles": unlinkedFiles
    };
}
