#import <Cocoa/Cocoa.h>
#import "IGGeniusViewController.h"
#import "IGFixerViewController.h"

typedef NS_ENUM(NSInteger, IGNavigationItem) {
    IGNavigationItemOverview = 0,
    IGNavigationItemAIPlaylist,
    IGNavigationItemMediaFixer,
    IGNavigationItemFolderFixer,
    IGNavigationItemIPodConverter,
    IGNavigationItemUSBExport,
    IGNavigationItemCoversOptimizer,
    IGNavigationItemDuplicateFinder,
    IGNavigationItemOfflinePlaylist,
    IGNavigationItemInfoEraser,
    IGNavigationItemLibraryDoctor,
    IGNavigationItemRecoveryCenter,
    IGNavigationItemSettings,
    IGNavigationItemCount
};

FOUNDATION_EXPORT BOOL IGNavigationItemRequiresReadableLibrary(IGNavigationItem item);
FOUNDATION_EXPORT NSRect IGCenteredLegacyPageFrame(NSSize preferredSize, NSRect availableBounds);
FOUNDATION_EXPORT BOOL IGTextIsEmbeddedLegacyFooter(NSString *text);
FOUNDATION_EXPORT NSString * const IGFooterVisibilityDidChangeNotification;

@interface IGMainWindowController : NSWindowController

- (void)updateButtonStates;
- (NSString *)overviewLibraryStatusText;
- (BOOL)overviewLibraryToolsAvailable;
- (void)switchViewToIndex:(NSInteger)index;
- (BOOL)refreshLibraryStatusWithCompletion:(void(^)(void))completionBlock;
+ (BOOL)globalFooterVisible;
+ (void)setGlobalFooterVisible:(BOOL)visible;

@end
