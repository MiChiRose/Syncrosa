#import "IGUSBService.h"
#import <AppKit/AppKit.h>
#import <sys/mount.h>

@implementation IGUSBDrive

- (void)dealloc {
#if !__has_feature(objc_arc)
    [_name release];
    [_volumeURL release];
    [_filesystemType release];
    [_filesystemLabel release];
    [super dealloc];
#endif
}

- (BOOL)isAndroidCompatible {
    NSString *typeLower = [self.filesystemType lowercaseString];
    NSString *labelLower = [self.filesystemLabel lowercaseString];
    return [typeLower rangeOfString:@"msdos"].location != NSNotFound ||
           [typeLower rangeOfString:@"fat"].location != NSNotFound ||
           [typeLower rangeOfString:@"exfat"].location != NSNotFound ||
           [labelLower rangeOfString:@"fat32"].location != NSNotFound ||
           [labelLower rangeOfString:@"exfat"].location != NSNotFound;
}

@end

@interface IGUSBService ()
@property (nonatomic, strong, readwrite) NSArray *availableDrives;
@property (nonatomic, assign, readwrite) BOOL isSearching;
@end

@implementation IGUSBService

+ (instancetype)sharedService {
    static IGUSBService *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.availableDrives = @[];
    }
    return self;
}

- (void)dealloc {
#if !__has_feature(objc_arc)
    [_availableDrives release];
    [super dealloc];
#endif
}

- (void)startMonitoring {
    // Manual updates only
}

- (void)stopMonitoring {
    // Manual updates only
}

- (void)volumeMounted:(NSNotification *)notification {
    // Manual updates only
}

- (void)volumeUnmounted:(NSNotification *)notification {
    // Manual updates only
}

- (void)updateDrives {
    if ([NSThread isMainThread]) {
        self.isSearching = YES;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"IGUSBDrivesUpdatedNotification" object:nil];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.isSearching = YES;
            [[NSNotificationCenter defaultCenter] postNotificationName:@"IGUSBDrivesUpdatedNotification" object:nil];
        });
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *keys = @[
            NSURLVolumeNameKey,
            NSURLVolumeIsRemovableKey,
            NSURLVolumeIsEjectableKey,
            NSURLVolumeTotalCapacityKey,
            NSURLVolumeAvailableCapacityKey,
            NSURLVolumeLocalizedFormatDescriptionKey
        ];
        
        NSArray *urls = [[NSFileManager defaultManager] mountedVolumeURLsIncludingResourceValuesForKeys:keys options:0];
        NSMutableArray *drives = [NSMutableArray array];
        
        for (NSURL *url in urls) {
            NSDictionary *values = [url resourceValuesForKeys:keys error:nil];
            if (!values) continue;
            
            BOOL isRemovable = [values[NSURLVolumeIsRemovableKey] boolValue];
            BOOL isEjectable = [values[NSURLVolumeIsEjectableKey] boolValue];
            
            if ((isRemovable || isEjectable) && [url.path hasPrefix:@"/Volumes/"]) {
                IGUSBDrive *drive = [[IGUSBDrive alloc] init];
                drive.name = values[NSURLVolumeNameKey] ?: [url lastPathComponent];
                drive.volumeURL = url;
                drive.totalSpace = [values[NSURLVolumeTotalCapacityKey] longLongValue];
                drive.freeSpace = [values[NSURLVolumeAvailableCapacityKey] longLongValue];
                drive.filesystemLabel = values[NSURLVolumeLocalizedFormatDescriptionKey] ?: @"Unknown";
                drive.filesystemType = [self getRawFilesystemType:url];
                
                // Deduplicate
                BOOL exists = NO;
                for (IGUSBDrive *d in drives) {
                    if ([d.volumeURL isEqual:drive.volumeURL]) {
                        exists = YES;
                        break;
                    }
                }
                if (!exists) {
                    [drives addObject:drive];
                }
#if !__has_feature(objc_arc)
                [drive release];
#endif
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.availableDrives = drives;
            self.isSearching = NO;
            [[NSNotificationCenter defaultCenter] postNotificationName:@"IGUSBDrivesUpdatedNotification" object:nil];
        });
    });
}

- (NSString *)getRawFilesystemType:(NSURL *)url {
    struct statfs stats;
    if (statfs([url.path fileSystemRepresentation], &stats) == 0) {
        return [NSString stringWithUTF8String:stats.f_fstypename];
    }
    return @"unknown";
}

@end

#import <CommonCrypto/CommonDigest.h>
#import <sys/stat.h>
#import <sys/file.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <limits.h>

NSString * const IGUSBExportJobsDidChangeNotification = @"IGUSBExportJobsDidChangeNotification";
static NSString * const IGUSBManifestName = @".syncrosa-export.json";

static NSError *IGUSBError(NSString *message) {
    return [NSError errorWithDomain:@"Syncrosa.USBExport" code:1 userInfo:@{NSLocalizedDescriptionKey: message ?: @"Export failed."}];
}
static BOOL IGUSBLeaf(id value) {
    if (![value isKindOfClass:[NSString class]] || [value length] == 0 || [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 240) return NO;
    NSMutableCharacterSet *invalid=[[[NSCharacterSet controlCharacterSet] mutableCopy] autorelease];[invalid addCharactersInString:@"/\\"];
    return ![value isEqualToString:@"."] && ![value isEqualToString:@".."] && [value rangeOfCharacterFromSet:invalid].location == NSNotFound;
}
static NSString *IGUSBNameKey(NSString *name) { return [[name stringByFoldingWithOptions:(NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch|NSWidthInsensitiveSearch) locale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]] precomposedStringWithCanonicalMapping]; }
static BOOL IGUSBIpodFilename(NSString *name) {
    return IGUSBLeaf(name)&&![name hasPrefix:@"."]&&[name lengthOfBytesUsingEncoding:NSUTF8StringEncoding]<=180&&
        [name rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ._-"] invertedSet]].location==NSNotFound;
}
static BOOL IGUSBHex(id value, NSUInteger length) {
    return [value isKindOfClass:[NSString class]] && [value length] == length &&
        [value rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet]].location == NSNotFound;
}
static NSString *IGUSBDataHash(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256([data bytes], (CC_LONG)[data length], digest);
    NSMutableString *value = [NSMutableString string];
    for (NSUInteger i=0; i<CC_SHA256_DIGEST_LENGTH; i++) [value appendFormat:@"%02x", digest[i]];
    return value;
}
static BOOL IGUSBLStat(NSString *path, struct stat *info) { return lstat([path fileSystemRepresentation], info) == 0; }
static BOOL IGUSBRegular(NSString *path) { struct stat s; return IGUSBLStat(path, &s) && S_ISREG(s.st_mode); }
static BOOL IGUSBDirectory(NSString *path) { struct stat s; return IGUSBLStat(path, &s) && S_ISDIR(s.st_mode); }
static BOOL IGUSBExists(NSString *path) { struct stat s; return IGUSBLStat(path, &s); }
static NSString *IGUSBFileHash(NSString *path, BOOL(^cancel)(void), NSError **error) {
    int fd = open([path fileSystemRepresentation], O_RDONLY | O_NOFOLLOW);
    if (fd < 0) { if (error) *error = IGUSBError(@"A source or exported file could not be opened safely."); return nil; }
    struct stat before, after;
    if (fstat(fd, &before) != 0 || !S_ISREG(before.st_mode)) { close(fd); if (error) *error=IGUSBError(@"Only regular music files can be exported."); return nil; }
    CC_SHA256_CTX context; CC_SHA256_Init(&context);
    unsigned char buffer[512*1024]; ssize_t count;
    while ((count=read(fd, buffer, sizeof(buffer))) > 0) {
        if (cancel && cancel()) { close(fd); if (error) *error=IGUSBError(@"Export cancelled."); return nil; }
        CC_SHA256_Update(&context, buffer, (CC_LONG)count);
    }
    BOOL stable = count == 0 && fstat(fd, &after) == 0 && before.st_ino == after.st_ino && before.st_dev == after.st_dev &&
        before.st_size == after.st_size && before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec && before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec;
    close(fd);
    if (!stable) { if (error) *error=IGUSBError(@"A file changed or became unavailable while it was being checked."); return nil; }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256_Final(digest, &context);
    NSMutableString *value=[NSMutableString string]; for (NSUInteger i=0;i<CC_SHA256_DIGEST_LENGTH;i++) [value appendFormat:@"%02x",digest[i]];
    return value;
}
static NSString *IGUSBSafeName(NSString *name, BOOL ipod) {
    NSMutableString *value = [[[name ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] mutableCopy] autorelease];
    if (ipod) CFStringTransform((CFMutableStringRef)value, NULL, kCFStringTransformStripCombiningMarks, NO);
    NSMutableCharacterSet *invalid=[[[NSCharacterSet controlCharacterSet] mutableCopy] autorelease];
    [invalid addCharactersInString:@"/\\?%*|\"<>:"];
    NSArray *parts=[value componentsSeparatedByCharactersInSet:invalid];
    NSString *clean=[parts componentsJoinedByString:@"_"];
    if (ipod) {
        NSMutableString *out=[NSMutableString string]; NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ._-"];
        for (NSUInteger i=0;i<[clean length];i++) { unichar ch=[clean characterAtIndex:i]; [out appendFormat:@"%C",(unichar)([allowed characterIsMember:ch]?ch:'_')]; }
        clean=out;
    }
    while ([clean lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > (ipod ? 70 : 90)) clean=[clean substringToIndex:[clean rangeOfComposedCharacterSequenceAtIndex:[clean length]-1].location];
    clean=[clean stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" ._-"]];
    return [clean length] ? clean : @"Track";
}
static NSDictionary *IGUSBReadJSON(NSURL *url, NSError **error) {
    if (!IGUSBRegular([url path])) { if(error)*error=IGUSBError(@"A manifest or journal is not a regular file."); return nil; }
    NSDictionary *attributes=[[NSFileManager defaultManager] attributesOfItemAtPath:[url path] error:error];
    if ([[attributes objectForKey:NSFileSize] unsignedLongLongValue] > 32ULL*1024ULL*1024ULL) { if(error)*error=IGUSBError(@"An export manifest or journal is too large."); return nil; }
    NSData *data=[NSData dataWithContentsOfURL:url options:0 error:error];
    id json=data?[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:error]:nil;
    if (![json isKindOfClass:[NSDictionary class]]) { if(error && !*error)*error=IGUSBError(@"An export manifest or journal is invalid."); return nil; }
    return json;
}
static BOOL IGUSBWriteJSON(NSDictionary *json, NSURL *url, NSError **error) {
    if (IGUSBExists([url path]) && !IGUSBRegular([url path])) { if(error)*error=IGUSBError(@"A manifest or journal path is unsafe."); return NO; }
    if(IGUSBRegular([url path])) {
        NSDictionary *existing=IGUSBReadJSON(url,nil);
        if(existing&&[existing isEqualToDictionary:json])return YES;
    }
    NSData *data=[NSJSONSerialization dataWithJSONObject:json options:0 error:error];
    if([data length]>32ULL*1024ULL*1024ULL) { if(error)*error=IGUSBError(@"The export plan is too large to save safely.");return NO; }
    return data && [data writeToURL:url options:NSDataWritingAtomic error:error];
}

@interface IGUSBExportService ()
@property (nonatomic, retain) NSURL *journalDirectory;
@property (nonatomic, assign) BOOL cancellationRequested;
@property (nonatomic, assign) BOOL running;
@end

@implementation IGUSBExportService
+ (instancetype)sharedService {
    static IGUSBExportService *service=nil; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *paths=NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES);
        NSString *root=[([paths count]?paths[0]:NSHomeDirectory()) stringByAppendingPathComponent:@"Syncrosa/USB Export Jobs"];
        service=[[self alloc] initWithJournalDirectory:[NSURL fileURLWithPath:root isDirectory:YES]];
    }); return service;
}
- (instancetype)initWithJournalDirectory:(NSURL *)directory {
    self=[super init]; if(self) self.journalDirectory=directory; return self;
}
- (void)dealloc { [_journalDirectory release]; [super dealloc]; }
- (BOOL)prepareJournalDirectory:(NSError **)error {
    NSString *path=[self.journalDirectory path];
    if (IGUSBExists(path)) { if(IGUSBDirectory(path)) return YES; if(error)*error=IGUSBError(@"The export journal folder is unsafe."); return NO; }
    return [[NSFileManager defaultManager] createDirectoryAtURL:self.journalDirectory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error];
}
- (NSURL *)journalURL:(NSString *)identifier {
    if (![[[NSUUID alloc] initWithUUIDString:identifier] autorelease]) return nil;
    return [self.journalDirectory URLByAppendingPathComponent:[NSString stringWithFormat:@"cocoa-%@.json",identifier]];
}
- (NSURL *)stepsURL:(NSString *)identifier {
    NSURL *journal=[self journalURL:identifier]; return journal?[[journal URLByDeletingPathExtension] URLByAppendingPathExtension:@"steps"]:nil;
}
- (BOOL)writeSnapshot:(NSMutableDictionary *)job error:(NSError **)error {
    job[@"generation"]=[[NSUUID UUID] UUIDString];
    NSMutableDictionary *snapshot=[NSMutableDictionary dictionaryWithDictionary:job];
    [snapshot removeObjectForKey:@"_checkpointIndex"]; [snapshot removeObjectForKey:@"_fullCheckpoint"];
    if(!IGUSBWriteJSON(snapshot,[self journalURL:job[@"id"]],error))return NO;
    NSURL *steps=[self stepsURL:job[@"id"]];
    if(IGUSBExists([steps path])) {
        if(!IGUSBRegular([steps path])||unlink([[steps path] fileSystemRepresentation])!=0) { if(error)*error=IGUSBError(@"Could not rotate the export checkpoints safely.");return NO; }
    }
    return YES;
}
- (BOOL)saveJob:(NSMutableDictionary *)job error:(NSError **)error {
    if (![self prepareJournalDirectory:error]) return NO;
    job[@"updatedAt"]=@([[NSDate date] timeIntervalSince1970]);
    NSURL *journal=[self journalURL:job[@"id"]], *steps=[self stepsURL:job[@"id"]];
    struct stat stepInfo;
    if(!IGUSBExists([journal path])||[job[@"_fullCheckpoint"] boolValue]||(IGUSBLStat([steps path],&stepInfo)&&stepInfo.st_size>60*1024*1024)) {
        BOOL result=[self writeSnapshot:job error:error];
        [job removeObjectForKey:@"_fullCheckpoint"];[job removeObjectForKey:@"_checkpointIndex"];return result;
    }
    if(!IGUSBRegular([journal path])||(IGUSBExists([steps path])&&!IGUSBRegular([steps path]))) { if(error)*error=IGUSBError(@"An export checkpoint path is unsafe.");return NO; }
    NSMutableDictionary *record=[NSMutableDictionary dictionaryWithDictionary:@{@"generation":job[@"generation"]?:@"",@"state":job[@"state"],@"updatedAt":job[@"updatedAt"],@"rootPath":job[@"rootPath"],@"rootIdentity":job[@"rootIdentity"],@"selectionFinalized":job[@"selectionFinalized"],@"completedCount":job[@"completedCount"]?:@0}];
    NSNumber *index=job[@"_checkpointIndex"];
    if(index && [index unsignedIntegerValue]<[job[@"items"] count]) { record[@"itemIndex"]=index;record[@"item"]=job[@"items"][[index unsignedIntegerValue]]; }
    NSData *json=[NSJSONSerialization dataWithJSONObject:record options:0 error:error]; if(!json)return NO;
    NSMutableData *line=[NSMutableData dataWithData:json];[line appendBytes:"\n" length:1];
    if([line length]>64*1024) { if(error)*error=IGUSBError(@"An export checkpoint is too large.");return NO; }
    int fd=open([[steps path] fileSystemRepresentation],O_RDWR|O_CREAT|O_APPEND|O_NOFOLLOW,0600);
    if(fd<0) { if(error)*error=IGUSBError(@"Could not open the export checkpoint log.");return NO; }
    struct stat info;BOOL ok=fstat(fd,&info)==0&&S_ISREG(info.st_mode);
    if(ok&&info.st_size>0) {
        off_t start=MAX((off_t)0,info.st_size-65536);size_t length=(size_t)(info.st_size-start);char tail[65536];
        ssize_t count=pread(fd,tail,length,start);
        if(count!=(ssize_t)length)ok=NO;
        else if(tail[length-1]!='\n') {
            ssize_t cut=(ssize_t)length-1;while(cut>=0&&tail[cut]!='\n')cut--;
            ok=ftruncate(fd,start+cut+1)==0;
        }
    }
    size_t offset=0;
    while(ok&&offset<[line length]) { ssize_t n=write(fd,(const char *)[line bytes]+offset,[line length]-offset);if(n<=0)ok=NO;else offset+=(size_t)n; }
    if(ok)ok=fsync(fd)==0;close(fd);
    if(!ok&&error)*error=IGUSBError(@"Could not persist the export checkpoint.");
    [job removeObjectForKey:@"_checkpointIndex"];return ok;
}
- (BOOL)saveItem:(NSMutableDictionary *)item job:(NSMutableDictionary *)job error:(NSError **)error {
    NSUInteger index=[job[@"items"] indexOfObjectIdenticalTo:item];
    if(index==NSNotFound) { if(error)*error=IGUSBError(@"The export checkpoint is inconsistent.");return NO; }
    job[@"_checkpointIndex"]=@(index);return [self saveJob:job error:error];
}
- (NSMutableDictionary *)loadJobURL:(NSURL *)url error:(NSError **)error {
    NSMutableDictionary *job=[[IGUSBReadJSON(url,error) mutableCopy] autorelease];
    if(!job||![self validJob:job])return nil;
    NSURL *steps=[self stepsURL:job[@"id"]];
    if(!IGUSBExists([steps path]))return job;
    if(!IGUSBRegular([steps path])) { if(error)*error=IGUSBError(@"The export checkpoint log is unsafe.");return nil; }
    NSDictionary *attributes=[[NSFileManager defaultManager] attributesOfItemAtPath:[steps path] error:error];
    if([attributes[NSFileSize] unsignedLongLongValue]>64ULL*1024ULL*1024ULL) { if(error)*error=IGUSBError(@"The export checkpoint log is too large.");return nil; }
    NSData *data=[NSData dataWithContentsOfURL:steps options:0 error:error];
    if(!data)return nil;
    const unsigned char *bytes=[data bytes];NSUInteger start=0;
    for(NSUInteger end=0;end<[data length];end++) {
        if(bytes[end]!='\n')continue;
        if(end==start) { start=end+1;continue; }
        NSData *line=[data subdataWithRange:NSMakeRange(start,end-start)];start=end+1;
        id record=[NSJSONSerialization JSONObjectWithData:line options:NSJSONReadingMutableContainers error:error];
        if(![record isKindOfClass:[NSDictionary class]])return nil;
        if(![record[@"generation"] isEqual:job[@"generation"]])continue;
        if(record[@"itemIndex"]) {
            if(![record[@"itemIndex"] isKindOfClass:[NSNumber class]]||[record[@"itemIndex"] unsignedIntegerValue]>=[job[@"items"] count]||![record[@"item"] isKindOfClass:[NSDictionary class]])return nil;
            job[@"items"][[record[@"itemIndex"] unsignedIntegerValue]]=record[@"item"];
        }
        for(NSString *key in @[@"state",@"updatedAt",@"rootPath",@"rootIdentity",@"selectionFinalized",@"completedCount"]) if(record[key])job[key]=record[key];
    }
    return [self validJob:job]?job:nil;
}
- (BOOL)validManifest:(NSDictionary *)manifest {
    if (![manifest[@"schemaVersion"] isKindOfClass:[NSNumber class]] || [manifest[@"schemaVersion"] integerValue]!=1 ||
        ![manifest[@"folderID"] isKindOfClass:[NSString class]] || ![[[NSUUID alloc] initWithUUIDString:manifest[@"folderID"]] autorelease] ||
        ![manifest[@"entries"] isKindOfClass:[NSArray class]]) return NO;
    NSMutableDictionary *names=[NSMutableDictionary dictionary];
    for (id entry in manifest[@"entries"]) {
        if (![entry isKindOfClass:[NSDictionary class]] || !IGUSBLeaf(entry[@"filename"]) ||
            [entry[@"filename"] hasPrefix:@".syncrosa-"] || !IGUSBHex(entry[@"sha256"],64) ||
            ![entry[@"sourceKey"] isKindOfClass:[NSString class]] || ![entry[@"size"] isKindOfClass:[NSNumber class]] || [entry[@"size"] longLongValue]<0) return NO;
        NSString *known=names[entry[@"filename"]]; if(known && ![known isEqualToString:[entry[@"sha256"] lowercaseString]]) return NO;
        NSString *sourceKey=entry[@"sourceKey"];
        if(!(([sourceKey hasPrefix:@"path:"]&&IGUSBHex([sourceKey substringFromIndex:5],64))||([sourceKey hasPrefix:@"pid:"]&&IGUSBHex([sourceKey substringFromIndex:4],16))))return NO;
        names[entry[@"filename"]]=[entry[@"sha256"] lowercaseString];
    }
    id playlistFiles=manifest[@"playlistFiles"];
    if (playlistFiles && ![playlistFiles isKindOfClass:[NSDictionary class]]) return NO;
    for (id name in playlistFiles) if(!IGUSBLeaf(name) || !IGUSBHex(playlistFiles[name],64) || [name hasPrefix:@".syncrosa-"]) return NO;
    return YES;
}
- (BOOL)validJob:(NSDictionary *)job {
    if (![job[@"schemaVersion"] isKindOfClass:[NSNumber class]] || [job[@"schemaVersion"] integerValue]!=1 ||
        ![job[@"track"] isEqual:@"cocoa"] || ![job[@"id"] isKindOfClass:[NSString class]] || ![self journalURL:job[@"id"]] ||
        !IGUSBLeaf(job[@"folderName"]) || ![job[@"folderID"] isKindOfClass:[NSString class]] || ![[[NSUUID alloc] initWithUUIDString:job[@"folderID"]] autorelease] ||
        ![job[@"items"] isKindOfClass:[NSArray class]] || ![job[@"options"] isKindOfClass:[NSDictionary class]] ||
        ![job[@"rootPath"] isKindOfClass:[NSString class]] || ![job[@"rootIdentity"] isKindOfClass:[NSString class]] ||
        ![job[@"volumeID"] isKindOfClass:[NSString class]] || ![job[@"state"] isKindOfClass:[NSString class]] ||
        ![job[@"playlistName"] isKindOfClass:[NSString class]] || ![job[@"destinationName"] isKindOfClass:[NSString class]] ||
        ![job[@"createdAt"] isKindOfClass:[NSNumber class]] || ![job[@"selectionFinalized"] isKindOfClass:[NSNumber class]] ||
        ![job[@"isVolumeRoot"] isKindOfClass:[NSNumber class]] || ![job[@"rootPath"] isAbsolutePath] ||
        ![job[@"generation"] isKindOfClass:[NSString class]] || ![[[NSUUID alloc] initWithUUIDString:job[@"generation"]] autorelease]) return NO;
    for(NSString *key in @[@"fitAvailable",@"m3u",@"m3u8",@"ipodSafeNames"]) if(![job[@"options"][key] isKindOfClass:[NSNumber class]])return NO;
    for (id item in job[@"items"]) {
        if (![item isKindOfClass:[NSDictionary class]] || ![item[@"sourcePath"] isKindOfClass:[NSString class]] || ![item[@"sourcePath"] isAbsolutePath] ||
            ![item[@"sourceKey"] isKindOfClass:[NSString class]] || !IGUSBLeaf(item[@"baseName"]) || ![item[@"state"] isKindOfClass:[NSString class]]) return NO;
        if(![@[@"pending",@"copying",@"copied",@"existing",@"drm",@"space",@"error",@"alias"] containsObject:item[@"state"]])return NO;
        if(item[@"size"]&&(![item[@"size"] isKindOfClass:[NSNumber class]]||[item[@"size"] longLongValue]<0))return NO;
        if(item[@"partialInode"]&&![item[@"partialInode"] isKindOfClass:[NSNumber class]])return NO;
        if(item[@"aliasIndex"]&&(![item[@"aliasIndex"] isKindOfClass:[NSNumber class]]||[item[@"aliasIndex"] unsignedIntegerValue]>=[job[@"items"] count]))return NO;
        if (item[@"filename"] && (!IGUSBLeaf(item[@"filename"])||[item[@"filename"] hasPrefix:@".syncrosa-"])) return NO;
        if (item[@"partialName"] && (!IGUSBLeaf(item[@"partialName"]) || ![item[@"partialName"] hasPrefix:[NSString stringWithFormat:@".syncrosa-part-%@-",job[@"id"]]])) return NO;
        if (item[@"sha256"] && !IGUSBHex(item[@"sha256"],64)) return NO;
    }
    return YES;
}
- (NSArray *)pendingJobsWithWarnings:(NSArray **)warnings {
    NSMutableArray *result=[NSMutableArray array], *issues=[NSMutableArray array];
    if (!IGUSBExists([self.journalDirectory path])) { if(warnings)*warnings=issues; return result; }
    if (!IGUSBDirectory([self.journalDirectory path])) { if(warnings)*warnings=@[@"USB export journals cannot be read safely."]; return result; }
    NSArray *files=[[NSFileManager defaultManager] contentsOfDirectoryAtURL:self.journalDirectory includingPropertiesForKeys:nil options:0 error:nil];
    for (NSURL *url in files) {
        if (![[url lastPathComponent] hasPrefix:@"cocoa-"] || ![[url pathExtension] isEqualToString:@"json"]) continue;
        NSError *error=nil; NSDictionary *job=[self loadJobURL:url error:&error];
        if(!job || ![self validJob:job] || ![[url lastPathComponent] isEqualToString:[[self journalURL:job[@"id"]] lastPathComponent]]) {
            [issues addObject:[NSString stringWithFormat:@"Could not read USB recovery journal %@. The file was preserved.",[url lastPathComponent]]]; continue;
        }
        if ([job[@"state"] isEqual:@"completed"]) continue;
        NSInteger completed=0; for(NSDictionary *item in job[@"items"]) if([@[@"copied",@"existing"] containsObject:item[@"state"]]) completed++;
        [result addObject:@{@"id":job[@"id"],@"playlistName":job[@"playlistName"]?:@"USB Export",@"state":job[@"state"],@"destinationName":job[@"destinationName"]?:@"",@"completedCount":@(completed),@"totalCount":@([job[@"items"] count]),@"createdAt":job[@"createdAt"]?:@0,@"track":@"cocoa"}];
    }
    [result sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:NO]]];
    if(warnings)*warnings=issues; return result;
}
- (BOOL)discardJobWithIdentifier:(NSString *)identifier error:(NSError **)error {
    @synchronized(self) { if(self.running) { if(error)*error=IGUSBError(@"Finish the active export before forgetting a journal."); return NO; } }
    NSURL *url=[self journalURL:identifier];
    if(!url || !IGUSBRegular([url path])) { if(error)*error=IGUSBError(@"The export journal cannot be removed safely."); return NO; }
    BOOL result=[[NSFileManager defaultManager] removeItemAtURL:url error:error];
    if(result&&IGUSBRegular([[self stepsURL:identifier] path]))[[NSFileManager defaultManager] removeItemAtURL:[self stepsURL:identifier] error:nil];
    if(result) [[NSNotificationCenter defaultCenter] postNotificationName:IGUSBExportJobsDidChangeNotification object:self]; return result;
}
- (int64_t)availableBytesAtURL:(NSURL *)url {
    struct statfs fs; return statfs([[url path] fileSystemRepresentation],&fs)==0 ? (int64_t)fs.f_bavail*(int64_t)fs.f_bsize : -1;
}
- (NSString *)volumeIdentity:(NSURL *)url {
    id value=nil; [url getResourceValue:&value forKey:NSURLVolumeUUIDStringKey error:nil]; return [value isKindOfClass:[NSString class]]?value:@"";
}
- (NSString *)rootIdentity:(NSString *)path {
    struct stat info; return IGUSBLStat(path,&info)&&S_ISDIR(info.st_mode)?[NSString stringWithFormat:@"%llu",(unsigned long long)info.st_ino]:nil;
}
- (BOOL)root:(NSURL *)root remainsDevice:(dev_t)device inode:(ino_t)inode folder:(NSURL *)folder folderInode:(ino_t)folderInode {
    struct stat r,f;
    return IGUSBLStat([root path],&r) && S_ISDIR(r.st_mode) && r.st_dev==device && r.st_ino==inode &&
        (!folder || (IGUSBLStat([folder path],&f)&&S_ISDIR(f.st_mode)&&f.st_dev==device&&f.st_ino==folderInode));
}
- (NSDictionary *)failedResult:(NSString *)message {
    return @{@"jobID":@"",@"status":@"paused",@"copiedCount":@0,@"existingCount":@0,@"skippedDRM":@0,@"skippedMissing":@0,@"skippedSpace":@0,@"totalRequested":@0,@"totalBytesCopied":@0,@"errors":@[message?:@"Export could not start."],@"completedCount":@0,@"totalCount":@0};
}
- (void)cancel { @synchronized(self) { self.cancellationRequested=YES; } }
- (void)startAsyncTracks:(NSArray *)tracks jobID:(NSString *)identifier destination:(NSURL *)destination playlistName:(NSString *)name options:(NSDictionary *)options progress:(void(^)(NSDictionary *))progress completion:(void(^)(NSDictionary *))completion {
    @synchronized(self) {
        if(self.running) { dispatch_async(dispatch_get_main_queue(), ^{ if(completion)completion([self failedResult:@"Another USB export is active."]); }); return; }
        self.running=YES; self.cancellationRequested=NO;
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^{
        NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
        BOOL(^cancel)(void)=^BOOL{ @synchronized(self) { return self.cancellationRequested; } };
        void(^notify)(NSDictionary *)=^(NSDictionary *value){ NSMutableDictionary *copy=[NSMutableDictionary dictionaryWithDictionary:value];if(!copy[@"currentTrack"])copy[@"currentTrack"]=copy[@"completedCount"]?:@0;if(!copy[@"totalTracks"])copy[@"totalTracks"]=copy[@"totalCount"]?:@0;if(progress)dispatch_async(dispatch_get_main_queue(), ^{ progress(copy); }); };
        NSDictionary *result=identifier?[self performResumeJobWithIdentifier:identifier destination:destination progress:notify cancel:cancel]:[self performExportTracks:tracks destination:destination playlistName:name options:options progress:notify cancel:cancel];
        dispatch_async(dispatch_get_main_queue(), ^{
            @synchronized(self) { self.running=NO; }
            [[NSNotificationCenter defaultCenter] postNotificationName:IGUSBExportJobsDidChangeNotification object:self];
            if(completion)completion(result);
        });
        [pool drain];
    });
}
- (void)exportTracks:(NSArray *)tracks destination:(NSURL *)destination playlistName:(NSString *)playlistName options:(NSDictionary *)options progress:(void(^)(NSDictionary *))progress completion:(void(^)(NSDictionary *))completion {
    [self startAsyncTracks:[[tracks copy] autorelease] jobID:nil destination:destination playlistName:playlistName options:[[options copy] autorelease] progress:progress completion:completion];
}
- (void)resumeJobWithIdentifier:(NSString *)identifier destination:(NSURL *)destination progress:(void(^)(NSDictionary *))progress completion:(void(^)(NSDictionary *))completion {
    [self startAsyncTracks:nil jobID:identifier destination:destination playlistName:nil options:nil progress:progress completion:completion];
}
- (NSDictionary *)performExportTracks:(NSArray *)tracks destination:(NSURL *)destination playlistName:(NSString *)playlistName options:(NSDictionary *)options progress:(void(^)(NSDictionary *))progress cancel:(BOOL(^)(void))cancel {
    if (!destination || !IGUSBDirectory([destination path])) return [self failedResult:@"Reconnect the original drive before exporting. The destination is unavailable or unsafe."];
    NSURL *root=[NSURL fileURLWithPath:[[destination path] stringByResolvingSymlinksInPath] isDirectory:YES];
    NSString *folderName=IGUSBSafeName(playlistName,NO);
    NSURL *folder=[root URLByAppendingPathComponent:folderName isDirectory:YES];
    if(IGUSBExists([folder path])&&!IGUSBDirectory([folder path])) return [self failedResult:@"The playlist folder is not a safe directory."];
    NSDictionary *existing=nil; NSURL *manifestURL=[folder URLByAppendingPathComponent:IGUSBManifestName];
    if(IGUSBExists([manifestURL path])) {
        NSError *error=nil; existing=IGUSBReadJSON(manifestURL,&error);
        if(!existing||![self validManifest:existing]) return [self failedResult:@"The USB export manifest is invalid. It was preserved; no music files were changed."];
    }
    NSMutableArray *items=[NSMutableArray array];
    BOOL ipod=[options[@"ipodSafeNames"] boolValue];
    for(id object in tracks) {
        if(![object isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *track=object;
        NSString *source=[track[@"path"] isKindOfClass:[NSString class]]?track[@"path"]:@"/";
        if(![source isAbsolutePath]) source=@"/";
        source=[source stringByStandardizingPath];
        NSString *identifier=[track[@"persistentID"] isKindOfClass:[NSString class]]?track[@"persistentID"]:nil;
        NSString *key=IGUSBHex(identifier,16)?[@"pid:" stringByAppendingString:[identifier uppercaseString]]:[@"path:" stringByAppendingString:IGUSBDataHash([[source stringByResolvingSymlinksInPath] dataUsingEncoding:NSUTF8StringEncoding])];
        NSString *artist=IGUSBSafeName([track[@"artist"] isKindOfClass:[NSString class]]?track[@"artist"]:@"",ipod);
        NSString *title=IGUSBSafeName([track[@"name"] isKindOfClass:[NSString class]]?track[@"name"]:@"",ipod);
        NSString *ext=[[source pathExtension] lowercaseString]; if([ext length]>16) ext=@"audio";
        NSString *name=[NSString stringWithFormat:@"%@ - %@%@%@",artist,title,[ext length]?@".":@"",ext];
        [items addObject:[NSMutableDictionary dictionaryWithDictionary:@{@"sourcePath":source,@"sourceKey":key,@"baseName":name,@"state":[ext isEqualToString:@"m4p"]?@"drm":@"pending"}]];
    }
    if(![items count]) return [self failedResult:@"No tracks were supplied for export."];
    id volumeRoot=nil; [root getResourceValue:&volumeRoot forKey:NSURLVolumeURLKey error:nil];
    NSMutableDictionary *job=[NSMutableDictionary dictionaryWithDictionary:@{
        @"schemaVersion":@1,@"track":@"cocoa",@"id":[[NSUUID UUID] UUIDString],@"folderID":existing[@"folderID"]?:[[NSUUID UUID] UUIDString],
        @"folderName":folderName,@"playlistName":playlistName?:@"Syncrosa Playlist",@"destinationName":[root lastPathComponent]?:@"Drive",
        @"rootPath":[root path],@"rootIdentity":[self rootIdentity:[root path]]?:@"",@"volumeID":[self volumeIdentity:root],
        @"isVolumeRoot":@([volumeRoot isKindOfClass:[NSURL class]] && [[[volumeRoot path] stringByResolvingSymlinksInPath] isEqualToString:[root path]]),
        @"createdAt":@([[NSDate date] timeIntervalSince1970]),@"state":@"pending",@"selectionFinalized":@NO,@"items":items,
        @"options":@{@"fitAvailable":@([options[@"fitAvailable"] boolValue]),@"m3u":@([options[@"m3u"] boolValue]),@"m3u8":@([options[@"m3u8"] boolValue]),@"ipodSafeNames":@(ipod)}}];
    NSError *error=nil;
    if(![self saveJob:job error:&error]) return [self failedResult:[NSString stringWithFormat:@"Could not save the export plan: %@",[error localizedDescription]]];
    return [self executeJob:job destination:root progress:progress cancel:cancel];
}
- (NSDictionary *)performResumeJobWithIdentifier:(NSString *)identifier destination:(NSURL *)destination progress:(void(^)(NSDictionary *))progress cancel:(BOOL(^)(void))cancel {
    NSURL *url=[self journalURL:identifier]; NSError *error=nil;
    NSMutableDictionary *job=url?[[[self loadJobURL:url error:&error] mutableCopy] autorelease]:nil;
    if(!job||![self validJob:job]||![job[@"id"] isEqualToString:identifier]) return [self failedResult:@"The recovery journal is invalid or unavailable. It was preserved."];
    if(!destination||!IGUSBDirectory([destination path])) return [self failedResult:@"Reconnect and select the original destination drive."];
    NSURL *root=[NSURL fileURLWithPath:[[destination path] stringByResolvingSymlinksInPath] isDirectory:YES];
    NSString *volumeID=[self volumeIdentity:root];
    BOOL sameVolume=[job[@"volumeID"] length]>0 && [job[@"volumeID"] isEqualToString:volumeID];
    BOOL sameRoot=[[self rootIdentity:[root path]] isEqualToString:job[@"rootIdentity"]];
    if (([job[@"volumeID"] length]>0&&!sameVolume) || (![job[@"isVolumeRoot"] boolValue]&&!sameRoot) ||
        ([job[@"volumeID"] length]==0&&(!sameRoot||![[root path] isEqualToString:job[@"rootPath"]]))) return [self failedResult:@"This is not the original export destination. No files were changed."];
    if([job[@"isVolumeRoot"] boolValue]) {
        id volumeRoot=nil; [root getResourceValue:&volumeRoot forKey:NSURLVolumeURLKey error:nil];
        if(![volumeRoot isKindOfClass:[NSURL class]]||![[[volumeRoot path] stringByResolvingSymlinksInPath] isEqualToString:[root path]]) return [self failedResult:@"Select the original drive itself, not a different folder."];
    }
    job[@"rootPath"]=[root path]; job[@"rootIdentity"]=[self rootIdentity:[root path]];
    return [self executeJob:job destination:root progress:progress cancel:cancel];
}
- (NSString *)candidateForItem:(NSMutableDictionary *)item folder:(NSURL *)folder manifest:(NSDictionary *)manifest reserved:(NSMutableSet *)reserved ipodSafe:(BOOL)ipod cancel:(BOOL(^)(void))cancel error:(NSError **)error {
    NSString *expected=item[@"baseName"];
    NSString *base=[expected stringByDeletingPathExtension], *ext=[expected pathExtension];
    NSMutableArray *candidates=[NSMutableArray array];
    if(item[@"filename"]) [candidates addObject:item[@"filename"]];
    for(NSDictionary *entry in manifest[@"entries"]) if([entry[@"sourceKey"] isEqualToString:item[@"sourceKey"]]&&![candidates containsObject:entry[@"filename"]]) [candidates addObject:entry[@"filename"]];
    NSSet *preferred=[NSSet setWithArray:candidates];
    NSArray *names=[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[folder path] error:error];
    if(!names) return nil;
    NSString *pattern=[NSString stringWithFormat:@"^%@_[0-9]+%@%@$",[NSRegularExpression escapedPatternForString:base],[ext length]?@"\\.":@"",[NSRegularExpression escapedPatternForString:ext]];
    NSRegularExpression *suffix=[NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil];
    if(![candidates containsObject:expected]) [candidates addObject:expected];
    for(NSString *name in [names sortedArrayUsingSelector:@selector(compare:)]) {
        if(([IGUSBNameKey(name) isEqualToString:IGUSBNameKey(expected)]||[suffix numberOfMatchesInString:name options:0 range:NSMakeRange(0,[name length])]>0)&&![candidates containsObject:name]) [candidates addObject:name];
    }
    for(NSString *name in candidates) {
        if(!IGUSBLeaf(name)||[name hasPrefix:@".syncrosa-"]) continue;
        BOOL stableName=[preferred containsObject:name]&&(!ipod||IGUSBIpodFilename(name));
        if(!stableName&&![IGUSBNameKey(name) isEqualToString:IGUSBNameKey(expected)]&&[suffix numberOfMatchesInString:name options:0 range:NSMakeRange(0,[name length])]==0)continue;
        if(ipod&&!IGUSBIpodFilename(name))continue;
        NSString *path=[[folder URLByAppendingPathComponent:name] path];
        struct stat attributes;
        if(!IGUSBLStat(path,&attributes)||!S_ISREG(attributes.st_mode)||attributes.st_size!=[item[@"size"] longLongValue]) continue;
        NSError *hashError=nil; NSString *hash=IGUSBFileHash(path,cancel,&hashError);
        if(hash && [hash isEqualToString:item[@"sha256"]]) { item[@"filename"]=name; return name; }
        if(cancel&&cancel()) { if(error)*error=hashError;return nil; }
    }
    NSString *name=expected; NSInteger index=2;
    while(IGUSBExists([[folder URLByAppendingPathComponent:name] path])||[reserved containsObject:IGUSBNameKey(name)]) {
        name=[NSString stringWithFormat:@"%@_%ld%@%@",base,(long)index++,[ext length]?@".":@"",ext];
        if(index>100000) { if(error)*error=IGUSBError(@"Too many filename collisions in the export folder.");return nil; }
    }
    item[@"filename"]=name; [reserved addObject:IGUSBNameKey(name)]; return nil;
}
- (BOOL)cleanOwnedPartial:(NSMutableDictionary *)item root:(NSURL *)root folder:(NSURL *)folder device:(dev_t)device rootInode:(ino_t)rootInode folderInode:(ino_t)folderInode error:(NSError **)error {
    NSString *name=item[@"partialName"];if(!name)return YES;
    if(![self root:root remainsDevice:device inode:rootInode folder:folder folderInode:folderInode]) { if(error)*error=IGUSBError(@"The destination changed before partial-file cleanup.");return NO; }
    NSString *path=[[folder URLByAppendingPathComponent:name] path];struct stat info;
    if(IGUSBLStat(path,&info)&&S_ISREG(info.st_mode)&&info.st_nlink==1&&[item[@"partialInode"] isKindOfClass:[NSNumber class]]&&info.st_ino==[item[@"partialInode"] unsignedLongLongValue]) {
        if(![self root:root remainsDevice:device inode:rootInode folder:folder folderInode:folderInode]||unlink([path fileSystemRepresentation])!=0) { if(error)*error=IGUSBError(@"Could not clean the owned partial copy safely.");return NO; }
    }
    /* Unknown or replaced partial paths are preserved, never followed or deleted. */
    [item removeObjectForKey:@"partialName"];[item removeObjectForKey:@"partialInode"];return YES;
}
- (BOOL)copyItem:(NSMutableDictionary *)item job:(NSMutableDictionary *)job root:(NSURL *)root folder:(NSURL *)folder device:(dev_t)device rootInode:(ino_t)rootInode folderInode:(ino_t)folderInode progress:(void(^)(NSDictionary *))progress cancel:(BOOL(^)(void))cancel bytes:(int64_t *)bytes error:(NSError **)error {
    NSString *source=item[@"sourcePath"], *destination=[[folder URLByAppendingPathComponent:item[@"filename"]] path];
    if(![self root:root remainsDevice:device inode:rootInode folder:folder folderInode:folderInode]) { if(error)*error=IGUSBError(@"The destination drive disconnected or changed.");return NO; }
    if(IGUSBExists(destination)) { if(error)*error=IGUSBError(@"The destination filename is now occupied. Resume to choose a safe name.");return NO; }
    NSString *partName=[NSString stringWithFormat:@".syncrosa-part-%@-%@",job[@"id"],[[NSUUID UUID] UUIDString]];
    item[@"partialName"]=partName; [item removeObjectForKey:@"partialInode"]; item[@"state"]=@"copying";
    if(![self saveItem:item job:job error:error]) return NO;
    NSString *temporary=[[folder URLByAppendingPathComponent:partName] path];
    int input=open([source fileSystemRepresentation],O_RDONLY|O_NOFOLLOW), output=-1;
    if(input<0) { if(error)*error=IGUSBError(@"The source file could not be opened safely.");return NO; }
    struct stat before,after,written;
    if(fstat(input,&before)!=0||!S_ISREG(before.st_mode)||before.st_size!=[item[@"size"] longLongValue]) { close(input);if(error)*error=IGUSBError(@"The source file changed. Resume to check it again.");return NO; }
    output=open([temporary fileSystemRepresentation],O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
    if(output<0) { close(input);if(error)*error=IGUSBError(@"Could not reserve a safe temporary file on the destination.");return NO; }
    fstat(output,&written); item[@"partialInode"]=@((unsigned long long)written.st_ino);
    if(![self saveItem:item job:job error:error]) { close(input);close(output);return NO; }
    CC_SHA256_CTX context;CC_SHA256_Init(&context);
    unsigned char buffer[512*1024];ssize_t count=0;BOOL success=YES;int64_t total=0;
    while(YES) {
        if((cancel&&cancel())||![self root:root remainsDevice:device inode:rootInode folder:folder folderInode:folderInode]) { if(error)*error=IGUSBError(cancel&&cancel()?@"Export cancelled.":@"The destination drive disconnected or changed.");success=NO;break; }
        count=read(input,buffer,sizeof(buffer)); if(count==0)break;
        if(count<0) { if(error)*error=IGUSBError(@"A source file became unreadable during copying.");success=NO;break; }
        ssize_t offset=0;
        while(offset<count) { ssize_t n=write(output,buffer+offset,(size_t)(count-offset));if(n<=0){success=NO;break;} offset+=n;total+=n;*bytes+=n; }
        if(!success) { if(error)*error=IGUSBError(@"The destination could not finish writing the file.");break; }
        CC_SHA256_Update(&context,buffer,(CC_LONG)count);
        if(progress)progress(@{@"phase":@"copying",@"currentTrackName":item[@"baseName"],@"fileBytes":@(total),@"fileSize":item[@"size"],@"bytesCopied":@(*bytes),@"completedCount":job[@"completedCount"]?:@0,@"totalCount":@([job[@"items"] count])});
        if([[NSUserDefaults standardUserDefaults] boolForKey:@"hdd_safe_mode"]&&total%(16*1024*1024)==0) [NSThread sleepForTimeInterval:0.005];
    }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256_Final(digest,&context);
    NSMutableString *hash=[NSMutableString string];for(NSUInteger i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[hash appendFormat:@"%02x",digest[i]];
    if(success&&(fstat(input,&after)!=0||before.st_ino!=after.st_ino||before.st_size!=after.st_size||before.st_mtimespec.tv_sec!=after.st_mtimespec.tv_sec||before.st_mtimespec.tv_nsec!=after.st_mtimespec.tv_nsec||![hash isEqualToString:item[@"sha256"]])) { if(error)*error=IGUSBError(@"The source changed while copying; the temporary copy was not promoted.");success=NO; }
    if(success&&fsync(output)!=0) { if(error)*error=IGUSBError(@"The destination could not flush the completed file.");success=NO; }
    close(input);close(output);
    if(success) {
        NSString *verified=IGUSBFileHash(temporary,cancel,error);
        if(!verified||![verified isEqualToString:item[@"sha256"]]) { if(error&&!*error)*error=IGUSBError(@"The copied file did not pass content verification.");success=NO; }
    }
    if(success&&(![self root:root remainsDevice:device inode:rootInode folder:folder folderInode:folderInode]||IGUSBExists(destination))) { if(error)*error=IGUSBError(@"The destination changed before the completed file could be saved.");success=NO; }
    if(success) success=[[NSFileManager defaultManager] moveItemAtPath:temporary toPath:destination error:error];
    if(success) { [item removeObjectForKey:@"partialName"];[item removeObjectForKey:@"partialInode"]; }
    return success;
}
- (BOOL)writePlaylists:(NSArray *)entries job:(NSDictionary *)job folder:(NSURL *)folder manifest:(NSMutableDictionary *)manifest error:(NSError **)error {
    if([entries count]==0) return YES;
    NSString *body=[NSString stringWithFormat:@"#EXTM3U\n%@\n",[entries componentsJoinedByString:@"\n"]];
    NSData *data=[body dataUsingEncoding:NSUTF8StringEncoding];NSString *desiredHash=IGUSBDataHash(data);
    NSMutableDictionary *owned=[NSMutableDictionary dictionaryWithDictionary:manifest[@"playlistFiles"]?:@{}];
    for(NSString *extension in @[@"m3u",@"m3u8"]) {
        if(![job[@"options"][extension] boolValue])continue;
        NSString *base=job[@"folderName"], *name=[base stringByAppendingPathExtension:extension];
        NSMutableArray *candidates=[NSMutableArray arrayWithObject:name];
        for(NSString *candidate in [[owned allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            if([[candidate pathExtension] isEqualToString:extension]&&[candidate hasPrefix:[base stringByAppendingString:@"_"]]) [candidates addObject:candidate];
        }
        BOOL ready=NO;
        for(NSString *candidate in candidates) {
            NSString *path=[[folder URLByAppendingPathComponent:candidate] path];
            if(!IGUSBExists(path)) { name=candidate;ready=YES;break; }
            if(!IGUSBRegular(path))continue;
            NSString *current=IGUSBFileHash(path,nil,nil);
            if([current isEqualToString:desiredHash]||[current isEqualToString:owned[candidate]]) { name=candidate;ready=YES;break; }
        }
        if(!ready) {
            NSInteger suffix=2;
            do { name=[[NSString stringWithFormat:@"%@_%ld",base,(long)suffix++] stringByAppendingPathExtension:extension]; }
            while(IGUSBExists([[folder URLByAppendingPathComponent:name] path]));
        }
        NSURL *url=[folder URLByAppendingPathComponent:name];
        if(IGUSBExists([url path])) {
            if(!IGUSBRegular([url path])) { if(error)*error=IGUSBError(@"A playlist filename changed unexpectedly.");return NO; }
            NSString *current=IGUSBFileHash([url path],nil,error);
            if([current isEqualToString:desiredHash]) { owned[name]=desiredHash;continue; }
            if(![current isEqualToString:owned[name]]) { if(error)*error=IGUSBError(@"An existing playlist file was edited and has been preserved.");return NO; }
        }
        if(![data writeToURL:url options:NSDataWritingAtomic error:error]) return NO;
        owned[name]=desiredHash;
    }
    manifest[@"playlistFiles"]=owned;return YES;
}
- (NSDictionary *)executeJob:(NSMutableDictionary *)job destination:(NSURL *)root progress:(void(^)(NSDictionary *))progress cancel:(BOOL(^)(void))cancel {
    NSMutableArray *errors=[NSMutableArray array];NSFileManager *fm=[NSFileManager defaultManager];
    NSInteger copied=0, existing=0, drm=0, missing=0, spaceSkipped=0;int64_t bytes=0;
    BOOL cancelled=NO, fatal=NO;
    struct stat rootInfo,folderInfo;
    if(!IGUSBLStat([root path],&rootInfo)||!S_ISDIR(rootInfo.st_mode))return [self failedResult:@"The original destination is unavailable."];
    NSURL *folder=[root URLByAppendingPathComponent:job[@"folderName"] isDirectory:YES];
    NSError *error=nil;
    if(![self root:root remainsDevice:rootInfo.st_dev inode:rootInfo.st_ino folder:nil folderInode:0]) return [self failedResult:@"The destination changed."];
    if(!IGUSBExists([folder path])) {
        if(![fm createDirectoryAtURL:folder withIntermediateDirectories:NO attributes:nil error:&error]) return [self failedResult:[NSString stringWithFormat:@"Could not create the export folder: %@",[error localizedDescription]]];
    }
    if(!IGUSBLStat([folder path],&folderInfo)||!S_ISDIR(folderInfo.st_mode)||folderInfo.st_dev!=rootInfo.st_dev)return [self failedResult:@"The export folder is unsafe or belongs to another volume."];
    NSString *lockPath=[[folder URLByAppendingPathComponent:@".syncrosa-export.lock"] path];
    int lockFD=open([lockPath fileSystemRepresentation],O_RDWR|O_CREAT|O_NOFOLLOW,0600);
    struct stat lockInfo;
    if(lockFD<0)return [self failedResult:@"The export folder could not be locked safely."];
    if(fstat(lockFD,&lockInfo)!=0||!S_ISREG(lockInfo.st_mode)||lockInfo.st_nlink!=1||flock(lockFD,LOCK_EX|LOCK_NB)!=0) {
        close(lockFD);return [self failedResult:@"Another export is using this folder, or its lock is unsafe. Try again after it finishes."];
    }
    @try {
    NSURL *manifestURL=[folder URLByAppendingPathComponent:IGUSBManifestName];
    NSMutableDictionary *manifest=nil;
    if(IGUSBExists([manifestURL path])) {
        manifest=[[IGUSBReadJSON(manifestURL,&error) mutableCopy] autorelease];
        if(!manifest||![self validManifest:manifest]||![manifest[@"folderID"] isEqualToString:job[@"folderID"]])return [self failedResult:@"The export folder manifest is invalid or belongs to another export. No music files were changed."];
    } else manifest=[NSMutableDictionary dictionaryWithDictionary:@{@"schemaVersion":@1,@"folderID":job[@"folderID"],@"entries":[NSMutableArray array],@"playlistFiles":[NSMutableDictionary dictionary]}];
    if(![self root:root remainsDevice:rootInfo.st_dev inode:rootInfo.st_ino folder:folder folderInode:folderInfo.st_ino]||!IGUSBWriteJSON(manifest,manifestURL,&error)) {
        [errors addObject:[NSString stringWithFormat:@"Could not save the drive manifest: %@",[error localizedDescription]?:@"Drive disconnected."]];fatal=YES;
    }
    NSArray *items=job[@"items"];NSMutableSet *reserved=[NSMutableSet set];
    for(NSString *name in [fm contentsOfDirectoryAtPath:[folder path] error:nil]) [reserved addObject:IGUSBNameKey(name)];
    NSMutableDictionary *plannedSources=[NSMutableDictionary dictionary], *plannedPaths=[NSMutableDictionary dictionary];
    for(NSMutableDictionary *item in items) if(![@[@"drm",@"space"] containsObject:item[@"state"]]) item[@"state"]=@"pending";
    job[@"state"]=@"running";job[@"completedCount"]=@0;
    if(!fatal&&![self saveJob:job error:&error]) { [errors addObject:@"Could not save the export checkpoint. No further files were copied."];fatal=YES; }
    NSInteger checked=0;
    for(NSMutableDictionary *item in items) {
        checked++;
        if(fatal)break;
        if(cancel&&cancel()) { cancelled=YES;break; }
        if([item[@"state"] isEqual:@"drm"]) { drm++;continue; }
        if([item[@"state"] isEqual:@"space"]) { spaceSkipped++;continue; }
        if(![self root:root remainsDevice:rootInfo.st_dev inode:rootInfo.st_ino folder:folder folderInode:folderInfo.st_ino]) { [errors addObject:@"The destination drive disconnected or changed."];fatal=YES;break; }
        error=nil;
        if(![self cleanOwnedPartial:item root:root folder:folder device:rootInfo.st_dev rootInode:rootInfo.st_ino folderInode:folderInfo.st_ino error:&error]) { [errors addObject:[error localizedDescription]];fatal=YES;break; }
        if(progress)progress(@{@"phase":@"checking",@"currentTrack":@(checked),@"currentTrackName":item[@"baseName"],@"completedCount":@(existing),@"totalCount":@([items count]),@"bytesCopied":@(bytes)});
        struct stat sourceInfo;
        item[@"state"]=@"pending";
        if(!IGUSBLStat(item[@"sourcePath"],&sourceInfo)||!S_ISREG(sourceInfo.st_mode)) {
            item[@"state"]=@"error";missing++;[errors addObject:[NSString stringWithFormat:@"Source unavailable or unsafe: %@",item[@"baseName"]]];continue;
        }
        error=nil;NSString *hash=IGUSBFileHash(item[@"sourcePath"],cancel,&error);
        if(!hash) {
            if(cancel&&cancel()) { cancelled=YES;break; }
            item[@"state"]=@"error";[errors addObject:[NSString stringWithFormat:@"%@: %@",item[@"baseName"],[error localizedDescription]?:@"Could not check the source."]];continue;
        }
        item[@"sha256"]=hash;item[@"size"]=@((int64_t)sourceInfo.st_size);
        NSString *pathKey=[item[@"sourcePath"] stringByResolvingSymlinksInPath];
        NSMutableDictionary *earlier=plannedSources[item[@"sourceKey"]]?:plannedPaths[pathKey];
        if(earlier&&[earlier[@"sha256"] isEqualToString:hash]) {
            item[@"filename"]=earlier[@"filename"];
            if([earlier[@"state"] isEqual:@"existing"]) { item[@"state"]=@"existing";existing++; }
            else { item[@"state"]=@"alias";item[@"aliasIndex"]=@([items indexOfObjectIdenticalTo:earlier]); }
            continue;
        }
        [item removeObjectForKey:@"aliasIndex"];
        error=nil;NSString *match=[self candidateForItem:item folder:folder manifest:manifest reserved:reserved ipodSafe:[job[@"options"][@"ipodSafeNames"] boolValue] cancel:cancel error:&error];
        if(cancel&&cancel()) { cancelled=YES;break; }
        if(error) { item[@"state"]=@"error";[errors addObject:[error localizedDescription]];continue; }
        if(match) { item[@"state"]=@"existing";existing++;[reserved addObject:IGUSBNameKey(match)]; }
        plannedSources[item[@"sourceKey"]]=item;plannedPaths[pathKey]=item;
    }
    int64_t available=[self availableBytesAtURL:root], required=0;
    if(!fatal&&!cancelled) {
        for(NSDictionary *item in items) if([item[@"state"] isEqual:@"pending"]) {
            int64_t size=[item[@"size"] longLongValue];
            if(size>LLONG_MAX-required) { [errors addObject:@"The export is too large to calculate safely."];fatal=YES;break; }
            required+=size;
        }
        if(required>0&&available<0) { [errors addObject:@"Could not determine the available space on the destination."];fatal=YES; }
        int64_t usable=MAX((int64_t)0,available-MIN((int64_t)(64*1024*1024),MAX((int64_t)0,available/100)));
        if(!fatal&&![job[@"selectionFinalized"] boolValue]&&[job[@"options"][@"fitAvailable"] boolValue]) {
            NSMutableArray *pending=[NSMutableArray array];for(NSMutableDictionary *item in items)if([item[@"state"] isEqual:@"pending"])[pending addObject:item];
            for(NSUInteger i=[pending count];i>1;i--)[pending exchangeObjectAtIndex:i-1 withObjectAtIndex:arc4random_uniform((uint32_t)i)];
            int64_t used=0;
            for(NSMutableDictionary *item in pending) {
                int64_t size=[item[@"size"] longLongValue];
                if(size<=usable-used)used+=size;else{item[@"state"]=@"space";spaceSkipped++;}
            }
            required=used;
        }
        for(NSMutableDictionary *item in items)if([item[@"state"] isEqual:@"alias"]&&[items[[item[@"aliasIndex"] unsignedIntegerValue]][@"state"] isEqual:@"space"]) { item[@"state"]=@"space";spaceSkipped++; }
        if(!fatal&&required>usable) { [errors addObject:@"Not enough space for the remaining files. Completed files were preserved; free space and resume from Recovery Center."];fatal=YES; }
        job[@"selectionFinalized"]=@YES;job[@"_fullCheckpoint"]=@YES;
        if(![self saveJob:job error:&error]) { [errors addObject:@"Could not save the selected export plan."];fatal=YES; }
    }
    NSMutableArray *completedEntries=[NSMutableArray array];
    for(NSMutableDictionary *item in items) {
        if([item[@"state"] isEqual:@"existing"]) [completedEntries addObject:item[@"filename"]];
    }
    /* Copy in original playlist order, including only the persisted fit selection. */
    if(!fatal&&!cancelled) for(NSMutableDictionary *item in items) {
        if(cancel&&cancel()) { cancelled=YES;break; }
        if(![item[@"state"] isEqual:@"pending"])continue;
        job[@"completedCount"]=@(existing+copied);
        error=nil;
        BOOL success=[self copyItem:item job:job root:root folder:folder device:rootInfo.st_dev rootInode:rootInfo.st_ino folderInode:folderInfo.st_ino progress:progress cancel:cancel bytes:&bytes error:&error];
        if(success) { item[@"state"]=@"copied";copied++; }
        else {
            item[@"state"]=@"error";
            if(cancel&&cancel())cancelled=YES;
            else [errors addObject:[NSString stringWithFormat:@"%@: %@",item[@"baseName"],[error localizedDescription]?:@"Copy failed."]];
        }
        if(![self saveItem:item job:job error:&error]) { [errors addObject:@"Could not save the completed-file checkpoint. Resume to verify files before continuing."];fatal=YES; }
        if(![self root:root remainsDevice:rootInfo.st_dev inode:rootInfo.st_ino folder:folder folderInode:folderInfo.st_ino]) { [errors addObject:@"The destination drive disconnected or changed."];fatal=YES; }
        if(progress)progress(@{@"phase":success?@"copied":@"paused",@"currentTrackName":item[@"baseName"],@"completedCount":@(existing+copied),@"totalCount":@([items count]),@"bytesCopied":@(bytes)});
        if(fatal||cancelled)break;
    }
    for(NSMutableDictionary *item in items)if([item[@"state"] isEqual:@"alias"]&&[@[@"copied",@"existing"] containsObject:items[[item[@"aliasIndex"] unsignedIntegerValue]][@"state"]]) { item[@"state"]=@"existing";existing++; }
    [completedEntries removeAllObjects];NSMutableArray *entries=[NSMutableArray arrayWithArray:manifest[@"entries"]];
    for(NSDictionary *item in items)if([@[@"copied",@"existing"] containsObject:item[@"state"]]) {
        [completedEntries addObject:item[@"filename"]];
        NSIndexSet *indices=[entries indexesOfObjectsPassingTest:^BOOL(id entry,NSUInteger index,BOOL *stop){return [entry[@"sourceKey"] isEqualToString:item[@"sourceKey"]];}];
        [entries removeObjectsAtIndexes:indices];
        [entries addObject:@{@"sourceKey":item[@"sourceKey"],@"filename":item[@"filename"],@"size":item[@"size"],@"sha256":item[@"sha256"]}];
    }
    manifest[@"entries"]=entries;
    if([self root:root remainsDevice:rootInfo.st_dev inode:rootInfo.st_ino folder:folder folderInode:folderInfo.st_ino]) {
        error=nil;
        if(![self writePlaylists:completedEntries job:job folder:folder manifest:manifest error:&error]) [errors addObject:[NSString stringWithFormat:@"Playlist file: %@",[error localizedDescription]?:@"Could not write the playlist."]];
        error=nil;
        if(!IGUSBWriteJSON(manifest,manifestURL,&error)) [errors addObject:[NSString stringWithFormat:@"Drive manifest: %@",[error localizedDescription]?:@"Could not save the manifest."]];
    } else if(![errors containsObject:@"The destination drive disconnected or changed."]) [errors addObject:@"The destination drive disconnected or changed."];
    NSString *state=cancelled?@"cancelled":([errors count]?@"paused":@"completed");
    job[@"state"]=state;job[@"completedCount"]=@(copied+existing);job[@"_fullCheckpoint"]=@YES;
    error=nil;
    if(![self saveJob:job error:&error]) { [errors addObject:@"Could not save the final recovery checkpoint."];state=@"paused"; }
    return @{@"jobID":job[@"id"],@"status":state,@"copiedCount":@(copied),@"existingCount":@(existing),@"skippedDRM":@(drm),@"skippedMissing":@(missing),@"skippedSpace":@(spaceSkipped),@"totalRequested":@([items count]),@"totalBytesCopied":@(bytes),@"errors":errors,@"completedCount":@(copied+existing),@"totalCount":@([items count])};
    } @finally { flock(lockFD,LOCK_UN);close(lockFD); }
}
@end
