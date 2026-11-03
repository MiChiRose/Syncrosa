import Foundation

struct iTunesResult: Codable {
    let trackName: String?
    let artistName: String?
    let collectionName: String?
    let primaryGenreName: String?
    let releaseDate: String?
    let trackNumber: Int?
    let artworkUrl100: String?
}

struct iTunesResponse: Codable {
    let results: [iTunesResult]
}

enum MetadataLookupResult {
    case matched(iTunesResult)
    case notFound
    case ambiguous
    case failed(String)
}

class MetadataService {
    static let shared = MetadataService()
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func searchURL(for track: String, artist: String) -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: "\(track) \(artist)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "25")
        ]
        return components?.url
    }

    /// Preserve recording-version words and reject editions with conflicting tags.
    static func selectMatch(from results: [iTunesResult], title: String, artist: String, album: String = "") -> MetadataLookupResult {
        let normalizedTitle = normalized(title)
        let normalizedArtist = normalized(artist)
        guard !normalizedTitle.isEmpty, !normalizedArtist.isEmpty else { return .notFound }
        var candidates = results.filter {
            normalized($0.trackName ?? "") == normalizedTitle &&
            normalized($0.artistName ?? "") == normalizedArtist
        }
        let normalizedAlbum = MetadataRepairTrack.isMissing(album) ? "" : normalized(album)
        if !normalizedAlbum.isEmpty {
            candidates = candidates.filter { normalized($0.collectionName ?? "") == normalizedAlbum }
        }
        guard let first = candidates.first else { return .notFound }
        let editions = Set(candidates.map {
            [normalized($0.collectionName ?? ""), normalized($0.primaryGenreName ?? ""), String($0.trackNumber ?? 0)]
                .joined(separator: "\t")
        })
        guard editions.count == 1 else { return .ambiguous }
        return .matched(first)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func lookupMetadata(for track: String, artist: String, album: String = "") async -> MetadataLookupResult {
        guard !MetadataRepairTrack.isMissing(track), !MetadataRepairTrack.isMissing(artist),
              let url = searchURL(for: track, artist: artist) else { return .notFound }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { return .failed("Invalid catalog response.") }
            guard (200...299).contains(response.statusCode) else {
                return .failed("Catalog request failed (HTTP \(response.statusCode)).")
            }
            let decoded = try JSONDecoder().decode(iTunesResponse.self, from: data)
            return Self.selectMatch(from: decoded.results, title: track, artist: artist, album: album)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // Preserve folder-fixer callers; uncertain matches never rename files.
    func fetchMetadata(for track: String, artist: String, completion: @escaping (iTunesResult?) -> Void) {
        Task {
            let result = await lookupMetadata(for: track, artist: artist)
            if case .matched(let metadata) = result { completion(metadata) }
            else { completion(nil) }
        }
    }
}

struct MetadataRepairTrack {
    let persistentID: String
    let title: String
    let artist: String
    let album: String
    let genre: String
    let trackNumber: Int?
    let hasLyrics: Bool?

    static func isMissing(_ value: String) -> Bool {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text.isEmpty || ["missing value", "unknown title", "unknown artist", "unknown album", "unknown genre"].contains(text)
    }

    func missingFields(in selected: Set<String>) -> Set<String> {
        var missing = Set<String>()
        for (key, value) in [("title", title), ("artist", artist), ("album", album), ("genre", genre)] {
            if selected.contains(key), Self.isMissing(value) { missing.insert(key) }
        }
        if selected.contains("trackNumber"), let trackNumber, trackNumber <= 0 { missing.insert("trackNumber") }
        // Unreadable lyrics are unknown, not permission to overwrite them.
        if selected.contains("lyrics"), hasLyrics == false { missing.insert("lyrics") }
        return missing
    }

    func changes(selected: Set<String>, metadata: iTunesResult?, lyrics: String?) -> [String: String] {
        let missing = missingFields(in: selected)
        var proposed: [String: String] = [:]
        if let metadata {
            proposed["title"] = metadata.trackName
            proposed["artist"] = metadata.artistName
            proposed["album"] = metadata.collectionName
            proposed["genre"] = metadata.primaryGenreName
            if let number = metadata.trackNumber, number > 0 { proposed["trackNumber"] = String(number) }
        }
        proposed["lyrics"] = lyrics
        return proposed.filter { missing.contains($0.key) && !Self.isMissing($0.value) }
    }
}

struct MetadataRepairSummary {
    private(set) var updated = 0
    private(set) var skipped = 0
    private(set) var notFound = 0
    private(set) var failed = 0

    // Errors can include a partially updated track. affectedCount always means
    // tracks that Music actually changed, never the number scanned.
    mutating func record(changed: Bool = false, skipped: Bool = false, noMatch: Bool = false, failed: Bool = false) {
        if changed { updated += 1 }
        if skipped { self.skipped += 1 }
        if noMatch { notFound += 1 }
        if failed { self.failed += 1 }
    }

    var status: String { failed > 0 ? (updated > 0 ? "WARN" : "ERROR") : (notFound > 0 ? "WARN" : "OK") }

    func message(russian: Bool) -> String {
        russian
            ? "Изменено треков: \(updated). Пропущено: \(skipped). Без надёжного совпадения: \(notFound). Треков с ошибками: \(failed)."
            : "Tracks changed: \(updated). Skipped: \(skipped). No confident match: \(notFound). Tracks with errors: \(failed)."
    }
}
