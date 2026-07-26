import AudioToolbox
import Foundation

struct IPodConversionResult {
    let convertedFiles: [URL]
    let failures: [(file: URL, message: String)]
    let wasCancelled: Bool
}

struct IPodCompatibilityInspection {
    let issues: [String]

    var isCompatible: Bool { issues.isEmpty }
}

final class IPodCompatibilityService {
    static let shared = IPodCompatibilityService()

    private let workQueue = DispatchQueue(label: "com.michirose.syncrosa.ipod-converter", qos: .userInitiated)
    private let stateLock = NSLock()
    private var cancellationRequested = false

    static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "mp4", "aac", "wav", "aiff", "aif", "caf"
    ]

    private init() {}

    static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func inspect(_ url: URL, deepScan: Bool = true) -> IPodCompatibilityInspection {
        guard isSupported(url) else {
            let name = url.pathExtension.isEmpty ? "unknown" : url.pathExtension.uppercased()
            return IPodCompatibilityInspection(issues: ["unsupported file type \(name)"])
        }

        var sourceFile: ExtAudioFileRef?
        var status = ExtAudioFileOpenURL(url as CFURL, &sourceFile)
        guard status == noErr, let sourceFile else {
            return IPodCompatibilityInspection(issues: [audioErrorDescription("cannot open audio stream", status)])
        }
        defer { ExtAudioFileDispose(sourceFile) }

        var sourceFormat = AudioStreamBasicDescription()
        var propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = ExtAudioFileGetProperty(
            sourceFile,
            kExtAudioFileProperty_FileDataFormat,
            &propertySize,
            &sourceFormat
        )
        guard status == noErr else {
            return IPodCompatibilityInspection(issues: [audioErrorDescription("cannot read audio format", status)])
        }

        var issues: [String] = []
        if sourceFormat.mSampleRate <= 0 || sourceFormat.mSampleRate > 48_000 {
            issues.append("sample rate \(Int(sourceFormat.mSampleRate.rounded())) Hz exceeds the iPod 5G limit")
        }
        if sourceFormat.mChannelsPerFrame == 0 || sourceFormat.mChannelsPerFrame > 2 {
            issues.append("\(sourceFormat.mChannelsPerFrame) audio channels; iPod 5G expects mono or stereo")
        }

        let acceptedFormats: Set<AudioFormatID> = [
            kAudioFormatMPEGLayer3,
            kAudioFormatMPEG4AAC,
            kAudioFormatAppleLossless,
            kAudioFormatLinearPCM
        ]
        if !acceptedFormats.contains(sourceFormat.mFormatID) {
            issues.append("audio codec \(fourCharacterCode(sourceFormat.mFormatID)) is not an iPod 5G-safe codec")
        }

        var audioFile: AudioFileID?
        propertySize = UInt32(MemoryLayout<AudioFileID?>.size)
        if ExtAudioFileGetProperty(
            sourceFile,
            kExtAudioFileProperty_AudioFile,
            &propertySize,
            &audioFile
        ) == noErr, let audioFile {
            var bitRate: UInt32 = 0
            var bitRateSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioFileGetProperty(audioFile, kAudioFilePropertyBitRate, &bitRateSize, &bitRate) == noErr,
               (sourceFormat.mFormatID == kAudioFormatMPEGLayer3 || sourceFormat.mFormatID == kAudioFormatMPEG4AAC),
               bitRate > 320_000 {
                issues.append("bit rate \(bitRate / 1_000) kbps exceeds the iPod 5G limit")
            }
        }

        guard deepScan else {
            return IPodCompatibilityInspection(issues: issues)
        }

        let channels = max(UInt32(1), sourceFormat.mChannelsPerFrame)
        let bytesPerFrame = channels * 2
        var clientFormat = AudioStreamBasicDescription(
            mSampleRate: sourceFormat.mSampleRate > 0 ? sourceFormat.mSampleRate : 44_100,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: bytesPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        status = ExtAudioFileSetProperty(
            sourceFile,
            kExtAudioFileProperty_ClientDataFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
            &clientFormat
        )
        guard status == noErr else {
            issues.append(audioErrorDescription("cannot prepare full decoder check", status))
            return IPodCompatibilityInspection(issues: issues)
        }

        let framesPerChunk: UInt32 = 16_384
        let bufferSize = Int(framesPerChunk * bytesPerFrame)
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer { buffer.deallocate() }

        while true {
            var frames = framesPerChunk
            var bufferList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: channels,
                    mDataByteSize: UInt32(bufferSize),
                    mData: buffer
                )
            )
            status = ExtAudioFileRead(sourceFile, &frames, &bufferList)
            if status != noErr {
                issues.append(audioErrorDescription("decoder failed before the end of the file", status))
                break
            }
            if frames == 0 {
                break
            }
        }
        return IPodCompatibilityInspection(issues: issues)
    }

    static func destinationURL(for source: URL, in directory: URL, fileManager: FileManager = .default) -> URL {
        let rawBase = source.deletingPathExtension().lastPathComponent
        let base = sanitizedFilenameComponent(rawBase)
        var candidate = directory.appendingPathComponent("\(base) (iPod).m4a")
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) (iPod \(suffix)).m4a")
            suffix += 1
        }
        return candidate
    }

    static func sanitizedFilenameComponent(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let parts = value.components(separatedBy: forbidden)
        let cleaned = parts.joined(separator: "-")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Audio" : String(cleaned.prefix(120))
    }

    func convert(
        files: [URL],
        to outputDirectory: URL,
        progress: @escaping (_ completed: Int, _ total: Int, _ filename: String) -> Void,
        completion: @escaping (IPodConversionResult) -> Void
    ) {
        stateLock.lock()
        cancellationRequested = false
        stateLock.unlock()

        workQueue.async {
            let directoryAccess = outputDirectory.startAccessingSecurityScopedResource()
            defer {
                if directoryAccess {
                    outputDirectory.stopAccessingSecurityScopedResource()
                }
            }

            var converted: [URL] = []
            var failures: [(file: URL, message: String)] = []
            var cancelled = false

            for (index, source) in files.enumerated() {
                if self.isCancellationRequested {
                    cancelled = true
                    break
                }

                DispatchQueue.main.async {
                    progress(index, files.count, source.lastPathComponent)
                }

                guard Self.isSupported(source) else {
                    failures.append((source, "Unsupported audio format."))
                    continue
                }

                let sourceAccess = source.startAccessingSecurityScopedResource()
                let destination = Self.destinationURL(for: source, in: outputDirectory)
                let conversionError = self.encodeCompatibleAudio(source: source, destination: destination)

                if sourceAccess {
                    source.stopAccessingSecurityScopedResource()
                }

                if conversionError == nil {
                    converted.append(destination)
                } else if self.isCancellationRequested {
                    try? FileManager.default.removeItem(at: destination)
                    cancelled = true
                } else {
                    try? FileManager.default.removeItem(at: destination)
                    failures.append((source, conversionError ?? "Audio conversion failed."))
                }

                DispatchQueue.main.async {
                    progress(index + 1, files.count, source.lastPathComponent)
                }

                if cancelled {
                    break
                }
            }

            let result = IPodConversionResult(
                convertedFiles: converted,
                failures: failures,
                wasCancelled: cancelled || self.isCancellationRequested
            )
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    func cancel() {
        stateLock.lock()
        cancellationRequested = true
        stateLock.unlock()
    }

    private var isCancellationRequested: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cancellationRequested
    }

    private func encodeCompatibleAudio(source: URL, destination: URL) -> String? {
        var sourceFile: ExtAudioFileRef?
        var destinationFile: ExtAudioFileRef?
        var status = ExtAudioFileOpenURL(source as CFURL, &sourceFile)
        guard status == noErr, let sourceFile else {
            return audioError("Could not open the audio file", status)
        }
        defer { ExtAudioFileDispose(sourceFile) }

        var sourceFormat = AudioStreamBasicDescription()
        var propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = ExtAudioFileGetProperty(
            sourceFile,
            kExtAudioFileProperty_FileDataFormat,
            &propertySize,
            &sourceFormat
        )
        guard status == noErr else {
            return audioError("Could not read the audio format", status)
        }

        let preservesALAC = sourceFormat.mFormatID == kAudioFormatAppleLossless
        if preservesALAC && (sourceFormat.mSampleRate <= 0 || sourceFormat.mSampleRate > 48_000) {
            return "This ALAC file uses \(Int(sourceFormat.mSampleRate.rounded())) Hz. Syncrosa will not reduce its sample rate automatically; the original remains unchanged."
        }
        if preservesALAC && (sourceFormat.mChannelsPerFrame == 0 || sourceFormat.mChannelsPerFrame > 2) {
            return "This ALAC file has \(sourceFormat.mChannelsPerFrame) channels. Syncrosa will not downmix lossless audio automatically; the original remains unchanged."
        }

        let channels = preservesALAC
            ? sourceFormat.mChannelsPerFrame
            : max(1, min(sourceFormat.mChannelsPerFrame, 2))
        let sampleRate = preservesALAC ? sourceFormat.mSampleRate : 44_100
        let losslessFlag: AudioFormatFlags
        let bitsPerChannel: UInt32
        let bytesPerSample: UInt32
        switch sourceFormat.mFormatFlags {
        case kAppleLosslessFormatFlag_20BitSourceData where preservesALAC:
            losslessFlag = kAppleLosslessFormatFlag_20BitSourceData
            bitsPerChannel = 20
            bytesPerSample = 3
        case kAppleLosslessFormatFlag_24BitSourceData where preservesALAC:
            losslessFlag = kAppleLosslessFormatFlag_24BitSourceData
            bitsPerChannel = 24
            bytesPerSample = 3
        case kAppleLosslessFormatFlag_32BitSourceData where preservesALAC:
            losslessFlag = kAppleLosslessFormatFlag_32BitSourceData
            bitsPerChannel = 32
            bytesPerSample = 4
        default:
            losslessFlag = kAppleLosslessFormatFlag_16BitSourceData
            bitsPerChannel = 16
            bytesPerSample = 2
        }
        let bytesPerFrame = channels * bytesPerSample
        let clientFlags = kLinearPCMFormatFlagIsSignedInteger |
            (bitsPerChannel == 20 ? kLinearPCMFormatFlagIsAlignedHigh : kAudioFormatFlagIsPacked)
        var clientFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: clientFlags,
            mBytesPerPacket: bytesPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: channels,
            mBitsPerChannel: bitsPerChannel,
            mReserved: 0
        )

        status = ExtAudioFileSetProperty(
            sourceFile,
            kExtAudioFileProperty_ClientDataFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
            &clientFormat
        )
        guard status == noErr else {
            return audioError("Could not prepare the audio decoder", status)
        }

        var destinationFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: preservesALAC ? kAudioFormatAppleLossless : kAudioFormatMPEG4AAC,
            mFormatFlags: preservesALAC ? losslessFlag : 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: preservesALAC ? 4_096 : 1_024,
            mBytesPerFrame: 0,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 0,
            mReserved: 0
        )
        status = ExtAudioFileCreateWithURL(
            destination as CFURL,
            kAudioFileM4AType,
            &destinationFormat,
            nil,
            AudioFileFlags.eraseFile.rawValue,
            &destinationFile
        )
        guard status == noErr, let destinationFile else {
            return audioError("Could not create the M4A file", status)
        }
        defer { ExtAudioFileDispose(destinationFile) }

        status = ExtAudioFileSetProperty(
            destinationFile,
            kExtAudioFileProperty_ClientDataFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
            &clientFormat
        )
        guard status == noErr else {
            return audioError(preservesALAC ? "Could not prepare the ALAC encoder" : "Could not prepare the AAC encoder", status)
        }

        if !preservesALAC {
            var converter: AudioConverterRef?
            propertySize = UInt32(MemoryLayout<AudioConverterRef?>.size)
            if ExtAudioFileGetProperty(
                destinationFile,
                kExtAudioFileProperty_AudioConverter,
                &propertySize,
                &converter
            ) == noErr, let converter {
                var bitrate: UInt32 = channels == 1 ? 96_000 : 192_000
                AudioConverterSetProperty(
                    converter,
                    kAudioConverterEncodeBitRate,
                    UInt32(MemoryLayout<UInt32>.size),
                    &bitrate
                )
            }
        }

        let framesPerChunk: UInt32 = 4_096
        let bufferSize = Int(framesPerChunk * bytesPerFrame)
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer { buffer.deallocate() }

        while true {
            if isCancellationRequested {
                return "Conversion cancelled."
            }

            var frames = framesPerChunk
            var bufferList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: channels,
                    mDataByteSize: UInt32(bufferSize),
                    mData: buffer
                )
            )
            status = ExtAudioFileRead(sourceFile, &frames, &bufferList)
            guard status == noErr else {
                return audioError("Could not decode the audio file", status)
            }
            if frames == 0 {
                break
            }
            status = ExtAudioFileWrite(destinationFile, frames, &bufferList)
            guard status == noErr else {
                return audioError("Could not write converted audio", status)
            }
        }
        return nil
    }

    private func audioError(_ prefix: String, _ status: OSStatus) -> String {
        Self.audioErrorDescription(prefix, status)
    }

    private static func audioErrorDescription(_ prefix: String, _ status: OSStatus) -> String {
        let value = UInt32(bitPattern: status)
        let characters = [
            Character(UnicodeScalar((value >> 24) & 0xff)!),
            Character(UnicodeScalar((value >> 16) & 0xff)!),
            Character(UnicodeScalar((value >> 8) & 0xff)!),
            Character(UnicodeScalar(value & 0xff)!)
        ]
        let code = String(characters)
        let printable = code.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value < 127 }
        return "\(prefix) (\(printable ? code : String(status)))."
    }

    private static func fourCharacterCode(_ value: UInt32) -> String {
        let characters = [
            UnicodeScalar((value >> 24) & 0xff),
            UnicodeScalar((value >> 16) & 0xff),
            UnicodeScalar((value >> 8) & 0xff),
            UnicodeScalar(value & 0xff)
        ].compactMap { $0 }.map(Character.init)
        let code = String(characters)
        return code.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value < 127 }
            ? code
            : String(value)
    }
}
