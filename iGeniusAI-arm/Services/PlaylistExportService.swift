import Foundation

class PlaylistExportService {
    static let shared = PlaylistExportService()
    
    struct TrackFile {
        let name: String
        let artist: String
        let filePath: String  // POSIX path
        let fileSize: Int64
        let isDRM: Bool
    }
    
    struct ExportProgress {
        let currentTrack: Int
        let totalTracks: Int
        let currentTrackName: String
        let bytesCopied: Int64
        let totalBytes: Int64
    }
    
    enum ExportMode {
        case all
        case fitAvailable // Copy what fits (random selection)
    }
    
    struct ExportResult {
        let copiedCount: Int
        let skippedDRM: Int
        let skippedNotDownloaded: Int
        let totalBytesCopied: Int64
        let errors: [String]
    }
    
    private init() {}
    
    func exportToUSB(
        tracks: [TrackFile],
        destination: URL,
        mode: ExportMode,
        progress: @escaping (ExportProgress) -> Void,
        completion: @escaping (ExportResult) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            var tracksToCopy = tracks
            var skippedDRM = 0
            var skippedNotDownloaded = 0
            var errors: [String] = []
            
            // 1. Filter out DRM/missing tracks first
            let filteredTracks = tracksToCopy.filter { track in
                if track.isDRM {
                    skippedDRM += 1
                    return false
                }
                if track.filePath.isEmpty || track.filePath == "missing value" || !FileManager.default.fileExists(atPath: track.filePath) {
                    skippedNotDownloaded += 1
                    return false
                }
                return true
            }
            
            tracksToCopy = filteredTracks
            
            // 2. Check if we need to fit available space
            var availableSpace: Int64 = 0
            if let attrs = try? destination.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
               let cap = attrs.volumeAvailableCapacity {
                availableSpace = Int64(cap)
            }
            
            if mode == .fitAvailable {
                // Shuffle tracks to copy random subset
                tracksToCopy.shuffle()
                
                var accumulatedSize: Int64 = 0
                var fittedTracks: [TrackFile] = []
                for track in tracksToCopy {
                    if accumulatedSize + track.fileSize <= availableSpace {
                        accumulatedSize += track.fileSize
                        fittedTracks.append(track)
                    }
                }
                tracksToCopy = fittedTracks
            } else {
                // Check if all tracks fit
                let totalSize = tracksToCopy.reduce(0) { $0 + $1.fileSize }
                if totalSize > availableSpace {
                    // Report error and stop immediately
                    completion(ExportResult(
                        copiedCount: 0,
                        skippedDRM: skippedDRM,
                        skippedNotDownloaded: skippedNotDownloaded,
                        totalBytesCopied: 0,
                        errors: ["Not enough space on drive"]
                    ))
                    return
                }
            }
            
            let totalTracks = tracksToCopy.count
            let totalBytes = tracksToCopy.reduce(0) { $0 + $1.fileSize }
            var currentTrackIndex = 0
            var totalBytesCopied: Int64 = 0
            var copiedCount = 0
            
            let fm = FileManager.default
            
            for track in tracksToCopy {
                currentTrackIndex += 1
                let sourceURL = URL(fileURLWithPath: track.filePath)
                
                // Construct unique destination URL
                var destFilename = "\(self.sanitizeFilename(track.artist)) - \(self.sanitizeFilename(track.name)).\(sourceURL.pathExtension)"
                var destURL = destination.appendingPathComponent(destFilename)
                
                var suffix = 2
                while fm.fileExists(atPath: destURL.path) {
                    destFilename = "\(self.sanitizeFilename(track.artist)) - \(self.sanitizeFilename(track.name))_\(suffix).\(sourceURL.pathExtension)"
                    destURL = destination.appendingPathComponent(destFilename)
                    suffix += 1
                }
                
                // Copy file in chunks of 1MB to support progress reporting and avoid memory spikes
                do {
                    try self.chunkedCopy(from: sourceURL, to: destURL) { bytesInChunk in
                        totalBytesCopied += bytesInChunk
                        let prog = ExportProgress(
                            currentTrack: currentTrackIndex,
                            totalTracks: totalTracks,
                            currentTrackName: "\(track.artist) - \(track.name)",
                            bytesCopied: totalBytesCopied,
                            totalBytes: totalBytes
                        )
                        DispatchQueue.main.async {
                            progress(prog)
                        }
                    }
                    copiedCount += 1
                } catch {
                    errors.append("\(track.artist) - \(track.name): \(error.localizedDescription)")
                    // Check if destination drive was disconnected (path does not exist)
                    if !fm.fileExists(atPath: destination.path) {
                        completion(ExportResult(
                            copiedCount: copiedCount,
                            skippedDRM: skippedDRM,
                            skippedNotDownloaded: skippedNotDownloaded,
                            totalBytesCopied: totalBytesCopied,
                            errors: errors + ["Drive disconnected"]
                        ))
                        return
                    }
                }
            }
            
            completion(ExportResult(
                copiedCount: copiedCount,
                skippedDRM: skippedDRM,
                skippedNotDownloaded: skippedNotDownloaded,
                totalBytesCopied: totalBytesCopied,
                errors: errors
            ))
        }
    }
    
    private func sanitizeFilename(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return name.components(separatedBy: invalidCharacters).joined(separator: "_")
    }
    
    private func chunkedCopy(from source: URL, to destination: URL, progress: @escaping (Int64) -> Void) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        
        let sourceHandle = try FileHandle(forReadingFrom: source)
        defer { sourceHandle.closeFile() }
        
        fm.createFile(atPath: destination.path, contents: nil)
        let destHandle = try FileHandle(forWritingTo: destination)
        defer { destHandle.closeFile() }
        
        let chunkSize = 1024 * 1024 // 1 MB
        
        while true {
            let data: Data
            if #available(macOS 10.15.4, *) {
                guard let d = try sourceHandle.read(upToCount: chunkSize) else { break }
                data = d
            } else {
                data = sourceHandle.readData(ofLength: chunkSize)
            }
            
            if data.isEmpty { break }
            
            if #available(macOS 10.15.4, *) {
                try destHandle.write(contentsOf: data)
            } else {
                destHandle.write(data)
            }
            
            progress(Int64(data.count))
        }
    }
}
