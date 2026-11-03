#import "IGMediaFixerManager.h"
#import "IGiTunesService.h"
#import "IGLyricsService.h"
#import "IGLogger.h"
#import "IGAIService.h"

static NSString *IGMediaJSONString(id value) {
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

static NSNumber *IGMediaJSONNumber(id value) {
    return [value respondsToSelector:@selector(integerValue)] ? value : @(0);
}

static NSInteger IGMediaYearFromReleaseDate(id value) {
    NSString *releaseDate = IGMediaJSONString(value);
    return [releaseDate length] >= 4 ? [[releaseDate substringToIndex:4] integerValue] : 0;
}

static NSString *IGMediaMusicComparisonText(id value) {
    NSString *text = [IGMediaJSONString(value) stringByFoldingWithOptions:(NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch)
                                                               locale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    text = [text lowercaseString];
    NSArray *words = [text componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]];
    NSMutableArray *nonempty = [NSMutableArray array];
    for (NSString *word in words) if ([word length] > 0) [nonempty addObject:word];
    return [nonempty componentsJoinedByString:@" "];
}

static BOOL IGMediaFieldIsMissing(id value, NSString *field) {
    NSString *text = [IGMediaJSONString(value) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [text length] == 0 || [text caseInsensitiveCompare:@"missing value"] == NSOrderedSame ||
           [text caseInsensitiveCompare:[@"Unknown " stringByAppendingString:field]] == NSOrderedSame;
}

NSDictionary *IGMediaBestAppleMusicMatch(NSArray *results, NSString *artist, NSString *title, NSString *album) {
    if (IGMediaFieldIsMissing(artist, @"Artist") || IGMediaFieldIsMissing(title, @"Title")) return nil;
    NSString *requestedArtist = IGMediaMusicComparisonText(artist);
    NSString *requestedTitle = IGMediaMusicComparisonText(title);
    NSString *requestedAlbum = IGMediaFieldIsMissing(album, @"Album") ? @"" : IGMediaMusicComparisonText(album);
    NSDictionary *best = nil;
    NSInteger bestScore = -1;
    BOOL ambiguous = NO;
    for (id value in results) {
        if (![value isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *candidate = value;
        /* Compare the complete title. Dropping brackets loses Live/Remix/Remaster identity. */
        if (![IGMediaMusicComparisonText(candidate[@"artistName"]) isEqualToString:requestedArtist] ||
            ![IGMediaMusicComparisonText(candidate[@"trackName"]) isEqualToString:requestedTitle]) continue;
        NSString *kind = IGMediaJSONString(candidate[@"kind"]);
        if ([kind length] > 0 && ![kind isEqualToString:@"song"]) continue;
        BOOL albumMatches = [requestedAlbum length] > 0 && [IGMediaMusicComparisonText(candidate[@"collectionName"]) isEqualToString:requestedAlbum];
        /* A known edition must agree; selecting another edition can change track numbering. */
        if ([requestedAlbum length] > 0 && !albumMatches) continue;
        NSInteger score = 100 + (albumMatches ? 40 : 0);
        NSDictionary *properties = @{@"alb": IGMediaJSONString(candidate[@"collectionName"]),
                                     @"gen": IGMediaJSONString(candidate[@"primaryGenreName"]),
                                     @"yr": @(IGMediaYearFromReleaseDate(candidate[@"releaseDate"])),
                                     @"title": IGMediaJSONString(candidate[@"trackName"]),
                                     @"art": IGMediaJSONString(candidate[@"artistName"]),
                                     @"trackNumber": IGMediaJSONNumber(candidate[@"trackNumber"])};
        if (score > bestScore) {
            best = properties;
            bestScore = score;
            ambiguous = NO;
        } else if (score == bestScore && ![best isEqualToDictionary:properties]) {
            ambiguous = YES;
        }
    }
    return ambiguous ? nil : best;
}

NSDictionary *IGMediaMissingMetadataProperties(NSDictionary *track, NSDictionary *metadata, NSString *lyrics, NSDictionary *options) {
    NSMutableDictionary *changes = [NSMutableDictionary dictionary];
    NSArray *fields = @[@"album", @"title", @"artist", @"genre"];
    NSArray *catalogKeys = @[@"alb", @"title", @"art", @"gen"];
    NSArray *labels = @[@"Album", @"Title", @"Artist", @"Genre"];
    for (NSUInteger index = 0; index < [fields count]; index++) {
        NSString *field = fields[index];
        NSString *replacement = IGMediaJSONString(metadata[catalogKeys[index]]);
        if ([options[field] boolValue] && IGMediaFieldIsMissing(track[field], labels[index]) &&
            [[replacement stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0) {
            changes[field] = replacement;
        }
    }
    NSInteger number = [metadata[@"trackNumber"] integerValue];
    if ([options[@"trackNumber"] boolValue] && [track[@"trackNumber"] integerValue] == 0 && number > 0) changes[@"trackNumber"] = @(number);
    if ([options[@"lyrics"] boolValue] && ![track[@"hasLyrics"] boolValue] &&
        [[IGMediaJSONString(lyrics) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0) changes[@"lyrics"] = lyrics;
    return changes;
}

static NSInteger IGMediaSeasonNumberFromName(NSString *name) {
    if (![name isKindOfClass:[NSString class]]) return 0;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"season\\s+([0-9]+)"
                                                                            options:NSRegularExpressionCaseInsensitive
                                                                              error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:name options:0 range:NSMakeRange(0, [name length])];
    return match && [match numberOfRanges] > 1 ? [[name substringWithRange:[match rangeAtIndex:1]] integerValue] : 0;
}

static NSString *IGMediaAppleScriptLiteral(id value) {
    if (![value isKindOfClass:[NSString class]]) {
        return @"";
    }

    NSMutableString *escaped = [value mutableCopy];
    [escaped replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\r\n" withString:@"\n" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\r" withString:@"\n" options:0 range:NSMakeRange(0, escaped.length)];
    NSString *result = [escaped copy];
#if !__has_feature(objc_arc)
    [escaped release];
    return [result autorelease];
#else
    return result;
#endif
}

static void IGMediaAddCACertIfAvailable(NSMutableArray *args) {
    NSString *caPath = [[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"];
    if (caPath.length > 0) {
        [args addObjectsFromArray:@[@"--cacert", caPath]];
    }
}

static NSString *IGMediaTempPath(NSString *extension) {
    NSString *baseName = [NSString stringWithFormat:@"syncrosa-curl-%@", [[NSProcessInfo processInfo] globallyUniqueString]];
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[baseName stringByAppendingPathExtension:extension]];
}

static NSData *IGMediaRunCurlWithLimit(NSArray *args, int *statusOut, unsigned long long maximumBytes) {
    NSString *stdoutPath = IGMediaTempPath(@"stdout");
    NSString *stderrPath = IGMediaTempPath(@"stderr");
    NSDictionary *attrs = @{NSFilePosixPermissions: [NSNumber numberWithUnsignedLong:0600]};
    [[NSFileManager defaultManager] createFileAtPath:stdoutPath contents:nil attributes:attrs];
    [[NSFileManager defaultManager] createFileAtPath:stderrPath contents:nil attributes:attrs];

    NSFileHandle *stdoutHandle = [NSFileHandle fileHandleForWritingAtPath:stdoutPath];
    NSFileHandle *stderrHandle = [NSFileHandle fileHandleForWritingAtPath:stderrPath];
    int status = -1;
    NSData *data = nil;
    BOOL exceededLimit = NO;

    @try {
        NSTask *task = [[[NSTask alloc] init] autorelease];
        NSString *curlPath = IGAICurlExecutablePath();
        [task setLaunchPath:curlPath];
        NSString *bundledLibPath = [[[curlPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"lib"] stringByStandardizingPath];
        BOOL bundledRuntime = [curlPath rangeOfString:@"/Contents/Resources/LegacyCurl/"].location != NSNotFound;
        if (bundledRuntime && [[NSFileManager defaultManager] fileExistsAtPath:bundledLibPath]) {
            NSMutableDictionary *environment = [NSMutableDictionary dictionaryWithDictionary:[[NSProcessInfo processInfo] environment]];
            [environment setObject:bundledLibPath forKey:@"DYLD_LIBRARY_PATH"];
            [task setEnvironment:environment];
        }
        [task setArguments:args];
        [task setStandardOutput:stdoutHandle];
        [task setStandardError:stderrHandle];
        [task launch];
        while ([task isRunning] && maximumBytes > 0) {
            NSDictionary *outputAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:stdoutPath error:nil];
            if ([[outputAttributes objectForKey:NSFileSize] unsignedLongLongValue] > maximumBytes) {
                exceededLimit = YES;
                [task terminate];
                break;
            }
            [NSThread sleepForTimeInterval:0.05];
        }
        [task waitUntilExit];
        status = exceededLimit ? -2 : [task terminationStatus];
        [stdoutHandle closeFile];
        [stderrHandle closeFile];
        if (!exceededLimit) data = [NSData dataWithContentsOfFile:stdoutPath];
        if (status != 0) {
            NSData *stderrData = [NSData dataWithContentsOfFile:stderrPath];
            NSString *stderrText = @"";
            if (stderrData.length > 0) {
                NSString *decoded = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding];
                stderrText = decoded ?: @"";
#if !__has_feature(objc_arc)
                [decoded autorelease];
#endif
            }
            if (stderrText.length > 0) {
                NSLog(@"Curl Apple metadata failed with status %d: %@", status, stderrText);
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"Curl Apple metadata fetch failed: %@", exception.reason);
        [stdoutHandle closeFile];
        [stderrHandle closeFile];
    }

    [[NSFileManager defaultManager] removeItemAtPath:stdoutPath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:stderrPath error:nil];
    if (statusOut) *statusOut = status;
    return data;
}

static NSData *IGMediaRunCurl(NSArray *args, int *statusOut) {
    return IGMediaRunCurlWithLimit(args, statusOut, 0);
}

static NSString *IGMediaEncodeURLComponent(NSString *value) {
    NSMutableCharacterSet *allowed = [[[NSCharacterSet alphanumericCharacterSet] mutableCopy] autorelease];
    [allowed addCharactersInString:@"-._~"];
    return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed];
}

static NSArray *IGMediaIMDbVideoMatches(NSData *data, BOOL television) {
    id jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![jsonObject isKindOfClass:[NSDictionary class]]) return [NSArray array];
    id itemsObject = [(NSDictionary *)jsonObject objectForKey:@"d"];
    if (![itemsObject isKindOfClass:[NSArray class]]) return [NSArray array];
    NSArray *items = itemsObject;
    NSMutableArray *matches = [NSMutableArray array];
    for (NSDictionary *item in items) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSString *identifier = IGMediaJSONString([item objectForKey:@"id"]);
        NSString *name = IGMediaJSONString([item objectForKey:@"l"]);
        NSString *queryType = [IGMediaJSONString([item objectForKey:@"q"]) lowercaseString];
        NSString *queryID = [IGMediaJSONString([item objectForKey:@"qid"]) lowercaseString];
        BOOL isTelevision = [queryType rangeOfString:@"tv"].location != NSNotFound ||
                            [queryID rangeOfString:@"tv"].location != NSNotFound;
        BOOL isMovie = [queryType isEqualToString:@"feature"] || [queryID isEqualToString:@"movie"] ||
                       [queryType isEqualToString:@"tv movie"] || [queryType isEqualToString:@"tvmovie"];
        if (![identifier hasPrefix:@"tt"] || [name length] == 0) continue;
        if (television ? !isTelevision : !isMovie) continue;

        NSInteger year = [[item objectForKey:@"y"] integerValue];
        NSString *cast = IGMediaJSONString([item objectForKey:@"s"]);
        NSDictionary *image = [[item objectForKey:@"i"] isKindOfClass:[NSDictionary class]] ? [item objectForKey:@"i"] : nil;
        NSString *artworkURL = IGMediaJSONString([image objectForKey:@"imageUrl"]);
        NSNumber *artworkWidth = [image objectForKey:@"width"] ?: @0;
        NSNumber *artworkHeight = [image objectForKey:@"height"] ?: @0;
        NSString *display = [NSString stringWithFormat:@"%@%@%@",
                             name,
                             year > 0 ? [NSString stringWithFormat:@" (%ld)", (long)year] : @"",
                             cast.length > 0 ? [NSString stringWithFormat:@" — %@", cast] : @""];
        NSString *description = cast.length > 0 ? [NSString stringWithFormat:@"Cast: %@", cast] : @"";
        [matches addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                            name, @"name",
                            television ? @"TV Show" : @"Movie", @"videoKind",
                            television ? name : @"", @"show",
                            @0, @"seasonNumber",
                            @0, @"episodeNumber",
                            @"", @"genre",
                            @"", @"originalGenre",
                            @"", @"localizedGenre",
                            [NSNumber numberWithInteger:year], @"year",
                            description, @"description",
                            description, @"originalDescription",
                            @"", @"localizedDescription",
                            @"", @"director",
                            @"", @"originalDirector",
                            @"", @"localizedDirector",
                            artworkURL, @"artworkURL",
                            artworkWidth, @"artworkWidth",
                            artworkHeight, @"artworkHeight",
                            display, @"displayTitle",
                            identifier, @"catalogID",
                            name, @"originalName",
                            @"", @"localizedName",
                            @"IMDb", @"catalogSource",
                            nil]];
    }
    return matches;
}

static NSArray *IGMediaMatchesByAddingRussianWikidataLabels(NSArray *matches, NSData *data) {
    id jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![jsonObject isKindOfClass:[NSDictionary class]]) return matches;
    id resultsObject = [(NSDictionary *)jsonObject objectForKey:@"results"];
    if (![resultsObject isKindOfClass:[NSDictionary class]]) return matches;
    id bindingsObject = [(NSDictionary *)resultsObject objectForKey:@"bindings"];
    if (![bindingsObject isKindOfClass:[NSArray class]]) return matches;
    NSArray *bindings = bindingsObject;
    NSMutableDictionary *localizedByID = [NSMutableDictionary dictionary];
    for (NSDictionary *binding in bindings) {
        if (![binding isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *imdb = [[binding objectForKey:@"imdb"] isKindOfClass:[NSDictionary class]] ? [binding objectForKey:@"imdb"] : nil;
        NSDictionary *ruLabel = [[binding objectForKey:@"ruLabel"] isKindOfClass:[NSDictionary class]] ? [binding objectForKey:@"ruLabel"] : nil;
        NSDictionary *ruDescription = [[binding objectForKey:@"ruDescription"] isKindOfClass:[NSDictionary class]] ? [binding objectForKey:@"ruDescription"] : nil;
        NSDictionary *enDescription = [[binding objectForKey:@"enDescription"] isKindOfClass:[NSDictionary class]] ? [binding objectForKey:@"enDescription"] : nil;
        NSDictionary *genresRu = [[binding objectForKey:@"genresRu"] isKindOfClass:[NSDictionary class]] ? [binding objectForKey:@"genresRu"] : nil;
        NSDictionary *genresEn = [[binding objectForKey:@"genresEn"] isKindOfClass:[NSDictionary class]] ? [binding objectForKey:@"genresEn"] : nil;
        NSDictionary *directorsRu = [[binding objectForKey:@"directorsRu"] isKindOfClass:[NSDictionary class]] ? [binding objectForKey:@"directorsRu"] : nil;
        NSDictionary *directorsEn = [[binding objectForKey:@"directorsEn"] isKindOfClass:[NSDictionary class]] ? [binding objectForKey:@"directorsEn"] : nil;
        NSString *identifier = IGMediaJSONString([imdb objectForKey:@"value"]);
        NSString *label = IGMediaJSONString([ruLabel objectForKey:@"value"]);
        NSString *description = IGMediaJSONString([ruDescription objectForKey:@"value"]);
        NSString *englishDescription = IGMediaJSONString([enDescription objectForKey:@"value"]);
        NSString *russianGenres = IGMediaJSONString([genresRu objectForKey:@"value"]);
        NSString *englishGenres = IGMediaJSONString([genresEn objectForKey:@"value"]);
        NSString *russianDirectors = IGMediaJSONString([directorsRu objectForKey:@"value"]);
        NSString *englishDirectors = IGMediaJSONString([directorsEn objectForKey:@"value"]);
        if ([identifier length] > 0 && [label length] > 0) {
            [localizedByID setObject:@{ @"label": label,
                                        @"description": description,
                                        @"englishDescription": englishDescription,
                                        @"russianGenres": russianGenres,
                                        @"englishGenres": englishGenres,
                                        @"russianDirectors": russianDirectors,
                                        @"englishDirectors": englishDirectors } forKey:identifier];
        }
    }
    if ([localizedByID count] == 0) return matches;

    NSMutableArray *localizedMatches = [NSMutableArray arrayWithCapacity:[matches count]];
    for (NSDictionary *match in matches) {
        NSString *identifier = [match objectForKey:@"catalogID"];
        NSDictionary *localized = [localizedByID objectForKey:identifier];
        if (!localized) {
            [localizedMatches addObject:match];
            continue;
        }
        NSString *englishName = IGMediaJSONString([match objectForKey:@"name"]);
        NSString *russianName = IGMediaJSONString([localized objectForKey:@"label"]);
        NSInteger year = [[match objectForKey:@"year"] integerValue];
        NSMutableDictionary *updated = [[match mutableCopy] autorelease];
        [updated setObject:russianName forKey:@"name"];
        [updated setObject:russianName forKey:@"localizedName"];
        NSString *russianDescription = IGMediaJSONString([localized objectForKey:@"description"]);
        NSString *englishDescription = IGMediaJSONString([localized objectForKey:@"englishDescription"]);
        NSString *russianGenre = IGMediaJSONString([localized objectForKey:@"russianGenres"]);
        NSString *englishGenre = IGMediaJSONString([localized objectForKey:@"englishGenres"]);
        NSString *russianDirector = IGMediaJSONString([localized objectForKey:@"russianDirectors"]);
        NSString *englishDirector = IGMediaJSONString([localized objectForKey:@"englishDirectors"]);
        if ([russianDescription length] > 0) {
            [updated setObject:russianDescription forKey:@"description"];
            [updated setObject:russianDescription forKey:@"localizedDescription"];
        }
        if ([englishDescription length] > 0) [updated setObject:englishDescription forKey:@"originalDescription"];
        if ([russianGenre length] > 0) {
            [updated setObject:russianGenre forKey:@"genre"];
            [updated setObject:russianGenre forKey:@"localizedGenre"];
        }
        if ([englishGenre length] > 0) [updated setObject:englishGenre forKey:@"originalGenre"];
        if ([russianDirector length] > 0) {
            [updated setObject:russianDirector forKey:@"director"];
            [updated setObject:russianDirector forKey:@"localizedDirector"];
        }
        if ([englishDirector length] > 0) [updated setObject:englishDirector forKey:@"originalDirector"];
        NSString *display = [NSString stringWithFormat:@"%@%@%@",
                             russianName,
                             year > 0 ? [NSString stringWithFormat:@" (%ld)", (long)year] : @"",
                             ![russianName isEqualToString:englishName] ? [NSString stringWithFormat:@" — %@", englishName] : @""];
        [updated setObject:display forKey:@"displayTitle"];
        [updated setObject:englishName forKey:@"originalName"];
        [localizedMatches addObject:updated];
    }
    return localizedMatches;
}

NSArray *IGMediaAppleVideoMatchesFromData(NSData *data, BOOL television, NSInteger requestedSeason, NSInteger requestedEpisode) {
    id jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![jsonObject isKindOfClass:[NSDictionary class]]) return [NSArray array];
    id resultsObject = [(NSDictionary *)jsonObject objectForKey:@"results"];
    if (![resultsObject isKindOfClass:[NSArray class]]) return [NSArray array];
    NSArray *results = resultsObject;
    NSMutableArray *matches = [NSMutableArray array];
    NSMutableArray *numberedMatches = [NSMutableArray array];
    BOOL specificEpisode = television && requestedSeason > 0 && requestedEpisode > 0;
    for (NSDictionary *item in results) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSString *trackName = IGMediaJSONString([item objectForKey:@"trackName"]);
        NSString *collectionName = IGMediaJSONString([item objectForKey:@"collectionName"]);
        NSString *artistName = IGMediaJSONString([item objectForKey:@"artistName"]);
        NSString *showName = television ? (artistName.length > 0 ? artistName : collectionName) : @"";
        NSString *name = specificEpisode ? trackName : (television ? (collectionName.length > 0 ? collectionName : trackName) : trackName);
        if ([name length] == 0) continue;
        NSString *description = IGMediaJSONString([item objectForKey:@"longDescription"]);
        if ([description length] == 0) description = IGMediaJSONString([item objectForKey:@"shortDescription"]);
        NSInteger year = IGMediaYearFromReleaseDate([item objectForKey:@"releaseDate"]);
        NSString *genre = IGMediaJSONString([item objectForKey:@"primaryGenreName"]);
        NSString *artworkURL = IGMediaJSONString([item objectForKey:@"artworkUrl100"]);
        if ([artworkURL length] > 0) artworkURL = [artworkURL stringByReplacingOccurrencesOfString:@"100x100" withString:@"600x600"];
        NSInteger seasonNumber = television ? IGMediaSeasonNumberFromName(collectionName) : 0;
        NSInteger episodeNumber = specificEpisode ? [[item objectForKey:@"trackNumber"] integerValue] : 0;
        NSString *display = specificEpisode ?
            [NSString stringWithFormat:@"%@ — S%02ldE%02ld %@%@", showName, (long)seasonNumber, (long)episodeNumber, name,
             year > 0 ? [NSString stringWithFormat:@" (%ld)", (long)year] : @""] :
            [NSString stringWithFormat:@"%@%@%@", name,
                             year > 0 ? [NSString stringWithFormat:@" (%ld)", (long)year] : @"",
                             genre.length > 0 ? [NSString stringWithFormat:@" — %@", genre] : @""];
        NSDictionary *match = @{ @"name": name, @"videoKind": television ? @"TV Show" : @"Movie",
                              @"show": showName, @"seasonNumber": @(seasonNumber),
                              @"episodeNumber": @(episodeNumber), @"genre": genre, @"originalGenre": genre, @"localizedGenre": @"",
                              @"year": @(year), @"description": description,
                              @"originalDescription": description, @"localizedDescription": @"",
                              @"director": @"", @"originalDirector": @"", @"localizedDirector": @"",
                              @"artworkURL": artworkURL, @"artworkWidth": @0, @"artworkHeight": @0,
                              @"displayTitle": display, @"originalName": name, @"localizedName": @"",
                              @"catalogSource": @"Apple" };
        [matches addObject:match];
        if (television && requestedSeason > 0 && requestedEpisode > 0 &&
            seasonNumber == requestedSeason && episodeNumber == requestedEpisode) {
            [numberedMatches addObject:match];
        }
    }
    return [numberedMatches count] > 0 ? numberedMatches : matches;
}

static NSString *IGMediaPlainTextFromHTML(id value) {
    NSString *text = IGMediaJSONString(value);
    if ([text length] == 0) return @"";
    NSString *withoutTags = [text stringByReplacingOccurrencesOfString:@"<[^>]+>"
                                                              withString:@""
                                                                 options:NSRegularExpressionSearch
                                                                   range:NSMakeRange(0, [text length])];
    withoutTags = [withoutTags stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
    withoutTags = [withoutTags stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
    withoutTags = [withoutTags stringByReplacingOccurrencesOfString:@"&#39;" withString:@"'"];
    withoutTags = [withoutTags stringByReplacingOccurrencesOfString:@"&nbsp;" withString:@" "];
    return [withoutTags stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSArray *IGMediaTVMazeEpisodeMatches(NSData *data, NSInteger requestedSeason, NSInteger requestedEpisode) {
    id jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![jsonObject isKindOfClass:[NSDictionary class]]) return [NSArray array];
    NSDictionary *show = jsonObject;
    NSDictionary *embedded = [[show objectForKey:@"_embedded"] isKindOfClass:[NSDictionary class]] ? [show objectForKey:@"_embedded"] : nil;
    NSArray *episodes = [[embedded objectForKey:@"episodes"] isKindOfClass:[NSArray class]] ? [embedded objectForKey:@"episodes"] : nil;
    NSDictionary *episode = nil;
    for (NSDictionary *candidate in episodes) {
        if (![candidate isKindOfClass:[NSDictionary class]]) continue;
        if ([[candidate objectForKey:@"season"] integerValue] == requestedSeason &&
            [[candidate objectForKey:@"number"] integerValue] == requestedEpisode) {
            episode = candidate;
            break;
        }
    }
    if (!episode) return [NSArray array];

    NSString *showName = IGMediaJSONString([show objectForKey:@"name"]);
    NSString *episodeName = IGMediaJSONString([episode objectForKey:@"name"]);
    NSArray *genres = [[show objectForKey:@"genres"] isKindOfClass:[NSArray class]] ? [show objectForKey:@"genres"] : [NSArray array];
    NSString *genre = [genres componentsJoinedByString:@", "];
    NSString *description = IGMediaPlainTextFromHTML([episode objectForKey:@"summary"]);
    if ([description length] == 0) description = IGMediaPlainTextFromHTML([show objectForKey:@"summary"]);
    NSString *airdate = IGMediaJSONString([episode objectForKey:@"airdate"]);
    NSInteger year = [airdate length] >= 4 ? [[airdate substringToIndex:4] integerValue] : 0;
    if (year == 0) {
        NSString *premiered = IGMediaJSONString([show objectForKey:@"premiered"]);
        year = [premiered length] >= 4 ? [[premiered substringToIndex:4] integerValue] : 0;
    }
    NSDictionary *episodeImage = [[episode objectForKey:@"image"] isKindOfClass:[NSDictionary class]] ? [episode objectForKey:@"image"] : nil;
    NSDictionary *showImage = [[show objectForKey:@"image"] isKindOfClass:[NSDictionary class]] ? [show objectForKey:@"image"] : nil;
    NSString *artworkURL = IGMediaJSONString([episodeImage objectForKey:@"original"]);
    if ([artworkURL length] == 0) artworkURL = IGMediaJSONString([showImage objectForKey:@"original"]);
    NSString *identifier = [NSString stringWithFormat:@"tvmaze:%@", [episode objectForKey:@"id"] ?: @""];
    NSString *display = [NSString stringWithFormat:@"%@ — S%02ldE%02ld %@%@",
                         showName, (long)requestedSeason, (long)requestedEpisode, episodeName,
                         year > 0 ? [NSString stringWithFormat:@" (%ld)", (long)year] : @""];
    NSDictionary *match = @{ @"name": episodeName,
                             @"videoKind": @"TV Show",
                             @"show": showName,
                             @"seasonNumber": @(requestedSeason),
                             @"episodeNumber": @(requestedEpisode),
                             @"genre": genre,
                             @"originalGenre": genre,
                             @"localizedGenre": @"",
                             @"year": @(year),
                             @"description": description,
                             @"originalDescription": description,
                             @"localizedDescription": @"",
                             @"director": @"",
                             @"originalDirector": @"",
                             @"localizedDirector": @"",
                             @"artworkURL": artworkURL,
                             @"artworkWidth": @0,
                             @"artworkHeight": @0,
                             @"displayTitle": display,
                             @"catalogID": identifier,
                             @"originalName": episodeName,
                             @"localizedName": @"",
                             @"catalogSource": @"TVmaze" };
    return [NSArray arrayWithObject:match];
}

@implementation IGMediaFixerManager

+ (instancetype)sharedManager {
    static IGMediaFixerManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (NSString *)normalizeText:(NSString *)text {
    if (!text || text.length == 0) return @"";

    NSMutableString *mutableString = [text mutableCopy];
    CFStringTransform((__bridge CFMutableStringRef)mutableString, NULL, kCFStringTransformToLatin, NO);
    CFStringTransform((__bridge CFMutableStringRef)mutableString, NULL, kCFStringTransformStripDiacritics, NO);

    NSString *clean = [[mutableString lowercaseString] stringByReplacingOccurrencesOfString:@"[^a-z0-9\\s]" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, mutableString.length)];
    NSArray *words = [clean componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *normalized = [[words filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]] componentsJoinedByString:@" "];
#if !__has_feature(objc_arc)
    [mutableString release];
#endif
    return normalized;
}

- (NSDictionary *)appleMetadataForArtist:(NSString *)artist title:(NSString *)title album:(NSString *)album errorMessage:(NSString **)errorMessage {
    if (errorMessage) *errorMessage = nil;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"only_local_mode"]) return nil;
    if (IGMediaFieldIsMissing(artist, @"Artist") || IGMediaFieldIsMissing(title, @"Title")) return nil;
    NSString *searchTerm = [NSString stringWithFormat:@"%@ %@", artist, title];
    NSString *urlString = [NSString stringWithFormat:@"https://itunes.apple.com/search?term=%@&media=music&entity=song&limit=25", IGMediaEncodeURLComponent(searchTerm)];
    @try {
        NSMutableArray *args = [NSMutableArray arrayWithArray:@[@"-fsSL", @"-m", @"20"]];
        IGMediaAddCACertIfAvailable(args);
        [args addObject:urlString];
        int status = -1;
        NSData *data = IGMediaRunCurlWithLimit(args, &status, 4ULL * 1024ULL * 1024ULL);
        if (status != 0 || [data length] == 0) {
            if (errorMessage) *errorMessage = @"Apple metadata request failed or timed out.";
            return nil;
        }
        NSError *parseError = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        id results = [json isKindOfClass:[NSDictionary class]] ? [json objectForKey:@"results"] : nil;
        if (parseError || ![results isKindOfClass:[NSArray class]]) {
            if (errorMessage) *errorMessage = @"Apple metadata returned an invalid response.";
            return nil;
        }
        return IGMediaBestAppleMusicMatch(results, artist, title, album);
    } @catch (NSException *exception) {
        if (errorMessage) *errorMessage = @"Apple metadata request could not be completed.";
        return nil;
    }
}

- (void)searchVideoMetadataForTitle:(NSString *)title
                          videoKind:(NSString *)videoKind
                          completion:(void(^)(NSArray *results, NSString *errorMessage))completionBlock {
    [self searchVideoMetadataForTitle:title
                            videoKind:videoKind
                             showName:@""
                         seasonNumber:0
                        episodeNumber:0
                           completion:completionBlock];
}

- (void)searchVideoMetadataForTitle:(NSString *)title
                          videoKind:(NSString *)videoKind
                           showName:(NSString *)showName
                       seasonNumber:(NSInteger)seasonNumber
                      episodeNumber:(NSInteger)episodeNumber
                         completion:(void(^)(NSArray *results, NSString *errorMessage))completionBlock {
    NSString *trimmed = [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed length] == 0) {
        if (completionBlock) completionBlock([NSArray array], @"Enter a movie or TV-show title first.");
        return;
    }
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"only_local_mode"]) {
        if (completionBlock) completionBlock([NSArray array], @"Online catalog search is disabled by Only Local Mode.");
        return;
    }

    BOOL television = [videoKind isEqualToString:@"TV Show"];
    NSString *trimmedShow = [showName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BOOL specificEpisode = television && [trimmedShow length] > 0 && seasonNumber > 0 && episodeNumber > 0;
    NSString *searchText = specificEpisode ? [NSString stringWithFormat:@"%@ %@", trimmedShow, trimmed] : trimmed;
    NSString *encoded = IGMediaEncodeURLComponent(searchText);
    NSString *encodedShow = IGMediaEncodeURLComponent(specificEpisode ? trimmedShow : trimmed);
    NSString *imdbURL = [NSString stringWithFormat:@"https://v3.sg.media-imdb.com/suggestion/x/%@.json", encoded];
    NSString *appleURL = [NSString stringWithFormat:@"https://itunes.apple.com/search?term=%@&country=US&media=%@&entity=%@&limit=20",
                          encoded, television ? @"tvShow" : @"movie", television ? (specificEpisode ? @"tvEpisode" : @"tvSeason") : @"movie"];
    NSString *tvMazeURL = specificEpisode ?
        [NSString stringWithFormat:@"https://api.tvmaze.com/singlesearch/shows?q=%@&embed=episodes", encodedShow] : nil;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (specificEpisode) {
            NSMutableArray *episodeMatches = [NSMutableArray array];
            NSMutableArray *tvMazeArgs = [NSMutableArray arrayWithArray:@[@"-sSL", @"--fail", @"--proto", @"=https", @"--proto-redir", @"=https",
                                                                         @"--max-filesize", @"10485760", @"-m", @"20", @"-A", @"Syncrosa/3.5.0 metadata lookup"]];
            IGMediaAddCACertIfAvailable(tvMazeArgs);
            [tvMazeArgs addObject:tvMazeURL];
            int tvMazeStatus = -1;
            NSData *tvMazeData = IGMediaRunCurlWithLimit(tvMazeArgs, &tvMazeStatus, 10ULL * 1024ULL * 1024ULL);
            if (tvMazeStatus == 0 && [tvMazeData length] > 0) {
                [episodeMatches addObjectsFromArray:IGMediaTVMazeEpisodeMatches(tvMazeData, seasonNumber, episodeNumber)];
            }

            NSMutableArray *appleArgs = [NSMutableArray arrayWithArray:@[@"-sSL", @"--fail", @"--proto", @"=https", @"--proto-redir", @"=https",
                                                                        @"--max-filesize", @"10485760", @"-m", @"20"]];
            IGMediaAddCACertIfAvailable(appleArgs);
            [appleArgs addObject:appleURL];
            int appleStatus = -1;
            NSData *appleData = IGMediaRunCurlWithLimit(appleArgs, &appleStatus, 10ULL * 1024ULL * 1024ULL);
            if (appleStatus == 0 && [appleData length] > 0) {
                NSArray *appleMatches = IGMediaAppleVideoMatchesFromData(appleData, YES, seasonNumber, episodeNumber);
                for (NSDictionary *appleMatch in appleMatches) {
                    BOOL duplicate = NO;
                    for (NSDictionary *existing in episodeMatches) {
                        if ([[existing objectForKey:@"name"] caseInsensitiveCompare:[appleMatch objectForKey:@"name"]] == NSOrderedSame &&
                            [[existing objectForKey:@"seasonNumber"] integerValue] == [[appleMatch objectForKey:@"seasonNumber"] integerValue] &&
                            [[existing objectForKey:@"episodeNumber"] integerValue] == [[appleMatch objectForKey:@"episodeNumber"] integerValue]) {
                            duplicate = YES;
                            break;
                        }
                    }
                    if (!duplicate) [episodeMatches addObject:appleMatch];
                }
            }
            NSString *episodeError = nil;
            if ([episodeMatches count] == 0 && tvMazeStatus != 0 && appleStatus != 0) {
                episodeError = @"TV episode catalog search failed. Check the network connection and try again.";
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completionBlock) completionBlock(episodeMatches, episodeError);
            });
            return;
        }

        NSMutableArray *args = [NSMutableArray arrayWithArray:@[@"-sSL", @"--fail", @"--proto", @"=https", @"--proto-redir", @"=https",
                                                                 @"--max-filesize", @"10485760", @"-m", @"20"]];
        IGMediaAddCACertIfAvailable(args);
        [args addObject:imdbURL];
        int status = -1;
        NSData *data = IGMediaRunCurlWithLimit(args, &status, 10ULL * 1024ULL * 1024ULL);
        NSArray *matches = status == 0 && [data length] > 0 ? IGMediaIMDbVideoMatches(data, television) : [NSArray array];
        NSString *errorMessage = nil;
        if ([matches count] > 0) {
            NSMutableString *values = [NSMutableString string];
            for (NSDictionary *match in matches) {
                NSString *identifier = [match objectForKey:@"catalogID"];
                if ([identifier length] > 0) [values appendFormat:@" \"%@\"", identifier];
            }
            NSString *sparql = [NSString stringWithFormat:
                                @"SELECT ?imdb ?ruLabel ?ruDescription ?enDescription "
                                 "(GROUP_CONCAT(DISTINCT ?genreRu; separator=\", \") AS ?genresRu) "
                                 "(GROUP_CONCAT(DISTINCT ?genreEn; separator=\", \") AS ?genresEn) "
                                 "(GROUP_CONCAT(DISTINCT ?directorRu; separator=\", \") AS ?directorsRu) "
                                 "(GROUP_CONCAT(DISTINCT ?directorEn; separator=\", \") AS ?directorsEn) WHERE { "
                                 "VALUES ?imdb { %@ } ?item wdt:P345 ?imdb. "
                                 "?item rdfs:label ?ruLabel. FILTER(LANG(?ruLabel) = \"ru\") "
                                 "OPTIONAL { ?item schema:description ?ruDescription. FILTER(LANG(?ruDescription) = \"ru\") } "
                                 "OPTIONAL { ?item schema:description ?enDescription. FILTER(LANG(?enDescription) = \"en\") } "
                                 "OPTIONAL { ?item wdt:P136 ?genre. OPTIONAL { ?genre rdfs:label ?genreRu. FILTER(LANG(?genreRu) = \"ru\") } OPTIONAL { ?genre rdfs:label ?genreEn. FILTER(LANG(?genreEn) = \"en\") } } "
                                 "OPTIONAL { ?item wdt:P57 ?director. OPTIONAL { ?director rdfs:label ?directorRu. FILTER(LANG(?directorRu) = \"ru\") } OPTIONAL { ?director rdfs:label ?directorEn. FILTER(LANG(?directorEn) = \"en\") } } "
                                 "} GROUP BY ?imdb ?ruLabel ?ruDescription ?enDescription",
                                values];
            NSString *wikidataURL = [NSString stringWithFormat:@"https://query.wikidata.org/sparql?format=json&query=%@", IGMediaEncodeURLComponent(sparql)];
            NSMutableArray *wikidataArgs = [NSMutableArray arrayWithArray:@[@"-sSL", @"-m", @"20", @"-A", @"Syncrosa/3.5.0 metadata lookup"]];
            IGMediaAddCACertIfAvailable(wikidataArgs);
            [wikidataArgs addObject:wikidataURL];
            int wikidataStatus = -1;
            NSData *wikidataData = IGMediaRunCurl(wikidataArgs, &wikidataStatus);
            if (wikidataStatus == 0 && [wikidataData length] > 0) {
                matches = IGMediaMatchesByAddingRussianWikidataLabels(matches, wikidataData);
            }
        }
        if ([matches count] == 1) {
            NSDictionary *onlyMatch = [matches objectAtIndex:0];
            NSString *localizedName = [onlyMatch objectForKey:@"localizedName"];
            NSCharacterSet *cyrillic = [NSCharacterSet characterSetWithCharactersInString:
                                        @"АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдеёжзийклмнопрстуфхцчшщъыьэюя"];
            if ([localizedName length] == 0 && [trimmed rangeOfCharacterFromSet:cyrillic].location != NSNotFound) {
                NSMutableDictionary *localizedMatch = [[onlyMatch mutableCopy] autorelease];
                [localizedMatch setObject:trimmed forKey:@"localizedName"];
                matches = [NSArray arrayWithObject:localizedMatch];
            }
        }
        if ([matches count] == 0) {
            NSMutableArray *fallbackArgs = [NSMutableArray arrayWithArray:@[@"-sSL", @"-m", @"20"]];
            IGMediaAddCACertIfAvailable(fallbackArgs);
            [fallbackArgs addObject:appleURL];
            int fallbackStatus = -1;
            NSData *fallbackData = IGMediaRunCurl(fallbackArgs, &fallbackStatus);
            if (fallbackStatus == 0 && [fallbackData length] > 0) {
                matches = IGMediaAppleVideoMatchesFromData(fallbackData, television, 0, 0);
            } else if (status != 0) {
                errorMessage = @"Movie catalog search failed. Check the network connection and try again.";
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completionBlock) completionBlock(matches, errorMessage);
        });
    });
}

- (void)downloadVideoArtworkAtURLString:(NSString *)urlString
                              completion:(void(^)(NSURL *fileURL, NSString *errorMessage))completionBlock {
    NSString *secureString = [urlString hasPrefix:@"http://"] ? [@"https://" stringByAppendingString:[urlString substringFromIndex:7]] : urlString;
    NSURL *url = [NSURL URLWithString:secureString];
    NSString *host = [[url host] lowercaseString];
    BOOL trustedHost = [host isEqualToString:@"itunes.apple.com"] || [host hasSuffix:@".itunes.apple.com"] ||
                       [host isEqualToString:@"mzstatic.com"] || [host hasSuffix:@".mzstatic.com"] ||
                       [host isEqualToString:@"media-amazon.com"] || [host hasSuffix:@".media-amazon.com"] ||
                       [host isEqualToString:@"tvmaze.com"] || [host hasSuffix:@".tvmaze.com"];
    if (![[url scheme] isEqualToString:@"https"] || !trustedHost) {
        if (completionBlock) completionBlock(nil, @"The catalog returned an unsupported artwork URL.");
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray *args = [NSMutableArray arrayWithArray:@[@"-sSL", @"--fail", @"--proto", @"=https", @"--proto-redir", @"=https",
                                                                 @"--max-filesize", @"10485760", @"-m", @"20"]];
        IGMediaAddCACertIfAvailable(args);
        [args addObject:secureString];
        int status = -1;
        NSData *data = IGMediaRunCurlWithLimit(args, &status, 10ULL * 1024ULL * 1024ULL);
        NSURL *fileURL = nil;
        NSString *errorMessage = nil;
        if (status == 0 && [data length] > 0 && [data length] <= 10 * 1024 * 1024) {
            NSString *path = IGMediaTempPath(@"jpg");
            NSDictionary *attrs = @{NSFilePosixPermissions: [NSNumber numberWithUnsignedLong:0600]};
            if ([[NSFileManager defaultManager] createFileAtPath:path contents:data attributes:attrs]) {
                fileURL = [NSURL fileURLWithPath:path];
            } else {
                errorMessage = @"Could not save the selected artwork temporarily.";
            }
        } else {
            errorMessage = @"Could not download artwork from the movie catalog.";
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completionBlock) completionBlock(fileURL, errorMessage);
        });
    });
}

- (void)getMergeCandidatesWithCompletion:(void(^)(NSArray *candidates))completionBlock {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [[IGLogger sharedLogger] log:@"MediaFixer manager: merge candidate scan started"];
        IGiTunesService *service = [IGiTunesService sharedService];
        NSString *countStr = [service runAppleScriptNamed:@"mediaFixer.merge.count" source:@"tell application \"iTunes\" to count every track of library playlist 1"];
        NSInteger total = [countStr integerValue];
        [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"MediaFixer manager: merge candidate total=%ld raw=%@", (long)total, countStr ?: @""]];
        if (total <= 0) {
            dispatch_async(dispatch_get_main_queue(), ^{ completionBlock(@[]); });
            return;
        }

        NSMutableDictionary *groups = [NSMutableDictionary dictionary];
        NSInteger chunkSize = 150;

        for (NSInteger start = 1; start <= total; start += chunkSize) {
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            NSInteger end = MIN(start + chunkSize - 1, total);
            NSString *script = [NSString stringWithFormat:
                @"on replaceText(theText, oldText, newText)\n"
                "    set AppleScript's text item delimiters to oldText\n"
                "    set textItems to every text item of theText\n"
                "    set AppleScript's text item delimiters to newText\n"
                "    set newString to textItems as text\n"
                "    set AppleScript's text item delimiters to \"\"\n"
                "    return newString\n"
                "end replaceText\n"
                "on textValue(v)\n"
                "    try\n"
                "        if v is missing value then return \"\"\n"
                "        set s to v as text\n"
                "        set s to my replaceText(s, tab, \" \")\n"
                "        set s to my replaceText(s, linefeed, \" \")\n"
                "        set s to my replaceText(s, return, \" \")\n"
                "        return s\n"
                "    on error\n"
                "        return \"\"\n"
                "    end try\n"
                "end textValue\n"
                "set out to \"\"\n"
                "tell application \"iTunes\"\n"
                "    set trks to tracks %ld thru %ld of library playlist 1\n"
                "    repeat with t in trks\n"
                "        try\n"
                "            set out to out & my textValue(persistent ID of t) & tab & my textValue(artist of t) & tab & my textValue(album of t) & linefeed\n"
                "        end try\n"
                "    end repeat\n"
                "end tell\n"
                "return out", (long)start, (long)end];

            NSString *raw = [service runAppleScriptNamed:@"mediaFixer.merge.chunk" source:script];
            NSArray *lines = [raw componentsSeparatedByString:@"\n"];
            NSInteger parsedRows = 0;

            for (NSString *line in lines) {
                if (line.length == 0) continue;

                NSArray *parts = [line componentsSeparatedByString:@"\t"];
                if (parts.count < 3) continue;

                NSString *pid = parts[0];
                NSString *artist = parts[1];
                NSString *album = parts[2];

                if (pid.length == 0 || album.length == 0) continue;

                NSString *key = [NSString stringWithFormat:@"%@|%@", [artist lowercaseString], [self normalizeText:album]];
                if (!groups[key]) groups[key] = [NSMutableArray array];
                [groups[key] addObject:@{@"pid": pid, @"alb": album}];
                parsedRows++;
            }
            [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"MediaFixer manager: merge chunk %ld-%ld parsed=%ld", (long)start, (long)end, (long)parsedRows]];
#if !__has_feature(objc_arc)
            [pool drain];
#endif
        }

        NSMutableArray *toFix = [NSMutableArray array];
        for (NSString *key in groups) {
            NSArray *tracks = groups[key];
            NSMutableSet *variants = [NSMutableSet set];
            NSCountedSet *counts = [[NSCountedSet alloc] init];

            for (NSDictionary *t in tracks) {
                [variants addObject:t[@"alb"]];
                [counts addObject:t[@"alb"]];
            }

            if (variants.count > 1) {
                NSString *mainVariant = nil;
                NSUInteger maxCount = 0;
                for (NSString *v in variants) {
                    if ([counts countForObject:v] > maxCount) {
                        maxCount = [counts countForObject:v];
                        mainVariant = v;
                    }
                }

                NSMutableArray *targets = [NSMutableArray array];
                for (NSDictionary *t in tracks) {
                    if (![t[@"alb"] isEqualToString:mainVariant]) {
                        [targets addObject:t];
                    }
                }
                [toFix addObject:@{@"main": mainVariant, @"targets": targets}];
            }
#if !__has_feature(objc_arc)
            [counts release];
#endif
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"MediaFixer manager: merge candidates=%ld", (long)toFix.count]];
            completionBlock(toFix);
        });
    });
}

- (void)runMetadataFixWithProgress:(void(^)(NSInteger current, NSInteger total))progressBlock
                        completion:(void(^)(void))completionBlock {
    NSDictionary *allOptions = @{
        @"album": @(YES),
        @"title": @(YES),
        @"artist": @(YES),
        @"genre": @(YES),
        @"trackNumber": @(YES),
        @"lyrics": @(YES)
    };
    [self runMetadataFixWithOptions:allOptions progress:progressBlock completion:completionBlock];
}

- (IGiTunesService *)metadataLibraryService {
    return [IGiTunesService sharedService];
}

- (NSString *)metadataLyricsForArtist:(NSString *)artist title:(NSString *)title errorMessage:(NSString **)errorMessage {
    return [[IGLyricsService sharedService] lyricsForArtist:artist title:title errorMessage:errorMessage];
}

- (void)runMetadataFixWithOptions:(NSDictionary *)options
                         progress:(void(^)(NSInteger current, NSInteger total))progressBlock
                       completion:(void(^)(void))completionBlock {
    [self runMetadataFixWithOptions:options progress:progressBlock reportCompletion:^(NSDictionary *report) {
        if (completionBlock) completionBlock();
    }];
}

- (void)runMetadataFixWithOptions:(NSDictionary *)options
                         progress:(void(^)(NSInteger current, NSInteger total))progressBlock
                 reportCompletion:(void(^)(NSDictionary *report))completionBlock {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        IGiTunesService *service = [self metadataLibraryService];
        NSString *countStr = [service runAppleScriptNamed:@"mediaFixer.metadata.count" source:@"tell application \"iTunes\" to count every track of library playlist 1"];
        NSScanner *countScanner = [NSScanner scannerWithString:countStr ?: @""];
        NSInteger total = 0;
        BOOL readable = [countScanner scanInteger:&total] && [countScanner isAtEnd] && total >= 0;
        NSInteger changed = 0, skipped = 0, noMatch = 0, errors = 0;
        NSMutableSet *changedIDs = [NSMutableSet set];
        NSMutableArray *errorMessages = [NSMutableArray array];
        if (!readable) {
            total = 0;
            errors = 1;
            [errorMessages addObject:@"Could not read the iTunes library count."];
        }
        BOOL onlyLocal = [[NSUserDefaults standardUserDefaults] boolForKey:@"only_local_mode"];
        void (^reportProgress)(NSInteger) = ^(NSInteger current) {
            if (progressBlock) dispatch_async(dispatch_get_main_queue(), ^{ progressBlock(current, total); });
        };
        NSInteger chunkSize = 150;
        for (NSInteger start = 1; start <= total; start += chunkSize) {
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            NSInteger end = MIN(start + chunkSize - 1, total);
            NSString *chunkScript = [NSString stringWithFormat:
                @"on replaceText(theText, oldText, newText)\n"
                "    set AppleScript's text item delimiters to oldText\n"
                "    set textItems to every text item of theText\n"
                "    set AppleScript's text item delimiters to newText\n"
                "    set newString to textItems as text\n"
                "    set AppleScript's text item delimiters to \"\"\n"
                "    return newString\n"
                "end replaceText\n"
                "on textValue(v)\n"
                "    try\n"
                "        if v is missing value then return \"\"\n"
                "        set s to v as text\n"
                "        set s to my replaceText(s, tab, \" \")\n"
                "        set s to my replaceText(s, linefeed, \" \")\n"
                "        set s to my replaceText(s, return, \" \")\n"
                "        return s\n"
                "    on error\n"
                "        return \"\"\n"
                "    end try\n"
                "end textValue\n"
                "on numberValue(v)\n"
                "    try\n"
                "        if v is missing value then return \"0\"\n"
                "        return (v as integer) as text\n"
                "    on error\n"
                "        return \"-1\"\n"
                "    end try\n"
                "end numberValue\n"
                "set out to \"\"\n"
                "tell application \"iTunes\"\n"
                "    set trks to tracks %ld thru %ld of library playlist 1\n"
                "    repeat with t in trks\n"
                "        try\n"
                "            set pid to my textValue(persistent ID of t)\n"
                "            set nm to my textValue(name of t)\n"
                "            set art to my textValue(artist of t)\n"
                "            set alb to my textValue(album of t)\n"
                "            set gen to my textValue(genre of t)\n"
                "            set trk to my numberValue(track number of t)\n"
                "            set hasLyrics to \"UNKNOWN\"\n"
                "            try\n"
                "                set hasLyrics to \"YES\"\n"
                "                if lyrics of t is \"\" or lyrics of t is missing value then set hasLyrics to \"NO\"\n"
                "            on error\n"
                "                set hasLyrics to \"UNKNOWN\"\n"
                "            end try\n"
                "            set out to out & pid & tab & nm & tab & art & tab & alb & tab & gen & tab & trk & tab & hasLyrics & linefeed\n"
                "        on error\n"
                "            set out to out & \"SKIP\" & linefeed\n"
                "        end try\n"
                "    end repeat\n"
                "end tell\n"
                "return out", (long)start, (long)end];

            NSString *chunkRaw = [service runAppleScriptNamed:@"mediaFixer.metadata.chunk" source:chunkScript];
            NSArray *lines = [chunkRaw componentsSeparatedByString:@"\n"];
            NSInteger seenRows = 0;
            for (NSString *rawLine in lines) {
                NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
                if ([line length] == 0) continue;
                if (seenRows >= end - start + 1) break;
                NSInteger currentIndex = start + seenRows++;
                @try {
                    NSArray *parts = [line componentsSeparatedByString:@"\t"];
                    if ([parts count] < 7 || [parts[0] length] == 0) {
                        errors++;
                        if ([errorMessages count] < 25) [errorMessages addObject:[NSString stringWithFormat:@"Could not read track %ld.", (long)currentIndex]];
                        reportProgress(currentIndex);
                        continue;
                    }
                    NSDictionary *track = @{@"title": parts[1], @"artist": parts[2], @"album": parts[3], @"genre": parts[4],
                                            @"trackNumber": @([parts[5] integerValue]), @"hasLyrics": @(![parts[6] isEqualToString:@"NO"])};
                    BOOL unreadableLyrics = [options[@"lyrics"] boolValue] && ![parts[6] isEqualToString:@"YES"] && ![parts[6] isEqualToString:@"NO"];
                    BOOL unreadableNumber = [options[@"trackNumber"] boolValue] && [track[@"trackNumber"] integerValue] < 0;
                    BOOL snapshotReadError = unreadableLyrics || unreadableNumber;
                    if (snapshotReadError && [errorMessages count] < 25) [errorMessages addObject:[NSString stringWithFormat:@"Could not read selected fields for %@; unreadable fields were preserved.", track[@"title"]]];
                    BOOL needsMetadata = ([options[@"title"] boolValue] && IGMediaFieldIsMissing(track[@"title"], @"Title")) ||
                                         ([options[@"artist"] boolValue] && IGMediaFieldIsMissing(track[@"artist"], @"Artist")) ||
                                         ([options[@"album"] boolValue] && IGMediaFieldIsMissing(track[@"album"], @"Album")) ||
                                         ([options[@"genre"] boolValue] && IGMediaFieldIsMissing(track[@"genre"], @"Genre")) ||
                                         ([options[@"trackNumber"] boolValue] && [track[@"trackNumber"] integerValue] == 0);
                    BOOL needsLyrics = [options[@"lyrics"] boolValue] && ![track[@"hasLyrics"] boolValue];
                    if ((!needsMetadata && !needsLyrics) || onlyLocal) {
                        if (snapshotReadError) errors++;
                        else skipped++;
                        reportProgress(currentIndex);
                        continue;
                    }
                    NSString *metadataError = nil;
                    NSDictionary *metadata = needsMetadata ? [self appleMetadataForArtist:track[@"artist"] title:track[@"title"] album:track[@"album"] errorMessage:&metadataError] : nil;
                    NSString *lyricsError = nil;
                    NSString *lyrics = nil;
                    if (needsLyrics) {
                        NSString *artist = IGMediaFieldIsMissing(track[@"artist"], @"Artist") ? metadata[@"art"] : track[@"artist"];
                        NSString *title = IGMediaFieldIsMissing(track[@"title"], @"Title") ? metadata[@"title"] : track[@"title"];
                        lyrics = [self metadataLyricsForArtist:artist title:title errorMessage:&lyricsError];
                    }
                    NSDictionary *changes = IGMediaMissingMetadataProperties(track, metadata, lyrics, options);
                    BOOL trackFailed = snapshotReadError || [metadataError length] > 0 || [lyricsError length] > 0;
                    BOOL didChange = NO;
                    if ([changes count] > 0) {
                        NSMutableArray *updates = [NSMutableArray array];
                        NSArray *fields = @[@"album", @"title", @"artist", @"genre", @"trackNumber", @"lyrics"];
                        NSArray *scriptFields = @[@"album", @"name", @"artist", @"genre", @"track number", @"lyrics"];
                        NSArray *labels = @[@"Album", @"Title", @"Artist", @"Genre", @"", @""];
                        for (NSUInteger index = 0; index < [fields count]; index++) {
                            id replacement = changes[fields[index]];
                            if (!replacement) continue;
                            NSString *field = scriptFields[index];
                            NSString *condition = [fields[index] isEqualToString:@"trackNumber"] ? @"existingValue is missing value or existingValue is 0" :
                                [NSString stringWithFormat:@"existingValue is missing value or existingValue is \"\" or existingValue is \"missing value\"%@", [labels[index] length] > 0 ? [NSString stringWithFormat:@" or existingValue is \"Unknown %@\"", labels[index]] : @""];
                            NSString *valueLiteral = [fields[index] isEqualToString:@"trackNumber"] ? [replacement stringValue] : [NSString stringWithFormat:@"\"%@\"", IGMediaAppleScriptLiteral(replacement)];
                            [updates addObject:[NSString stringWithFormat:@"set existingValue to %@ of t\nif %@ then\nset %@ of t to %@\nset changedFields to changedFields + 1\nend if", field, condition, field, valueLiteral]];
                        }
                        NSString *script = [NSString stringWithFormat:
                            @"set changedFields to 0\ntell application \"iTunes\"\ntry\nset t to (some track of library playlist 1 whose persistent ID is \"%@\")\n%@\nreturn \"OK\" & tab & (changedFields as text)\non error\nreturn \"ERROR\" & tab & (changedFields as text)\nend try\nend tell", IGMediaAppleScriptLiteral(parts[0]), [updates componentsJoinedByString:@"\n"]];
                        NSString *result = [service runAppleScriptNamed:@"mediaFixer.metadata.updateTrack" source:script];
                        NSArray *status = [result componentsSeparatedByString:@"\t"];
                        BOOL validResult = [status count] == 2 && ([status[0] isEqualToString:@"OK"] || [status[0] isEqualToString:@"ERROR"]);
                        didChange = validResult && [status[1] integerValue] > 0;
                        if (!validResult || ![status[0] isEqualToString:@"OK"]) {
                            trackFailed = YES;
                            if ([errorMessages count] < 25) [errorMessages addObject:[NSString stringWithFormat:@"iTunes could not finish updating %@.", track[@"title"]]];
                        }
                    }
                    if (didChange) {
                        changed++;
                        [changedIDs addObject:parts[0]];
                    }
                    if (trackFailed) {
                        errors++;
                        if ([errorMessages count] < 25 && ([metadataError length] > 0 || [lyricsError length] > 0)) {
                            [errorMessages addObject:[NSString stringWithFormat:@"%@: %@%@%@", track[@"title"], metadataError ?: @"", metadataError && lyricsError ? @" " : @"", lyricsError ?: @""]];
                        }
                    } else if ([changes count] == 0) noMatch++;
                    else if (!didChange) skipped++; /* Another tool filled the field after the snapshot. */
                } @catch (NSException *exception) {
                    errors++;
                    if ([errorMessages count] < 25) [errorMessages addObject:[NSString stringWithFormat:@"Could not process track %ld.", (long)currentIndex]];
                }
                reportProgress(currentIndex);
            }
            NSInteger unread = (end - start + 1) - seenRows;
            if (unread > 0) {
                errors += unread;
                if ([errorMessages count] < 25) [errorMessages addObject:[NSString stringWithFormat:@"Could not read %ld tracks in this batch.", (long)unread]];
            }
            reportProgress(end);
            [pool drain];
        }
        NSDictionary *report = @{@"total": @(total), @"changed": @(changed), @"skipped": @(skipped), @"noMatch": @(noMatch),
                                 @"errors": @(errors), @"errorMessages": errorMessages, @"onlyLocal": @(onlyLocal),
                                 @"changedIDs": [[changedIDs allObjects] sortedArrayUsingSelector:@selector(compare:)]};
        dispatch_async(dispatch_get_main_queue(), ^{
            [[IGLogger sharedLogger] log:[NSString stringWithFormat:@"MediaFixer metadata report: %@", report]];
            if (completionBlock) completionBlock(report);
        });
    });
}

@end
