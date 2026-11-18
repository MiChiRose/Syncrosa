#import <Cocoa/Cocoa.h>

@interface IGSettingsViewController : NSViewController

- (void)refreshOpenRouterModelsIfNeeded;
- (void)checkForUpdatesOnLaunch;
- (void)checkForUpdatesManually:(BOOL)manual;

@end
