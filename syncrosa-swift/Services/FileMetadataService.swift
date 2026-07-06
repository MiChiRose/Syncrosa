import Foundation
import AVFoundation

struct FileMetadataFixResult {
    let success: Bool
    let underscoreNormalizationFailed: Bool
}

class FileMetadataService {
    static let shared = FileMetadataService()
    
    func fixFile(url: URL, downloadCover: Bool, checkedTags: [String: Bool], normalizeUnderscores: Bool = false) -> FileMetadataFixResult {
        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        var underscoreNormalizationFailed = false
        var workingURL = url

        if normalizeUnderscores {
            do {
                workingURL = try normalizeUnderscoresInFilename(url)
            } catch {
                underscoreNormalizationFailed = true
                workingURL = url
            }
        }
        
        // 1. Extract current info
        var artist = ""
        var title = ""
        
        let asset = AVAsset(url: workingURL)
        let metadataSemaphore = DispatchSemaphore(value: 0)
        
        Task {
            if let metadata = try? await asset.load(.metadata) {
                for item in metadata {
                    if let commonKey = item.commonKey {
                        if commonKey == .commonKeyArtist {
                            artist = (try? await item.load(.stringValue)) ?? ""
                        } else if commonKey == .commonKeyTitle {
                            title = (try? await item.load(.stringValue)) ?? ""
                        }
                    }
                }
            }
            metadataSemaphore.signal()
        }
        _ = metadataSemaphore.wait(timeout: .now() + 5.0)
        
        // 2. If info is missing, parse from filename
        if artist.isEmpty || title.isEmpty {
            let filename = workingURL.deletingPathExtension().lastPathComponent
            let parsed = parseFilename(filename)
            if artist.isEmpty { artist = parsed.artist }
            if title.isEmpty { title = parsed.title }
        }
        
        // 3. Search iTunes for better metadata
        MetadataService.shared.fetchMetadata(for: title, artist: artist) { result in
            defer { semaphore.signal() }
            
            guard let result = result else {
                success = !artist.isEmpty && !title.isEmpty
                return
            }
            
            // 4. Update info applying only checked tags
            let newArtist = (checkedTags["artist"] == true) ? (result.artistName ?? artist) : artist
            let newTitle = (checkedTags["title"] == true) ? (result.trackName ?? title) : title
            
            // Log other tags if checked (AVFoundation lacks direct tag editing without export, so we print/rename)
            if checkedTags["album"] == true {
                print("Album tag matches: \(result.collectionName ?? "")")
            }
            if checkedTags["genre"] == true {
                print("Genre tag matches: \(result.primaryGenreName ?? "")")
            }
            if checkedTags["trackNumber"] == true {
                print("Track number tag matches: \(result.trackNumber ?? 0)")
            }
            
            // Fetch lyrics if checked
            if checkedTags["lyrics"] == true {
                let semLyrics = DispatchSemaphore(value: 0)
                LyricsService.shared.fetchLyrics(artist: newArtist, title: newTitle) { lyrics in
                    if let ly = lyrics {
                        print("Lyrics found: \(ly.prefix(50))...")
                    }
                    semLyrics.signal()
                }
                _ = semLyrics.wait(timeout: .now() + 5.0)
            }
            
            let sanitizedArtist = self.sanitizeFilename(newArtist)
            let sanitizedTitle = self.sanitizeFilename(newTitle)
            let newFilename = "\(sanitizedArtist) - \(sanitizedTitle).\(workingURL.pathExtension)"
            let desiredUrl = workingURL.deletingLastPathComponent().appendingPathComponent(newFilename)
            let newUrl = self.uniqueDestinationURL(for: desiredUrl, originalURL: workingURL)
            
            do {
                if workingURL.standardized.path != newUrl.standardized.path {
                    if workingURL.path.lowercased() == newUrl.path.lowercased() {
                        // Case-only rename: use a temp name first to avoid deleting the source file on case-insensitive macOS volumes
                        let tempUrl = workingURL.deletingLastPathComponent().appendingPathComponent("temp_\(UUID().uuidString)_\(workingURL.lastPathComponent)")
                        try FileManager.default.moveItem(at: workingURL, to: tempUrl)
                        try FileManager.default.moveItem(at: tempUrl, to: newUrl)
                    } else {
                        try FileManager.default.moveItem(at: workingURL, to: newUrl)
                    }
                    workingURL = newUrl
                }
                
                // If downloadCover is true and album tag is checked, try to download cover
                if downloadCover && checkedTags["album"] == true, let artworkUrl = result.artworkUrl100 {
                    self.downloadCover(url: artworkUrl, destinationFolder: newUrl.deletingLastPathComponent(), baseName: "\(sanitizedArtist) - \(sanitizedTitle)")
                }
                
                success = true
            } catch {
                print("Error renaming file: \(error)")
                success = false
            }
        }
        
        _ = semaphore.wait(timeout: .now() + 10)
        return FileMetadataFixResult(success: success, underscoreNormalizationFailed: underscoreNormalizationFailed)
    }

    private func normalizeUnderscoresInFilename(_ url: URL) throws -> URL {
        let baseName = url.deletingPathExtension().lastPathComponent
        guard baseName.contains("_") else { return url }

        let normalizedBase = baseName
            .replacingOccurrences(of: "_+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedBase.isEmpty, normalizedBase != baseName else { return url }

        let ext = url.pathExtension
        let newName = ext.isEmpty ? normalizedBase : "\(normalizedBase).\(ext)"
        let desiredURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        let newURL = uniqueDestinationURL(for: desiredURL, originalURL: url)
        guard url.standardized.path != newURL.standardized.path else { return url }

        try FileManager.default.moveItem(at: url, to: newURL)
        return newURL
    }
    
    private func parseFilename(_ filename: String) -> (artist: String, title: String) {
        let parts = filename.components(separatedBy: " - ")
        if parts.count >= 2 {
            return (parts[0].trimmingCharacters(in: .whitespaces), parts[1].trimmingCharacters(in: .whitespaces))
        }
        
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

    private func uniqueDestinationURL(for desiredURL: URL, originalURL: URL? = nil) -> URL {
        let fm = FileManager.default
        if let originalURL = originalURL {
            if originalURL.standardized.path == desiredURL.standardized.path ||
                originalURL.path.lowercased() == desiredURL.path.lowercased() {
                return desiredURL
            }
        }
        if !fm.fileExists(atPath: desiredURL.path) {
            return desiredURL
        }

        let folder = desiredURL.deletingLastPathComponent()
        let baseName = desiredURL.deletingPathExtension().lastPathComponent
        let ext = desiredURL.pathExtension
        var suffix = 2
        while true {
            let candidateName = ext.isEmpty ? "\(baseName) \(suffix)" : "\(baseName) \(suffix).\(ext)"
            let candidate = folder.appendingPathComponent(candidateName)
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }
    
    private func downloadCover(url artworkUrl: String, destinationFolder: URL, baseName: String) {
        guard let url = URL(string: artworkUrl.replacingOccurrences(of: "100x100bb", with: "600x600bb")) else { return }
        
        let task = URLSession.shared.downloadTask(with: url) { localURL, response, error in
            guard let localURL = localURL, error == nil else { return }
            let destURL = self.uniqueDestinationURL(for: destinationFolder.appendingPathComponent("\(baseName).jpg"))
            try? FileManager.default.moveItem(at: localURL, to: destURL)
        }
        task.resume()
    }
}
