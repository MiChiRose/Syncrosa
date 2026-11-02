import Foundation

struct MusicLibraryAITrack: Codable, Equatable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let genre: String
    let year: Int
}

struct MusicLibraryAIManifest: Codable, Equatable {
    let schema: String
    let app: String
    let generatedAt: String
    let instructions: String
    let trackCount: Int
    let selectionExample: MusicLibraryAISelection
    let tracks: [MusicLibraryAITrack]
}

struct MusicLibraryAISelectedTrack: Codable, Equatable {
    let id: String?
    let persistentID: String?
}

struct MusicLibraryAISelection: Codable, Equatable {
    let playlistName: String?
    let trackIDs: [String]?
    let selectedTrackIDs: [String]?
    let tracks: [MusicLibraryAISelectedTrack]?
}

final class MusicLibraryExchangeService {
    static let shared = MusicLibraryExchangeService()

    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private init() {}

    func makeManifest(from tracks: [MusicTrack]) -> MusicLibraryAIManifest {
        MusicLibraryAIManifest(
            schema: "syncrosa-music-library-v1",
            app: "Syncrosa",
            generatedAt: formatter.string(from: Date()),
            instructions: "This file contains the entire readable music catalog, not a random sample. Ask the user for a mood, occasion and desired track count, then choose from all tracks. Return ONLY one JSON object in the selectionExample format: playlistName and an ordered trackIDs array. Copy each 16-character ID exactly from tracks; do not invent IDs, repeat tracks, return the catalog, or add Markdown. Select no more tracks than the catalog contains. The user can use any assistant or agent; no Syncrosa API key or paid subscription is required to export or import this file.",
            trackCount: tracks.count,
            selectionExample: MusicLibraryAISelection(playlistName: "My Playlist", trackIDs: Array(tracks.prefix(2).map(\.persistentID)), selectedTrackIDs: nil, tracks: nil),
            tracks: tracks.map {
                MusicLibraryAITrack(
                    id: $0.persistentID,
                    title: $0.name,
                    artist: $0.artist,
                    album: $0.album,
                    genre: $0.genre,
                    year: $0.year
                )
            }
        )
    }

    func writeManifest(_ manifest: MusicLibraryAIManifest, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: url, options: .atomic)
    }

    func readSelection(from url: URL) throws -> MusicLibraryAISelection {
        let data = try Data(contentsOf: url)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MusicLibraryExchangeError.invalidSelection
        }
        if let schemaValue = root["schema"] {
            guard let schema = schemaValue as? String else { throw MusicLibraryExchangeError.invalidSelection }
            let normalizedSchema = schema.lowercased()
            if normalizedSchema.contains("library") || normalizedSchema.contains("manifest") {
                throw MusicLibraryExchangeError.catalogInsteadOfSelection
            }
        }
        // Accept replies made from previous Cocoa export instructions as well.
        let aliases = ["trackIDs", "persistentIDs", "persistentIds", "trackIds", "selectedPersistentIDs"]
        var ids: [String] = []
        for key in aliases where root[key] != nil {
            guard let values = root[key] as? [String] else { throw MusicLibraryExchangeError.invalidSelection }
            ids.append(contentsOf: values)
        }
        if !ids.isEmpty { root["trackIDs"] = ids }
        let normalized = try JSONSerialization.data(withJSONObject: root)
        return try JSONDecoder().decode(MusicLibraryAISelection.self, from: normalized)
    }

    /// Validate the complete reply before an existing playlist can be replaced.
    func validatedTrackIDs(from selection: MusicLibraryAISelection, availableTrackIDs: Set<String>) throws -> [String] {
        let candidates = candidateTrackIDs(from: selection)
        guard !candidates.isEmpty else { throw MusicLibraryExchangeError.invalidSelection }
        guard candidates.allSatisfy({ isPersistentID($0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()) }) else {
            throw MusicLibraryExchangeError.invalidSelection
        }
        let ids = validatedTrackIDs(from: selection)
        let available = Set(availableTrackIDs.map { $0.uppercased() })
        let missingCount = ids.filter { !available.contains($0) }.count
        guard missingCount == 0 else { throw MusicLibraryExchangeError.unknownTracks(missingCount) }
        return ids
    }

    func validatedTrackIDs(from selection: MusicLibraryAISelection) -> [String] {
        let candidates = candidateTrackIDs(from: selection)

        var seen = Set<String>()
        return candidates.compactMap { rawValue in
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard isPersistentID(value), seen.insert(value).inserted else { return nil }
            return value
        }
    }

    private func candidateTrackIDs(from selection: MusicLibraryAISelection) -> [String] {
        var candidates = selection.trackIDs ?? []
        candidates.append(contentsOf: selection.selectedTrackIDs ?? [])
        for track in selection.tracks ?? [] {
            if track.id == nil && track.persistentID == nil { candidates.append("") }
            if let id = track.id { candidates.append(id) }
            if let id = track.persistentID { candidates.append(id) }
        }

        return candidates
    }

    private func isPersistentID(_ value: String) -> Bool {
        value.count == 16 && value.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789ABCDEF").contains($0) }
    }
}

enum MusicLibraryExchangeError: Error {
    case invalidSelection
    case catalogInsteadOfSelection
    case unknownTracks(Int)

    func message(language: String) -> String {
        let russian = language == "ru"
        switch self {
        case .invalidSelection:
            return russian ? "В ответе должны быть playlistName и список корректных идентификаторов trackIDs. Плейлист не изменён." : "The reply must contain playlistName and valid trackIDs. The playlist was not changed."
        case .catalogInsteadOfSelection:
            return russian ? "Это экспорт медиатеки. Выберите JSON с подборкой, который вернул ваш AI-агент." : "This is a library export. Choose the selection JSON returned by your AI assistant."
        case .unknownTracks(let count):
            return russian ? "В текущей медиатеке не найдено идентификаторов: \(count). Обновите экспорт и подборку. Плейлист не изменён." : "\(count) selected IDs were not found in the current library. Refresh the export and selection. The playlist was not changed."
        }
    }
}
