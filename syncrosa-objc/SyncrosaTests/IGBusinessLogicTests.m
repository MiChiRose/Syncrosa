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
#import "IGIPodCompatibilityService.h"
#import "IGOperationActivity.h"
#import "IGVideoFileMetadataService.h"
#import "IGUSBService.h"
#import <sys/file.h>
#import <fcntl.h>
#import <unistd.h>

@interface IGUSBExportTestService : IGUSBExportService
@property (nonatomic, assign) int64_t availableOverride;
@property (nonatomic, assign) BOOL blockCapacityForPartial;
@end
@implementation IGUSBExportTestService
- (instancetype)initWithJournalDirectory:(NSURL *)directory { self=[super initWithJournalDirectory:directory];if(self)self.availableOverride=-1;return self; }
- (int64_t)availableBytesAtURL:(NSURL *)url {
    if(self.blockCapacityForPartial)for(NSString *name in [[NSFileManager defaultManager] enumeratorAtPath:[url path]])if([[name lastPathComponent] hasPrefix:@".syncrosa-part-"])return 0;
    return self.availableOverride>=0?self.availableOverride:[super availableBytesAtURL:url];
}
@end

static NSURL *IGUSBTestFolder(void) {
    NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"syncrosa-usb-test-" stringByAppendingString:[[NSUUID UUID] UUIDString]]] isDirectory:YES];
    for(NSString *name in @[@"sources",@"destination",@"journals",@"other"])[[NSFileManager defaultManager] createDirectoryAtURL:[root URLByAppendingPathComponent:name] withIntermediateDirectories:YES attributes:nil error:nil];
    return root;
}
static NSDictionary *IGUSBTestTrack(NSURL *root,NSString *filename,NSString *title,NSData *data) {
    NSURL *url=[[root URLByAppendingPathComponent:@"sources"] URLByAppendingPathComponent:filename];[data writeToURL:url atomically:YES];
    return @{@"path":[url path],@"name":title,@"artist":@"Artist",@"size":@([data length])};
}
static NSArray *IGUSBTestMusicNames(NSURL *root) {
    NSArray *names=[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[root URLByAppendingPathComponent:@"destination/Mix"] path] error:nil];
    NSMutableArray *music=[NSMutableArray array];for(NSString *name in names)if([[name pathExtension] isEqualToString:@"mp3"])[music addObject:name];return music;
}

/* Offline doubles keep repair regression tests away from the user's iTunes library. */
@interface IGMetadataRepairTestLibrary : NSObject
@property (nonatomic, copy) NSString *rows;
@property (nonatomic, copy) NSString *lastUpdateScript;
@end
@implementation IGMetadataRepairTestLibrary
- (NSString *)runAppleScriptNamed:(NSString *)name source:(NSString *)source {
    if ([name isEqualToString:@"mediaFixer.metadata.count"]) return @"10";
    if ([name isEqualToString:@"mediaFixer.metadata.chunk"]) return self.rows;
    self.lastUpdateScript = source;
    if ([source rangeOfString:@"0000000000000005"].location != NSNotFound) return @"ERROR\t0";
    if ([source rangeOfString:@"0000000000000007"].location != NSNotFound) return @"OK\t0";
    return @"OK\t1";
}
- (void)dealloc { [_rows release]; [_lastUpdateScript release]; [super dealloc]; }
@end

@interface IGMetadataRepairTestManager : IGMediaFixerManager
@property (nonatomic, retain) IGMetadataRepairTestLibrary *testLibrary;
@property (nonatomic, assign) NSInteger lyricsRequests;
@end
@implementation IGMetadataRepairTestManager
- (id)metadataLibraryService { return self.testLibrary; }
- (NSDictionary *)appleMetadataForArtist:(NSString *)artist title:(NSString *)title album:(NSString *)album errorMessage:(NSString **)errorMessage {
    if (errorMessage) *errorMessage = nil;
    if ([title isEqualToString:@"Unmatched"]) return nil;
    if ([title isEqualToString:@"Network Error"]) {
        if (errorMessage) *errorMessage = @"Network unavailable";
        return nil;
    }
    return @{@"gen": @"Rock"};
}
- (NSString *)metadataLyricsForArtist:(NSString *)artist title:(NSString *)title errorMessage:(NSString **)errorMessage {
    self.lyricsRequests++;
    if (errorMessage) *errorMessage = @"Lyrics unavailable";
    return nil;
}
- (void)dealloc { [_testLibrary release]; [super dealloc]; }
@end

@interface IGBusinessLogicTests : XCTestCase @end

@implementation IGBusinessLogicTests

- (void)testUSBRepeatSkipsVerifiedFilesAndDetectsSameSizeChanges {
    NSURL *root=IGUSBTestFolder();
    @try {
        NSDictionary *track=IGUSBTestTrack(root,@"source.mp3",@"Song",[@"AAAA" dataUsingEncoding:NSUTF8StringEncoding]);
        IGUSBExportTestService *service=[[[IGUSBExportTestService alloc] initWithJournalDirectory:[root URLByAppendingPathComponent:@"journals"]] autorelease];
        NSDictionary *first=[service performExportTracks:@[track] destination:[root URLByAppendingPathComponent:@"destination"] playlistName:@"Mix" options:@{} progress:nil cancel:nil];
        XCTAssertEqualObjects(first[@"status"],@"completed");XCTAssertEqualObjects(first[@"copiedCount"],@1);
        service.availableOverride=0;
        NSDictionary *repeat=[service performExportTracks:@[track] destination:[root URLByAppendingPathComponent:@"destination"] playlistName:@"Mix" options:@{} progress:nil cancel:nil];
        XCTAssertEqualObjects(repeat[@"status"],@"completed");XCTAssertEqualObjects(repeat[@"copiedCount"],@0);XCTAssertEqualObjects(repeat[@"existingCount"],@1);
        NSDate *date=[[[NSFileManager defaultManager] attributesOfItemAtPath:track[@"path"] error:nil] objectForKey:NSFileModificationDate];
        [[@"BBBB" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:track[@"path"] atomically:YES];
        [[NSFileManager defaultManager] setAttributes:@{NSFileModificationDate:date} ofItemAtPath:track[@"path"] error:nil];
        service.availableOverride=-1;
        NSDictionary *changed=[service performExportTracks:@[track] destination:[root URLByAppendingPathComponent:@"destination"] playlistName:@"Mix" options:@{} progress:nil cancel:nil];
        XCTAssertEqualObjects(changed[@"copiedCount"],@1);XCTAssertEqualObjects(changed[@"existingCount"],@0);XCTAssertEqual([IGUSBTestMusicNames(root) count],(NSUInteger)2);
        XCTAssertEqualObjects([NSData dataWithContentsOfURL:[root URLByAppendingPathComponent:@"destination/Mix/Artist - Song.mp3"]],[@"AAAA" dataUsingEncoding:NSUTF8StringEncoding]);
    } @finally { [[NSFileManager defaultManager] removeItemAtURL:root error:nil]; }
}
- (void)testUSBAdoptsLegacyCopiesAndPreservesUnrelatedPlaylistFiles {
    NSURL *root=IGUSBTestFolder();
    @try {
        NSDictionary *track=IGUSBTestTrack(root,@"source.mp3",@"Song",[@"AAAA" dataUsingEncoding:NSUTF8StringEncoding]);
        [[NSFileManager defaultManager] createDirectoryAtURL:[root URLByAppendingPathComponent:@"destination/Mix"] withIntermediateDirectories:NO attributes:nil error:nil];
        [[@"AAAA" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:[root URLByAppendingPathComponent:@"destination/Mix/Artist - Song_2.mp3"] atomically:YES];
        NSURL *userPlaylist=[root URLByAppendingPathComponent:@"destination/Mix/Mix.m3u8"];
        [@"User playlist" writeToURL:userPlaylist atomically:YES encoding:NSUTF8StringEncoding error:nil];
        IGUSBExportService *service=[[[IGUSBExportService alloc] initWithJournalDirectory:[root URLByAppendingPathComponent:@"journals"]] autorelease];
        NSDictionary *result=[service performExportTracks:@[track] destination:[root URLByAppendingPathComponent:@"destination"] playlistName:@"Mix" options:@{@"m3u8":@YES} progress:nil cancel:nil];
        XCTAssertEqualObjects(result[@"status"],@"completed");XCTAssertEqualObjects(result[@"existingCount"],@1);XCTAssertEqualObjects(result[@"copiedCount"],@0);
        XCTAssertEqualObjects([NSString stringWithContentsOfURL:userPlaylist encoding:NSUTF8StringEncoding error:nil],@"User playlist");
        XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[[root URLByAppendingPathComponent:@"destination/Mix/Mix_2.m3u8"] path]]);
    } @finally { [[NSFileManager defaultManager] removeItemAtURL:root error:nil]; }
}
- (void)testUSBCancelRestartAndOwnedPartialCleanupBeforeSpaceCheck {
    NSURL *root=IGUSBTestFolder();
    @try {
        NSDictionary *first=IGUSBTestTrack(root,@"one.mp3",@"One",[@"AAAA" dataUsingEncoding:NSUTF8StringEncoding]);
        NSMutableData *big=[NSMutableData dataWithLength:2*1024*1024];memset([big mutableBytes],42,[big length]);
        NSDictionary *second=IGUSBTestTrack(root,@"two.mp3",@"Two",big);
        IGUSBExportTestService *service=[[[IGUSBExportTestService alloc] initWithJournalDirectory:[root URLByAppendingPathComponent:@"journals"]] autorelease];
        __block BOOL cancel=NO;
        NSDictionary *stopped=[service performExportTracks:@[first,second] destination:[root URLByAppendingPathComponent:@"destination"] playlistName:@"Mix" options:@{@"m3u8":@YES} progress:^(NSDictionary *progress){if([progress[@"currentTrackName"] isEqualToString:@"Artist - Two.mp3"]&&[progress[@"fileBytes"] longLongValue]>0)cancel=YES;} cancel:^BOOL{return cancel;}];
        XCTAssertEqualObjects(stopped[@"status"],@"cancelled");XCTAssertEqualObjects(stopped[@"copiedCount"],@1);
        NSString *partialPlaylist=[NSString stringWithContentsOfURL:[root URLByAppendingPathComponent:@"destination/Mix/Mix.m3u8"] encoding:NSUTF8StringEncoding error:nil];
        XCTAssertEqualObjects(partialPlaylist,@"#EXTM3U\nArtist - One.mp3\n");
        IGUSBExportTestService *restarted=[[[IGUSBExportTestService alloc] initWithJournalDirectory:[root URLByAppendingPathComponent:@"journals"]] autorelease];restarted.blockCapacityForPartial=YES;
        NSArray *warnings=nil;NSArray *pending=[restarted pendingJobsWithWarnings:&warnings];XCTAssertEqual([pending count],(NSUInteger)1);XCTAssertEqual([warnings count],(NSUInteger)0);
        NSURL *steps=[[root URLByAppendingPathComponent:@"journals"] URLByAppendingPathComponent:[NSString stringWithFormat:@"cocoa-%@.steps",stopped[@"jobID"]]];
        unsigned char tail[]={0x7b,0xf0};[[NSData dataWithBytes:tail length:2] writeToURL:steps atomically:YES];
        XCTAssertEqual([[restarted pendingJobsWithWarnings:&warnings] count],(NSUInteger)1);XCTAssertEqual([warnings count],(NSUInteger)0);
        NSDictionary *finished=[restarted performResumeJobWithIdentifier:stopped[@"jobID"] destination:[root URLByAppendingPathComponent:@"destination"] progress:nil cancel:nil];
        XCTAssertEqualObjects(finished[@"status"],@"completed");XCTAssertEqualObjects(finished[@"existingCount"],@1);XCTAssertEqualObjects(finished[@"copiedCount"],@1);XCTAssertEqual([IGUSBTestMusicNames(root) count],(NSUInteger)2);
        for(NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[root URLByAppendingPathComponent:@"destination/Mix"] path] error:nil])XCTAssertFalse([name hasPrefix:@".syncrosa-part-"]);
        XCTAssertEqualObjects([NSString stringWithContentsOfURL:[root URLByAppendingPathComponent:@"destination/Mix/Mix.m3u8"] encoding:NSUTF8StringEncoding error:nil],@"#EXTM3U\nArtist - One.mp3\nArtist - Two.mp3\n");
    } @finally { [[NSFileManager defaultManager] removeItemAtURL:root error:nil]; }
}
- (void)testUSBRejectsWrongRootAndCorruptManifestWithoutChangingFiles {
    NSURL *root=IGUSBTestFolder();
    @try {
        NSDictionary *track=IGUSBTestTrack(root,@"source.mp3",@"Song",[@"AAAA" dataUsingEncoding:NSUTF8StringEncoding]);
        IGUSBExportService *service=[[[IGUSBExportService alloc] initWithJournalDirectory:[root URLByAppendingPathComponent:@"journals"]] autorelease];
        NSDictionary *stopped=[service performExportTracks:@[track] destination:[root URLByAppendingPathComponent:@"destination"] playlistName:@"Mix" options:@{} progress:nil cancel:^BOOL{return YES;}];
        NSDictionary *wrong=[service performResumeJobWithIdentifier:stopped[@"jobID"] destination:[root URLByAppendingPathComponent:@"other"] progress:nil cancel:nil];
        XCTAssertEqualObjects(wrong[@"status"],@"paused");XCTAssertEqualObjects(wrong[@"copiedCount"],@0);XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[[root URLByAppendingPathComponent:@"other/Mix"] path]]);
        NSURL *manifest=[root URLByAppendingPathComponent:@"destination/Mix/.syncrosa-export.json"];
        NSDictionary *bad=@{@"schemaVersion":@1,@"folderID":[[NSUUID UUID] UUIDString],@"entries":@[@{@"sourceKey":[@"path:" stringByAppendingString:[@"" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0]],@"filename":@"../escape.mp3",@"size":@4,@"sha256":[@"" stringByPaddingToLength:64 withString:@"b" startingAtIndex:0]}]};
        [[NSJSONSerialization dataWithJSONObject:bad options:0 error:nil] writeToURL:manifest atomically:YES];
        NSDictionary *result=[service performExportTracks:@[track] destination:[root URLByAppendingPathComponent:@"destination"] playlistName:@"Mix" options:@{} progress:nil cancel:nil];
        XCTAssertEqualObjects(result[@"status"],@"paused");XCTAssertEqualObjects(result[@"copiedCount"],@0);XCTAssertEqual([IGUSBTestMusicNames(root) count],(NSUInteger)0);
    } @finally { [[NSFileManager defaultManager] removeItemAtURL:root error:nil]; }
}
- (void)testUSBSymlinkFolderAndCrossProcessLockNeverWriteThrough {
    NSURL *root=IGUSBTestFolder();
    @try {
        NSDictionary *track=IGUSBTestTrack(root,@"source.mp3",@"Song",[@"AAAA" dataUsingEncoding:NSUTF8StringEncoding]);
        NSURL *mix=[root URLByAppendingPathComponent:@"destination/Mix"];
        [[NSFileManager defaultManager] createSymbolicLinkAtPath:[mix path] withDestinationPath:[[root URLByAppendingPathComponent:@"other"] path] error:nil];
        IGUSBExportService *service=[[[IGUSBExportService alloc] initWithJournalDirectory:[root URLByAppendingPathComponent:@"journals"]] autorelease];
        NSDictionary *unsafe=[service performExportTracks:@[track] destination:[root URLByAppendingPathComponent:@"destination"] playlistName:@"Mix" options:@{} progress:nil cancel:nil];XCTAssertEqualObjects(unsafe[@"status"],@"paused");
        XCTAssertEqual([[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[root URLByAppendingPathComponent:@"other"] path] error:nil] count],(NSUInteger)0);
        [[NSFileManager defaultManager] removeItemAtURL:mix error:nil];[[NSFileManager defaultManager] createDirectoryAtURL:mix withIntermediateDirectories:NO attributes:nil error:nil];
        int fd=open([[[mix URLByAppendingPathComponent:@".syncrosa-export.lock"] path] fileSystemRepresentation],O_RDWR|O_CREAT,0600);flock(fd,LOCK_EX|LOCK_NB);
        NSDictionary *busy=[service performExportTracks:@[track] destination:[root URLByAppendingPathComponent:@"destination"] playlistName:@"Mix" options:@{} progress:nil cancel:nil];
        flock(fd,LOCK_UN);close(fd);XCTAssertEqualObjects(busy[@"status"],@"paused");XCTAssertEqual([IGUSBTestMusicNames(root) count],(NSUInteger)0);
        XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[[mix URLByAppendingPathComponent:@".syncrosa-export.json"] path]]);
    } @finally { [[NSFileManager defaultManager] removeItemAtURL:root error:nil]; }
}
- (void)testUSBStablePersistentIDReusesAudioAfterLibraryMetadataAndPathChange {
    NSURL *root=IGUSBTestFolder();
    @try {
        NSDictionary *original=IGUSBTestTrack(root,@"source.mp3",@"Before",[@"AAAA" dataUsingEncoding:NSUTF8StringEncoding]);
        NSMutableDictionary *first=[NSMutableDictionary dictionaryWithDictionary:original];first[@"persistentID"]=@"AABBCCDDEEFF0011";
        IGUSBExportService *service=[[[IGUSBExportService alloc] initWithJournalDirectory:[root URLByAppendingPathComponent:@"journals"]] autorelease];
        NSDictionary *initial=[service performExportTracks:@[first] destination:[root URLByAppendingPathComponent:@"destination"] playlistName:@"Mix" options:@{} progress:nil cancel:nil];XCTAssertEqualObjects(initial[@"copiedCount"],@1);
        NSString *renamed=[[root URLByAppendingPathComponent:@"sources/renamed.mp3"] path];
        [[NSFileManager defaultManager] moveItemAtPath:first[@"path"] toPath:renamed error:nil];
        NSMutableDictionary *updated=[NSMutableDictionary dictionaryWithDictionary:first];updated[@"path"]=renamed;updated[@"name"]=@"After";updated[@"artist"]=@"Another Artist";
        NSDictionary *result=[service performExportTracks:@[updated] destination:[root URLByAppendingPathComponent:@"destination"] playlistName:@"Mix" options:@{} progress:nil cancel:nil];
        XCTAssertEqualObjects(result[@"status"],@"completed");XCTAssertEqualObjects(result[@"copiedCount"],@0);XCTAssertEqualObjects(result[@"existingCount"],@1);XCTAssertEqual([IGUSBTestMusicNames(root) count],(NSUInteger)1);
    } @finally { [[NSFileManager defaultManager] removeItemAtURL:root error:nil]; }
}
- (void)testUSBFitSelectionStaysStableAcrossCancellationAndLargerCapacity {
    NSURL *root=IGUSBTestFolder();
    @try {
        NSArray *tracks=@[IGUSBTestTrack(root,@"one.mp3",@"One",[@"AAAA" dataUsingEncoding:NSUTF8StringEncoding]),IGUSBTestTrack(root,@"two.mp3",@"Two",[@"BBBB" dataUsingEncoding:NSUTF8StringEncoding]),IGUSBTestTrack(root,@"three.mp3",@"Three",[@"CCCC" dataUsingEncoding:NSUTF8StringEncoding])];
        IGUSBExportTestService *service=[[[IGUSBExportTestService alloc] initWithJournalDirectory:[root URLByAppendingPathComponent:@"journals"]] autorelease];service.availableOverride=6;
        __block BOOL cancel=NO;
        NSDictionary *stopped=[service performExportTracks:tracks destination:[root URLByAppendingPathComponent:@"destination"] playlistName:@"Mix" options:@{@"fitAvailable":@YES} progress:^(NSDictionary *progress){if([progress[@"fileBytes"] longLongValue]>0)cancel=YES;} cancel:^BOOL{return cancel;}];
        XCTAssertEqualObjects(stopped[@"status"],@"cancelled");XCTAssertEqualObjects(stopped[@"skippedSpace"],@2);
        service.availableOverride=1000;
        NSDictionary *resumed=[service performResumeJobWithIdentifier:stopped[@"jobID"] destination:[root URLByAppendingPathComponent:@"destination"] progress:nil cancel:nil];
        XCTAssertEqualObjects(resumed[@"status"],@"completed");XCTAssertEqualObjects(resumed[@"copiedCount"],@1);XCTAssertEqualObjects(resumed[@"skippedSpace"],@2);XCTAssertEqual([IGUSBTestMusicNames(root) count],(NSUInteger)1);
        NSURL *badJournal=[[root URLByAppendingPathComponent:@"journals"] URLByAppendingPathComponent:[NSString stringWithFormat:@"cocoa-%@.json",[[NSUUID UUID] UUIDString]]];
        [[@"{" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:badJournal atomically:YES];
        NSArray *warnings=nil;[service pendingJobsWithWarnings:&warnings];XCTAssertEqual([warnings count],(NSUInteger)1);XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[badJournal path]]);
    } @finally { [[NSFileManager defaultManager] removeItemAtURL:root error:nil]; }
}
- (void)testUSBRepeatedTrackCopiesOnceAndCaseCollisionsRemainDistinct {
    NSURL *root=IGUSBTestFolder();
    @try {
        NSDictionary *first=IGUSBTestTrack(root,@"one.mp3",@"Song",[@"AAAA" dataUsingEncoding:NSUTF8StringEncoding]);
        NSDictionary *second=IGUSBTestTrack(root,@"two.mp3",@"song",[@"BBBB" dataUsingEncoding:NSUTF8StringEncoding]);
        IGUSBExportService *service=[[[IGUSBExportService alloc] initWithJournalDirectory:[root URLByAppendingPathComponent:@"journals"]] autorelease];
        NSDictionary *result=[service performExportTracks:@[first,first,second] destination:[root URLByAppendingPathComponent:@"destination"] playlistName:@"Mix" options:@{@"m3u8":@YES} progress:nil cancel:nil];
        XCTAssertEqualObjects(result[@"status"],@"completed");XCTAssertEqualObjects(result[@"copiedCount"],@2);XCTAssertEqualObjects(result[@"existingCount"],@1);XCTAssertEqual([IGUSBTestMusicNames(root) count],(NSUInteger)2);
        NSString *playlist=[NSString stringWithContentsOfURL:[root URLByAppendingPathComponent:@"destination/Mix/Mix.m3u8"] encoding:NSUTF8StringEncoding error:nil];
        XCTAssertEqualObjects(playlist,@"#EXTM3U\nArtist - Song.mp3\nArtist - Song.mp3\nArtist - song_2.mp3\n");
        NSString *longTitle=[@"" stringByPaddingToLength:80 withString:@"🎵" startingAtIndex:0];
        NSDictionary *unicode=IGUSBTestTrack(root,@"unicode.mp3",longTitle,[@"CCCC" dataUsingEncoding:NSUTF8StringEncoding]);
        NSDictionary *unicodeResult=[service performExportTracks:@[unicode] destination:[root URLByAppendingPathComponent:@"destination"] playlistName:@"Unicode" options:@{} progress:nil cancel:nil];
        XCTAssertEqualObjects(unicodeResult[@"status"],@"completed");XCTAssertEqualObjects(unicodeResult[@"copiedCount"],@1);
    } @finally { [[NSFileManager defaultManager] removeItemAtURL:root error:nil]; }
}

- (void)testMusicMatchingKeepsRecordingVersionsAndRejectsAmbiguousEditions {
    NSDictionary *studio = @{@"artistName": @"The Artist", @"trackName": @"A Song", @"collectionName": @"Original Album", @"trackNumber": @2};
    NSDictionary *live = @{@"artistName": @"The Artist", @"trackName": @"A Song (Live)", @"collectionName": @"Concert", @"trackNumber": @7};
    NSDictionary *compilation = @{@"artistName": @"The Artist", @"trackName": @"A Song", @"collectionName": @"Greatest Hits", @"trackNumber": @9};
    NSDictionary *match = IGMediaBestAppleMusicMatch(@[studio, live], @"THE ARTIST", @"A Song [Live]", @"");
    XCTAssertEqualObjects(match[@"alb"], @"Concert");
    XCTAssertNil(IGMediaBestAppleMusicMatch(@[live], @"The Artist", @"A Song", @""));
    XCTAssertNil(IGMediaBestAppleMusicMatch(@[studio, compilation], @"The Artist", @"A Song", @""));
    XCTAssertEqualObjects(IGMediaBestAppleMusicMatch(@[compilation, studio], @"The Artist", @"A Song", @"Original Album")[@"trackNumber"], @2);
    XCTAssertNil(IGMediaBestAppleMusicMatch(@[studio], @"Other Artist", @"A Song", @""));
    XCTAssertNil(IGMediaBestAppleMusicMatch(@[studio], @"", @"A Song", @""));
}

- (void)testMissingMetadataRepairPreservesExistingLyricsAndDisabledFields {
    NSDictionary *track = @{@"title": @"Original", @"artist": @"Artist", @"album": @"Album", @"genre": @"", @"trackNumber": @3, @"hasLyrics": @YES};
    NSDictionary *metadata = @{@"title": @"Replacement", @"art": @"New Artist", @"alb": @"Other Album", @"gen": @"Rock", @"trackNumber": @9};
    NSDictionary *options = @{@"title": @YES, @"artist": @YES, @"album": @YES, @"genre": @YES, @"trackNumber": @YES, @"lyrics": @YES};
    XCTAssertEqualObjects(IGMediaMissingMetadataProperties(track, metadata, @"New lyrics", options), (@{@"genre": @"Rock"}));
    NSMutableDictionary *missingLyrics = [NSMutableDictionary dictionaryWithDictionary:track];
    missingLyrics[@"hasLyrics"] = @NO;
    XCTAssertEqualObjects(IGMediaMissingMetadataProperties(missingLyrics, metadata, @"New lyrics", @{@"lyrics": @YES}), (@{@"lyrics": @"New lyrics"}));
    XCTAssertEqualObjects(IGMediaMissingMetadataProperties(missingLyrics, metadata, @"New lyrics", @{}), (@{}));
}

- (void)testMetadataRepairReportsRealWritesAndErrorsWithoutTouchingITunes {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id savedLocalMode = [[defaults objectForKey:@"only_local_mode"] retain];
    [defaults setBool:NO forKey:@"only_local_mode"];
    IGMetadataRepairTestManager *manager = [[[IGMetadataRepairTestManager alloc] init] autorelease];
    manager.testLibrary = [[[IGMetadataRepairTestLibrary alloc] init] autorelease];
    manager.testLibrary.rows = @"0000000000000001\tComplete\tArtist\tAlbum\tRock\t1\tYES\n"
                               "0000000000000002\tMissing Genre\tArtist\tAlbum\t\t1\tYES\n"
                               "0000000000000003\tUnmatched\tArtist\tAlbum\t\t1\tYES\n"
                               "0000000000000004\tNetwork Error\tArtist\tAlbum\t\t1\tYES\n"
                               "0000000000000005\tWrite Error\tArtist\tAlbum\t\t1\tYES\n"
                               "0000000000000006\tLyrics Error\tArtist\tAlbum\tRock\t1\tNO\n"
                               "0000000000000007\tRace\tArtist\tAlbum\t\t1\tYES\n"
                               "0000000000000008\tPartial\tArtist\tAlbum\t\t1\tNO\n"
                               "0000000000000009\tUnreadable Lyrics\tArtist\tAlbum\tRock\t1\tUNKNOWN\n"
                               "0000000000000010\tUnreadable Number\tArtist\tAlbum\tRock\t-1\tYES\n";
    XCTestExpectation *finished = [self expectationWithDescription:@"offline metadata repair"];
    [manager runMetadataFixWithOptions:@{@"genre": @YES, @"lyrics": @YES, @"trackNumber": @YES} progress:nil reportCompletion:^(NSDictionary *report) {
        XCTAssertEqualObjects(report[@"total"], @10);
        XCTAssertEqualObjects(report[@"changed"], @2);
        XCTAssertEqualObjects(report[@"skipped"], @2);
        XCTAssertEqualObjects(report[@"noMatch"], @1);
        XCTAssertEqualObjects(report[@"errors"], @6);
        XCTAssertEqualObjects(report[@"changedIDs"], (@[@"0000000000000002", @"0000000000000008"]));
        XCTAssertEqual(manager.lyricsRequests, (NSInteger)2);
        XCTAssertTrue([manager.testLibrary.lastUpdateScript rangeOfString:@"set existingValue to genre of t"].location != NSNotFound);
        XCTAssertTrue([manager.testLibrary.lastUpdateScript rangeOfString:@"changedFields"].location != NSNotFound);
        [finished fulfill];
    }];
    @try {
        [self waitForExpectationsWithTimeout:5.0 handler:nil];
    } @finally {
        if (savedLocalMode) [defaults setObject:savedLocalMode forKey:@"only_local_mode"];
        else [defaults removeObjectForKey:@"only_local_mode"];
        [savedLocalMode release];
    }
}

- (void)testExternalAgentJSONValidationRequiresOnlyKnownCatalogIDs {
    NSString *identifier = @"A1B2C3D4E5F67890";
    NSSet *available = [NSSet setWithObject:identifier];
    XCTAssertNil(IGPlaylistJSONSelectionValidationError(@{@"playlistName": @"Mix", @"trackIDs": @[identifier]}, available));
    XCTAssertNotNil(IGPlaylistJSONSelectionValidationError(@{@"trackIDs": @[identifier, @"1111111111111111"]}, available));
    XCTAssertNotNil(IGPlaylistJSONSelectionValidationError(@{@"schema": @"syncrosa-itunes-library-v1", @"tracks": @[@{@"persistentID": identifier}]}, available));
    XCTAssertNotNil(IGPlaylistJSONSelectionValidationError(@{@"tracks": @[[NSNull null]]}, available));
    XCTAssertNil(IGPlaylistJSONSelectionValidationError(@[identifier], available));
    XCTAssertNil(IGPlaylistJSONSelectionValidationError(@[@{@"id": identifier}], available));
    XCTAssertNotNil(IGPlaylistJSONSelectionValidationError(@[identifier, [NSNull null]], available));
    XCTAssertNotNil(IGPlaylistJSONSelectionValidationError(@[identifier, @"1111111111111111"], available));
    XCTAssertNotNil(IGPlaylistJSONSelectionValidationError(@{@"schema": @42, @"trackIDs": @[identifier]}, available));
}

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
    track.fileSizeBytes = 123456789ULL;
    NSDictionary *json = IGPlaylistJSONObjectForTrack(track);
    XCTAssertEqualObjects([json objectForKey:@"persistentID"], @"ABCDEF12");
    XCTAssertEqualObjects([json objectForKey:@"id"], @"ABCDEF12");
    XCTAssertEqualObjects([json objectForKey:@"title"], @"Children");
    XCTAssertEqualObjects([json objectForKey:@"artist"], @"Robert Miles");
    XCTAssertEqualObjects([json objectForKey:@"album"], @"Dreamland");
    XCTAssertEqualObjects([json objectForKey:@"genre"], @"Trance");
    XCTAssertEqualObjects([json objectForKey:@"year"], @1996);
    XCTAssertEqualObjects([json objectForKey:@"fileSizeBytes"], @123456789ULL);
    XCTAssertTrue([[json objectForKey:@"fileSize"] length] > 0);
}

- (void)testOperationActivityPreventsOverlappingJobs {
    IGOperationActivity *activity = [IGOperationActivity sharedActivity];
    [activity finishOperationWithIdentifier:activity.activeIdentifier];

    XCTAssertTrue([activity beginOperationWithIdentifier:IGOperationActivityUSBExportIdentifier]);
    XCTAssertTrue([activity isOperationActiveWithIdentifier:IGOperationActivityUSBExportIdentifier]);
    XCTAssertFalse([activity beginOperationWithIdentifier:IGOperationActivityAIPlaylistIdentifier]);

    [activity finishOperationWithIdentifier:IGOperationActivityUSBExportIdentifier];
    XCTAssertTrue([activity beginOperationWithIdentifier:IGOperationActivityAIPlaylistIdentifier]);
    [activity finishOperationWithIdentifier:IGOperationActivityAIPlaylistIdentifier];
    XCTAssertNil(activity.activeIdentifier);
}

- (void)testEpisodeDisplayTitleSortsLegacyIPodEpisodesAndAvoidsDuplicatePrefixes {
    XCTAssertEqualObjects([IGVideoFileMetadataService episodeDisplayTitleForTitle:@"Ash Catches a Pokémon"
                                                                      seasonNumber:1
                                                                     episodeNumber:1],
                          @"S1E01 — Ash Catches a Pokémon");
    XCTAssertEqualObjects([IGVideoFileMetadataService episodeDisplayTitleForTitle:@"S01E05 - Showdown in Pewter City"
                                                                      seasonNumber:1
                                                                     episodeNumber:5],
                          @"S1E05 — Showdown in Pewter City");
    XCTAssertEqualObjects([IGVideoFileMetadataService episodeDisplayTitleForTitle:@"S1E09 — The School of Hard Knocks"
                                                                      seasonNumber:1
                                                                     episodeNumber:9],
                          @"S1E09 — The School of Hard Knocks");
    XCTAssertEqualObjects([IGVideoFileMetadataService episodeDisplayTitleForTitle:@"Movie Title"
                                                                      seasonNumber:0
                                                                     episodeNumber:0],
                          @"Movie Title");
}

- (void)testAppleVideoParserKeepsSeasonResultsAndFormatsSpecificEpisodes {
    NSDictionary *seasonJSON = @{@"results": @[@{
        @"collectionName": @"Pokémon, Season 1",
        @"artistName": @"Pokémon",
        @"releaseDate": @"1998-09-08T07:00:00Z",
        @"primaryGenreName": @"Animation"
    }]};
    NSData *seasonData = [NSJSONSerialization dataWithJSONObject:seasonJSON options:0 error:nil];
    NSArray *seasonMatches = IGMediaAppleVideoMatchesFromData(seasonData, YES, 0, 0);
    XCTAssertEqual([seasonMatches count], (NSUInteger)1);
    XCTAssertEqualObjects([[seasonMatches objectAtIndex:0] objectForKey:@"name"], @"Pokémon, Season 1");
    XCTAssertEqualObjects([[seasonMatches objectAtIndex:0] objectForKey:@"episodeNumber"], @0);
    XCTAssertEqualObjects([[seasonMatches objectAtIndex:0] objectForKey:@"displayTitle"], @"Pokémon, Season 1 (1998) — Animation");

    NSDictionary *episodeJSON = @{@"results": @[@{
        @"trackName": @"Showdown in Pewter City",
        @"collectionName": @"Pokémon, Season 1",
        @"artistName": @"Pokémon",
        @"trackNumber": @5,
        @"releaseDate": @"1998-09-14T07:00:00Z"
    }]};
    NSData *episodeData = [NSJSONSerialization dataWithJSONObject:episodeJSON options:0 error:nil];
    NSArray *episodeMatches = IGMediaAppleVideoMatchesFromData(episodeData, YES, 1, 5);
    XCTAssertEqual([episodeMatches count], (NSUInteger)1);
    XCTAssertEqualObjects([[episodeMatches objectAtIndex:0] objectForKey:@"name"], @"Showdown in Pewter City");
    XCTAssertEqualObjects([[episodeMatches objectAtIndex:0] objectForKey:@"episodeNumber"], @5);
    XCTAssertEqualObjects([[episodeMatches objectAtIndex:0] objectForKey:@"displayTitle"],
                          @"Pokémon — S01E05 Showdown in Pewter City (1998)");
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
    XCTAssertEqual(IGNavigationItemCount, (NSInteger)14);
    XCTAssertTrue(IGNavigationItemRequiresReadableLibrary(IGNavigationItemAIPlaylist));
    XCTAssertTrue(IGNavigationItemRequiresReadableLibrary(IGNavigationItemLibraryDoctor));
    XCTAssertTrue(IGNavigationItemRequiresReadableLibrary(IGNavigationItemUSBExport));
    XCTAssertFalse(IGNavigationItemRequiresReadableLibrary(IGNavigationItemVideoMetadata));
    XCTAssertFalse(IGNavigationItemRequiresReadableLibrary(IGNavigationItemOverview));
    XCTAssertFalse(IGNavigationItemRequiresReadableLibrary(IGNavigationItemFolderFixer));
    XCTAssertFalse(IGNavigationItemRequiresReadableLibrary(IGNavigationItemIPodConverter));
    XCTAssertFalse(IGNavigationItemRequiresReadableLibrary(IGNavigationItemInfoEraser));
    XCTAssertFalse(IGNavigationItemRequiresReadableLibrary(IGNavigationItemRecoveryCenter));
    XCTAssertFalse(IGNavigationItemRequiresReadableLibrary(IGNavigationItemSettings));
}

- (void)testIPodConverterBuildsSafeNonDestructiveDestinationNames {
    NSURL *directory = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    NSURL *source = [NSURL fileURLWithPath:@"/tmp/Long: Mix?.mp3"];
    NSURL *destination = [IGIPodCompatibilityService destinationURLForSourceURL:source
                                                                   directoryURL:directory
                                                                    fileManager:[NSFileManager defaultManager]];
    XCTAssertTrue([[destination lastPathComponent] hasSuffix:@"(iPod).m4a"] ||
                  [[destination lastPathComponent] rangeOfString:@"(iPod "].location != NSNotFound);
    XCTAssertNotEqualObjects(destination, source);
    XCTAssertTrue([IGIPodCompatibilityService isSupportedFileURL:source]);
    XCTAssertFalse([IGIPodCompatibilityService isSupportedFileURL:[NSURL fileURLWithPath:@"/tmp/notes.txt"]]);
    NSArray *issues = [IGIPodCompatibilityService compatibilityIssuesForFileURL:[NSURL fileURLWithPath:@"/tmp/notes.txt"]
                                                                        deepScan:YES];
    XCTAssertTrue([issues count] > 0);
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

- (void)testVideoFilenameHintsRecognizeMoviesAndEpisodes {
    NSDictionary *movie = [IGVideoFileMetadataService filenameHintsForURL:[NSURL fileURLWithPath:@"/tmp/Star_Wars_Episode_III.m4v"]];
    XCTAssertEqualObjects([movie objectForKey:@"videoKind"], @"Movie");
    XCTAssertEqualObjects([movie objectForKey:@"name"], @"Star Wars Episode III");

    NSDictionary *episode = [IGVideoFileMetadataService filenameHintsForURL:[NSURL fileURLWithPath:@"/tmp/The.Show.S02E07.Chapter_Name.mp4"]];
    XCTAssertEqualObjects([episode objectForKey:@"videoKind"], @"TV Show");
    XCTAssertEqualObjects([episode objectForKey:@"show"], @"The Show");
    XCTAssertEqualObjects([episode objectForKey:@"name"], @"Chapter Name");
    XCTAssertEqualObjects([episode objectForKey:@"seasonNumber"], @2);
    XCTAssertEqualObjects([episode objectForKey:@"episodeNumber"], @7);

    NSDictionary *pokemon = [IGVideoFileMetadataService filenameHintsForName:@"Pokemon 1x05 Showdown in Pewter City"];
    XCTAssertEqualObjects([pokemon objectForKey:@"videoKind"], @"TV Show");
    XCTAssertEqualObjects([pokemon objectForKey:@"show"], @"Pokemon");
    XCTAssertEqualObjects([pokemon objectForKey:@"name"], @"Showdown in Pewter City");
    XCTAssertEqualObjects([pokemon objectForKey:@"seasonNumber"], @1);
    XCTAssertEqualObjects([pokemon objectForKey:@"episodeNumber"], @5);

    NSDictionary *lowercase = [IGVideoFileMetadataService filenameHintsForName:@"Pokemon 01x006 Clefairy and the Moon Stone"];
    XCTAssertEqualObjects([lowercase objectForKey:@"videoKind"], @"TV Show");
    XCTAssertEqualObjects([lowercase objectForKey:@"seasonNumber"], @1);
    XCTAssertEqualObjects([lowercase objectForKey:@"episodeNumber"], @6);
    XCTAssertEqualObjects([lowercase objectForKey:@"name"], @"Clefairy and the Moon Stone");
}

- (void)testVideoMetadataCommentPreservesTelevisionNumbers {
    NSDictionary *numbers = [IGVideoFileMetadataService televisionHintsForMetadataComment:@"User note stays here\nSyncrosa TV S02E107"];
    XCTAssertEqualObjects([numbers objectForKey:@"seasonNumber"], @2);
    XCTAssertEqualObjects([numbers objectForKey:@"episodeNumber"], @107);
    XCTAssertNil([IGVideoFileMetadataService televisionHintsForMetadataComment:@"ordinary comment"]);
}

- (void)testVideoFolderScanIsRecursiveAndLimitedToSafeContainers {
    NSString *rootPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
    NSString *nestedPath = [rootPath stringByAppendingPathComponent:@"Season 1"];
    NSFileManager *manager = [NSFileManager defaultManager];
    XCTAssertTrue([manager createDirectoryAtPath:nestedPath withIntermediateDirectories:YES attributes:nil error:nil]);
    [manager createFileAtPath:[rootPath stringByAppendingPathComponent:@"Movie.M4V"] contents:[NSData data] attributes:nil];
    [manager createFileAtPath:[nestedPath stringByAppendingPathComponent:@"Episode.mp4"] contents:[NSData data] attributes:nil];
    [manager createFileAtPath:[rootPath stringByAppendingPathComponent:@"Unsupported.mkv"] contents:[NSData data] attributes:nil];
    [manager createFileAtPath:[rootPath stringByAppendingPathComponent:@".hidden.mp4"] contents:[NSData data] attributes:nil];
    [manager createFileAtPath:[rootPath stringByAppendingPathComponent:@"Movie.syncrosa-backup.m4v"] contents:[NSData data] attributes:nil];

    NSArray *videos = [IGVideoFileMetadataService videoFileURLsInDirectory:[NSURL fileURLWithPath:rootPath]];
    XCTAssertEqual([videos count], (NSUInteger)2);
    XCTAssertTrue([[[videos objectAtIndex:0] path] hasSuffix:@"Movie.M4V"]);
    XCTAssertTrue([[[videos objectAtIndex:1] path] hasSuffix:@"Episode.mp4"]);
    XCTAssertTrue([manager removeItemAtPath:rootPath error:nil]);
}

@end
