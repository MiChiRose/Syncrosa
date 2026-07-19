#import <Foundation/Foundation.h>
#import "IGTrack.h"

@interface IGiTunesService : NSObject

+ (instancetype)sharedService;

/**
 * Returns YES when iTunes is already running. This check does not launch iTunes.
 */
- (BOOL)iTunesIsRunning;

/**
 * Opens iTunes only after a user-facing confirmation happened in the UI layer.
 */
- (BOOL)launchITunesForUserActionWithOperation:(NSString *)operation;

/**
 * Checks whether the iTunes library is readable and how many tracks it has.
 * trackCount is -1 when the library cannot be read.
 */
- (void)fetchLibraryTrackCountWithCompletion:(void(^)(NSInteger trackCount, NSString *errorMessage))completionBlock;
- (NSInteger)readLibraryTrackCountSyncWithErrorMessage:(NSString **)errorMessage;

/**
 * Fetches all tracks from iTunes library playlist 1.
 * @param progressBlock A block called with (currentCount, totalCount).
 * @param completionBlock A block called with the array of IGTrack objects.
 */
- (void)fetchAllTracksWithProgress:(void(^)(NSInteger current, NSInteger total))progressBlock 
                        completion:(void(^)(NSArray *tracks))completionBlock;

/**
 * Creates a playlist in iTunes and adds tracks by their persistent IDs.
 */
- (void)createPlaylistWithName:(NSString *)name 
                 persistentIDs:(NSArray *)pids 
                    completion:(void(^)(NSInteger addedCount))completionBlock;

/**
 * Imports local file paths into iTunes and duplicates the imported tracks into a user playlist.
 */
- (void)importFilePaths:(NSArray *)paths
         asPlaylistName:(NSString *)playlistName
          clearPlaylist:(BOOL)clearPlaylist
             completion:(void(^)(NSInteger addedCount, NSArray *errors))completionBlock;

/**
 * Fetches all user playlists from iTunes.
 */
- (void)fetchPlaylistsWithCompletion:(void(^)(NSArray *playlists))completionBlock;

/**
 * Fetches all tracks from a specific playlist (including locations and sizes).
 */
- (void)fetchTracksForPlaylist:(NSString *)playlistName 
                    completion:(void(^)(NSArray *tracks))completionBlock;

/**
 * Fetches local file track references for diagnostics.
 */
- (void)fetchLibraryFileTrackReferencesWithCompletion:(void(^)(NSArray *tracks))completionBlock;

/**
 * Executes an AppleScript command on the main thread and returns the string result.
 */
- (NSString *)runAppleScript:(NSString *)source;
- (NSString *)runAppleScriptNamed:(NSString *)name source:(NSString *)source;
- (void)writeStartupDiagnostics;

@end
