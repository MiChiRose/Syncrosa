import Foundation

struct iTunesResult: Codable {
    let trackName: String?
    let artistName: String?
    let collectionName: String?
    let primaryGenreName: String?
    let releaseDate: String?
    let trackNumber: Int?
}

struct iTunesResponse: Codable {
    let results: [iTunesResult]
}

class MetadataService {
    static let shared = MetadataService()
    
    func fetchMetadata(for track: String, artist: String, completion: @escaping (iTunesResult?) -> Void) {
        let query = "\(track) \(artist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: "https://itunes.apple.com/search?term=\(query)&entity=song&limit=1")!
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
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
