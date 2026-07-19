#import "IGUpdateSupport.h"

static NSString * const IGUpdateManifestURLStringValue = @"https://syncrosa-updates.telegraphica.workers.dev/v1/update-manifest?platform=macos&track=cocoa&channel=stable";
static NSString * const IGUpdateManifestURLDefaultsKey = @"SyncrosaUpdateManifestURL";
static NSString * const IGUpdateProjectReleasesURLValue = @"https://github.com/MiChiRose/Syncrosa/releases";

static NSString *IGUpdateStringValue(id object) {
    return [object isKindOfClass:[NSString class]] ? object : nil;
}

static NSDictionary *IGUpdatePreferredCocoaAsset(NSArray *assets) {
    NSUInteger index = 0;
    for (index = 0; index < [assets count]; index++) {
        id assetObject = [assets objectAtIndex:index];
        if (![assetObject isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *asset = (NSDictionary *)assetObject;
        NSString *name = IGUpdateStringValue([asset objectForKey:@"name"]);
        NSString *download = IGUpdateStringValue([asset objectForKey:@"browser_download_url"]);
        if ([download length] == 0) {
            download = IGUpdateStringValue([asset objectForKey:@"download_url"]);
        }
        NSString *lower = [name lowercaseString];
        if ([lower rangeOfString:@"syncrosa_cocoa_v"].location != NSNotFound &&
            [lower hasSuffix:@".zip"] &&
            [download length] > 0) {
            return asset;
        }
    }
    return nil;
}

static NSString *IGUpdateFirstStringValue(NSDictionary *dictionary, NSArray *keys) {
    for (NSString *key in keys) {
        NSString *value = IGUpdateStringValue([dictionary objectForKey:key]);
        if ([value length] > 0) {
            return value;
        }
    }
    return nil;
}

static NSDictionary *IGUpdateInfoFromReleaseDictionary(NSDictionary *release, NSString *source) {
    NSString *tagName = IGUpdateFirstStringValue(release, [NSArray arrayWithObjects:@"tag_name", @"tagName", @"tag", @"version", nil]);
    NSString *name = IGUpdateFirstStringValue(release, [NSArray arrayWithObjects:@"name", @"title", @"releaseTitle", nil]);
    NSString *version = [tagName length] > 0 ? tagName : name;
    if ([version hasPrefix:@"v"]) {
        version = [version substringFromIndex:1];
    }
    if ([version length] == 0) {
        return nil;
    }

    NSString *htmlURL = IGUpdateFirstStringValue(release, [NSArray arrayWithObjects:@"html_url", @"release_url", @"releaseURL", @"releaseUrl", @"url", nil]);
    if ([htmlURL length] == 0) {
        htmlURL = IGUpdateProjectReleasesURLValue;
    }

    NSArray *assets = [[release objectForKey:@"assets"] isKindOfClass:[NSArray class]] ? [release objectForKey:@"assets"] : nil;
    NSDictionary *asset = IGUpdatePreferredCocoaAsset(assets);
    NSDictionary *cocoa = [[release objectForKey:@"cocoa"] isKindOfClass:[NSDictionary class]] ? [release objectForKey:@"cocoa"] : nil;
    NSString *downloadURL = IGUpdateFirstStringValue(release, [NSArray arrayWithObjects:@"download_url", @"downloadURL", @"downloadUrl", @"cocoaDownloadURL", @"cocoaDownloadUrl", nil]);
    NSString *fileName = IGUpdateFirstStringValue(release, [NSArray arrayWithObjects:@"file_name", @"fileName", @"assetName", nil]);
    if ([downloadURL length] == 0 && cocoa) {
        downloadURL = IGUpdateFirstStringValue(cocoa, [NSArray arrayWithObjects:@"download_url", @"downloadURL", @"downloadUrl", @"url", nil]);
    }
    if ([fileName length] == 0 && cocoa) {
        fileName = IGUpdateFirstStringValue(cocoa, [NSArray arrayWithObjects:@"file_name", @"fileName", @"assetName", nil]);
    }
    if ([downloadURL length] == 0 && asset) {
        downloadURL = IGUpdateStringValue([asset objectForKey:@"browser_download_url"]);
        if ([downloadURL length] == 0) {
            downloadURL = IGUpdateStringValue([asset objectForKey:@"download_url"]);
        }
    }
    if ([fileName length] == 0 && asset) {
        fileName = IGUpdateStringValue([asset objectForKey:@"name"]);
    }

    if (!IGUpdateURLStringIsTrusted(downloadURL)) {
        downloadURL = nil;
    }
    if (!IGUpdateURLStringIsTrusted(htmlURL)) {
        htmlURL = IGUpdateProjectReleasesURLValue;
    }

    NSString *body = IGUpdateFirstStringValue(release, [NSArray arrayWithObjects:@"body", @"notes", @"releaseNotes", @"release_notes", @"body_markdown", nil]);
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                 version, @"version",
                                 htmlURL, @"url",
                                 source ? source : @"unknown", @"source",
                                 nil];
    if ([name length] > 0) {
        [info setObject:name forKey:@"title"];
    }
    if ([body length] > 0) {
        [info setObject:body forKey:@"notes"];
    }
    if ([downloadURL length] > 0) {
        [info setObject:downloadURL forKey:@"download_url"];
    }
    if ([fileName length] > 0) {
        [info setObject:fileName forKey:@"file_name"];
    }
    return info;
}

static NSDictionary *IGLatestManifestUpdateInfoWithError(NSError **error) {
    NSString *manifestURL = IGUpdateManifestURLString();
    NSURL *url = [NSURL URLWithString:manifestURL];
    if (!url) {
        if (error) {
            *error = [NSError errorWithDomain:@"SyncrosaUpdate"
                                         code:10
                                     userInfo:[NSDictionary dictionaryWithObject:@"Update manifest URL is invalid." forKey:NSLocalizedDescriptionKey]];
        }
        return nil;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:12.0];
    [request setHTTPMethod:@"GET"];
    [request setValue:IGUpdateCheckUserAgentString() forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];

    NSURLResponse *response = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:error];
    if (![data isKindOfClass:[NSData class]] || [data length] == 0) {
        return nil;
    }
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
        if (statusCode < 200 || statusCode >= 300) {
            if (error) {
                NSString *message = [NSString stringWithFormat:@"Update manifest returned HTTP %ld.", (long)statusCode];
                *error = [NSError errorWithDomain:@"SyncrosaUpdate"
                                             code:statusCode
                                         userInfo:[NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey]];
            }
            return nil;
        }
    }

    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"SyncrosaUpdate"
                                         code:11
                                     userInfo:[NSDictionary dictionaryWithObject:@"Update manifest did not return an object." forKey:NSLocalizedDescriptionKey]];
        }
        return nil;
    }
    NSDictionary *info = IGUpdateInfoFromReleaseDictionary((NSDictionary *)json, @"cloudflare");
    if (!info && error) {
        *error = [NSError errorWithDomain:@"SyncrosaUpdate"
                                     code:12
                                 userInfo:[NSDictionary dictionaryWithObject:@"Update manifest does not contain a release version." forKey:NSLocalizedDescriptionKey]];
    }
    return info;
}

NSString *IGCurrentApplicationVersionString(void) {
    NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    if ([version length] == 0) {
        version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
    }
    return ([version length] > 0) ? version : @"0.0.0";
}

NSString *IGUpdateManifestURLString(void) {
    NSString *overrideURL = [[NSUserDefaults standardUserDefaults] stringForKey:IGUpdateManifestURLDefaultsKey];
    if ([overrideURL length] > 0 && [overrideURL rangeOfString:@"syncrosa-updates.michirose.workers.dev"].location == NSNotFound) {
        return overrideURL;
    }
    NSString *plistURL = [[[NSBundle mainBundle] infoDictionary] objectForKey:IGUpdateManifestURLDefaultsKey];
    if ([plistURL isKindOfClass:[NSString class]] && [plistURL length] > 0) {
        return plistURL;
    }
    return IGUpdateManifestURLStringValue;
}

NSString *IGUpdateProjectReleasesURLString(void) {
    return IGUpdateProjectReleasesURLValue;
}

NSURL *IGUpdateProjectReleasesURL(void) {
    return [NSURL URLWithString:IGUpdateProjectReleasesURLValue];
}

NSString *IGUpdateCheckUserAgentString(void) {
    NSString *version = IGCurrentApplicationVersionString();
    if ([version length] == 0) {
        version = @"unknown";
    }
    return [NSString stringWithFormat:@"Syncrosa/%@ (Mac OS X; Mavericks-compatible)", version];
}

static NSArray *IGVersionParts(NSString *version) {
    NSMutableArray *parts = [NSMutableArray array];
    NSScanner *scanner = [NSScanner scannerWithString:version ? version : @""];
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    while (![scanner isAtEnd]) {
        NSString *number = nil;
        if ([scanner scanCharactersFromSet:digits intoString:&number]) {
            [parts addObject:[NSNumber numberWithInteger:[number integerValue]]];
        } else {
            [scanner scanUpToCharactersFromSet:digits intoString:NULL];
        }
    }
    return parts;
}

BOOL IGVersionStringIsNewer(NSString *remoteVersion, NSString *currentVersion) {
    NSArray *leftParts = IGVersionParts(remoteVersion);
    NSArray *rightParts = IGVersionParts(currentVersion);
    NSUInteger count = MAX([leftParts count], [rightParts count]);
    NSUInteger index = 0;
    for (index = 0; index < count; index++) {
        NSInteger leftValue = index < [leftParts count] ? [[leftParts objectAtIndex:index] integerValue] : 0;
        NSInteger rightValue = index < [rightParts count] ? [[rightParts objectAtIndex:index] integerValue] : 0;
        if (leftValue > rightValue) return YES;
        if (leftValue < rightValue) return NO;
    }
    return NO;
}

BOOL IGUpdateURLStringIsTrusted(NSString *urlString) {
    if (![urlString isKindOfClass:[NSString class]] || [urlString length] == 0) {
        return NO;
    }
    NSURL *url = [NSURL URLWithString:urlString];
    NSString *scheme = [[url scheme] lowercaseString];
    NSString *host = [[url host] lowercaseString];
    if (![scheme isEqualToString:@"https"] || [host length] == 0) {
        return NO;
    }
    if ([host isEqualToString:@"github.com"] ||
        [host isEqualToString:@"raw.githubusercontent.com"] ||
        [host isEqualToString:@"objects.githubusercontent.com"] ||
        [host isEqualToString:@"github-releases.githubusercontent.com"] ||
        [host isEqualToString:@"syncrosa-updates.telegraphica.workers.dev"]) {
        return YES;
    }
    return NO;
}

NSDictionary *IGLatestUpdateInfoWithError(NSError **error) {
    NSError *manifestError = nil;
    NSDictionary *manifestInfo = IGLatestManifestUpdateInfoWithError(&manifestError);
    if (manifestInfo) {
        return manifestInfo;
    }

    if (error) {
        if (manifestError) {
            NSString *message = [manifestError localizedDescription];
            if ([message length] == 0) {
                message = @"Update manifest did not return release information.";
            }
            *error = [NSError errorWithDomain:@"SyncrosaUpdate"
                                         code:13
                                     userInfo:[NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey]];
        } else {
            *error = [NSError errorWithDomain:@"SyncrosaUpdate"
                                         code:30
                                     userInfo:[NSDictionary dictionaryWithObject:@"No update information could be loaded." forKey:NSLocalizedDescriptionKey]];
        }
    }
    return nil;
}

NSString *IGUpdateDownloadURLStringFromInfo(NSDictionary *info) {
    return [info isKindOfClass:[NSDictionary class]] ? IGUpdateStringValue([info objectForKey:@"download_url"]) : nil;
}

NSString *IGUpdateReleaseURLStringFromInfo(NSDictionary *info) {
    NSString *url = [info isKindOfClass:[NSDictionary class]] ? IGUpdateStringValue([info objectForKey:@"url"]) : nil;
    return [url length] > 0 ? url : IGUpdateProjectReleasesURLValue;
}

NSString *IGUpdateReleaseTitleFromInfo(NSDictionary *info) {
    NSString *title = [info isKindOfClass:[NSDictionary class]] ? IGUpdateStringValue([info objectForKey:@"title"]) : nil;
    return [title length] > 0 ? title : @"Syncrosa Release Notes";
}

NSString *IGUpdateReleaseNotesFromInfo(NSDictionary *info) {
    NSString *notes = [info isKindOfClass:[NSDictionary class]] ? IGUpdateStringValue([info objectForKey:@"notes"]) : nil;
    return [notes length] > 0 ? notes : IGUpdateBundledReleaseNotes();
}

NSString *IGUpdateSourceFromInfo(NSDictionary *info) {
    NSString *source = [info isKindOfClass:[NSDictionary class]] ? IGUpdateStringValue([info objectForKey:@"source"]) : nil;
    return [source length] > 0 ? source : @"unknown";
}

NSString *IGUpdateShortErrorMessage(NSError *error) {
    (void)error;
    return @"Network update error. Open Release Notes for details.";
}

NSString *IGUpdateDetailedErrorMessage(NSError *error) {
    NSString *technical = [error localizedDescription];
    NSString *summary = @"Unknown network error.";
    if ([technical length] > 0) {
        if ([technical rangeOfString:@"SSL"].location != NSNotFound ||
            [technical rangeOfString:@"certificate"].location != NSNotFound) {
            summary = @"TLS certificate verification failed.";
        } else {
            NSArray *lines = [technical componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
            NSString *firstLine = [lines count] > 0 ? [lines objectAtIndex:0] : technical;
            if ([firstLine length] > 0) {
                summary = firstLine;
            }
        }
    }
    return [NSString stringWithFormat:
            @"Syncrosa could not check updates from this Mac.\n\n"
            "Most likely cause:\n"
            "This OS X version rejected the update server TLS certificate chain, the update manifest is unavailable, or the network is offline.\n\n"
            "What to try:\n"
            "1. Check that the Mac date and time are correct.\n"
            "2. If the error remains, open the releases page from a newer browser and download the Cocoa build manually.\n\n"
            "Syncrosa keeps certificate verification enabled for safety.\n\n"
            "Update manifest:\n%@\n\n"
            "Manual releases page:\n%@\n\n"
            "Technical summary:\n%@",
            IGUpdateManifestURLString(),
            IGUpdateProjectReleasesURLValue,
            summary];
}

NSString *IGUpdateBundledReleaseNotes(void) {
    return @"Syncrosa Legacy Update Notes\n\n"
           "This build includes the latest bundled release notes available inside the app.\n\n"
           "What's improved:\n"
           "- Cleaner update checking and safer update buttons for the legacy Cocoa interface.\n"
           "- Settings now keeps API key validation next to the API key field.\n"
           "- Full-library JSON export/import flow for external AI playlist planning.\n\n"
           "If this Mac cannot reach the update server because of old system certificates, open the Syncrosa releases page manually from a newer browser:\n"
           "https://github.com/MiChiRose/Syncrosa/releases";
}
