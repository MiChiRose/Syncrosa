import Foundation

struct FolderPlaylistTrack: Identifiable, Codable, Equatable {
    let id: String
    let relativePath: String
    let fileName: String
    let artistHint: String
    let titleHint: String
    let fileExtension: String
    let fileSize: Int64
}

struct FolderPlaylistManifest: Codable {
    let schema: String
    let app: String
    let generatedAt: String
    let folderName: String
    let instructions: String
    let tracks: [FolderPlaylistTrack]
}

struct ExternalPlaylistSelection: Codable {
    let playlistName: String?
    let trackIDs: [String]?
    let selectedTrackIDs: [String]?
    let relativePaths: [String]?
    let tracks: [FolderPlaylistSelectedTrack]?
}

struct FolderPlaylistSelectedTrack: Codable {
    let id: String?
    let relativePath: String?
    let fileName: String?
}

struct FolderPlaylistImportProgress {
    let current: Int
    let total: Int
    let fileName: String
}

struct FolderPlaylistImportResult {
    let importedCount: Int
    let skippedCount: Int
    let errors: [String]
}

class FolderPlaylistImportService {
    static let shared = FolderPlaylistImportService()

    private let importableExtensions: Set<String> = ["mp3", "m4a", "mp4", "aac", "wav", "aiff", "aif", "alac"]
    private let manifestExtensions: Set<String> = ["mp3", "m4a", "mp4", "aac", "wav", "aiff", "aif", "alac", "flac"]
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private init() {}

    func scanFolder(_ folderURL: URL) -> [FolderPlaylistTrack] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var tracks: [FolderPlaylistTrack] = []
        while let fileURL = enumerator.nextObject() as? URL {
            let ext = fileURL.pathExtension.lowercased()
            guard manifestExtensions.contains(ext) else { continue }
            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true { continue }

            let relative = relativePath(for: fileURL, base: folderURL)
            let hints = parseArtistTitle(from: fileURL.deletingPathExtension().lastPathComponent)
            let size = Int64(values?.fileSize ?? 0)
            tracks.append(FolderPlaylistTrack(
                id: stableID(relativePath: relative, size: size),
                relativePath: relative,
                fileName: fileURL.lastPathComponent,
                artistHint: hints.artist,
                titleHint: hints.title,
                fileExtension: ext,
                fileSize: size
            ))
        }
        return tracks.sorted { $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending }
    }

    func buildManifest(folderURL: URL, tracks: [FolderPlaylistTrack]) -> FolderPlaylistManifest {
        FolderPlaylistManifest(
            schema: "syncrosa-folder-playlist-manifest-v1",
            app: "Syncrosa",
            generatedAt: dateFormatter.string(from: Date()),
            folderName: folderURL.lastPathComponent,
            instructions: "Ask an AI assistant to choose tracks for a playlist. Return JSON like {\"playlistName\":\"Name\",\"trackIDs\":[\"id-from-this-file\"]}. You may also return selectedTrackIDs, relativePaths, or tracks with id/relativePath.",
            tracks: tracks
        )
    }

    func writeManifest(_ manifest: FolderPlaylistManifest, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: .atomic)
    }

    func readSelection(from url: URL) throws -> ExternalPlaylistSelection {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ExternalPlaylistSelection.self, from: data)
    }

    func selectedTracks(from selection: ExternalPlaylistSelection, availableTracks: [FolderPlaylistTrack]) -> [FolderPlaylistTrack] {
        var selectedKeys = Set<String>()
        for id in selection.trackIDs ?? [] { selectedKeys.insert(id) }
        for id in selection.selectedTrackIDs ?? [] { selectedKeys.insert(id) }
        for path in selection.relativePaths ?? [] { selectedKeys.insert(path) }
        for track in selection.tracks ?? [] {
            if let id = track.id { selectedKeys.insert(id) }
            if let path = track.relativePath { selectedKeys.insert(path) }
            if let name = track.fileName { selectedKeys.insert(name) }
        }
        guard !selectedKeys.isEmpty else { return [] }
        return availableTracks.filter { track in
            selectedKeys.contains(track.id) ||
            selectedKeys.contains(track.relativePath) ||
            selectedKeys.contains(track.fileName)
        }
    }

    func importableURLs(for tracks: [FolderPlaylistTrack], folderURL: URL) -> (urls: [URL], skipped: [FolderPlaylistTrack]) {
        var urls: [URL] = []
        var skipped: [FolderPlaylistTrack] = []
        for track in tracks {
            guard importableExtensions.contains(track.fileExtension.lowercased()) else {
                skipped.append(track)
                continue
            }
            let url = folderURL.appendingPathComponent(track.relativePath)
            if FileManager.default.fileExists(atPath: url.path) {
                urls.append(url)
            } else {
                skipped.append(track)
            }
        }
        return (urls, skipped)
    }

    func estimatedImportSeconds(fileCount: Int, totalBytes: Int64, hddSafeMode: Bool) -> Int {
        let mb = Double(max(0, totalBytes)) / 1_048_576.0
        let base = Double(fileCount) * (hddSafeMode ? 0.9 : 0.35)
        let disk = mb / (hddSafeMode ? 18.0 : 45.0)
        return max(3, Int(ceil(base + disk)))
    }

    func importFolderTracks(
        playlistName: String,
        fileURLs: [URL],
        hddSafeMode: Bool,
        progress: @escaping (FolderPlaylistImportProgress) -> Void,
        completion: @escaping (FolderPlaylistImportResult) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let validURLs = fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !validURLs.isEmpty else {
                DispatchQueue.main.async {
                    completion(FolderPlaylistImportResult(importedCount: 0, skippedCount: fileURLs.count, errors: ["No readable files to import."]))
                }
                return
            }

            var imported = 0
            var errors: [String] = []
            let batchSize = hddSafeMode ? 12 : 25

            for batchStart in stride(from: 0, to: validURLs.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, validURLs.count)
                let batch = Array(validURLs[batchStart..<batchEnd])
                let result = MusicService.shared.importFilesAsPlaylistBatch(
                    playlistName: playlistName,
                    fileURLs: batch,
                    clearPlaylist: batchStart == 0
                )
                imported += result.importedCount
                errors.append(contentsOf: result.errors)

                DispatchQueue.main.async {
                    progress(FolderPlaylistImportProgress(
                        current: batchEnd,
                        total: validURLs.count,
                        fileName: batch.last?.lastPathComponent ?? ""
                    ))
                }
                if hddSafeMode {
                    Thread.sleep(forTimeInterval: 0.08)
                }
            }

            DispatchQueue.main.async {
                completion(FolderPlaylistImportResult(
                    importedCount: imported,
                    skippedCount: fileURLs.count - validURLs.count,
                    errors: errors
                ))
            }
        }
    }

    private func relativePath(for fileURL: URL, base: URL) -> String {
        let basePath = base.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        if filePath.hasPrefix(basePath + "/") {
            return String(filePath.dropFirst(basePath.count + 1))
        }
        return fileURL.lastPathComponent
    }

    private func stableID(relativePath: String, size: Int64) -> String {
        "\(relativePath)#\(size)"
    }

    private func parseArtistTitle(from baseName: String) -> (artist: String, title: String) {
        let cleaned = baseName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = [" - ", " – ", " — ", "-"]
        for separator in separators {
            let parts = cleaned.components(separatedBy: separator)
            if parts.count >= 2 {
                return (
                    parts[0].trimmingCharacters(in: .whitespacesAndNewlines),
                    parts.dropFirst().joined(separator: separator).trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        }
        return ("", cleaned)
    }
}
