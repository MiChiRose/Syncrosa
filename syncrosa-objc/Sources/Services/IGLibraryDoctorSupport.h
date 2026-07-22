#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSDictionary *IGLibraryDoctorTagScore(NSArray *tracks);
FOUNDATION_EXPORT NSDictionary *IGLibraryDoctorJSONObject(NSArray *tracks);
FOUNDATION_EXPORT NSString *IGLibraryDoctorCSVString(NSArray *tracks);
FOUNDATION_EXPORT NSArray *IGLibraryDoctorAudioFilePathsAtURL(NSURL *directoryURL);
FOUNDATION_EXPORT NSDictionary *IGLibraryDoctorLinkAudit(NSArray *libraryReferences, NSArray *folderFilePaths);
