import Foundation

class LyricsService {
    static let shared = LyricsService()
    
    func fetchLyrics(artist: String, title: String, completion: @escaping (String?) -> Void) {
        var pathAllowed = CharacterSet.urlPathAllowed
        pathAllowed.remove(charactersIn: "/?#")
        guard !artist.isEmpty && !title.isEmpty,
              let escapedArtist = artist.addingPercentEncoding(withAllowedCharacters: pathAllowed),
              let escapedTitle = title.addingPercentEncoding(withAllowedCharacters: pathAllowed),
              let url = URL(string: "https://api.lyrics.ovh/v1/\(escapedArtist)/\(escapedTitle)") else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data,
                  error == nil,
                  let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode) else {
                completion(nil)
                return
            }
            
            struct LyricsResponse: Codable {
                let lyrics: String?
            }
            
            do {
                let decoded = try JSONDecoder().decode(LyricsResponse.self, from: data)
                completion(decoded.lyrics)
            } catch {
                completion(nil)
            }
        }.resume()
    }
}
