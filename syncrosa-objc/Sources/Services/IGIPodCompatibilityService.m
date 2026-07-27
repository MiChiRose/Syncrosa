#import "IGIPodCompatibilityService.h"
#import "IGiTunesService.h"
#import "IGLogger.h"
#import <AudioToolbox/AudioToolbox.h>

@interface IGIPodCompatibilityService ()
@property (nonatomic, assign) BOOL cancellationRequested;
- (BOOL)isCancellationRequested;
- (BOOL)copyContentsOfURL:(NSURL *)sourceURL
            toExistingURL:(NSURL *)destinationURL
                    error:(NSError **)error;
@end

static NSString *IGAudioError(NSString *prefix, OSStatus status)
{
    UInt32 value = (UInt32)status;
    char code[5] = {
        (char)((value >> 24) & 0xff),
        (char)((value >> 16) & 0xff),
        (char)((value >> 8) & 0xff),
        (char)(value & 0xff),
        0
    };
    BOOL printable = YES;
    for (NSInteger index = 0; index < 4; index++) {
        if (code[index] < 32 || code[index] > 126) {
            printable = NO;
            break;
        }
    }
    NSString *detail = printable ? [NSString stringWithUTF8String:code] : [NSString stringWithFormat:@"%d", (int)status];
    return [NSString stringWithFormat:@"%@ (%@).", prefix, detail];
}

static NSString *IGAudioFormatCode(UInt32 formatID)
{
    UInt32 value = (UInt32)formatID;
    char code[5] = {
        (char)((value >> 24) & 0xff),
        (char)((value >> 16) & 0xff),
        (char)((value >> 8) & 0xff),
        (char)(value & 0xff),
        0
    };
    for (NSInteger index = 0; index < 4; index++) {
        if (code[index] < 32 || code[index] > 126) {
            return [NSString stringWithFormat:@"%u", (unsigned int)value];
        }
    }
    return [NSString stringWithUTF8String:code];
}

static NSString *IGEncodeCompatibleFile(NSURL *sourceURL,
                                        NSURL *destinationURL,
                                        IGIPodCompatibilityService *service,
                                        void (^frameProgressBlock)(double progress))
{
    ExtAudioFileRef sourceFile = NULL;
    ExtAudioFileRef destinationFile = NULL;
    void *buffer = NULL;
    NSString *errorMessage = nil;
    OSStatus status = ExtAudioFileOpenURL((CFURLRef)sourceURL, &sourceFile);
    if (status != noErr || !sourceFile) {
        return IGAudioError(@"Could not open the audio file", status);
    }

    AudioStreamBasicDescription sourceFormat;
    memset(&sourceFormat, 0, sizeof(sourceFormat));
    UInt32 propertySize = sizeof(sourceFormat);
    status = ExtAudioFileGetProperty(sourceFile,
                                     kExtAudioFileProperty_FileDataFormat,
                                     &propertySize,
                                     &sourceFormat);
    if (status != noErr) {
        errorMessage = IGAudioError(@"Could not read the audio format", status);
        goto cleanup;
    }

    SInt64 sourceFrameLength = 0;
    propertySize = sizeof(sourceFrameLength);
    if (ExtAudioFileGetProperty(sourceFile,
                                kExtAudioFileProperty_FileLengthFrames,
                                &propertySize,
                                &sourceFrameLength) != noErr) {
        sourceFrameLength = 0;
    }

    BOOL preservesALAC = sourceFormat.mFormatID == kAudioFormatAppleLossless;
    if (preservesALAC && (sourceFormat.mSampleRate <= 0.0 || sourceFormat.mSampleRate > 48000.0)) {
        errorMessage = [NSString stringWithFormat:
            @"This ALAC file uses %.0f Hz. Syncrosa will not reduce its sample rate automatically; the original remains unchanged.",
            sourceFormat.mSampleRate];
        goto cleanup;
    }
    if (preservesALAC && (sourceFormat.mChannelsPerFrame == 0 || sourceFormat.mChannelsPerFrame > 2)) {
        errorMessage = [NSString stringWithFormat:
            @"This ALAC file has %u channels. Syncrosa will not downmix lossless audio automatically; the original remains unchanged.",
            (unsigned int)sourceFormat.mChannelsPerFrame];
        goto cleanup;
    }

    UInt32 channels = preservesALAC
        ? sourceFormat.mChannelsPerFrame
        : MAX(1, MIN(sourceFormat.mChannelsPerFrame, 2));
    Float64 outputSampleRate = preservesALAC ? sourceFormat.mSampleRate : 44100.0;
    UInt32 losslessFlag = kAppleLosslessFormatFlag_16BitSourceData;
    UInt32 bitsPerChannel = 16;
    UInt32 bytesPerSample = 2;
    if (preservesALAC) {
        switch (sourceFormat.mFormatFlags) {
            case kAppleLosslessFormatFlag_20BitSourceData:
                losslessFlag = kAppleLosslessFormatFlag_20BitSourceData;
                bitsPerChannel = 20;
                bytesPerSample = 3;
                break;
            case kAppleLosslessFormatFlag_24BitSourceData:
                losslessFlag = kAppleLosslessFormatFlag_24BitSourceData;
                bitsPerChannel = 24;
                bytesPerSample = 3;
                break;
            case kAppleLosslessFormatFlag_32BitSourceData:
                losslessFlag = kAppleLosslessFormatFlag_32BitSourceData;
                bitsPerChannel = 32;
                bytesPerSample = 4;
                break;
            default:
                break;
        }
    }
    UInt32 bytesPerFrame = channels * bytesPerSample;
    AudioStreamBasicDescription clientFormat;
    memset(&clientFormat, 0, sizeof(clientFormat));
    clientFormat.mSampleRate = outputSampleRate;
    clientFormat.mFormatID = kAudioFormatLinearPCM;
    clientFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger |
        (bitsPerChannel == 20 ? kLinearPCMFormatFlagIsAlignedHigh : kAudioFormatFlagIsPacked);
    clientFormat.mBytesPerPacket = bytesPerFrame;
    clientFormat.mFramesPerPacket = 1;
    clientFormat.mBytesPerFrame = bytesPerFrame;
    clientFormat.mChannelsPerFrame = channels;
    clientFormat.mBitsPerChannel = bitsPerChannel;

    status = ExtAudioFileSetProperty(sourceFile,
                                     kExtAudioFileProperty_ClientDataFormat,
                                     sizeof(clientFormat),
                                     &clientFormat);
    if (status != noErr) {
        errorMessage = IGAudioError(@"Could not prepare the audio decoder", status);
        goto cleanup;
    }

    AudioStreamBasicDescription destinationFormat;
    memset(&destinationFormat, 0, sizeof(destinationFormat));
    destinationFormat.mSampleRate = outputSampleRate;
    destinationFormat.mFormatID = preservesALAC ? kAudioFormatAppleLossless : kAudioFormatMPEG4AAC;
    destinationFormat.mFormatFlags = preservesALAC ? losslessFlag : 0;
    destinationFormat.mFramesPerPacket = preservesALAC ? 4096 : 1024;
    destinationFormat.mChannelsPerFrame = channels;

    status = ExtAudioFileCreateWithURL((CFURLRef)destinationURL,
                                       kAudioFileM4AType,
                                       &destinationFormat,
                                       NULL,
                                       kAudioFileFlags_EraseFile,
                                       &destinationFile);
    if (status != noErr || !destinationFile) {
        errorMessage = IGAudioError(@"Could not create the M4A file", status);
        goto cleanup;
    }

    status = ExtAudioFileSetProperty(destinationFile,
                                     kExtAudioFileProperty_ClientDataFormat,
                                     sizeof(clientFormat),
                                     &clientFormat);
    if (status != noErr) {
        errorMessage = IGAudioError(preservesALAC ? @"Could not prepare the ALAC encoder" : @"Could not prepare the AAC encoder", status);
        goto cleanup;
    }

    if (!preservesALAC) {
        AudioConverterRef converter = NULL;
        propertySize = sizeof(converter);
        if (ExtAudioFileGetProperty(destinationFile,
                                    kExtAudioFileProperty_AudioConverter,
                                    &propertySize,
                                    &converter) == noErr && converter) {
            UInt32 bitrate = channels == 1 ? 96000 : 192000;
            AudioConverterSetProperty(converter,
                                      kAudioConverterEncodeBitRate,
                                      sizeof(bitrate),
                                      &bitrate);
        }
    }

    const UInt32 framesPerChunk = 4096;
    UInt32 bufferSize = framesPerChunk * bytesPerFrame;
    buffer = malloc(bufferSize);
    if (!buffer) {
        errorMessage = @"Could not allocate an audio conversion buffer.";
        goto cleanup;
    }

    double estimatedClientFrames = 0.0;
    if (sourceFrameLength > 0 && sourceFormat.mSampleRate > 0.0) {
        estimatedClientFrames = ((double)sourceFrameLength * clientFormat.mSampleRate) / sourceFormat.mSampleRate;
    }
    double processedClientFrames = 0.0;
    CFAbsoluteTime lastProgressTime = 0.0;
    if (frameProgressBlock) {
        frameProgressBlock(0.0);
    }

    while (YES) {
        if ([service isCancellationRequested]) {
            errorMessage = @"Conversion cancelled.";
            goto cleanup;
        }

        UInt32 frames = framesPerChunk;
        AudioBufferList bufferList;
        bufferList.mNumberBuffers = 1;
        bufferList.mBuffers[0].mNumberChannels = channels;
        bufferList.mBuffers[0].mDataByteSize = bufferSize;
        bufferList.mBuffers[0].mData = buffer;

        status = ExtAudioFileRead(sourceFile, &frames, &bufferList);
        if (status != noErr) {
            errorMessage = IGAudioError(@"Could not decode the audio file", status);
            goto cleanup;
        }
        if (frames == 0) {
            break;
        }
        status = ExtAudioFileWrite(destinationFile, frames, &bufferList);
        if (status != noErr) {
            errorMessage = IGAudioError(@"Could not write converted audio", status);
            goto cleanup;
        }

        processedClientFrames += frames;
        if (frameProgressBlock && estimatedClientFrames > 0.0) {
            CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
            double fraction = MIN(1.0, processedClientFrames / estimatedClientFrames);
            if (fraction >= 1.0 || lastProgressTime == 0.0 || (now - lastProgressTime) >= 0.25) {
                lastProgressTime = now;
                frameProgressBlock(fraction);
            }
        }
    }

    if (frameProgressBlock) {
        frameProgressBlock(1.0);
    }

cleanup:
    if (buffer) {
        free(buffer);
    }
    if (destinationFile) {
        ExtAudioFileDispose(destinationFile);
    }
    if (sourceFile) {
        ExtAudioFileDispose(sourceFile);
    }
    return errorMessage;
}

@implementation IGIPodCompatibilityService

+ (instancetype)sharedService {
    static IGIPodCompatibilityService *service = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        service = [[IGIPodCompatibilityService alloc] init];
    });
    return service;
}

+ (NSSet *)supportedExtensions {
    static NSSet *extensions = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        extensions = [[NSSet alloc] initWithObjects:@"mp3", @"m4a", @"mp4", @"aac",
                      @"wav", @"aiff", @"aif", @"caf", nil];
    });
    return extensions;
}

+ (BOOL)isSupportedFileURL:(NSURL *)fileURL {
    NSString *extension = [[fileURL pathExtension] lowercaseString];
    return [[[self class] supportedExtensions] containsObject:extension];
}

+ (NSArray *)compatibilityIssuesForFileURL:(NSURL *)fileURL deepScan:(BOOL)deepScan {
    NSMutableArray *issues = [NSMutableArray array];
    if (![self isSupportedFileURL:fileURL]) {
        NSString *extension = [[fileURL pathExtension] uppercaseString];
        [issues addObject:[NSString stringWithFormat:@"unsupported file type %@",
                           [extension length] > 0 ? extension : @"unknown"]];
        return issues;
    }

    ExtAudioFileRef sourceFile = NULL;
    OSStatus status = ExtAudioFileOpenURL((CFURLRef)fileURL, &sourceFile);
    if (status != noErr || !sourceFile) {
        [issues addObject:IGAudioError(@"cannot open audio stream", status)];
        return issues;
    }

    AudioStreamBasicDescription sourceFormat;
    memset(&sourceFormat, 0, sizeof(sourceFormat));
    UInt32 propertySize = sizeof(sourceFormat);
    status = ExtAudioFileGetProperty(sourceFile,
                                     kExtAudioFileProperty_FileDataFormat,
                                     &propertySize,
                                     &sourceFormat);
    if (status != noErr) {
        [issues addObject:IGAudioError(@"cannot read audio format", status)];
        ExtAudioFileDispose(sourceFile);
        return issues;
    }

    if (sourceFormat.mSampleRate <= 0.0 || sourceFormat.mSampleRate > 48000.0) {
        [issues addObject:[NSString stringWithFormat:@"sample rate %.0f Hz exceeds the iPod 5G limit",
                           sourceFormat.mSampleRate]];
    }
    if (sourceFormat.mChannelsPerFrame == 0 || sourceFormat.mChannelsPerFrame > 2) {
        [issues addObject:[NSString stringWithFormat:@"%u audio channels; iPod 5G expects mono or stereo",
                           (unsigned int)sourceFormat.mChannelsPerFrame]];
    }
    BOOL acceptedCodec = sourceFormat.mFormatID == kAudioFormatMPEGLayer3 ||
                         sourceFormat.mFormatID == kAudioFormatMPEG4AAC ||
                         sourceFormat.mFormatID == kAudioFormatAppleLossless ||
                         sourceFormat.mFormatID == kAudioFormatLinearPCM;
    if (!acceptedCodec) {
        [issues addObject:[NSString stringWithFormat:@"audio codec %@ is not an iPod 5G-safe codec",
                           IGAudioFormatCode(sourceFormat.mFormatID)]];
    }

    AudioFileID audioFile = NULL;
    propertySize = sizeof(audioFile);
    if (ExtAudioFileGetProperty(sourceFile,
                                kExtAudioFileProperty_AudioFile,
                                &propertySize,
                                &audioFile) == noErr && audioFile) {
        UInt32 bitRate = 0;
        UInt32 bitRateSize = sizeof(bitRate);
        if (AudioFileGetProperty(audioFile,
                                 kAudioFilePropertyBitRate,
                                 &bitRateSize,
                                 &bitRate) == noErr &&
            (sourceFormat.mFormatID == kAudioFormatMPEGLayer3 ||
             sourceFormat.mFormatID == kAudioFormatMPEG4AAC) &&
            bitRate > 320000) {
            [issues addObject:[NSString stringWithFormat:@"bit rate %u kbps exceeds the iPod 5G limit",
                               (unsigned int)(bitRate / 1000)]];
        }
    }

    if (deepScan) {
        UInt32 channels = MAX((UInt32)1, sourceFormat.mChannelsPerFrame);
        UInt32 bytesPerFrame = channels * sizeof(SInt16);
        AudioStreamBasicDescription clientFormat;
        memset(&clientFormat, 0, sizeof(clientFormat));
        clientFormat.mSampleRate = sourceFormat.mSampleRate > 0.0 ? sourceFormat.mSampleRate : 44100.0;
        clientFormat.mFormatID = kAudioFormatLinearPCM;
        clientFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
        clientFormat.mBytesPerPacket = bytesPerFrame;
        clientFormat.mFramesPerPacket = 1;
        clientFormat.mBytesPerFrame = bytesPerFrame;
        clientFormat.mChannelsPerFrame = channels;
        clientFormat.mBitsPerChannel = 16;

        status = ExtAudioFileSetProperty(sourceFile,
                                         kExtAudioFileProperty_ClientDataFormat,
                                         sizeof(clientFormat),
                                         &clientFormat);
        if (status != noErr) {
            [issues addObject:IGAudioError(@"cannot prepare full decoder check", status)];
        } else {
            const UInt32 framesPerChunk = 16384;
            UInt32 bufferSize = framesPerChunk * bytesPerFrame;
            void *buffer = malloc(bufferSize);
            if (!buffer) {
                [issues addObject:@"cannot allocate decoder check buffer"];
            } else {
                while (YES) {
                    UInt32 frames = framesPerChunk;
                    AudioBufferList bufferList;
                    bufferList.mNumberBuffers = 1;
                    bufferList.mBuffers[0].mNumberChannels = channels;
                    bufferList.mBuffers[0].mDataByteSize = bufferSize;
                    bufferList.mBuffers[0].mData = buffer;
                    status = ExtAudioFileRead(sourceFile, &frames, &bufferList);
                    if (status != noErr) {
                        [issues addObject:IGAudioError(@"decoder failed before the end of the file", status)];
                        break;
                    }
                    if (frames == 0) {
                        break;
                    }
                }
                free(buffer);
            }
        }
    }

    ExtAudioFileDispose(sourceFile);
    return issues;
}

+ (NSString *)safeBaseName:(NSString *)value {
    NSCharacterSet *forbidden = [NSCharacterSet characterSetWithCharactersInString:@"/:\\?%*|\"<>"];
    NSArray *parts = [value componentsSeparatedByCharactersInSet:forbidden];
    NSString *cleaned = [parts componentsJoinedByString:@"-"];
    while ([cleaned rangeOfString:@"  "].location != NSNotFound) {
        cleaned = [cleaned stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    }
    cleaned = [cleaned stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([cleaned length] == 0) {
        cleaned = @"Audio";
    }
    if ([cleaned length] > 120) {
        cleaned = [cleaned substringToIndex:120];
    }
    return cleaned;
}

+ (NSURL *)destinationURLForSourceURL:(NSURL *)sourceURL
                          directoryURL:(NSURL *)directoryURL
                           fileManager:(NSFileManager *)fileManager {
    NSFileManager *manager = fileManager ?: [NSFileManager defaultManager];
    NSString *base = [self safeBaseName:[[sourceURL URLByDeletingPathExtension] lastPathComponent]];
    NSString *filename = [NSString stringWithFormat:@"%@ (iPod).m4a", base];
    NSURL *candidate = [directoryURL URLByAppendingPathComponent:filename];
    NSInteger suffix = 2;
    while ([manager fileExistsAtPath:[candidate path]]) {
        filename = [NSString stringWithFormat:@"%@ (iPod %ld).m4a", base, (long)suffix];
        candidate = [directoryURL URLByAppendingPathComponent:filename];
        suffix++;
    }
    return candidate;
}

- (void)convertFiles:(NSArray *)fileURLs
         toDirectory:(NSURL *)directoryURL
            progress:(IGIPodConversionProgressBlock)progressBlock
          completion:(IGIPodConversionCompletionBlock)completionBlock {
    [self convertFiles:fileURLs
           toDirectory:directoryURL
                  mode:IGIPodConversionModeCreateCopy
              progress:progressBlock
            completion:completionBlock];
}

- (NSURL *)backupURLForSourceURL:(NSURL *)sourceURL fileManager:(NSFileManager *)fileManager {
    NSString *base = [[[sourceURL lastPathComponent] stringByDeletingPathExtension]
                      stringByAppendingString:@" (Syncrosa Backup)"];
    NSString *extension = [sourceURL pathExtension];
    NSString *filename = [base stringByAppendingPathExtension:extension];
    NSURL *directory = [sourceURL URLByDeletingLastPathComponent];
    NSURL *candidate = [directory URLByAppendingPathComponent:filename];
    NSInteger suffix = 2;
    while ([fileManager fileExistsAtPath:[candidate path]]) {
        filename = [[NSString stringWithFormat:@"%@ %ld", base, (long)suffix]
                    stringByAppendingPathExtension:extension];
        candidate = [directory URLByAppendingPathComponent:filename];
        suffix++;
    }
    return candidate;
}

- (NSString *)replaceITunesTrackAtSourceURL:(NSURL *)sourceURL
                         convertedFileURL:(NSURL *)convertedURL {
    if (![[[sourceURL pathExtension] lowercaseString] isEqualToString:@"m4a"]) {
        return @"Replace in iTunes currently supports M4A source files only. Use Create Copy for other formats.";
    }

    IGiTunesService *iTunes = [IGiTunesService sharedService];
    NSString *lookupError = nil;
    NSString *persistentID = [iTunes persistentIDForFilePath:[sourceURL path]
                                               errorMessage:&lookupError];
    if ([persistentID length] == 0) {
        return lookupError ?: @"The source file is not referenced by iTunes.";
    }

    NSFileManager *manager = [NSFileManager defaultManager];
    NSURL *backupURL = [self backupURLForSourceURL:sourceURL fileManager:manager];
    NSError *fileError = nil;
    if (![manager copyItemAtURL:sourceURL toURL:backupURL error:&fileError]) {
        return [NSString stringWithFormat:@"Could not create the original-file backup: %@",
                [fileError localizedDescription] ?: @"unknown error"];
    }

    if (![self copyContentsOfURL:convertedURL toExistingURL:sourceURL error:&fileError]) {
        [self copyContentsOfURL:backupURL toExistingURL:sourceURL error:nil];
        return [NSString stringWithFormat:@"Could not put the converted file in place: %@",
                [fileError localizedDescription] ?: @"unknown error"];
    }

    NSString *metadataError = nil;
    if (![iTunes reapplyMetadataForPersistentID:persistentID errorMessage:&metadataError]) {
        // Restore the original bytes in place so the iTunes alias continues to
        // reference the same filesystem object during rollback as well.
        if (![self copyContentsOfURL:backupURL toExistingURL:sourceURL error:&fileError]) {
            return [NSString stringWithFormat:
                    @"iTunes metadata could not be restored, and the original-file rollback also failed: %@",
                    [fileError localizedDescription] ?: @"unknown error"];
        }
        return metadataError ?: @"iTunes could not restore the track metadata.";
    }

    [manager removeItemAtURL:convertedURL error:nil];
    [[IGLogger sharedLogger] log:[NSString stringWithFormat:
        @"iPod converter replaced track in place pid=%@ source=%@ backup=%@",
        persistentID, [sourceURL path], [backupURL path]]];
    return nil;
}

- (BOOL)copyContentsOfURL:(NSURL *)sourceURL
            toExistingURL:(NSURL *)destinationURL
                    error:(NSError **)error {
    NSFileHandle *input = [NSFileHandle fileHandleForReadingAtPath:[sourceURL path]];
    NSFileHandle *output = [NSFileHandle fileHandleForWritingAtPath:[destinationURL path]];
    if (!input || !output) {
        if (error) {
            *error = [NSError errorWithDomain:@"SyncrosaIPodConverter"
                                         code:30
                                     userInfo:[NSDictionary dictionaryWithObject:
                                               @"Could not open the source or destination file."
                                                                          forKey:NSLocalizedDescriptionKey]];
        }
        return NO;
    }

    BOOL succeeded = YES;
    @try {
        [output truncateFileAtOffset:0];
        while (YES) {
            @autoreleasepool {
                NSData *chunk = [input readDataOfLength:(1024 * 1024)];
                if ([chunk length] == 0) {
                    break;
                }
                [output writeData:chunk];
            }
        }
        [output synchronizeFile];
    } @catch (NSException *exception) {
        succeeded = NO;
        if (error) {
            *error = [NSError errorWithDomain:@"SyncrosaIPodConverter"
                                         code:31
                                     userInfo:[NSDictionary dictionaryWithObject:
                                               ([exception reason] ?: @"Could not overwrite the iTunes media file.")
                                                                          forKey:NSLocalizedDescriptionKey]];
        }
    }
    [input closeFile];
    [output closeFile];
    return succeeded;
}

- (void)convertFiles:(NSArray *)fileURLs
         toDirectory:(NSURL *)directoryURL
                mode:(IGIPodConversionMode)mode
            progress:(IGIPodConversionProgressBlock)progressBlock
          completion:(IGIPodConversionCompletionBlock)completionBlock {
    NSArray *files = [fileURLs copy];
    NSURL *outputDirectory = [directoryURL copy];
    IGIPodConversionProgressBlock progressCopy = [progressBlock copy];
    IGIPodConversionCompletionBlock completionCopy = [completionBlock copy];

    @synchronized (self) {
        self.cancellationRequested = NO;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray *converted = [NSMutableArray array];
        NSMutableArray *failures = [NSMutableArray array];
        BOOL cancelled = NO;

        NSInteger total = [files count];
        for (NSInteger index = 0; index < total; index++) {
            @autoreleasepool {
                @synchronized (self) {
                    cancelled = self.cancellationRequested;
                }
                if (cancelled) {
                    break;
                }

                NSURL *sourceURL = [files objectAtIndex:index];
                if (progressCopy) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        progressCopy(index, total, [sourceURL lastPathComponent], 0.0);
                    });
                }

                if (![[self class] isSupportedFileURL:sourceURL]) {
                    [failures addObject:@{
                        @"file": sourceURL,
                        @"message": @"Unsupported audio format."
                    }];
                    continue;
                }

                NSURL *destinationDirectory = mode == IGIPodConversionModeReplaceITunesTrack
                    ? [sourceURL URLByDeletingLastPathComponent]
                    : outputDirectory;
                NSURL *destinationURL = [[self class] destinationURLForSourceURL:sourceURL
                                                                    directoryURL:destinationDirectory
                                                                     fileManager:[NSFileManager defaultManager]];
                NSString *conversionError = IGEncodeCompatibleFile(sourceURL,
                                                                    destinationURL,
                                                                    self,
                                                                    ^(double fileProgress) {
                    if (progressCopy) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            progressCopy(index, total, [sourceURL lastPathComponent], fileProgress);
                        });
                    }
                });
                if (!conversionError && mode == IGIPodConversionModeReplaceITunesTrack) {
                    conversionError = [self replaceITunesTrackAtSourceURL:sourceURL
                                                        convertedFileURL:destinationURL];
                    if (!conversionError) {
                        [converted addObject:sourceURL];
                    }
                } else if (!conversionError) {
                    [converted addObject:destinationURL];
                } else if ([self isCancellationRequested]) {
                    [[NSFileManager defaultManager] removeItemAtURL:destinationURL error:nil];
                    cancelled = YES;
                } else {
                    [[NSFileManager defaultManager] removeItemAtURL:destinationURL error:nil];
                    [failures addObject:@{@"file": sourceURL, @"message": conversionError}];
                }

                if (progressCopy) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        progressCopy(index, total, [sourceURL lastPathComponent], 1.0);
                    });
                }

                if (cancelled) {
                    break;
                }
            }
        }

        @synchronized (self) {
            cancelled = cancelled || self.cancellationRequested;
        }
        if (completionCopy) {
            NSArray *convertedResult = [NSArray arrayWithArray:converted];
            NSArray *failureResult = [NSArray arrayWithArray:failures];
            dispatch_async(dispatch_get_main_queue(), ^{
                completionCopy(convertedResult, failureResult, cancelled);
#if !__has_feature(objc_arc)
                [progressCopy release];
                [completionCopy release];
                [files release];
                [outputDirectory release];
#endif
            });
        } else {
#if !__has_feature(objc_arc)
            [progressCopy release];
            [completionCopy release];
            [files release];
            [outputDirectory release];
#endif
        }
    });
}

- (void)cancelConversion {
    @synchronized (self) {
        self.cancellationRequested = YES;
    }
}

- (BOOL)isCancellationRequested {
    @synchronized (self) {
        return self.cancellationRequested;
    }
}

@end
