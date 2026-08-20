#import "IGVideoFileMetadataService.h"
#import <AVFoundation/AVFoundation.h>
#import <AppKit/AppKit.h>
#import <math.h>

static NSString *IGVideoFileString(id value) {
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

static NSString *IGVideoFileMetadataString(NSArray *items, NSString *keySpace, NSString *key) {
    for (AVMetadataItem *item in items) {
        if ((keySpace == nil || [[item keySpace] isEqual:keySpace]) && [[item key] isEqual:key]) {
            NSString *value = [item stringValue];
            if ([value length] > 0) return value;
        }
    }
    return @"";
}

static NSData *IGVideoFileMetadataData(NSArray *items, NSString *keySpace, NSString *key) {
    for (AVMetadataItem *item in items) {
        if ((keySpace == nil || [[item keySpace] isEqual:keySpace]) && [[item key] isEqual:key]) {
            id value = [item value];
            if ([value isKindOfClass:[NSData class]]) return value;
        }
    }
    return nil;
}

static AVMutableMetadataItem *IGVideoFileMetadataItem(NSString *key, id value) {
    AVMutableMetadataItem *item = [AVMutableMetadataItem metadataItem];
    [item setKeySpace:AVMetadataKeySpaceiTunes];
    [item setKey:key];
    [item setValue:value];
    return item;
}

static NSData *IGVideoFileArtworkJPEGData(NSURL *artworkURL) {
    if (![artworkURL isFileURL]) return nil;
    NSImage *image = [[[NSImage alloc] initWithContentsOfURL:artworkURL] autorelease];
    NSData *tiffData = [image TIFFRepresentation];
    NSBitmapImageRep *representation = [NSBitmapImageRep imageRepWithData:tiffData];
    if (!representation) return nil;
    return [representation representationUsingType:NSJPEGFileType
                                        properties:[NSDictionary dictionaryWithObject:[NSNumber numberWithDouble:0.92]
                                                                               forKey:NSImageCompressionFactor]];
}

static BOOL IGVideoFileMetadataItemMatches(AVMetadataItem *item, NSString *keySpace, NSString *key) {
    return [[[item keySpace] description] isEqual:keySpace] && [[[item key] description] isEqual:key];
}

static NSDictionary *IGVideoFileTelevisionNumbersFromComment(NSString *comment) {
    if (![comment isKindOfClass:[NSString class]]) return nil;
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:@"(?:^|\\n)Syncrosa TV S([0-9]{1,2})E([0-9]{1,3})$"
                                                                                  options:0
                                                                                    error:nil];
    NSTextCheckingResult *match = [expression firstMatchInString:comment options:0 range:NSMakeRange(0, [comment length])];
    if (!match || [match numberOfRanges] < 3) return nil;
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInteger:[[comment substringWithRange:[match rangeAtIndex:1]] integerValue]], @"seasonNumber",
            [NSNumber numberWithInteger:[[comment substringWithRange:[match rangeAtIndex:2]] integerValue]], @"episodeNumber",
            nil];
}

static NSString *IGVideoFileCommentWithoutTelevisionMarker(NSString *comment) {
    if (![comment isKindOfClass:[NSString class]] || [comment length] == 0) return @"";
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:@"(?:^|\\n)Syncrosa TV S[0-9]{1,2}E[0-9]{1,3}$"
                                                                                  options:0
                                                                                    error:nil];
    NSString *cleaned = [expression stringByReplacingMatchesInString:comment
                                                              options:0
                                                                range:NSMakeRange(0, [comment length])
                                                         withTemplate:@""];
    return [cleaned stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\r\n"]];
}

static NSURL *IGVideoFileUniqueBackupURL(NSURL *fileURL) {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSURL *directory = [fileURL URLByDeletingLastPathComponent];
    NSString *extension = [fileURL pathExtension];
    NSString *base = [[fileURL lastPathComponent] stringByDeletingPathExtension];
    for (NSInteger suffix = 0; suffix < 10000; suffix++) {
        NSString *marker = suffix == 0 ? @"syncrosa-backup" : [NSString stringWithFormat:@"syncrosa-backup-%ld", (long)(suffix + 1)];
        NSString *name = [NSString stringWithFormat:@"%@.%@.%@", base, marker, extension];
        NSURL *candidate = [directory URLByAppendingPathComponent:name];
        if (![manager fileExistsAtPath:[candidate path]]) return candidate;
    }
    return nil;
}

@implementation IGVideoFileMetadataService

+ (instancetype)sharedService {
    static IGVideoFileMetadataService *service = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        service = [[IGVideoFileMetadataService alloc] init];
    });
    return service;
}

+ (NSArray *)supportedVideoExtensions {
    return [NSArray arrayWithObjects:@"mp4", @"m4v", nil];
}

+ (NSArray *)videoFileURLsInDirectory:(NSURL *)directoryURL {
    if (![directoryURL isFileURL]) return [NSArray array];
    NSFileManager *manager = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [manager enumeratorAtURL:directoryURL
                                      includingPropertiesForKeys:[NSArray arrayWithObject:NSURLIsDirectoryKey]
                                                         options:NSDirectoryEnumerationSkipsHiddenFiles
                                                    errorHandler:nil];
    NSMutableArray *matches = [NSMutableArray array];
    NSArray *extensions = [self supportedVideoExtensions];
    for (NSURL *url in enumerator) {
        NSNumber *directory = nil;
        [url getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil];
        if ([directory boolValue]) continue;
        if ([[[url lastPathComponent] lowercaseString] rangeOfString:@".syncrosa-backup"].location != NSNotFound) continue;
        if ([extensions containsObject:[[url pathExtension] lowercaseString]]) {
            [matches addObject:url];
        }
    }
    [matches sortUsingComparator:^NSComparisonResult(NSURL *left, NSURL *right) {
        return [[left path] localizedCaseInsensitiveCompare:[right path]];
    }];
    return matches;
}

+ (NSDictionary *)filenameHintsForName:(NSString *)name {
    NSString *base = name ?: @"";
    NSString *clean = [[base stringByReplacingOccurrencesOfString:@"_" withString:@" "] stringByReplacingOccurrencesOfString:@"." withString:@" "];
    clean = [clean stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSRegularExpression *episodeExpression = [NSRegularExpression regularExpressionWithPattern:@"(?i)\\b(?:S([0-9]{1,2})E([0-9]{1,3})|([0-9]{1,2})X([0-9]{1,3}))\\b"
                                                                                        options:0
                                                                                          error:nil];
    NSTextCheckingResult *episodeMatch = [episodeExpression firstMatchInString:clean options:0 range:NSMakeRange(0, [clean length])];
    if (episodeMatch && [episodeMatch numberOfRanges] >= 5) {
        NSRange seasonRange = [episodeMatch rangeAtIndex:1].location != NSNotFound ? [episodeMatch rangeAtIndex:1] : [episodeMatch rangeAtIndex:3];
        NSRange episodeRange = [episodeMatch rangeAtIndex:2].location != NSNotFound ? [episodeMatch rangeAtIndex:2] : [episodeMatch rangeAtIndex:4];
        NSInteger season = [[clean substringWithRange:seasonRange] integerValue];
        NSInteger episode = [[clean substringWithRange:episodeRange] integerValue];
        NSString *show = [[clean substringToIndex:[episodeMatch range].location] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" .-_"]];
        NSString *episodeTitle = [[clean substringFromIndex:NSMaxRange([episodeMatch range])] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" .-_"]];
        return [NSDictionary dictionaryWithObjectsAndKeys:
                [episodeTitle length] > 0 ? episodeTitle : clean, @"name",
                @"TV Show", @"videoKind",
                show ?: @"", @"show",
                [NSNumber numberWithInteger:season], @"seasonNumber",
                [NSNumber numberWithInteger:episode], @"episodeNumber",
                nil];
    }
    return [NSDictionary dictionaryWithObjectsAndKeys:
            clean, @"name",
            @"Movie", @"videoKind",
            @"", @"show",
            [NSNumber numberWithInteger:0], @"seasonNumber",
            [NSNumber numberWithInteger:0], @"episodeNumber",
            nil];
}

+ (NSDictionary *)filenameHintsForURL:(NSURL *)fileURL {
    NSString *base = [[fileURL lastPathComponent] stringByDeletingPathExtension] ?: @"";
    return [self filenameHintsForName:base];
}

+ (NSDictionary *)televisionHintsForMetadataComment:(NSString *)comment {
    return IGVideoFileTelevisionNumbersFromComment(comment);
}

+ (NSString *)episodeDisplayTitleForTitle:(NSString *)title
                             seasonNumber:(NSInteger)seasonNumber
                            episodeNumber:(NSInteger)episodeNumber {
    NSString *cleanTitle = [IGVideoFileString(title) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (seasonNumber <= 0 || episodeNumber <= 0 || [cleanTitle length] == 0) return cleanTitle;

    NSRegularExpression *existingPrefix = [NSRegularExpression regularExpressionWithPattern:@"(?i)^S[0-9]{1,2}E[0-9]{1,3}\\s*(?:—|–|-|:)\\s*"
                                                                                       options:0
                                                                                         error:nil];
    cleanTitle = [existingPrefix stringByReplacingMatchesInString:cleanTitle
                                                           options:0
                                                             range:NSMakeRange(0, [cleanTitle length])
                                                      withTemplate:@""];
    cleanTitle = [cleanTitle stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([cleanTitle length] == 0) return @"";
    return [NSString stringWithFormat:@"S%ldE%02ld — %@", (long)seasonNumber, (long)episodeNumber, cleanTitle];
}

- (void)readMetadataAtURL:(NSURL *)fileURL
               completion:(void(^)(NSDictionary *metadata, NSString *errorMessage))completionBlock {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSDictionary *hints = [[self class] filenameHintsForURL:fileURL];
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:fileURL options:nil];
        NSArray *items = [asset metadata];
        NSString *name = IGVideoFileMetadataString(items, AVMetadataKeySpaceiTunes, AVMetadataiTunesMetadataKeySongName);
        if ([name length] == 0) name = IGVideoFileMetadataString(items, AVMetadataKeySpaceQuickTimeMetadata, AVMetadataQuickTimeMetadataKeyTitle);
        if ([name length] == 0) name = [hints objectForKey:@"name"];
        NSString *genre = IGVideoFileMetadataString(items, AVMetadataKeySpaceiTunes, AVMetadataiTunesMetadataKeyUserGenre);
        if ([genre length] == 0) genre = IGVideoFileMetadataString(items, AVMetadataKeySpaceQuickTimeMetadata, AVMetadataQuickTimeMetadataKeyGenre);
        NSString *releaseDate = IGVideoFileMetadataString(items, AVMetadataKeySpaceiTunes, AVMetadataiTunesMetadataKeyReleaseDate);
        NSInteger year = [releaseDate length] >= 4 ? [[releaseDate substringToIndex:4] integerValue] : 0;
        NSString *description = IGVideoFileMetadataString(items, AVMetadataKeySpaceiTunes, AVMetadataiTunesMetadataKeyDescription);
        if ([description length] == 0) description = IGVideoFileMetadataString(items, AVMetadataKeySpaceQuickTimeMetadata, AVMetadataQuickTimeMetadataKeyDescription);
        NSString *director = IGVideoFileMetadataString(items, AVMetadataKeySpaceiTunes, AVMetadataiTunesMetadataKeyDirector);
        if ([director length] == 0) director = IGVideoFileMetadataString(items, AVMetadataKeySpaceQuickTimeMetadata, AVMetadataQuickTimeMetadataKeyDirector);
        NSString *show = IGVideoFileMetadataString(items, AVMetadataKeySpaceiTunes, AVMetadataiTunesMetadataKeyAlbum);
        if ([show length] == 0) show = [hints objectForKey:@"show"];
        NSString *comment = IGVideoFileMetadataString(items, AVMetadataKeySpaceiTunes, AVMetadataiTunesMetadataKeyUserComment);
        NSDictionary *televisionNumbers = [[self class] televisionHintsForMetadataComment:comment];
        NSString *videoKind = televisionNumbers ? @"TV Show" : ([hints objectForKey:@"videoKind"] ?: @"Movie");
        NSNumber *seasonNumber = televisionNumbers ? [televisionNumbers objectForKey:@"seasonNumber"] : ([hints objectForKey:@"seasonNumber"] ?: @0);
        NSNumber *episodeNumber = televisionNumbers ? [televisionNumbers objectForKey:@"episodeNumber"] : ([hints objectForKey:@"episodeNumber"] ?: @0);
        NSData *artwork = IGVideoFileMetadataData(items, AVMetadataKeySpaceiTunes, AVMetadataiTunesMetadataKeyCoverArt);
        if (!artwork) artwork = IGVideoFileMetadataData(items, AVMetadataKeySpaceQuickTimeMetadata, AVMetadataQuickTimeMetadataKeyArtwork);
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[fileURL path] error:nil];
        NSDictionary *result = [NSDictionary dictionaryWithObjectsAndKeys:
                                [fileURL path] ?: @"", @"persistentID",
                                fileURL, @"fileURL",
                                name ?: @"", @"name",
                                videoKind, @"videoKind",
                                show ?: @"", @"show",
                                seasonNumber, @"seasonNumber",
                                episodeNumber, @"episodeNumber",
                                genre ?: @"", @"genre",
                                [NSNumber numberWithInteger:year], @"year",
                                director ?: @"", @"director",
                                description ?: @"", @"description",
                                description ?: @"", @"longDescription",
                                [NSNumber numberWithBool:artwork != nil], @"hasArtwork",
                                [attributes objectForKey:NSFileSize] ?: @0, @"fileSizeBytes",
                                @"Folder", @"sourceType",
                                nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completionBlock) completionBlock(result, nil);
        });
    });
}

- (void)writeMetadata:(NSDictionary *)metadata
           artworkURL:(NSURL *)artworkURL
            toFileURL:(NSURL *)fileURL
           completion:(void(^)(BOOL success, NSURL *backupURL, NSString *errorMessage))completionBlock {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSFileManager *manager = [NSFileManager defaultManager];
        NSDictionary *attributes = [manager attributesOfItemAtPath:[fileURL path] error:nil];
        NSString *directoryPath = [[fileURL URLByDeletingLastPathComponent] path];
        if (![manager isWritableFileAtPath:directoryPath]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completionBlock) completionBlock(NO, nil, @"The video folder is read-only. Choose a writable folder or drive.");
            });
            return;
        }
        unsigned long long fileSize = [[attributes objectForKey:NSFileSize] unsignedLongLongValue];
        NSDictionary *filesystem = [manager attributesOfFileSystemForPath:directoryPath error:nil];
        unsigned long long freeBytes = [[filesystem objectForKey:NSFileSystemFreeSize] unsignedLongLongValue];
        if (!attributes || freeBytes < fileSize + 50ULL * 1024ULL * 1024ULL) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completionBlock) completionBlock(NO, nil, @"Not enough free space beside the video to create a verified replacement.");
            });
            return;
        }

        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:fileURL options:nil];
        NSUInteger originalTrackCount = [[asset tracks] count];
        double originalDuration = CMTimeGetSeconds([asset duration]);
        if (originalTrackCount == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completionBlock) completionBlock(NO, nil, @"The selected file does not contain a readable video or audio track.");
            });
            return;
        }
        AVAssetExportSession *session = [AVAssetExportSession exportSessionWithAsset:asset presetName:AVAssetExportPresetPassthrough];
        if (!session) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completionBlock) completionBlock(NO, nil, @"This video cannot be updated without re-encoding.");
            });
            return;
        }

        NSString *extension = [[fileURL pathExtension] lowercaseString];
        NSString *fileType = [extension isEqualToString:@"m4v"] ? AVFileTypeAppleM4V : AVFileTypeMPEG4;
        if (![[session supportedFileTypes] containsObject:fileType]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completionBlock) completionBlock(NO, nil, @"The video container does not support safe metadata export.");
            });
            return;
        }

        NSMutableArray *newItems = [NSMutableArray array];
        NSString *name = IGVideoFileString([metadata objectForKey:@"name"]);
        NSString *genre = IGVideoFileString([metadata objectForKey:@"genre"]);
        NSString *director = IGVideoFileString([metadata objectForKey:@"director"]);
        NSString *description = IGVideoFileString([metadata objectForKey:@"description"]);
        NSString *videoKind = IGVideoFileString([metadata objectForKey:@"videoKind"]);
        NSString *show = IGVideoFileString([metadata objectForKey:@"show"]);
        NSInteger season = MAX((NSInteger)0, [[metadata objectForKey:@"seasonNumber"] integerValue]);
        NSInteger episode = MAX((NSInteger)0, [[metadata objectForKey:@"episodeNumber"] integerValue]);
        NSInteger year = MAX((NSInteger)0, [[metadata objectForKey:@"year"] integerValue]);
        NSArray *originalMetadataItems = [asset metadata];
        NSString *originalAlbum = IGVideoFileMetadataString(originalMetadataItems, AVMetadataKeySpaceiTunes, AVMetadataiTunesMetadataKeyAlbum);
        NSString *originalComment = IGVideoFileMetadataString(originalMetadataItems, AVMetadataKeySpaceiTunes, AVMetadataiTunesMetadataKeyUserComment);
        BOOL hadTelevisionMarker = IGVideoFileTelevisionNumbersFromComment(originalComment) != nil;
        NSString *preservedComment = IGVideoFileCommentWithoutTelevisionMarker(originalComment);
        NSString *desiredAlbum = @"";
        NSString *desiredComment = preservedComment;
        if ([videoKind isEqualToString:@"TV Show"]) {
            desiredAlbum = [show length] > 0 ? show : originalAlbum;
            NSString *marker = [NSString stringWithFormat:@"Syncrosa TV S%02ldE%02ld", (long)season, (long)episode];
            desiredComment = [preservedComment length] > 0 ? [NSString stringWithFormat:@"%@\n%@", preservedComment, marker] : marker;
        } else if (!hadTelevisionMarker) {
            desiredAlbum = originalAlbum;
        }
        if ([name length] > 0) [newItems addObject:IGVideoFileMetadataItem(AVMetadataiTunesMetadataKeySongName, name)];
        if ([genre length] > 0) [newItems addObject:IGVideoFileMetadataItem(AVMetadataiTunesMetadataKeyUserGenre, genre)];
        if ([director length] > 0) [newItems addObject:IGVideoFileMetadataItem(AVMetadataiTunesMetadataKeyDirector, director)];
        if ([description length] > 0) [newItems addObject:IGVideoFileMetadataItem(AVMetadataiTunesMetadataKeyDescription, description)];
        if (year > 0) [newItems addObject:IGVideoFileMetadataItem(AVMetadataiTunesMetadataKeyReleaseDate, [NSString stringWithFormat:@"%04ld", (long)year])];
        if ([desiredAlbum length] > 0) [newItems addObject:IGVideoFileMetadataItem(AVMetadataiTunesMetadataKeyAlbum, desiredAlbum)];
        if ([desiredComment length] > 0) [newItems addObject:IGVideoFileMetadataItem(AVMetadataiTunesMetadataKeyUserComment, desiredComment)];
        NSData *artworkData = IGVideoFileArtworkJPEGData(artworkURL);
        if ([artworkData length] > 0) {
            AVMutableMetadataItem *artworkItem = IGVideoFileMetadataItem(AVMetadataiTunesMetadataKeyCoverArt, artworkData);
            [artworkItem setDataType:@"com.apple.metadata.datatype.JPEG"];
            [newItems addObject:artworkItem];
        }

        NSArray *keysToReplace = [NSArray arrayWithObjects:
                                  AVMetadataiTunesMetadataKeySongName,
                                  AVMetadataiTunesMetadataKeyUserGenre,
                                  AVMetadataiTunesMetadataKeyDirector,
                                  AVMetadataiTunesMetadataKeyDescription,
                                  AVMetadataiTunesMetadataKeyReleaseDate,
                                  AVMetadataiTunesMetadataKeyAlbum,
                                  AVMetadataiTunesMetadataKeyUserComment,
                                  nil];
        NSMutableArray *exportMetadata = [NSMutableArray array];
        for (AVMetadataItem *existingItem in originalMetadataItems) {
            BOOL replaced = NO;
            for (NSString *key in keysToReplace) {
                if (IGVideoFileMetadataItemMatches(existingItem, AVMetadataKeySpaceiTunes, key)) {
                    replaced = YES;
                    break;
                }
            }
            if (!replaced && [artworkData length] > 0 &&
                IGVideoFileMetadataItemMatches(existingItem, AVMetadataKeySpaceiTunes, AVMetadataiTunesMetadataKeyCoverArt)) {
                replaced = YES;
            }
            if (!replaced) [exportMetadata addObject:existingItem];
        }
        [exportMetadata addObjectsFromArray:newItems];

        NSString *temporaryName = [NSString stringWithFormat:@".syncrosa-video-%@.%@", [[NSProcessInfo processInfo] globallyUniqueString], extension];
        NSURL *temporaryURL = [[fileURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:temporaryName];
        [manager removeItemAtURL:temporaryURL error:nil];
        [session setOutputURL:temporaryURL];
        [session setOutputFileType:fileType];
        [session setShouldOptimizeForNetworkUse:NO];
        [session setMetadata:exportMetadata];
        [session exportAsynchronouslyWithCompletionHandler:^{
            if ([session status] != AVAssetExportSessionStatusCompleted) {
                NSString *message = [[session error] localizedDescription] ?: @"The video metadata export failed.";
                [manager removeItemAtURL:temporaryURL error:nil];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completionBlock) completionBlock(NO, nil, message);
                });
                return;
            }

            NSDictionary *temporaryAttributes = [manager attributesOfItemAtPath:[temporaryURL path] error:nil];
            AVURLAsset *verifiedAsset = [AVURLAsset URLAssetWithURL:temporaryURL options:nil];
            NSUInteger verifiedTrackCount = [[verifiedAsset tracks] count];
            double verifiedDuration = CMTimeGetSeconds([verifiedAsset duration]);
            BOOL durationMatches = (!isfinite(originalDuration) || !isfinite(verifiedDuration)) ? YES :
                                   fabs(originalDuration - verifiedDuration) <= MAX(0.5, originalDuration * 0.001);
            NSArray *verifiedItems = [verifiedAsset metadata];
            NSString *verifiedName = IGVideoFileMetadataString(verifiedItems, AVMetadataKeySpaceiTunes, AVMetadataiTunesMetadataKeySongName);
            NSString *verifiedGenre = IGVideoFileMetadataString(verifiedItems, AVMetadataKeySpaceiTunes, AVMetadataiTunesMetadataKeyUserGenre);
            NSString *verifiedDirector = IGVideoFileMetadataString(verifiedItems, AVMetadataKeySpaceiTunes, AVMetadataiTunesMetadataKeyDirector);
            NSString *verifiedDescription = IGVideoFileMetadataString(verifiedItems, AVMetadataKeySpaceiTunes, AVMetadataiTunesMetadataKeyDescription);
            NSString *verifiedReleaseDate = IGVideoFileMetadataString(verifiedItems, AVMetadataKeySpaceiTunes, AVMetadataiTunesMetadataKeyReleaseDate);
            NSString *expectedReleaseDate = year > 0 ? [NSString stringWithFormat:@"%04ld", (long)year] : @"";
            NSString *verifiedShow = IGVideoFileMetadataString(verifiedItems, AVMetadataKeySpaceiTunes, AVMetadataiTunesMetadataKeyAlbum);
            NSString *verifiedComment = IGVideoFileMetadataString(verifiedItems, AVMetadataKeySpaceiTunes, AVMetadataiTunesMetadataKeyUserComment);
            NSString *expectedShow = desiredAlbum;
            NSString *expectedComment = desiredComment;
            BOOL metadataMatches = [verifiedName isEqualToString:name] &&
                                   [verifiedGenre isEqualToString:genre] &&
                                   [verifiedDirector isEqualToString:director] &&
                                   [verifiedDescription isEqualToString:description] &&
                                   (([expectedReleaseDate length] == 0 && [verifiedReleaseDate length] == 0) ||
                                    ([expectedReleaseDate length] > 0 && [verifiedReleaseDate hasPrefix:expectedReleaseDate])) &&
                                   [verifiedShow isEqualToString:expectedShow] &&
                                   [verifiedComment isEqualToString:expectedComment];
            BOOL artworkMatches = [artworkData length] == 0 ||
                                  IGVideoFileMetadataData(verifiedItems, AVMetadataKeySpaceiTunes, AVMetadataiTunesMetadataKeyCoverArt) != nil;
            if ([[temporaryAttributes objectForKey:NSFileSize] unsignedLongLongValue] == 0 ||
                verifiedTrackCount != originalTrackCount || !durationMatches || !metadataMatches || !artworkMatches) {
                [manager removeItemAtURL:temporaryURL error:nil];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completionBlock) completionBlock(NO, nil, @"The exported video did not preserve its tracks and requested metadata; the original was not changed.");
                });
                return;
            }

            NSURL *backupURL = IGVideoFileUniqueBackupURL(fileURL);
            NSError *fileError = nil;
            if (!backupURL || ![manager moveItemAtURL:fileURL toURL:backupURL error:&fileError]) {
                [manager removeItemAtURL:temporaryURL error:nil];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completionBlock) completionBlock(NO, nil, [fileError localizedDescription] ?: @"Could not preserve the original video.");
                });
                return;
            }
            if (![manager moveItemAtURL:temporaryURL toURL:fileURL error:&fileError]) {
                NSError *replacementError = fileError;
                NSError *restoreError = nil;
                BOOL restored = [manager moveItemAtURL:backupURL toURL:fileURL error:&restoreError] &&
                                [manager fileExistsAtPath:[fileURL path]];
                [manager removeItemAtURL:temporaryURL error:nil];
                NSString *message = nil;
                if (restored) {
                    message = [NSString stringWithFormat:@"Could not install the replacement (%@). The original was restored.",
                               [replacementError localizedDescription] ?: @"file-system error"];
                } else {
                    message = [NSString stringWithFormat:@"Could not install the replacement (%@). The original remains at %@%@",
                               [replacementError localizedDescription] ?: @"file-system error",
                               [backupURL path],
                               restoreError ? [NSString stringWithFormat:@". Automatic restore also failed: %@", [restoreError localizedDescription]] : @"."];
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completionBlock) completionBlock(NO, restored ? nil : backupURL, message);
                });
                return;
            }
            NSMutableDictionary *restorableAttributes = [NSMutableDictionary dictionary];
            NSArray *restorableKeys = [NSArray arrayWithObjects:NSFilePosixPermissions, NSFileModificationDate, nil];
            for (NSString *key in restorableKeys) {
                id value = [attributes objectForKey:key];
                if (value) [restorableAttributes setObject:value forKey:key];
            }
            if ([restorableAttributes count] > 0) {
                [manager setAttributes:restorableAttributes ofItemAtPath:[fileURL path] error:nil];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completionBlock) completionBlock(YES, backupURL, nil);
            });
        }];
    });
}

@end
