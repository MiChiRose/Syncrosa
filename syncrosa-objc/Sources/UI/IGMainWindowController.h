#import <Cocoa/Cocoa.h>
#import "IGGeniusViewController.h"
#import "IGFixerViewController.h"

@interface IGMainWindowController : NSWindowController

- (void)updateButtonStates;
- (void)switchViewToIndex:(NSInteger)index;
- (BOOL)refreshLibraryStatusWithCompletion:(void(^)(void))completionBlock;

@end
