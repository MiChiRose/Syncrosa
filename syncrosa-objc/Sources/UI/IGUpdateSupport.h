#ifndef IGUpdateSupport_h
#define IGUpdateSupport_h

#import <Foundation/Foundation.h>

NSString *IGCurrentApplicationVersionString(void);
NSString *IGUpdateManifestURLString(void);
NSString *IGUpdateProjectReleasesURLString(void);
NSURL *IGUpdateProjectReleasesURL(void);
NSString *IGUpdateCheckUserAgentString(void);
BOOL IGVersionStringIsNewer(NSString *remoteVersion, NSString *currentVersion);
BOOL IGUpdateURLStringIsTrusted(NSString *urlString);

NSDictionary *IGLatestUpdateInfoWithError(NSError **error);
NSString *IGUpdateDownloadURLStringFromInfo(NSDictionary *info);
NSString *IGUpdateReleaseURLStringFromInfo(NSDictionary *info);
NSString *IGUpdateReleaseTitleFromInfo(NSDictionary *info);
NSString *IGUpdateReleaseNotesFromInfo(NSDictionary *info);
NSString *IGUpdateSourceFromInfo(NSDictionary *info);

NSString *IGUpdateShortErrorMessage(NSError *error);
NSString *IGUpdateDetailedErrorMessage(NSError *error);
NSString *IGUpdateBundledReleaseNotes(void);

#endif
