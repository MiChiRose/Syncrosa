#import <Cocoa/Cocoa.h>
#import <XCTest/XCTest.h>
#import "IGTrack.h"
#import "IGMediaFixerManager.h"
#import "IGPlaylistJSONSupport.h"
#import "IGUpdateSupport.h"
#import "IGTheme.h"

@interface IGBusinessLogicTests : XCTestCase @end

@implementation IGBusinessLogicTests

- (void)testTrackModelIntegrity {
    IGTrack *track = [[IGTrack alloc] initWithPersistentID:@"TEST_PID" 
                                                      name:@"Test Title" 
                                                    artist:@"Test Artist" 
                                                     album:@"Test Album" 
                                                     genre:@"Test Genre" 
                                                      year:2026];
    XCTAssertEqualObjects(track.persistentID, @"TEST_PID");
    XCTAssertEqualObjects(track.name, @"Test Title");
    XCTAssertEqual(track.year, 2026);
}

- (void)testTextNormalization {
    IGMediaFixerManager *mgr = [IGMediaFixerManager sharedManager];
    NSString *input = @"H\'e\'ll\'o W\'o\'rld!!! [2024]";
    NSString *output = [mgr normalizeText:input];
    // Should remove diacritics and special chars
    XCTAssertEqualObjects(output, @"h e ll o w o rld 2024");
}

- (void)testPlaylistJSONPersistentIDImport {
    NSDictionary *json = @{
        @"playlistName": @" Late Night ",
        @"persistentIDs": @[@"abcd1234", @"ABCD1234", @"not safe", @"123"],
        @"tracks": @[
            @{@"persistentID": @"00ffAA11"},
            @{@"persistentId": @"beefCAFE"},
            @{@"id": @"BAD-ID"}
        ]
    };
    NSArray *ids = IGPlaylistJSONPersistentIDsFromJSONObject(json);
    XCTAssertEqualObjects(ids, (@[@"ABCD1234", @"00FFAA11", @"BEEFCAFE"]));
    XCTAssertEqualObjects(IGPlaylistJSONPlaylistNameFromJSONObject(json), @"Late Night");
}

- (void)testPlaylistJSONTrackExportShape {
    IGTrack *track = [[IGTrack alloc] initWithPersistentID:@"ABCDEF12"
                                                      name:@"Children"
                                                    artist:@"Robert Miles"
                                                     album:@"Dreamland"
                                                     genre:@"Trance"
                                                      year:1996];
    NSDictionary *json = IGPlaylistJSONObjectForTrack(track);
    XCTAssertEqualObjects([json objectForKey:@"persistentID"], @"ABCDEF12");
    XCTAssertEqualObjects([json objectForKey:@"id"], @"ABCDEF12");
    XCTAssertEqualObjects([json objectForKey:@"title"], @"Children");
    XCTAssertEqualObjects([json objectForKey:@"artist"], @"Robert Miles");
    XCTAssertEqualObjects([json objectForKey:@"album"], @"Dreamland");
    XCTAssertEqualObjects([json objectForKey:@"genre"], @"Trance");
    XCTAssertEqualObjects([json objectForKey:@"year"], @1996);
}

- (void)testUpdateVersionComparison {
    XCTAssertTrue(IGVersionStringIsNewer(@"3.4.6", @"3.4.5"));
    XCTAssertTrue(IGVersionStringIsNewer(@"v3.5.0", @"3.4.9"));
    XCTAssertFalse(IGVersionStringIsNewer(@"3.4.5", @"3.4.5"));
    XCTAssertFalse(IGVersionStringIsNewer(@"3.4.4", @"3.4.5"));
}

- (void)testUpdateManifestDefaultsAreUserFacing {
    XCTAssertTrue([IGUpdateManifestURLString() hasPrefix:@"https://"]);
    XCTAssertTrue([IGUpdateManifestURLString() rangeOfString:@"syncrosa-updates.telegraphica.workers.dev"].location != NSNotFound);
    XCTAssertEqualObjects(IGUpdateShortErrorMessage(nil), @"Network update error. Open Release Notes for details.");
    XCTAssertTrue(IGUpdateURLStringIsTrusted(@"https://github.com/MiChiRose/Syncrosa/releases"));
    XCTAssertTrue(IGUpdateURLStringIsTrusted(IGUpdateManifestURLString()));
    XCTAssertFalse(IGUpdateURLStringIsTrusted(@"http://github.com/MiChiRose/Syncrosa/releases"));
    XCTAssertFalse(IGUpdateURLStringIsTrusted(@"https://example.com/Syncrosa.zip"));
}

- (void)testUpdateManifestIgnoresRetiredWorkerOverride {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = @"SyncrosaUpdateManifestURL";
    NSString *previous = [[defaults stringForKey:key] copy];
    [defaults setObject:@"https://syncrosa-updates.michirose.workers.dev/v1/update-manifest?platform=macos&track=cocoa&channel=stable" forKey:key];

    XCTAssertTrue([IGUpdateManifestURLString() rangeOfString:@"syncrosa-updates.telegraphica.workers.dev"].location != NSNotFound);

    if ([previous length] > 0) {
        [defaults setObject:previous forKey:key];
    } else {
        [defaults removeObjectForKey:key];
    }
    [previous release];
}

- (void)testLegacyAppearanceChoicesAndPersistence {
    NSArray *themeIDs = IGThemeIdentifiers();
    NSMutableArray *displayNames = [NSMutableArray arrayWithCapacity:[themeIDs count]];
    for (NSString *identifier in themeIDs) {
        [displayNames addObject:IGThemeDisplayNameForIdentifier(identifier)];
    }
    XCTAssertEqual([themeIDs count], (NSUInteger)6);
    XCTAssertEqualObjects(displayNames, (@[@"Classic Graphite", @"Aqua Blue", @"Sage Graphite", @"Soft Plum", @"Ruby Graphite", @"Ocean Mist"]));
    XCTAssertEqualObjects(IGAppearanceModeIdentifiers(), (@[@"system", @"light", @"dark"]));

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *savedTheme = [[defaults stringForKey:IGThemeDefaultsKey] copy];
    NSString *savedAppearance = [[defaults stringForKey:IGAppearanceModeDefaultsKey] copy];
    @try {
        IGSetActiveThemeIdentifier([themeIDs objectAtIndex:4]);
        IGSetActiveAppearanceModeIdentifier(@"dark");
        XCTAssertEqualObjects(IGActiveThemeIdentifier(), @"ruby-graphite");
        XCTAssertEqualObjects(IGActiveAppearanceModeIdentifier(), @"dark");

        IGSetActiveThemeIdentifier(@"unsupported-theme");
        IGSetActiveAppearanceModeIdentifier(@"unsupported-mode");
        XCTAssertEqualObjects(IGActiveThemeIdentifier(), @"classic-graphite");
        XCTAssertEqualObjects(IGActiveAppearanceModeIdentifier(), @"system");
    } @finally {
        if ([savedTheme length] > 0) {
            [defaults setObject:savedTheme forKey:IGThemeDefaultsKey];
        } else {
            [defaults removeObjectForKey:IGThemeDefaultsKey];
        }
        if ([savedAppearance length] > 0) {
            [defaults setObject:savedAppearance forKey:IGAppearanceModeDefaultsKey];
        } else {
            [defaults removeObjectForKey:IGAppearanceModeDefaultsKey];
        }
        [defaults synchronize];
        [savedTheme release];
        [savedAppearance release];
    }
}

@end
