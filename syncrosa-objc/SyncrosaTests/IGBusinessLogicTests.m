#import <Cocoa/Cocoa.h>
#import <XCTest/XCTest.h>
#import "IGTrack.h"
#import "IGMediaFixerManager.h"
#import "IGPlaylistJSONSupport.h"
#import "IGUpdateSupport.h"
#import "IGTheme.h"
#import "IGMainWindowController.h"
#import "IGLibraryDoctorSupport.h"
#import "IGRecoveryCenterViewController.h"
#import "IGIconProvider.h"
#import "IGAIService.h"

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

- (void)testAITransportSelectsAnExecutableCurlAndUsesConciseErrors {
    NSString *curlPath = IGAICurlExecutablePath();
    XCTAssertTrue([[NSFileManager defaultManager] isExecutableFileAtPath:curlPath]);
    NSError *tlsError = [NSError errorWithDomain:@"IGCurlError" code:35 userInfo:nil];
    XCTAssertEqualObjects(IGAIUserFacingNetworkErrorMessage(tlsError),
                          @"Secure connection failed. This Mac could not negotiate modern TLS with the AI provider.");
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

- (void)testLegacyNavigationLibraryRequirements {
    XCTAssertEqual(IGNavigationItemCount, (NSInteger)12);
    XCTAssertTrue(IGNavigationItemRequiresReadableLibrary(IGNavigationItemAIPlaylist));
    XCTAssertTrue(IGNavigationItemRequiresReadableLibrary(IGNavigationItemLibraryDoctor));
    XCTAssertTrue(IGNavigationItemRequiresReadableLibrary(IGNavigationItemUSBExport));
    XCTAssertFalse(IGNavigationItemRequiresReadableLibrary(IGNavigationItemOverview));
    XCTAssertFalse(IGNavigationItemRequiresReadableLibrary(IGNavigationItemFolderFixer));
    XCTAssertFalse(IGNavigationItemRequiresReadableLibrary(IGNavigationItemInfoEraser));
    XCTAssertFalse(IGNavigationItemRequiresReadableLibrary(IGNavigationItemRecoveryCenter));
    XCTAssertFalse(IGNavigationItemRequiresReadableLibrary(IGNavigationItemSettings));
}

- (void)testGlobalFooterVisibilityPersistence {
    BOOL original = [IGMainWindowController globalFooterVisible];
    @try {
        [IGMainWindowController setGlobalFooterVisible:NO];
        XCTAssertFalse([IGMainWindowController globalFooterVisible]);
        [IGMainWindowController setGlobalFooterVisible:YES];
        XCTAssertTrue([IGMainWindowController globalFooterVisible]);
    } @finally {
        [IGMainWindowController setGlobalFooterVisible:original];
    }
}

- (void)testLegacyPageCanvasKeepsItsDesignedWidthWhenSidebarCollapses {
    NSRect expanded = IGCenteredLegacyPageFrame(NSMakeSize(580.0, 500.0), NSMakeRect(0.0, 0.0, 620.0, 504.0));
    XCTAssertEqualWithAccuracy(NSMinX(expanded), 20.0, 0.001);
    XCTAssertEqualWithAccuracy(NSWidth(expanded), 580.0, 0.001);
    XCTAssertEqualWithAccuracy(NSMinY(expanded), 4.0, 0.001);

    NSRect collapsed = IGCenteredLegacyPageFrame(NSMakeSize(580.0, 500.0), NSMakeRect(0.0, 0.0, 800.0, 504.0));
    XCTAssertEqualWithAccuracy(NSMinX(collapsed), 110.0, 0.001);
    XCTAssertEqualWithAccuracy(NSWidth(collapsed), 580.0, 0.001);

    NSRect constrained = IGCenteredLegacyPageFrame(NSMakeSize(580.0, 500.0), NSMakeRect(0.0, 0.0, 520.0, 460.0));
    XCTAssertEqualWithAccuracy(NSMinX(constrained), 0.0, 0.001);
    XCTAssertEqualWithAccuracy(NSWidth(constrained), 520.0, 0.001);
    XCTAssertEqualWithAccuracy(NSHeight(constrained), 460.0, 0.001);
}

- (void)testEmbeddedLegacyFooterDetectionCoversGenericAndToolSpecificNotes {
    XCTAssertTrue(IGTextIsEmbeddedLegacyFooter(@"© 2026 Syncrosa | Note: AI models are not perfect."));
    XCTAssertTrue(IGTextIsEmbeddedLegacyFooter(@"© 2026 Syncrosa | Note: DRM protected tracks are skipped."));
    XCTAssertFalse(IGTextIsEmbeddedLegacyFooter(@"The selected playlist has no local files to export."));
}

- (void)testChoiceControlThemeRefreshesAfterEnabledChange {
    NSString *savedTheme = [[IGActiveThemeIdentifier() copy] autorelease];
    NSString *savedAppearance = [[IGActiveAppearanceModeIdentifier() copy] autorelease];
    @try {
        IGSetActiveThemeIdentifier(@"classic-graphite");
        IGSetActiveAppearanceModeIdentifier(@"light");

        NSButton *checkbox = [[[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 180, 22)] autorelease];
        checkbox.buttonType = NSSwitchButton;
        checkbox.title = @"Playlist option";
        checkbox.enabled = NO;
        IGApplyThemeToButton(checkbox, IGThemeButtonRoleSecondary);
        NSColor *disabledColor = [[checkbox attributedTitle] attribute:NSForegroundColorAttributeName
                                                               atIndex:0
                                                        effectiveRange:NULL];
        XCTAssertEqualObjects(disabledColor, IGThemeMutedTextColor());

        checkbox.enabled = YES;
        IGApplyThemeToButton(checkbox, IGThemeButtonRoleSecondary);
        NSColor *enabledColor = [[checkbox attributedTitle] attribute:NSForegroundColorAttributeName
                                                              atIndex:0
                                                       effectiveRange:NULL];
        XCTAssertEqualObjects(enabledColor, IGThemeTextColor());
        XCTAssertNotEqualObjects(enabledColor, disabledColor);
    } @finally {
        IGSetActiveThemeIdentifier(savedTheme);
        IGSetActiveAppearanceModeIdentifier(savedAppearance);
    }
}

- (void)testRecoveryHistorySanitizesMalformedEntries {
    NSDictionary *valid = @{ @"tool": @"Library Doctor", @"message": @"Finished" };
    NSArray *input = @[valid, [NSNull null], @42, @"broken"];
    XCTAssertEqualObjects(IGRecoverySanitizedHistoryEntries(input), (@[valid]));
    XCTAssertEqualObjects(IGRecoverySanitizedHistoryEntries(@{ @"unexpected": @"shape" }), (@[]));
}

- (void)testLegacyNavigationIconsAreBundled {
    XCTAssertNotNil(IGIconImageNamed(@"menu"));
    XCTAssertNotNil(IGIconImageNamed(@"doctor"));
    XCTAssertNotNil(IGIconImageNamed(@"settings"));
    XCTAssertNotNil(IGIconImageNamed(@"usb"));
}

- (void)testLibraryDoctorTagScoreAndReportFormats {
    IGTrack *complete = [[[IGTrack alloc] initWithPersistentID:@"ABCDEF12"
                                                          name:@"A \"Quoted\", Title"
                                                        artist:@"Artist"
                                                         album:@"Album"
                                                         genre:@"Electronic"
                                                          year:1999] autorelease];
    IGTrack *sparse = [[[IGTrack alloc] initWithPersistentID:@"12345678"
                                                        name:@"Title Only"
                                                      artist:@""
                                                       album:@""
                                                       genre:@""
                                                        year:0] autorelease];
    NSArray *tracks = @[complete, sparse];
    NSDictionary *score = IGLibraryDoctorTagScore(tracks);
    XCTAssertEqualObjects([score objectForKey:@"trackCount"], @2);
    XCTAssertEqualObjects([score objectForKey:@"completenessPercent"], @60);
    XCTAssertEqualObjects([score objectForKey:@"missingArtist"], @1);
    XCTAssertEqualObjects([score objectForKey:@"missingAlbum"], @1);
    XCTAssertEqualObjects([score objectForKey:@"missingGenre"], @1);
    XCTAssertEqualObjects([score objectForKey:@"missingYear"], @1);

    NSDictionary *json = IGLibraryDoctorJSONObject(tracks);
    XCTAssertEqualObjects([json objectForKey:@"schemaVersion"], @1);
    XCTAssertEqual([[json objectForKey:@"tracks"] count], (NSUInteger)2);

    NSString *csv = IGLibraryDoctorCSVString(tracks);
    XCTAssertTrue([csv hasPrefix:@"persistentID,title,artist,album,genre,year"]);
    XCTAssertTrue([csv rangeOfString:@"\"A \"\"Quoted\"\", Title\""].location != NSNotFound);
}

- (void)testLibraryDoctorLinkAuditDoesNotMutateInputs {
    NSDictionary *missing = @{ @"path": @"/path/that/does/not/exist.mp3", @"name": @"Missing" };
    NSArray *references = @[missing];
    NSArray *folderFiles = @[@"/another/path/unlinked.m4a"];
    NSDictionary *report = IGLibraryDoctorLinkAudit(references, folderFiles);
    XCTAssertEqualObjects([report objectForKey:@"libraryReferenceCount"], @1);
    XCTAssertEqualObjects([report objectForKey:@"folderFileCount"], @1);
    XCTAssertEqualObjects([report objectForKey:@"missingReferenceCount"], @1);
    XCTAssertEqualObjects([report objectForKey:@"unlinkedFileCount"], @1);
    XCTAssertEqualObjects([references objectAtIndex:0], missing);
}

@end
