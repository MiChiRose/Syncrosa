import Foundation
import AVFoundation

class FileMetadataService {
    static let shared = FileMetadataService()
    
    struct FixResult {
        let success: Bool
        let newURL: URL?
        let message: String
    }
    
    func fixFile(url: URL, downloadCover: Bool) -> FixResult {
        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        var resultURL: URL? = nil
        var message = ""
        
        // 1. Extract current info
        var artist = ""
        var title = ""
        
        let asset = AVAsset(url: url)
        let metadata = asset.metadata
        
        for item in metadata {
            if let commonKey = item.commonKey {
                if commonKey == .commonKeyArtist {
                    artist = item.stringValue ?? ""
                } else if commonKey == .commonKeyTitle {
                    title = item.stringValue ?? ""
                }
            }
        }
        
        // 2. If info is missing, parse from filename
        if artist.isEmpty || title.isEmpty {
            let filename = url.deletingPathExtension().lastPathComponent
            let parsed = parseFilename(filename)
            if artist.isEmpty { artist = parsed.artist }
            if title.isEmpty { title = parsed.title }
        }
        
        // 3. Search iTunes for better metadata
        MetadataService.shared.fetchMetadata(for: title, artist: artist) { result in
            defer { semaphore.signal() }
            
            guard let result = result else {
                message = "Metadata not found in iTunes."
                success = !artist.isEmpty && !title.isEmpty
                return
            }
            
            // 4. Update file
            let newArtist = result.artistName ?? artist
            let newTitle = result.trackName ?? title
            
            let sanitizedArtist = self.sanitizeFilename(newArtist)
            let sanitizedTitle = self.sanitizeFilename(newTitle)
            let newFilename = "\(sanitizedArtist) - \(sanitizedTitle).\(url.pathExtension)"
            let newUrl = url.deletingLastPathComponent().appendingPathComponent(newFilename)
            
            do {
                if url.path != newUrl.path {
                    // Check if file already exists at destination
                    if FileManager.default.fileExists(atPath: newUrl.path) {
                        try FileManager.default.removeItem(at: newUrl)
                    }
                    try FileManager.default.moveItem(at: url, to: newUrl)
                    message = "Renamed: \(newFilename)"
                    resultURL = newUrl
                } else {
                    message = "Metadata verified (no rename needed)."
                }
                
                // If downloadCover is true, try to download it
                if downloadCover, let artworkUrl = result.artworkUrl100 {
                    self.downloadCover(url: artworkUrl, destinationFolder: newUrl.deletingLastPathComponent(), baseName: "\(sanitizedArtist) - \(sanitizedTitle)")
                }
                
                success = true
            } catch {
                message = "Error: \(error.localizedDescription)"
                success = false
            }
        }
        
        _ = semaphore.wait(timeout: .now() + 10)
        return FixResult(success: success, newURL: resultURL, message: message)
    }
    
    private func parseFilename(_ filename: String) -> (artist: String, title: String) {
        // Pattern: Artist - Title
        let parts = filename.components(separatedBy: " - ")
        if parts.count >= 2 {
            return (parts[0].trimmingCharacters(in: .whitespaces), parts[1].trimmingCharacters(in: .whitespaces))
        }
        
        // Pattern: Artist-Title
        let parts2 = filename.components(separatedBy: "-")
        if parts2.count >= 2 {
            return (parts2[0].trimmingCharacters(in: .whitespaces), parts2[1].trimmingCharacters(in: .whitespaces))
        }
        
        return ("", filename)
    }
    
    private func sanitizeFilename(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>")
        return name.components(separatedBy: invalidCharacters).joined(separator: "_")
    }
    
    private func downloadCover(url artworkUrl: String, destinationFolder: URL, baseName: String) {
        guard let url = URL(string: artworkUrl.replacingOccurrences(of: "100x100bb", with: "600x600bb")) else { return }
        
        let task = URLSession.shared.downloadTask(with: url) { localURL, response, error in
            guard let localURL = localURL, error == nil else { return }
            let destURL = destinationFolder.appendingPathComponent("\(baseName).jpg")
            try? FileManager.default.moveItem(at: localURL, to: destURL)
        }
        task.resume()
    }
}
