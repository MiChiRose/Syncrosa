import Foundation

enum LyricsLookupResult {
    case found(String)
    case notFound
    case failed(String)
}

class LyricsService {
    static let shared = LyricsService()
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func lookupLyrics(artist: String, title: String) async -> LyricsLookupResult {
        var pathAllowed = CharacterSet.urlPathAllowed
        pathAllowed.remove(charactersIn: "/?#")
        guard !MetadataRepairTrack.isMissing(artist), !MetadataRepairTrack.isMissing(title),
              let escapedArtist = artist.addingPercentEncoding(withAllowedCharacters: pathAllowed),
              let escapedTitle = title.addingPercentEncoding(withAllowedCharacters: pathAllowed),
              let url = URL(string: "https://api.lyrics.ovh/v1/\(escapedArtist)/\(escapedTitle)") else { return .notFound }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { return .failed("Invalid lyrics response.") }
            if response.statusCode == 404 { return .notFound }
            guard (200...299).contains(response.statusCode) else {
                return .failed("Lyrics request failed (HTTP \(response.statusCode)).")
            }
            struct LyricsResponse: Codable { let lyrics: String? }
            let decoded = try JSONDecoder().decode(LyricsResponse.self, from: data)
            guard let lyrics = decoded.lyrics, !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .notFound }
            return .found(lyrics)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func fetchLyrics(artist: String, title: String, completion: @escaping (String?) -> Void) {
        Task {
            if case .found(let lyrics) = await lookupLyrics(artist: artist, title: title) { completion(lyrics) }
            else { completion(nil) }
        }
    }
}
