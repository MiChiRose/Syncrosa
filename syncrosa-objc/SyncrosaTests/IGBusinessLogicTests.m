#import <Cocoa/Cocoa.h>
#import <XCTest/XCTest.h>
#import "IGTrack.h"
#import "IGMediaFixerManager.h"

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

@end
