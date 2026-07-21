import Foundation

enum LibraryToolkitSource: String, CaseIterable, Codable, Identifiable {
    case musicLibrary
    case localFilename
    case iTunesSearch
    case musicBrainz
    case discogs
    case aiAgent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .musicLibrary:
            return "Music Library"
        case .localFilename:
            return "Local Filename"
        case .iTunesSearch:
            return "iTunes Search"
        case .musicBrainz:
            return "MusicBrainz"
        case .discogs:
            return "Discogs"
        case .aiAgent:
            return "External AI"
        }
    }
}

struct LibraryToolkitPreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var renameTemplate: String
    var enabledSources: [LibraryToolkitSource]
    var includeArtwork: Bool
    var onlyMissingFields: Bool
    var advancedMode: Bool

    static let defaults: [LibraryToolkitPreset] = [
        LibraryToolkitPreset(
            id: UUID(uuidString: "9E608E9F-64EF-44EA-A3E9-938EA2386CC1")!,
            name: "Safe Metadata Audit",
            renameTemplate: "{artist} - {title}",
            enabledSources: [.musicLibrary, .localFilename],
            includeArtwork: true,
            onlyMissingFields: true,
            advancedMode: false
        ),
        LibraryToolkitPreset(
            id: UUID(uuidString: "7BA82A1A-A37B-458F-8638-D76A79274C0B")!,
            name: "iPod Cleanup",
            renameTemplate: "{track} {artist} - {title}",
            enabledSources: [.musicLibrary, .localFilename],
            includeArtwork: false,
            onlyMissingFields: true,
            advancedMode: false
        ),
        LibraryToolkitPreset(
            id: UUID(uuidString: "452C5815-3763-465A-8BC5-1621672A4AF6")!,
            name: "Artwork Pass",
            renameTemplate: "{artist} - {title}",
            enabledSources: [.musicLibrary, .iTunesSearch],
            includeArtwork: true,
            onlyMissingFields: true,
            advancedMode: true
        )
    ]
}

struct LibraryToolkitTrackSnapshot: Identifiable, Codable, Equatable {
    var id: String { persistentID.isEmpty ? path : persistentID }
    let persistentID: String
    let title: String
    let artist: String
    let album: String
    let albumArtist: String
    let genre: String
    let composer: String
    let comments: String
    let path: String
    let kind: String
    let year: Int
    let trackNumber: Int
    let discNumber: Int
    let bpm: Int
    let rating: Int
    let size: Int64
    let hasArtwork: Bool
    let fileExists: Bool

    var filename: String {
        path.isEmpty ? title : URL(fileURLWithPath: path).lastPathComponent
    }

    var format: String {
        let ext = URL(fileURLWithPath: path).pathExtension.uppercased()
        return ext.isEmpty ? kind : ext
    }

    var missingFields: [String] {
        var fields: [String] = []
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields.append("title") }
        if artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields.append("artist") }
        if album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields.append("album") }
        if genre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields.append("genre") }
        if year <= 0 { fields.append("year") }
        if !hasArtwork { fields.append("artwork") }
        if path.isEmpty || !fileExists { fields.append("linked file") }
        return fields
    }

    var completenessScore: Int {
        let total = 7
        let complete = total - missingFields.count
        return max(0, min(100, Int((Double(complete) / Double(total)) * 100.0)))
    }
}

struct LibraryToolkitChangePreview: Identifiable, Codable, Equatable {
    let id: UUID
    let trackID: String
    let trackTitle: String
    let field: String
    let oldValue: String
    let newValue: String
    let source: String
    let risk: String
    let path: String
}

struct LibraryToolkitUndoOperation: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let trackID: String
    let originalPath: String
    let currentPath: String
    let action: String
}

struct LibraryToolkitUndoPackage: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let name: String
    let operations: [LibraryToolkitUndoOperation]
}

struct LibraryToolkitReport: Codable {
    let generatedAt: Date
    let appVersion: String
    let presetName: String
    let enabledSources: [String]
    let renameTemplate: String
    let onlyMissingFields: Bool
    let includeArtwork: Bool
    let advancedMode: Bool
    let totalTracks: Int
    let averageCompleteness: Int
    let missingFiles: Int
    let missingArtwork: Int
    let unlinkedFolderFiles: Int
    let missingFieldCounts: [String: Int]
    let formatCounts: [String: Int]
    let unlinkedFilePaths: [String]
    let previews: [LibraryToolkitChangePreview]
    let tracks: [LibraryToolkitTrackSnapshot]
}

final class LibraryToolkitService {
    static let shared = LibraryToolkitService()

    private let fileManager = FileManager.default
    private let musicExtensions = Set(["mp3", "m4a", "mp4", "aac", "wav", "aiff", "aif", "alac", "flac"])

    private var toolkitDirectory: URL {
        SyncrosaStorage.applicationSupportDirectory.appendingPathComponent("LibraryToolkit", isDirectory: true)
    }

    private var presetsURL: URL {
        toolkitDirectory.appendingPathComponent("presets.json")
    }

    private var undoDirectory: URL {
        toolkitDirectory.appendingPathComponent("Undo Packages", isDirectory: true)
    }

    func loadPresets() -> [LibraryToolkitPreset] {
        guard let data = try? Data(contentsOf: presetsURL),
              let presets = try? JSONDecoder.syncrosa.decode([LibraryToolkitPreset].self, from: data),
              !presets.isEmpty else {
            return LibraryToolkitPreset.defaults
        }
        return presets
    }

    func savePresets(_ presets: [LibraryToolkitPreset]) throws {
        try SyncrosaStorage.ensureDirectory(toolkitDirectory)
        let data = try JSONEncoder.prettySyncrosa.encode(presets)
        try data.write(to: presetsURL, options: .atomic)
    }

    func loadUndoPackages() -> [LibraryToolkitUndoPackage] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: undoDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return files
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder.syncrosa.decode(LibraryToolkitUndoPackage.self, from: data)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func loadTracks(progress: @escaping (Int, Int) -> Void) -> [LibraryToolkitTrackSnapshot] {
        MusicService.shared.getLibraryToolkitRawTracks(progress: progress).map { raw in
            LibraryToolkitTrackSnapshot(
                persistentID: raw.persistentID,
                title: raw.name,
                artist: raw.artist,
                album: raw.album,
                albumArtist: raw.albumArtist,
                genre: raw.genre,
                composer: raw.composer,
                comments: raw.comments,
                path: raw.path,
                kind: raw.kind,
                year: raw.year,
                trackNumber: raw.trackNumber,
                discNumber: raw.discNumber,
                bpm: raw.bpm,
                rating: raw.rating,
                size: raw.size,
                hasArtwork: raw.hasArtwork,
                fileExists: !raw.path.isEmpty && fileManager.fileExists(atPath: raw.path)
            )
        }
    }

    func makePreviews(
        tracks: [LibraryToolkitTrackSnapshot],
        preset: LibraryToolkitPreset,
        renameTemplate: String
    ) -> [LibraryToolkitChangePreview] {
        let trimmedTemplate = renameTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        var previews: [LibraryToolkitChangePreview] = []

        for track in tracks {
            if preset.enabledSources.contains(.localFilename),
               let filenameSuggestion = filenameMetadataSuggestion(for: track) {
                if shouldSuggest(field: "artist", current: track.artist, preset: preset),
                   !filenameSuggestion.artist.isEmpty,
                   filenameSuggestion.artist.caseInsensitiveCompare(track.artist) != .orderedSame {
                    previews.append(change(track: track, field: "artist", old: track.artist, new: filenameSuggestion.artist, source: LibraryToolkitSource.localFilename.title, risk: "low"))
                }
                if shouldSuggest(field: "title", current: track.title, preset: preset),
                   !filenameSuggestion.title.isEmpty,
                   filenameSuggestion.title.caseInsensitiveCompare(track.title) != .orderedSame {
                    previews.append(change(track: track, field: "title", old: track.title, new: filenameSuggestion.title, source: LibraryToolkitSource.localFilename.title, risk: "low"))
                }
            }

            if !trimmedTemplate.isEmpty,
               let renamePreview = renamedPath(for: track, template: trimmedTemplate),
               renamePreview != track.path {
                previews.append(change(track: track, field: "filename", old: track.path, new: renamePreview, source: "Rename Template", risk: "medium"))
            }
        }

        return previews
    }

    func createReport(
        tracks: [LibraryToolkitTrackSnapshot],
        previews: [LibraryToolkitChangePreview],
        unlinkedFiles: [URL],
        preset: LibraryToolkitPreset
    ) -> LibraryToolkitReport {
        let average = tracks.isEmpty ? 0 : tracks.map(\.completenessScore).reduce(0, +) / tracks.count
        var missingFieldCounts: [String: Int] = [:]
        var formatCounts: [String: Int] = [:]
        for track in tracks {
            for field in track.missingFields {
                missingFieldCounts[field, default: 0] += 1
            }
            formatCounts[track.format, default: 0] += 1
        }

        return LibraryToolkitReport(
            generatedAt: Date(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            presetName: preset.name,
            enabledSources: preset.enabledSources.map(\.title).sorted(),
            renameTemplate: preset.renameTemplate,
            onlyMissingFields: preset.onlyMissingFields,
            includeArtwork: preset.includeArtwork,
            advancedMode: preset.advancedMode,
            totalTracks: tracks.count,
            averageCompleteness: average,
            missingFiles: tracks.filter { !$0.fileExists }.count,
            missingArtwork: tracks.filter { !$0.hasArtwork }.count,
            unlinkedFolderFiles: unlinkedFiles.count,
            missingFieldCounts: missingFieldCounts,
            formatCounts: formatCounts,
            unlinkedFilePaths: unlinkedFiles.map(\.path),
            previews: previews,
            tracks: tracks
        )
    }

    func writeReport(_ report: LibraryToolkitReport, to url: URL) throws {
        let data = try JSONEncoder.prettySyncrosa.encode(report)
        try data.write(to: url, options: .atomic)
    }

    func writeCSVReport(tracks: [LibraryToolkitTrackSnapshot], to url: URL) throws {
        var lines = ["title,artist,album,genre,year,format,score,path"]
        for track in tracks {
            lines.append([
                csv(track.title),
                csv(track.artist),
                csv(track.album),
                csv(track.genre),
                "\(track.year)",
                csv(track.format),
                "\(track.completenessScore)",
                csv(track.path)
            ].joined(separator: ","))
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    func createUndoPackage(name: String, previews: [LibraryToolkitChangePreview]) throws -> LibraryToolkitUndoPackage {
        try SyncrosaStorage.ensureDirectory(undoDirectory)
        let operations = previews
            .filter { $0.field == "filename" && !$0.path.isEmpty }
            .map {
                LibraryToolkitUndoOperation(
                    id: UUID(),
                    createdAt: Date(),
                    trackID: $0.trackID,
                    originalPath: $0.oldValue,
                    currentPath: $0.newValue,
                    action: "rename"
                )
            }
        let package = LibraryToolkitUndoPackage(id: UUID(), createdAt: Date(), name: name, operations: operations)
        let url = undoDirectory.appendingPathComponent("\(package.id.uuidString).json")
        try JSONEncoder.prettySyncrosa.encode(package).write(to: url, options: .atomic)
        return package
    }

    func createMetadataUndoPackage(name: String, previews: [LibraryToolkitChangePreview]) throws -> LibraryToolkitUndoPackage {
        try SyncrosaStorage.ensureDirectory(undoDirectory)
        let operations = previews
            .filter { $0.field != "filename" && !$0.trackID.isEmpty }
            .map {
                LibraryToolkitUndoOperation(
                    id: UUID(),
                    createdAt: Date(),
                    trackID: $0.trackID,
                    originalPath: $0.oldValue,
                    currentPath: $0.newValue,
                    action: "metadata:\($0.field)"
                )
            }
        let package = LibraryToolkitUndoPackage(id: UUID(), createdAt: Date(), name: name, operations: operations)
        let url = undoDirectory.appendingPathComponent("\(package.id.uuidString).json")
        try JSONEncoder.prettySyncrosa.encode(package).write(to: url, options: .atomic)
        return package
    }

    func applyRenamePreviews(_ previews: [LibraryToolkitChangePreview]) throws -> LibraryToolkitUndoPackage {
        let renamePreviews = previews.filter { $0.field == "filename" && !$0.oldValue.isEmpty && !$0.newValue.isEmpty }
        guard !renamePreviews.isEmpty else {
            throw LibraryToolkitError.noRenamePreviews
        }

        var destinations = Set<String>()
        for preview in renamePreviews {
            let oldURL = URL(fileURLWithPath: preview.oldValue).standardizedFileURL
            let newURL = URL(fileURLWithPath: preview.newValue).standardizedFileURL
            guard fileManager.fileExists(atPath: oldURL.path) else {
                throw LibraryToolkitError.sourceMissing(oldURL.path)
            }
            guard oldURL.path != newURL.path else { continue }
            guard destinations.insert(newURL.path).inserted else {
                throw LibraryToolkitError.duplicateDestination(newURL.path)
            }
            if fileManager.fileExists(atPath: newURL.path) {
                throw LibraryToolkitError.destinationExists(newURL.path)
            }
        }

        let package = try createUndoPackage(name: "Rename Template", previews: renamePreviews)
        var completed: [(old: URL, new: URL)] = []
        do {
            for preview in renamePreviews {
                let oldURL = URL(fileURLWithPath: preview.oldValue).standardizedFileURL
                let newURL = URL(fileURLWithPath: preview.newValue).standardizedFileURL
                guard oldURL.path != newURL.path else { continue }
                try fileManager.moveItem(at: oldURL, to: newURL)
                completed.append((oldURL, newURL))
            }
        } catch {
            for move in completed.reversed()
            where fileManager.fileExists(atPath: move.new.path) && !fileManager.fileExists(atPath: move.old.path) {
                try? fileManager.moveItem(at: move.new, to: move.old)
            }
            throw error
        }
        return package
    }

    func restoreUndoPackage(_ package: LibraryToolkitUndoPackage) throws -> Int {
        var restored = 0
        for operation in package.operations {
            if operation.action == "rename" {
                let currentURL = URL(fileURLWithPath: operation.currentPath)
                let originalURL = URL(fileURLWithPath: operation.originalPath)
                guard fileManager.fileExists(atPath: currentURL.path),
                      !fileManager.fileExists(atPath: originalURL.path) else {
                    continue
                }
                try fileManager.moveItem(at: currentURL, to: originalURL)
                restored += 1
            } else if operation.action.hasPrefix("metadata:") {
                let field = String(operation.action.dropFirst("metadata:".count))
                if MusicService.shared.updateTrack(persistentID: operation.trackID, properties: [field: operation.originalPath]) {
                    restored += 1
                }
            }
        }
        return restored
    }

    func writeArtworkCSV(tracks: [LibraryToolkitTrackSnapshot], to url: URL) throws {
        var lines = ["title,artist,album,format,has_artwork,path"]
        for track in tracks {
            lines.append([
                csv(track.title),
                csv(track.artist),
                csv(track.album),
                csv(track.format),
                track.hasArtwork ? "true" : "false",
                csv(track.path)
            ].joined(separator: ","))
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    func scanUnlinkedFiles(in folder: URL, linkedTracks: [LibraryToolkitTrackSnapshot]) -> [URL] {
        let linkedPaths = Set(linkedTracks.map { URL(fileURLWithPath: $0.path).standardizedFileURL.path })
        let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var files: [URL] = []

        while let fileURL = enumerator?.nextObject() as? URL {
            guard musicExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
            let standardized = fileURL.standardizedFileURL.path
            if !linkedPaths.contains(standardized) {
                files.append(fileURL)
            }
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func renamedPath(for track: LibraryToolkitTrackSnapshot, template: String) -> String? {
        guard !track.path.isEmpty else { return nil }
        let oldURL = URL(fileURLWithPath: track.path)
        let ext = oldURL.pathExtension
        var name = template
        let replacements: [String: String] = [
            "{artist}": track.artist,
            "{title}": track.title,
            "{album}": track.album,
            "{albumArtist}": track.albumArtist,
            "{genre}": track.genre,
            "{year}": track.year > 0 ? "\(track.year)" : "",
            "{track}": track.trackNumber > 0 ? String(format: "%02d", track.trackNumber) : "",
            "{disc}": track.discNumber > 0 ? "\(track.discNumber)" : ""
        ]
        for (token, value) in replacements {
            name = name.replacingOccurrences(of: token, with: value)
        }
        guard !name.contains("{") && !name.contains("}") else { return nil }
        name = sanitizeFilename(name)
        guard !name.isEmpty else { return nil }
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(name).appendingPathExtension(ext)
        return newURL.path
    }

    private func filenameMetadataSuggestion(for track: LibraryToolkitTrackSnapshot) -> (artist: String, title: String)? {
        let base = URL(fileURLWithPath: track.path).deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }

        let separators = [" - ", " – ", " — "]
        for separator in separators where base.contains(separator) {
            let parts = base.components(separatedBy: separator)
            guard parts.count >= 2 else { continue }
            return (cleanMetadataGuess(parts[0]), cleanMetadataGuess(parts.dropFirst().joined(separator: separator)))
        }

        return ("", cleanMetadataGuess(base))
    }

    private func shouldSuggest(field: String, current: String, preset: LibraryToolkitPreset) -> Bool {
        if !preset.onlyMissingFields { return true }
        return current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func change(
        track: LibraryToolkitTrackSnapshot,
        field: String,
        old: String,
        new: String,
        source: String,
        risk: String
    ) -> LibraryToolkitChangePreview {
        LibraryToolkitChangePreview(
            id: UUID(),
            trackID: track.persistentID,
            trackTitle: track.title.isEmpty ? track.filename : track.title,
            field: field,
            oldValue: old,
            newValue: new,
            source: source,
            risk: risk,
            path: track.path
        )
    }

    private func sanitizeFilename(_ value: String) -> String {
        let illegal = CharacterSet(charactersIn: "/:")
        let sanitized = value
            .components(separatedBy: illegal)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private func cleanMetadataGuess(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func csv(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

enum LibraryToolkitError: LocalizedError {
    case noRenamePreviews
    case sourceMissing(String)
    case destinationExists(String)
    case duplicateDestination(String)

    var errorDescription: String? {
        switch self {
        case .noRenamePreviews:
            return "No rename previews are available."
        case .sourceMissing(let path):
            return "Source file is missing: \(path)"
        case .destinationExists(let path):
            return "Destination already exists: \(path)"
        case .duplicateDestination(let path):
            return "More than one file would be renamed to: \(path)"
        }
    }
}

private extension JSONEncoder {
    static var prettySyncrosa: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var syncrosa: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
