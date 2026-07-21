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
            instructions: "Choose tracks for one playlist. Return a JSON object containing playlistName and trackIDs. Every trackID must be copied unchanged from this file.",
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
        return try JSONDecoder().decode(MusicLibraryAISelection.self, from: data)
    }

    func validatedTrackIDs(from selection: MusicLibraryAISelection) -> [String] {
        var candidates = selection.trackIDs ?? []
        candidates.append(contentsOf: selection.selectedTrackIDs ?? [])
        for track in selection.tracks ?? [] {
            if let id = track.id { candidates.append(id) }
            if let id = track.persistentID { candidates.append(id) }
        }

        var seen = Set<String>()
        return candidates.compactMap { rawValue in
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard value.count == 16,
                  value.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789ABCDEF").contains($0) }),
                  seen.insert(value).inserted else {
                return nil
            }
            return value
        }
    }
}
