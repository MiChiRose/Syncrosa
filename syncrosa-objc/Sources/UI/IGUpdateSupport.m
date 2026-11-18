#import "IGUpdateSupport.h"
#import "IGAIService.h"
#import <CommonCrypto/CommonDigest.h>
#import <fcntl.h>
#import <poll.h>
#import <unistd.h>
#import <errno.h>
#import <stdlib.h>
#import <string.h>
#import <sys/stat.h>

static NSString * const IGUpdateManifestURLStringValue = @"https://syncrosa-updates.telegraphica.workers.dev/v1/update-manifest?platform=macos&track=cocoa&channel=stable";
static NSString * const IGUpdateManifestURLDefaultsKey = @"SyncrosaUpdateManifestURL";
static NSString * const IGUpdateProjectReleasesURLValue = @"https://github.com/MiChiRose/Syncrosa/releases";

static NSString *IGUpdateStringValue(id object) {
    return [object isKindOfClass:[NSString class]] ? object : nil;
}

static NSString * const IGUpdateGitHubAPIURL = @"https://api.github.com/repos/MiChiRose/Syncrosa/releases/latest";
static const unsigned long long IGUpdateMaximumInstallerSize = 256ULL * 1024 * 1024;

static NSError *IGUpdateError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"SyncrosaUpdate" code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSString *IGUpdateFirstStringValue(NSDictionary *dictionary, NSArray *keys) {
    for (NSString *key in keys) {
        NSString *value = IGUpdateStringValue(dictionary[key]);
        if (value.length > 0) return value;
    }
    return nil;
}

static BOOL IGUpdateStringContainsOnly(NSString *string, NSString *characters) {
    return string.length > 0 &&
        [string rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:characters] invertedSet]].location == NSNotFound;
}

static BOOL IGUpdateVersionIsValid(NSString *version) {
    if (![version isKindOfClass:[NSString class]]) return NO;
    NSArray *parts = [version componentsSeparatedByString:@"."];
    if (parts.count != 3) return NO;
    for (NSString *part in parts) {
        if (part.length > 9 || !IGUpdateStringContainsOnly(part, @"0123456789")) return NO;
    }
    return YES;
}

static NSString *IGUpdateInstallerName(NSString *version) {
    return [NSString stringWithFormat:@"Syncrosa_Cocoa_v%@.dmg", version];
}

static NSString *IGUpdateInstallerURL(NSString *version) {
    return [NSString stringWithFormat:@"%@/download/v%@/%@", IGUpdateProjectReleasesURLValue,
            version, IGUpdateInstallerName(version)];
}

NSDictionary *IGUpdateInfoFromReleaseDictionary(NSDictionary *release, NSString *source) {
    if (![release isKindOfClass:[NSDictionary class]]) return nil;
    if ([release[@"draft"] isEqual:@YES] || [release[@"prerelease"] isEqual:@YES] ||
        [release[@"test"] isEqual:@YES]) return nil;

    NSString *version = IGUpdateFirstStringValue(release, @[@"tag_name", @"tagName", @"tag", @"version"]);
    if ([version hasPrefix:@"v"]) version = [version substringFromIndex:1];
    if (!IGUpdateVersionIsValid(version)) return nil;

    // Build the release link from the validated version and fixed project path.
    NSString *releaseURL = [NSString stringWithFormat:@"%@/tag/v%@", IGUpdateProjectReleasesURLValue, version];
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithDictionary:@{
        @"version": version, @"url": releaseURL, @"source": source ?: @"unknown"
    }];
    NSString *title = IGUpdateFirstStringValue(release, @[@"name", @"title", @"releaseTitle"]);
    NSString *notes = IGUpdateFirstStringValue(release, @[@"body", @"notes", @"releaseNotes"]);
    if (title.length) info[@"title"] = title;
    if (notes.length) info[@"notes"] = notes;

    NSArray *assets = [release[@"assets"] isKindOfClass:[NSArray class]] ? release[@"assets"] : nil;
    NSString *installerName = IGUpdateInstallerName(version);
    NSString *zipName = [[installerName stringByDeletingPathExtension] stringByAppendingPathExtension:@"zip"];
    BOOL hasCocoaAsset = [source isEqual:@"cloudflare"] &&
        [IGUpdateFirstStringValue(release, @[@"file_name", @"fileName", @"assetName"]) isEqual:zipName];
    for (id asset in assets) {
        if (![asset isKindOfClass:[NSDictionary class]]) continue;
        id assetName = asset[@"name"];
        if ([assetName isEqual:zipName]) hasCocoaAsset = YES;
        if (![assetName isEqual:installerName] ||
            ![asset[@"browser_download_url"] isEqual:IGUpdateInstallerURL(version)]) continue;
        hasCocoaAsset = YES;
        id size = asset[@"size"];
        NSString *digest = IGUpdateStringValue(asset[@"digest"]);
        if (![size isKindOfClass:[NSNumber class]] || CFGetTypeID((CFTypeRef)size) == CFBooleanGetTypeID() ||
            [size doubleValue] < 1 || [size doubleValue] > IGUpdateMaximumInstallerSize ||
            [size doubleValue] != [size unsignedLongLongValue] ||
            ![digest hasPrefix:@"sha256:"]) continue;
        NSString *sha256 = [[digest substringFromIndex:7] lowercaseString];
        if (sha256.length != CC_SHA256_DIGEST_LENGTH * 2 ||
            !IGUpdateStringContainsOnly(sha256, @"0123456789abcdef")) continue;

        info[@"download_url"] = IGUpdateInstallerURL(version);
        info[@"file_name"] = IGUpdateInstallerName(version);
        info[@"sha256"] = sha256;
        info[@"size"] = size;
        break;
    }
    return hasCocoaAsset ? info : nil;
}

// Read curl's response in bounded chunks, including when the server omits Content-Length.
static BOOL IGUpdateTransfer(NSString *url, NSUInteger limit, NSInteger timeout, NSProgress *progress,
                             BOOL (^consume)(const void *, NSUInteger), NSError **error) {
    NSTask *task = [[[NSTask alloc] init] autorelease];
    NSString *curlPath = IGAICurlExecutablePath();
    [task setLaunchPath:curlPath];
    if ([curlPath rangeOfString:@"/Contents/Resources/LegacyCurl/"].location != NSNotFound) {
        NSMutableDictionary *environment = [NSMutableDictionary dictionaryWithDictionary:[[NSProcessInfo processInfo] environment]];
        environment[@"DYLD_LIBRARY_PATH"] = [[curlPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"lib"];
        [task setEnvironment:environment];
    }
    NSMutableArray *args = [NSMutableArray arrayWithArray:@[
        @"--disable", @"--silent", @"--fail", @"--location", @"--max-redirs", @"5", @"--globoff",
        @"--proto", @"=https", @"--proto-redir", @"=https", @"--connect-timeout", @"8",
        @"--max-time", [NSString stringWithFormat:@"%ld", (long)timeout],
        @"--speed-time", @"15", @"--speed-limit", @"1", @"--max-filesize",
        [NSString stringWithFormat:@"%lu", (unsigned long)limit], @"--user-agent", IGUpdateCheckUserAgentString()
    ]];
    NSString *caPath = [[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"];
    if (caPath.length) [args addObjectsFromArray:@[@"--cacert", caPath]];
    [args addObjectsFromArray:@[@"--url", url]];
    [task setArguments:args];
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    [task setStandardError:[NSFileHandle fileHandleWithNullDevice]];
    @try {
        [task launch];
    } @catch (NSException *exception) {
        if (error) *error = IGUpdateError(20, @"The secure download tool could not start.");
        return NO;
    }

    int fd = [[pipe fileHandleForReading] fileDescriptor];
    unsigned char buffer[65536];
    NSUInteger received = 0;
    BOOL complete = NO;
    while (![progress isCancelled]) {
        struct pollfd input = { fd, POLLIN, 0 };
        int ready = poll(&input, 1, 250);
        if (ready == 0 || (ready < 0 && errno == EINTR)) continue;
        if (ready < 0 || (input.revents & (POLLERR | POLLNVAL))) break;
        ssize_t count = read(fd, buffer, sizeof(buffer));
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) {
            complete = count == 0;
            break;
        }
        if ((NSUInteger)count > limit - received || !consume(buffer, (NSUInteger)count)) break;
        received += (NSUInteger)count;
    }
    if (!complete && [task isRunning]) [task terminate];
    [[pipe fileHandleForReading] closeFile];
    [task waitUntilExit];
    if (complete && [task terminationStatus] == 0 && ![progress isCancelled]) return YES;
    if (error) *error = IGUpdateError(21, @"The secure transfer failed or was interrupted.");
    return NO;
}

static NSDictionary *IGUpdateReadRelease(NSString *url, NSString *source, NSError **error) {
    NSMutableData *data = [NSMutableData data];
    if (!IGUpdateTransfer(url, 1024 * 1024, 15, nil, ^BOOL(const void *bytes, NSUInteger length) {
        [data appendBytes:bytes length:length];
        return YES;
    }, error)) return nil;

    id release = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    NSDictionary *info = IGUpdateInfoFromReleaseDictionary(release, source);
    if (!info && release && error) *error = IGUpdateError(12, @"The update server returned invalid release information.");
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
    if (![scheme isEqualToString:@"https"] || [host length] == 0 || url.user || url.password ||
        (url.port && [url.port integerValue] != 443)) {
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
    // GitHub includes the installer digest and size. The existing service
    // still resolves the latest Cocoa release if GitHub's API is unavailable.
    NSError *githubError = nil;
    NSDictionary *github = IGUpdateReadRelease(IGUpdateGitHubAPIURL, @"github", &githubError);
    if (IGUpdateDownloadURLStringFromInfo(github)) return github;

    NSError *manifestError = nil;
    NSString *manifestURL = IGUpdateManifestURLString();
    NSDictionary *manifest = IGUpdateURLStringIsTrusted(manifestURL)
        ? IGUpdateReadRelease(manifestURL, @"cloudflare", &manifestError) : nil;
    if (manifest && (!github || IGVersionStringIsNewer(manifest[@"version"], github[@"version"]))) return manifest;
    if (github) return github;

    if (error) *error = manifestError ?: githubError ?: IGUpdateError(13, @"Release information is unavailable.");
    return nil;
}

static NSString *IGUpdateDigestString(CC_SHA256_CTX *hash) {
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(bytes, hash);
    NSMutableString *digest = [NSMutableString stringWithCapacity:sizeof(bytes) * 2];
    for (NSUInteger i = 0; i < sizeof(bytes); i++) [digest appendFormat:@"%02x", bytes[i]];
    return digest;
}

BOOL IGUpdateInstallerMatchesRelease(NSString *path, NSDictionary *info) {
    int fd = open([path fileSystemRepresentation], O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
    if (fd < 0) return NO;

    struct stat status;
    unsigned long long expectedSize = [info[@"size"] unsignedLongLongValue];
    BOOL matches = expectedSize > 0 && expectedSize <= IGUpdateMaximumInstallerSize &&
        fstat(fd, &status) == 0 && S_ISREG(status.st_mode) && (unsigned long long)status.st_size == expectedSize;
    if (matches) {
        CC_SHA256_CTX hash;
        CC_SHA256_Init(&hash);
        unsigned long long received = 0;
        unsigned char bytes[65536];
        while (YES) {
            ssize_t count = read(fd, bytes, sizeof(bytes));
            if (count < 0 && errno == EINTR) continue;
            if (count <= 0 || (unsigned long long)count > expectedSize - received) {
                matches = count == 0 && received == expectedSize &&
                    [IGUpdateDigestString(&hash) isEqual:info[@"sha256"]];
                break;
            }
            CC_SHA256_Update(&hash, bytes, (CC_LONG)count);
            received += count;
        }
    }
    close(fd);
    return matches;
}

NSString *IGDownloadUpdateInstaller(NSDictionary *info, NSString *folder, NSProgress *progress,
                                    void (^reportProgress)(double), NSError **error) {
    NSString *version = info[@"version"];
    unsigned long long size = [info[@"size"] unsignedLongLongValue];
    if (!IGUpdateVersionIsValid(version) || ![info[@"download_url"] isEqual:IGUpdateInstallerURL(version)] ||
        size == 0 || size > IGUpdateMaximumInstallerSize || folder.length == 0) {
        if (error) *error = IGUpdateError(22, @"There is no verified disk image for this release.");
        return nil;
    }

    NSFileManager *files = [NSFileManager defaultManager];
    if (![files createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    NSString *pattern = [folder stringByAppendingPathComponent:@".syncrosa-update.XXXXXX"];
    char *directory = strdup([pattern fileSystemRepresentation]);
    if (!directory || !mkdtemp(directory)) {
        free(directory);
        if (error) *error = IGUpdateError(23, @"A temporary download folder could not be created.");
        return nil;
    }
    NSString *staging = [files stringWithFileSystemRepresentation:directory length:strlen(directory)];
    free(directory);
    NSString *partial = [staging stringByAppendingPathComponent:@"installer.part"];
    int fd = open([partial fileSystemRepresentation], O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (fd < 0) {
        [files removeItemAtPath:staging error:NULL];
        if (error) *error = IGUpdateError(24, @"The disk image could not be saved.");
        return nil;
    }

    NSUInteger expectedSize = (NSUInteger)size;
    __block NSUInteger received = 0;
    __block NSInteger lastPercent = -1;
    __block CC_SHA256_CTX hash;
    CC_SHA256_Init(&hash);
    BOOL fetched = IGUpdateTransfer(info[@"download_url"], expectedSize, 300, progress,
        ^BOOL(const void *bytes, NSUInteger length) {
            const unsigned char *cursor = bytes;
            NSUInteger left = length;
            while (left > 0) {
                ssize_t written = write(fd, cursor, left);
                if (written < 0 && errno == EINTR) continue;
                if (written <= 0) return NO;
                cursor += written;
                left -= written;
            }
            CC_SHA256_Update(&hash, bytes, (CC_LONG)length);
            received += length;
            NSInteger percent = (NSInteger)(100 * received / expectedSize);
            if (reportProgress && percent > lastPercent) {
                reportProgress(percent / 100.0);
                lastPercent = percent;
            }
            return YES;
        }, error);

    BOOL closed = close(fd) == 0;
    NSString *result = nil;
    if (fetched && closed && ![progress isCancelled]) {
        if (received == expectedSize && [IGUpdateDigestString(&hash) isEqual:info[@"sha256"]]) {
            NSString *name = IGUpdateInstallerName(version);
            for (NSUInteger index = 1; index < 1000 && ![progress isCancelled]; index++) {
                NSString *candidateName = index == 1 ? name :
                    [NSString stringWithFormat:@"%@-%lu.dmg", [name stringByDeletingPathExtension], (unsigned long)index];
                NSString *candidate = [folder stringByAppendingPathComponent:candidateName];
                // An atomic hard link publishes the verified file without overwriting a previous download.
                if (link([partial fileSystemRepresentation], [candidate fileSystemRepresentation]) == 0) {
                    result = candidate;
                    break;
                }
                if (errno != EEXIST) break;
            }
            if (!result && error) *error = IGUpdateError(24, @"The disk image could not be saved.");
        } else if (error) {
            *error = IGUpdateError(25, @"The downloaded image did not match the release checksum and size.");
        }
    } else if (!closed && error) {
        *error = IGUpdateError(24, @"The disk image could not be saved.");
    }
    [files removeItemAtPath:staging error:NULL];
    return result;
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
    return @"Choose Check for Updates to read the latest release notes. You can also find them on GitHub.\n\n"
           "https://github.com/MiChiRose/Syncrosa/releases";
}
