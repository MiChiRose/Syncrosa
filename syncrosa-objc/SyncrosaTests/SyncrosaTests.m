//
//  SyncrosaTests.m
//  SyncrosaTests
//
//  Created by MacBook Pro on 6/11/26.
//  Copyright (c) 2026 MacBook Pro. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <XCTest/XCTest.h>
#import "IGOperationActivity.h"

@interface SyncrosaTests : XCTestCase

@end

@implementation SyncrosaTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testExample {
    // This is an example of a functional test case.
    XCTAssert(YES, @"Pass");
}


- (NSString *)recoveryTestDirectory {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"syncrosa-recovery-test-" stringByAppendingString:[[NSProcessInfo processInfo] globallyUniqueString]]];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    return path;
}

- (NSDictionary *)recoveryTestMarker:(NSString *)identifier {
    return @{@"id": identifier, @"tool": @"Folder Fixer", @"title": @"Rename", @"message": @"Interrupted",
             @"startedAt": @([[NSDate date] timeIntervalSince1970]), @"affectedCount": @2, @"backupPath": @"/preserved/backup"};
}

- (void)testRecoveryRegistryKeepsOtherOperationsWhenOneFinishes {
    NSString *directory = [self recoveryTestDirectory];
    @try {
        IGOperationActivity *first = [[[IGOperationActivity alloc] initWithRecoveryDirectory:directory] autorelease];
        XCTAssertTrue([first saveRecoveryMarker:[self recoveryTestMarker:@"first"] error:NULL]);
        XCTAssertTrue([first saveRecoveryMarker:[self recoveryTestMarker:@"second"] error:NULL]);
        XCTAssertEqual([first.recoveryMarkers count], (NSUInteger)0);
        IGOperationActivity *restored = [[[IGOperationActivity alloc] initWithRecoveryDirectory:directory] autorelease];
        XCTAssertEqual([restored.recoveryMarkers count], (NSUInteger)2);
        XCTAssertTrue([restored saveRecoveryMarker:[self recoveryTestMarker:@"third"] error:NULL]);
        XCTAssertTrue([restored finishRecoveryMarkerWithIdentifier:@"third" error:NULL]);
        XCTAssertTrue([restored finishRecoveryMarkerWithIdentifier:nil error:NULL]);
        XCTAssertEqual([restored.recoveryMarkers count], (NSUInteger)2);
        XCTAssertTrue([restored clearRecoveryMarkerWithIdentifier:@"first" error:NULL]);
        IGOperationActivity *again = [[[IGOperationActivity alloc] initWithRecoveryDirectory:directory] autorelease];
        XCTAssertEqual([again.recoveryMarkers count], (NSUInteger)1);
        XCTAssertEqualObjects(again.recoveryMarkers[0][@"id"], @"second");
        XCTAssertFalse([first clearRecoveryMarkerWithIdentifier:@"second" error:NULL]);
    } @finally { [[NSFileManager defaultManager] removeItemAtPath:directory error:nil]; }
}

- (void)testRecoveryRegistryPreservesCorruptRecordsAndReportsWarnings {
    NSString *directory = [self recoveryTestDirectory];
    @try {
        NSString *records = [[directory stringByAppendingPathComponent:@"Recovery Operations"] stringByAppendingPathComponent:@"Cocoa"];
        [[NSFileManager defaultManager] createDirectoryAtPath:records withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *invalid = [records stringByAppendingPathComponent:@"broken.plist"];
        NSData *bytes = [@"unfinished record" dataUsingEncoding:NSUTF8StringEncoding];
        [bytes writeToFile:invalid atomically:YES];
        NSString *legacy = [directory stringByAppendingPathComponent:@"active-operation.json"];
        [bytes writeToFile:legacy atomically:YES];
        IGOperationActivity *activity = [[[IGOperationActivity alloc] initWithRecoveryDirectory:directory] autorelease];
        XCTAssertEqual([activity.recoveryMarkers count], (NSUInteger)0);
        XCTAssertTrue([activity.recoveryWarnings count] >= 2);
        [activity clearRecoveryMarkerWithIdentifier:@"missing" error:NULL];
        XCTAssertEqualObjects([NSData dataWithContentsOfFile:invalid], bytes);
        XCTAssertEqualObjects([NSData dataWithContentsOfFile:legacy], bytes);
    } @finally { [[NSFileManager defaultManager] removeItemAtPath:directory error:nil]; }
}

- (void)testRecoveryRegistryMigratesLegacyFormatsWithoutDeletingBackups {
    NSString *directory = [self recoveryTestDirectory];
    @try {
        NSString *backup = [directory stringByAppendingPathComponent:@"saved-backup.bin"];
        NSData *backupData = [@"keep original bytes" dataUsingEncoding:NSUTF8StringEncoding];
        [backupData writeToFile:backup atomically:YES];
        NSMutableDictionary *marker = [NSMutableDictionary dictionaryWithDictionary:[self recoveryTestMarker:@"old-host_1234_5678"]];
        marker[@"backupPath"] = backup;
        NSString *plistPath = [directory stringByAppendingPathComponent:@"active-operation.plist"];
        [marker writeToFile:plistPath atomically:YES];
        NSMutableDictionary *json = [NSMutableDictionary dictionaryWithDictionary:[self recoveryTestMarker:@"00000000-0000-0000-0000-000000000001"]];
        json[@"startedAt"] = @"2026-11-03T10:00:00Z";
        NSString *jsonPath = [directory stringByAppendingPathComponent:@"active-operation.json"];
        [[NSJSONSerialization dataWithJSONObject:json options:0 error:nil] writeToFile:jsonPath atomically:YES];
        IGOperationActivity *activity = [[[IGOperationActivity alloc] initWithRecoveryDirectory:directory] autorelease];
        XCTAssertEqual([activity.recoveryMarkers count], (NSUInteger)2);
        XCTAssertEqual([activity.recoveryWarnings count], (NSUInteger)0);
        XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:plistPath]);
        XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:jsonPath]);
        XCTAssertTrue([activity clearRecoveryMarkerWithIdentifier:@"old-host_1234_5678" error:NULL]);
        XCTAssertEqualObjects([NSData dataWithContentsOfFile:backup], backupData);
        IGOperationActivity *again = [[[IGOperationActivity alloc] initWithRecoveryDirectory:directory] autorelease];
        XCTAssertEqual([again.recoveryMarkers count], (NSUInteger)1);
    } @finally { [[NSFileManager defaultManager] removeItemAtPath:directory error:nil]; }
}

- (void)testRecoveryMigrationFailurePreservesLegacyData {
    NSString *directory = [self recoveryTestDirectory];
    @try {
        NSString *legacy = [directory stringByAppendingPathComponent:@"active-operation.plist"];
        [[self recoveryTestMarker:@"legacy"] writeToFile:legacy atomically:YES];
        [[@"not a directory" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:[directory stringByAppendingPathComponent:@"Recovery Operations"] atomically:YES];
        IGOperationActivity *activity = [[[IGOperationActivity alloc] initWithRecoveryDirectory:directory] autorelease];
        XCTAssertTrue([activity.recoveryWarnings count] > 0);
        XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:legacy]);
        XCTAssertFalse([activity saveRecoveryMarker:[self recoveryTestMarker:@"new"] error:NULL]);
        XCTAssertTrue([activity.recoveryWarnings count] > 0);
    } @finally { [[NSFileManager defaultManager] removeItemAtPath:directory error:nil]; }
}

- (void)testOperationActivityRejectsDuplicateIdentifierWhileRunning {
    NSString *directory = [self recoveryTestDirectory];
    @try {
        IGOperationActivity *activity = [[[IGOperationActivity alloc] initWithRecoveryDirectory:directory] autorelease];
        XCTAssertTrue([activity beginOperationWithIdentifier:IGOperationActivityUSBExportIdentifier]);
        XCTAssertFalse([activity beginOperationWithIdentifier:IGOperationActivityUSBExportIdentifier]);
        XCTAssertFalse([activity beginOperationWithIdentifier:IGOperationActivityVideoMetadataIdentifier]);
        [activity finishOperationWithIdentifier:IGOperationActivityVideoMetadataIdentifier];
        XCTAssertTrue([activity isOperationActiveWithIdentifier:IGOperationActivityUSBExportIdentifier]);
        [activity finishOperationWithIdentifier:IGOperationActivityUSBExportIdentifier];
        XCTAssertTrue([activity beginOperationWithIdentifier:IGOperationActivityVideoMetadataIdentifier]);
    } @finally { [[NSFileManager defaultManager] removeItemAtPath:directory error:nil]; }
}

@end
