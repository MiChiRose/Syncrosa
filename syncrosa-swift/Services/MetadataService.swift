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

class MetadataService {
    static let shared = MetadataService()

    func searchURL(for track: String, artist: String) -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: "\(track) \(artist)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1")
        ]
        return components?.url
    }
    
    func fetchMetadata(for track: String, artist: String, completion: @escaping (iTunesResult?) -> Void) {
        guard let url = searchURL(for: track, artist: artist) else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data,
                  error == nil,
                  let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode) else {
                completion(nil)
                return
            }
            
            do {
                let response = try JSONDecoder().decode(iTunesResponse.self, from: data)
                completion(response.results.first)
            } catch {
                completion(nil)
            }
        }.resume()
    }
}
