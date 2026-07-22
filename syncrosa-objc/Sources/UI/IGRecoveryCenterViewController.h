#import <Cocoa/Cocoa.h>

FOUNDATION_EXPORT NSArray *IGRecoverySanitizedHistoryEntries(id value);

@interface IGRecoveryCenterViewController : NSViewController <NSTableViewDataSource>

- (void)reloadRecoveryData;

@end
