#import <Foundation/Foundation.h>

// A snapshot includes the current title and the file identity used at apply time.
FOUNDATION_EXPORT NSDictionary *SRReadTrackTitle(NSURL *file, NSError **error);
FOUNDATION_EXPORT NSURL *SRReplaceTrackTitle(NSURL *file, NSDictionary *snapshot, NSString *title,
                                            NSURL *backupDirectory, NSError **error);
FOUNDATION_EXPORT NSArray *SRScanTrackTitles(NSURL *folder, NSError **error);
FOUNDATION_EXPORT NSString *SRTitleFromFilename(NSURL *file);
FOUNDATION_EXPORT BOOL SRIsValidTrackTitle(NSString *title);
