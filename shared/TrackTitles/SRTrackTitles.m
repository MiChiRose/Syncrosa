#import "SRTrackTitles.h"
#import <copyfile.h>
#import <errno.h>
#import <fcntl.h>
#import <stdint.h>
#import <stdlib.h>
#import <string.h>
#import <sys/file.h>
#import <sys/stat.h>
#import <sys/time.h>
#import <unistd.h>

static const NSUInteger SRMetadataLimit = 32 * 1024 * 1024;

static id SRFailure(NSError **error, NSInteger code, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"SRTrackTitles" code:code
                                      userInfo:@{NSLocalizedDescriptionKey: message}];
    return nil;
}

BOOL SRIsValidTrackTitle(NSString *title) {
    if (title.length == 0 || title.length > 1024) return NO;
    if ([[title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0) return NO;
    return [title rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location == NSNotFound &&
           [title dataUsingEncoding:NSUTF8StringEncoding] != nil;
}

static uint32_t SRBig(const uint8_t *b, NSUInteger count) {
    uint32_t v = 0;
    for (NSUInteger i = 0; i < count; ++i) v = (v << 8) | b[i];
    return v;
}

static uint32_t SRLittle(const uint8_t *b) {
    return (uint32_t)b[0] | ((uint32_t)b[1] << 8) | ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24);
}

static void SRAppendInteger(NSMutableData *data, uint32_t value, NSUInteger count, NSUInteger bits, BOOL little) {
    uint8_t b[4];
    uint32_t mask = (1U << bits) - 1;
    for (NSUInteger i = 0; i < count; ++i) {
        b[little ? i : count - 1 - i] = value & mask;
        value >>= bits;
    }
    [data appendBytes:b length:count];
}

static BOOL SRReadBytes(int fd, off_t offset, void *buffer, size_t length) {
    uint8_t *b = buffer;
    while (length > 0) {
        ssize_t n = pread(fd, b, length, offset);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return NO;
        offset += n;
        b += n;
        length -= (size_t)n;
    }
    return YES;
}

static NSData *SRRead(int fd, off_t size, off_t offset, NSUInteger length) {
    if (offset < 0 || offset > size || length > SRMetadataLimit || (uint64_t)length > (uint64_t)(size - offset)) return nil;
    NSMutableData *data = [NSMutableData dataWithLength:length];
    return SRReadBytes(fd, offset, data.mutableBytes, length) ? data : nil;
}

static BOOL SRWriteBytes(int fd, const void *buffer, size_t length) {
    const uint8_t *b = buffer;
    while (length > 0) {
        ssize_t n = write(fd, b, length);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return NO;
        b += n;
        length -= (size_t)n;
    }
    return YES;
}

static BOOL SRCopyRange(int input, int output, off_t from, off_t to) {
    uint8_t buffer[64 * 1024];
    while (from < to) {
        size_t count = (size_t)MIN((off_t)sizeof(buffer), to - from);
        if (!SRReadBytes(input, from, buffer, count) || !SRWriteBytes(output, buffer, count)) return NO;
        from += count;
    }
    return YES;
}

static NSDictionary *SREdit(off_t offset, off_t length, NSData *data) {
    return @{@"offset": @(offset), @"length": @(length), @"data": data};
}

static NSString *SRTrimTag(NSString *text) {
    return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

static NSString *SRTextData(NSData *text, NSStringEncoding encoding) {
    NSString *value = [[NSString alloc] initWithData:text encoding:encoding];
    if (!value) return nil;
#if !__has_feature(objc_arc)
    [value autorelease];
#endif
    NSRange nul = [value rangeOfString:[NSString stringWithFormat:@"%C", (unichar)0]];
    if (nul.location != NSNotFound) value = [value substringToIndex:nul.location];
    return value;
}

static BOOL SRSafeSize(const uint8_t *bytes, uint32_t *value) {
    if ((bytes[0] | bytes[1] | bytes[2] | bytes[3]) & 0x80) return NO;
    *value = ((uint32_t)bytes[0] << 21) | ((uint32_t)bytes[1] << 14) | ((uint32_t)bytes[2] << 7) | bytes[3];
    return YES;
}

static NSDictionary *SRMP3(int fd, off_t size, NSString *replacement) {
    uint8_t header[10] = {'I','D','3',3,0,0,0,0,0,0};
    uint8_t probe[10];
    if (!SRReadBytes(fd, 0, probe, sizeof(probe))) return nil;
    uint32_t tagLength = 0;
    NSUInteger prefix = 0;
    if (memcmp(probe, "ID3", 3) == 0) {
        if (probe[3] < 2 || probe[3] > 4 || probe[5] != 0 || !SRSafeSize(probe + 6, &tagLength)) return nil;
        memcpy(header, probe, sizeof(header));
        prefix = 10;
    }
    NSData *tag = SRRead(fd, size, prefix, tagLength);
    off_t audioOffset = (off_t)prefix + tagLength;
    uint8_t mpeg[2];
    if (!tag || !SRReadBytes(fd, audioOffset, mpeg, 2) || mpeg[0] != 0xFF || (mpeg[1] & 0xE0) != 0xE0 ||
        (mpeg[1] & 0x06) == 0) return nil;

    NSUInteger nameWidth = header[3] == 2 ? 3 : 4;
    NSUInteger frameHeader = header[3] == 2 ? 6 : 10;
    const char *titleFrame = nameWidth == 3 ? "TT2" : "TIT2";
    NSString *title = nil;
    const uint8_t *bytes = tag.bytes;
    NSMutableData *frames = replacement ? [NSMutableData data] : nil;
    NSUInteger offset = 0;
    BOOL absoluteOffsets = NO;
    while (offset < tag.length && bytes[offset] != 0) {
        if (tag.length - offset < frameHeader) return nil;
        const uint8_t *frame = bytes + offset;
        for (NSUInteger i = 0; i < nameWidth; ++i) {
            if (!((frame[i] >= 'A' && frame[i] <= 'Z') || (frame[i] >= '0' && frame[i] <= '9'))) return nil;
        }
        uint32_t length = 0;
        if (header[3] == 4) {
            if (!SRSafeSize(frame + nameWidth, &length)) return nil;
        } else {
            length = SRBig(frame + nameWidth, nameWidth);
        }
        if (length > tag.length - offset - frameHeader) return nil;
        if (memcmp(frame, titleFrame, nameWidth) == 0) {
            if (title || length < 1 || (nameWidth == 4 && (frame[8] != 0 || frame[9] != 0))) return nil;
            NSStringEncoding encoding;
            switch (frame[frameHeader]) {
                case 0: encoding = NSISOLatin1StringEncoding; break;
                case 1: encoding = NSUTF16StringEncoding; break;
                case 2: encoding = NSUTF16BigEndianStringEncoding; break;
                case 3: encoding = NSUTF8StringEncoding; break;
                default: return nil;
            }
            title = SRTextData([NSData dataWithBytes:frame + frameHeader + 1 length:length - 1], encoding);
            if (!title) return nil;
        } else if (replacement) {
            if (nameWidth == 4 && (memcmp(frame, "CHAP", 4) == 0 || memcmp(frame, "ASPI", 4) == 0)) {
                absoluteOffsets = YES;
            }
            [frames appendBytes:frame length:frameHeader + length];
        }
        offset += frameHeader + length;
    }
    for (NSUInteger i = offset; i < tag.length; ++i) if (bytes[i] != 0) return nil;

    NSData *legacy = size - audioOffset >= 130 ? SRRead(fd, size, size - 128, 128) : nil;
    BOOL hasLegacy = legacy && memcmp(legacy.bytes, "TAG", 3) == 0;
    if (!title && hasLegacy) {
        title = SRTrimTag(SRTextData([legacy subdataWithRange:NSMakeRange(3, 30)], NSISOLatin1StringEncoding));
    }
    if (!replacement) return @{@"title": title ?: @""};

    // UTF-16 with a BOM is supported by every ID3v2 version handled here.
    NSData *encoded = [replacement dataUsingEncoding:NSUTF16LittleEndianStringEncoding];
    const uint8_t textHeader[] = {1,0xFF,0xFE};
    [frames appendBytes:titleFrame length:nameWidth];
    SRAppendInteger(frames, (uint32_t)(encoded.length + sizeof(textHeader)), nameWidth, header[3] == 4 ? 7 : 8, NO);
    if (nameWidth == 4) {
        const uint8_t flags[] = {0,0};
        [frames appendBytes:flags length:sizeof(flags)];
    }
    [frames appendBytes:textHeader length:sizeof(textHeader)];
    [frames appendData:encoded];
    if (absoluteOffsets && frames.length > tagLength) return nil;
    if (frames.length < tagLength) [frames setLength:tagLength];
    NSMutableData *newTag = [NSMutableData dataWithBytes:header length:6];
    SRAppendInteger(newTag, (uint32_t)frames.length, 4, 7, NO);
    [newTag appendData:frames];
    NSMutableArray *edits = [NSMutableArray arrayWithObject:SREdit(0, audioOffset, newTag)];
    if (hasLegacy) {
        // ID3v1 cannot store every Unicode value. Leave its title empty when
        // the exact replacement will not fit; ID3v2 carries the full title.
        uint8_t titleBytes[30] = {0};
        NSData *latin = [replacement dataUsingEncoding:NSISOLatin1StringEncoding];
        if (latin && latin.length <= sizeof(titleBytes)) memcpy(titleBytes, latin.bytes, latin.length);
        [edits addObject:SREdit(size - 125, 30, [NSData dataWithBytes:titleBytes length:30])];
    }
    return @{@"title": title ?: @"", @"edits": edits};
}

static NSData *SRFLACBlock(uint8_t flags, NSData *body) {
    if (body.length > 0xFFFFFF) return nil;
    NSMutableData *block = [NSMutableData dataWithBytes:&flags length:1];
    SRAppendInteger(block, (uint32_t)body.length, 3, 8, NO);
    [block appendData:body];
    return block;
}

static NSDictionary *SRFLAC(int fd, off_t size, NSString *replacement) {
    uint8_t magic[4];
    if (!SRReadBytes(fd, 0, magic, 4) || memcmp(magic, "fLaC", 4) != 0) return nil;
    off_t offset = 4;
    BOOL hasComment = NO, last = NO;
    NSString *title = @"";
    NSMutableArray *edits = [NSMutableArray array];
    for (NSUInteger block = 0; !last && block < 512; ++block) {
        uint8_t header[4];
        if (!SRReadBytes(fd, offset, header, 4)) return nil;
        last = !!(header[0] & 0x80);
        uint8_t type = header[0] & 0x7F;
        uint32_t length = SRBig(header + 1, 3);
        if ((block == 0 && (type != 0 || length != 34)) || type == 127 || size - offset - 4 < length) return nil;
        if (type == 4) {
            if (hasComment || length < 8) return nil;
            hasComment = YES;
            NSData *old = SRRead(fd, size, offset + 4, length);
            if (!old) return nil;
            const uint8_t *b = old.bytes;
            uint32_t vendorLength = SRLittle(b);
            if (vendorLength > length - 8) return nil;
            NSUInteger pos = 4 + vendorLength;
            NSMutableData *fields = [NSMutableData data];
            uint32_t count = SRLittle(b + pos), preserved = 0;
            pos += 4;
            BOOL hasTitle = NO;
            for (uint32_t i = 0; i < count; ++i) {
                if (length - pos < 4) return nil;
                uint32_t fieldLength = SRLittle(b + pos);
                if (fieldLength > length - pos - 4) return nil;
                if (fieldLength >= 6 && strncasecmp((const char *)b + pos + 4, "TITLE=", 6) == 0) {
                    if (hasTitle) return nil;
                    hasTitle = YES;
                    title = SRTextData([NSData dataWithBytes:b + pos + 10 length:fieldLength - 6], NSUTF8StringEncoding);
                    if (!title) return nil;
                } else if (replacement) {
                    [fields appendBytes:b + pos length:4 + fieldLength];
                    ++preserved;
                }
                pos += 4 + fieldLength;
            }
            if (pos != length) return nil;
            if (replacement) {
                NSMutableData *body = [NSMutableData dataWithBytes:b length:4 + vendorLength];
                SRAppendInteger(body, preserved + 1, 4, 8, YES);
                [body appendData:fields];
                NSData *text = [[@"TITLE=" stringByAppendingString:replacement] dataUsingEncoding:NSUTF8StringEncoding];
                SRAppendInteger(body, (uint32_t)text.length, 4, 8, YES);
                [body appendData:text];
                NSData *newBlock = SRFLACBlock(header[0], body);
                if (!newBlock) return nil;
                [edits addObject:SREdit(offset, 4 + length, newBlock)];
            }
        }
        if (last && !hasComment && replacement) {
            uint8_t withoutLast = type;
            [edits addObject:SREdit(offset, 1, [NSData dataWithBytes:&withoutLast length:1])];
            NSData *vendor = [@"Syncrosa" dataUsingEncoding:NSUTF8StringEncoding];
            NSData *text = [[@"TITLE=" stringByAppendingString:replacement] dataUsingEncoding:NSUTF8StringEncoding];
            NSMutableData *body = [NSMutableData data];
            SRAppendInteger(body, (uint32_t)vendor.length, 4, 8, YES);
            [body appendData:vendor];
            SRAppendInteger(body, 1, 4, 8, YES);
            SRAppendInteger(body, (uint32_t)text.length, 4, 8, YES);
            [body appendData:text];
            [edits addObject:SREdit(offset + 4 + length, 0, SRFLACBlock(0x84, body))];
        }
        offset += 4 + length;
    }
    uint8_t frame[2];
    if (!last || !SRReadBytes(fd, offset, frame, 2) || frame[0] != 0xFF || (frame[1] & 0xFE) != 0xF8) return nil;
    return @{@"title": title, @"edits": edits};
}

#define SRAtomType(a,b,c,d) (((uint32_t)(a)<<24) | ((uint32_t)(b)<<16) | ((uint32_t)(c)<<8) | (uint32_t)(d))

typedef struct {
    uint32_t type;
    uint64_t length;
    NSUInteger headerLength;
} SRAtom;

static BOOL SRDecodeAtom(const uint8_t *bytes, NSUInteger available, uint64_t remaining, SRAtom *atom) {
    if (available < 8) return NO;
    uint64_t length = SRBig(bytes, 4);
    atom->type = SRBig(bytes + 4, 4);
    atom->headerLength = 8;
    if (length == 1) {
        if (available < 16) return NO;
        length = ((uint64_t)SRBig(bytes + 8, 4) << 32) | SRBig(bytes + 12, 4);
        atom->headerLength = 16;
    }
    // A size-zero atom extends to end of file and cannot be followed by a relocated movie atom.
    if (length < atom->headerLength || length > remaining) return NO;
    atom->length = length;
    return YES;
}

static NSData *SRAtomOfType(uint32_t type, NSData *payload) {
    NSMutableData *atom = [NSMutableData data];
    SRAppendInteger(atom, (uint32_t)(8 + payload.length), 4, 8, NO);
    SRAppendInteger(atom, type, 4, 8, NO);
    [atom appendData:payload];
    return atom;
}

static NSData *SRTitleAtom(NSString *title) {
    const uint8_t dataHeader[] = {0,0,0,1,0,0,0,0};
    NSMutableData *value = [NSMutableData dataWithBytes:dataHeader length:sizeof(dataHeader)];
    [value appendData:[title dataUsingEncoding:NSUTF8StringEncoding]];
    return SRAtomOfType(SRAtomType(0xA9,'n','a','m'), SRAtomOfType(SRAtomType('d','a','t','a'), value));
}

static NSData *SRDefaultM4AHandler(void) {
    const uint8_t payload[] = {0,0,0,0,0,0,0,0,'m','d','i','r','a','p','p','l',0,0,0,0,0,0,0,0,0};
    return SRAtomOfType(SRAtomType('h','d','l','r'), [NSData dataWithBytes:payload length:sizeof(payload)]);
}

static NSString *SRReadM4ATitleItem(NSData *payload) {
    SRAtom data;
    if (!SRDecodeAtom(payload.bytes, payload.length, payload.length, &data) ||
        data.type != SRAtomType('d','a','t','a') || data.length != payload.length ||
        data.length < data.headerLength + 8) return nil;
    const uint8_t *bytes = payload.bytes;
    const uint8_t *value = bytes + data.headerLength;
    uint32_t type = SRBig(value, 4);
    if (type != 1 && type != 2) return nil;
    return SRTextData([NSData dataWithBytes:value + 8 length:(NSUInteger)data.length - data.headerLength - 8],
                      type == 1 ? NSUTF8StringEncoding : NSUTF16BigEndianStringEncoding);
}

// The iTunes-style path is moov/udta/meta/ilst/©nam. Preserve every sibling atom.
static NSData *SRM4AContainer(NSData *payload, NSUInteger level, NSString *replacement, NSString **title) {
    const uint32_t types[] = {SRAtomType('u','d','t','a'), SRAtomType('m','e','t','a'),
                              SRAtomType('i','l','s','t'), SRAtomType(0xA9,'n','a','m')};
    NSUInteger pos = level == 2 ? 4 : 0; // meta FullBox header
    if (payload.length < pos) return nil;
    const uint8_t *bytes = payload.bytes;
    if (level == 2 && SRBig(bytes, 4) != 0) return nil;
    NSMutableData *newPayload = [NSMutableData dataWithBytes:bytes length:pos];
    BOOL found = NO, hasHandler = NO;
    while (pos < payload.length) {
        SRAtom atom;
        if (!SRDecodeAtom(bytes + pos, payload.length - pos, payload.length - pos, &atom)) return nil;
        if (level == 0 && (atom.type == SRAtomType('m','v','e','x') || atom.type == SRAtomType('c','m','o','v') ||
                           atom.type == SRAtomType('m','e','t','a'))) return nil;
        if (level == 1 && atom.type == SRAtomType(0xA9,'n','a','m')) return nil;
        if (level == 2 && atom.type == SRAtomType('h','d','l','r')) {
            if (hasHandler || atom.length < atom.headerLength + 12 ||
                SRBig(bytes + pos + atom.headerLength + 8, 4) != SRAtomType('m','d','i','r')) return nil;
            hasHandler = YES;
        }
        if (atom.type == types[level]) {
            if (found) return nil;
            found = YES;
            NSData *child = [NSData dataWithBytes:bytes + pos + atom.headerLength
                                           length:(NSUInteger)atom.length - atom.headerLength];
            if (level == 3) {
                *title = SRReadM4ATitleItem(child);
                if (!*title) return nil;
                if (replacement) [newPayload appendData:SRTitleAtom(replacement)];
            } else {
                NSData *updated = SRM4AContainer(child, level + 1, replacement, title);
                if (!updated) return nil;
                if (replacement) [newPayload appendData:SRAtomOfType(atom.type, updated)];
            }
        } else if (replacement) {
            [newPayload appendBytes:bytes + pos length:(NSUInteger)atom.length];
        }
        pos += (NSUInteger)atom.length;
    }
    if (level == 2 && !hasHandler) return nil;
    if (!found && replacement) {
        if (level == 3) {
            [newPayload appendData:SRTitleAtom(replacement)];
        } else {
            NSData *child = [NSData data];
            if (level == 1) {
                NSMutableData *meta = [NSMutableData dataWithLength:4];
                [meta appendData:SRDefaultM4AHandler()];
                child = meta;
            }
            NSData *updated = SRM4AContainer(child, level + 1, replacement, title);
            if (!updated) return nil;
            [newPayload appendData:SRAtomOfType(types[level], updated)];
        }
    }
    return newPayload;
}

static NSDictionary *SRM4A(int fd, off_t size, NSString *replacement) {
    off_t offset = 0, movieOffset = -1;
    SRAtom movie = {0,0,0};
    BOOL hasAudioData = NO;
    NSUInteger count = 0;
    while (offset < size && count++ < 4096) {
        uint8_t probe[16];
        NSUInteger window = (NSUInteger)MIN((off_t)sizeof(probe), size - offset);
        SRAtom box;
        if (!SRReadBytes(fd, offset, probe, window) ||
            !SRDecodeAtom(probe, window, (uint64_t)(size - offset), &box)) return nil;
        if (box.type == SRAtomType('m','o','o','v')) {
            if (movieOffset != -1 || box.length > SRMetadataLimit) return nil;
            movieOffset = offset;
            movie = box;
        }
        if (box.type == SRAtomType('m','d','a','t') && box.length > box.headerLength) hasAudioData = YES;
        if (box.type == SRAtomType('m','o','o','f') || box.type == SRAtomType('s','i','d','x') ||
            box.type == SRAtomType('m','e','t','a')) return nil;
        offset += (off_t)box.length;
    }
    if (offset != size || movieOffset < 0 || !hasAudioData) return nil;
    NSData *metadata = SRRead(fd, size, movieOffset + movie.headerLength, (NSUInteger)movie.length - movie.headerLength);
    if (!metadata) return nil;
    NSString *title = @"";
    NSData *payload = SRM4AContainer(metadata, 0, replacement, &title);
    if (!payload) return nil;
    if (!replacement) return @{@"title": title};

    NSData *newMovie = SRAtomOfType(movie.type, payload);
    NSArray *edits;
    if (movieOffset + (off_t)movie.length == size || newMovie.length == movie.length) {
        edits = @[SREdit(movieOffset, (off_t)movie.length, newMovie)];
    } else {
        // Keep every existing media offset intact. The old space becomes a free atom.
        NSData *freeBox = SRAtomOfType(SRAtomType('f','r','e','e'), [NSMutableData dataWithLength:(NSUInteger)movie.length - 8]);
        edits = @[SREdit(movieOffset, (off_t)movie.length, freeBox), SREdit(size, 0, newMovie)];
    }
    return @{@"title": title, @"edits": edits};
}

static NSDictionary *SRTagPlan(int fd, off_t size, NSString *extension, NSString *title) {
    if ([extension isEqualToString:@"mp3"]) return SRMP3(fd, size, title);
    if ([extension isEqualToString:@"flac"]) return SRFLAC(fd, size, title);
    if ([extension isEqualToString:@"m4a"]) return SRM4A(fd, size, title);
    return nil;
}

static NSArray *SRFileIdentity(struct stat info) {
    return @[@(info.st_dev), @(info.st_ino), @(info.st_size), @(info.st_mtimespec.tv_sec), @(info.st_mtimespec.tv_nsec),
             @(info.st_ctimespec.tv_sec), @(info.st_ctimespec.tv_nsec)];
}

static int SROpenTrack(NSURL *file, struct stat *info) {
    if (![file isFileURL]) return -1;
    int fd = open([file.path fileSystemRepresentation], O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    if (fd >= 0 && (fstat(fd, info) != 0 || !S_ISREG(info->st_mode) || info->st_nlink != 1)) {
        close(fd);
        return -1;
    }
    return fd;
}

NSDictionary *SRReadTrackTitle(NSURL *file, NSError **error) {
    struct stat info, ending;
    int fd = SROpenTrack(file, &info);
    if (fd < 0) return SRFailure(error, 1, @"The file could not be opened for safe editing.");
    NSDictionary *value = SRTagPlan(fd, info.st_size, file.pathExtension.lowercaseString, nil);
    BOOL stable = fstat(fd, &ending) == 0 && [SRFileIdentity(info) isEqual:SRFileIdentity(ending)];
    close(fd);
    if (!stable) return SRFailure(error, 3, @"The file changed while it was being read.");
    if (!value) return SRFailure(error, 2, @"This audio tag layout cannot be edited safely.");
    return @{@"title": value[@"title"], @"identity": SRFileIdentity(info)};
}

static BOOL SRWriteEditedTrack(int input, int output, off_t size, NSArray *edits) {
    off_t offset = 0;
    for (NSDictionary *edit in edits) {
        off_t at = [edit[@"offset"] longLongValue], length = [edit[@"length"] longLongValue];
        NSData *bytes = edit[@"data"];
        if (at < offset || at > size || length < 0 || length > size - at ||
            !SRCopyRange(input, output, offset, at) || !SRWriteBytes(output, bytes.bytes, bytes.length)) return NO;
        offset = at + length;
    }
    return SRCopyRange(input, output, offset, size);
}

NSURL *SRReplaceTrackTitle(NSURL *file, NSDictionary *snapshot, NSString *title,
                           NSURL *backupDirectory, NSError **error) {
    if (!SRIsValidTrackTitle(title) || ![backupDirectory isFileURL]) {
        return SRFailure(error, 4, @"Enter a nonempty title before applying changes.");
    }

    struct stat info, current;
    int input = SROpenTrack(file, &info);
    if (input < 0) return SRFailure(error, 1, @"The file could not be opened for safe editing.");
    if (flock(input, LOCK_EX | LOCK_NB) != 0) {
        close(input);
        return SRFailure(error, 3, @"The file is already being edited.");
    }
    NSArray *identity = SRFileIdentity(info);
    if (![identity isEqual:snapshot[@"identity"]]) {
        close(input);
        return SRFailure(error, 3, @"The file changed after preview. Scan the folder again.");
    }
    NSString *extension = file.pathExtension.lowercaseString;
    NSDictionary *plan = SRTagPlan(input, info.st_size, extension, title);
    if (!plan || ![plan[@"title"] isEqual:snapshot[@"title"]]) {
        close(input);
        return SRFailure(error, 3, @"The tag changed after preview. Scan the folder again.");
    }

    const char *path = [file.path fileSystemRepresentation];
    NSURL *parent = [file URLByDeletingLastPathComponent];
    char *temporary = strdup([[[parent URLByAppendingPathComponent:@".syncrosa-title-XXXXXX"] path] fileSystemRepresentation]);
    int staged = temporary ? mkstemp(temporary) : -1;
    if (staged < 0) {
        free(temporary);
        close(input);
        return SRFailure(error, 5, @"A temporary file could not be created.");
    }

    BOOL ok = SRWriteEditedTrack(input, staged, info.st_size, plan[@"edits"]);
    struct stat stageInfo;
    if (ok) {
        ok = fstat(staged, &stageInfo) == 0 &&
             [SRTagPlan(staged, stageInfo.st_size, extension, nil)[@"title"] isEqual:title] &&
             fcopyfile(input, staged, NULL, COPYFILE_METADATA) == 0 && futimes(staged, NULL) == 0 && fsync(staged) == 0;
    }
    close(staged);

    NSURL *backup = nil;
    NSInteger code = 5;
    if (ok) {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSURL *itemDirectory = [backupDirectory URLByAppendingPathComponent:[[NSUUID UUID] UUIDString] isDirectory:YES];
        ok = [fm createDirectoryAtURL:itemDirectory withIntermediateDirectories:YES
                            attributes:@{NSFilePosixPermissions: @0700} error:NULL];
        if (ok) {
            backup = [itemDirectory URLByAppendingPathComponent:file.lastPathComponent];
            NSURL *partial = [itemDirectory URLByAppendingPathComponent:@".original.partial"];
            const char *partialPath = [partial.path fileSystemRepresentation];
            int original = open(partialPath, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
            ok = original >= 0;
            if (ok) {
                ok = SRCopyRange(input, original, 0, info.st_size) &&
                     fcopyfile(input, original, NULL, COPYFILE_METADATA) == 0 && fsync(original) == 0;
                close(original);
                if (ok) {
                    NSURL *locationInfo = [backupDirectory URLByAppendingPathComponent:
                                           [itemDirectory.lastPathComponent stringByAppendingString:@".plist"]];
                    NSDictionary *location = @{@"originalPath": file.path,
                                                @"backup": [NSString stringWithFormat:@"%@/%@", itemDirectory.lastPathComponent, backup.lastPathComponent],
                                                @"originalTitle": snapshot[@"title"], @"newTitle": title};
                    ok = [location writeToURL:locationInfo atomically:YES] &&
                         rename(partialPath, [backup.path fileSystemRepresentation]) == 0;
                }
                if (!ok) unlink(partialPath);
            }
        }
        if (!ok) code = 6;
    }
    if (ok) {
        if (lstat(path, &current) != 0 || !S_ISREG(current.st_mode) || current.st_nlink != 1 ||
            ![SRFileIdentity(current) isEqual:identity]) {
            ok = NO;
            code = 3;
        } else {
            ok = rename(temporary, path) == 0;
        }
    }
    if (!ok) unlink(temporary);
    free(temporary);
    close(input);
    if (ok) return backup;
    if (code == 3) return SRFailure(error, code, @"The file changed after preview. Scan the folder again.");
    if (code == 6) return SRFailure(error, code, @"The original could not be backed up.");
    return SRFailure(error, code, @"The title could not be written and verified.");
}

NSString *SRTitleFromFilename(NSURL *file) {
    NSString *base = [[file URLByDeletingPathExtension] lastPathComponent];
    for (NSString *separator in @[@" - ", @" – ", @" — "]) {
        NSRange split = [base rangeOfString:separator];
        if (split.location != NSNotFound && split.location > 0) {
            NSString *candidate = SRTrimTag([base substringFromIndex:NSMaxRange(split)]);
            if (SRIsValidTrackTitle(candidate)) return candidate;
        }
    }
    return nil;
}

NSArray *SRScanTrackTitles(NSURL *folder, NSError **error) {
    NSNumber *rootDirectory = nil;
    if (![folder getResourceValue:&rootDirectory forKey:NSURLIsDirectoryKey error:error] || !rootDirectory.boolValue) {
        return SRFailure(error, 7, @"The selected folder could not be read.");
    }
    NSSet *extensions = [NSSet setWithArray:@[@"mp3", @"m4a", @"flac", @"wav", @"aif", @"aiff", @"aac", @"ogg", @"opus", @"alac", @"m4p", @"wma"]];
    __block BOOL scanFailed = NO;
    NSArray *keys = @[NSURLIsSymbolicLinkKey, NSURLIsRegularFileKey];
    NSDirectoryEnumerator *items = [[NSFileManager defaultManager] enumeratorAtURL:folder
                                      includingPropertiesForKeys:keys options:NSDirectoryEnumerationSkipsHiddenFiles |
                                      NSDirectoryEnumerationSkipsPackageDescendants errorHandler:^BOOL(NSURL *url, NSError *failure) {
        scanFailed = YES;
        return NO;
    }];
    NSMutableArray *rows = [NSMutableArray array];
    if (!items) return SRFailure(error, 7, @"The selected folder could not be read.");
    for (NSURL *file in items) {
        @autoreleasepool {
            NSNumber *link = nil, *regular = nil;
            [file getResourceValue:&link forKey:NSURLIsSymbolicLinkKey error:NULL];
            if (link.boolValue) {
                [items skipDescendants];
                continue;
            }
            if (![extensions containsObject:file.pathExtension.lowercaseString] ||
                ![file getResourceValue:&regular forKey:NSURLIsRegularFileKey error:NULL] || !regular.boolValue) continue;
            NSError *failure = nil;
            NSDictionary *snapshot = SRReadTrackTitle(file, &failure);
            NSMutableDictionary *row = [NSMutableDictionary dictionaryWithObject:file forKey:@"file"];
            if (snapshot) {
                row[@"snapshot"] = snapshot;
                row[@"suggestion"] = SRTitleFromFilename(file) ?: @"";
            } else {
                row[@"error"] = @(failure.code);
            }
            [rows addObject:row];
        }
    }
    if (scanFailed) return SRFailure(error, 7, @"The folder could not be read completely.");
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [[left[@"file"] path] localizedStandardCompare:[right[@"file"] path]];
    }];
    return rows;
}
