import Foundation
import AppKit

class CoversOptimizerService {
    static let shared = CoversOptimizerService()
    
    private let fileManager = FileManager.default
    private let scriptQueue = DispatchQueue(label: "com.michirose.syncrosa.optimizerQueue")
    
    var backupFolder: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("AlbumCovers")
    }
    
    var manifestURL: URL {
        return backupFolder.appendingPathComponent("manifest.json")
    }
    
    var appName: String {
        return fileManager.fileExists(atPath: "/System/Applications/Music.app") ? "Music" : "iTunes"
    }
    
    private init() {
        createBackupFolderIfNeeded()
    }
    
    func createBackupFolderIfNeeded() {
        if !fileManager.fileExists(atPath: backupFolder.path) {
            try? fileManager.createDirectory(at: backupFolder, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    private func runScript(_ source: String) -> String? {
        var result: String?
        scriptQueue.sync {
            var error: NSDictionary?
            if let script = NSAppleScript(source: source) {
                let output = script.executeAndReturnError(&error)
                if let err = error {
                    print("AppleScript Error: \(err)")
                    result = nil
                } else {
                    result = output.stringValue
                }
            }
        }
        return result
    }
    
    // Structs for manifest
    struct CoverBackupInfo: Codable {
        let title: String
        let artist: String
        let originalFormat: String
        let originalWidth: Int
        let originalHeight: Int
        let backupDate: String
    }
    
    struct CoversManifest: Codable {
        let manifestVersion: Int
        var backups: [String: CoverBackupInfo] // persistentID -> CoverBackupInfo
    }
    
    private func loadManifest() -> CoversManifest {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(CoversManifest.self, from: data) else {
            return CoversManifest(manifestVersion: 1, backups: [:])
        }
        return manifest
    }
    
    private func saveManifest(_ manifest: CoversManifest) {
        if let data = try? JSONEncoder().encode(manifest) {
            try? data.write(to: manifestURL)
        }
    }
    
    func getTracksWithCovers() -> [(pid: String, title: String, artist: String)] {
        let script = """
        set out to ""
        tell application "\(appName)"
            try
                set trks to every track of library playlist 1
                repeat with t in trks
                    try
                        if exists artwork 1 of t then
                            set pid to persistent ID of t
                            set nm to name of t
                            set art to artist of t
                            set out to out & pid & "|" & nm & "|" & art & "\\n"
                        end if
                    end try
                end repeat
            end try
        end tell
        return out
        """
        
        guard let res = runScript(script) else { return [] }
        var list: [(pid: String, title: String, artist: String)] = []
        let lines = res.components(separatedBy: .newlines)
        for line in lines where line.contains("|") {
            let parts = line.components(separatedBy: "|")
            if parts.count >= 3 {
                list.append((pid: parts[0], title: parts[1], artist: parts[2]))
            }
        }
        return list
    }
    
    func backupCover(pid: String, title: String, artist: String) -> Bool {
        createBackupFolderIfNeeded()
        
        let pathWithoutExt = backupFolder.appendingPathComponent(pid).path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        
        let script = """
        tell application "\(appName)"
            try
                set t to (some track whose persistent ID is "\(pid)")
                if exists artwork 1 of t then
                    tell artwork 1 of t
                        set rawData to raw data
                        if format is JPEG picture then
                            set ext to "jpg"
                        else
                            set ext to "png"
                        end if
                        set w to width
                        set h to height
                    end tell
                    
                    set destFile to POSIX file ("\(pathWithoutExt)." & ext)
                    set fileRef to open for access destFile with write permission
                    set eof fileRef to 0
                    write rawData to fileRef starting at 0
                    close access fileRef
                    return ext & "|" & w & "|" & h
                else
                    return "NO_ARTWORK"
                end if
            on error errMsg number errNum
                try
                    close access fileRef
                end try
                return "ERROR: " & errNum & " - " & errMsg
            end try
        end tell
        """
        
        guard let response = runScript(script) else { return false }
        if response == "NO_ARTWORK" || response.hasPrefix("ERROR") {
            print("Backup failed for \(pid): \(response)")
            return false
        }
        
        let parts = response.components(separatedBy: "|")
        if parts.count >= 3 {
            let ext = parts[0]
            let w = Int(parts[1]) ?? 0
            let h = Int(parts[2]) ?? 0
            
            // Update manifest
            var manifest = loadManifest()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            let dateStr = formatter.string(from: Date())
            
            let info = CoverBackupInfo(
                title: title,
                artist: artist,
                originalFormat: ext,
                originalWidth: w,
                originalHeight: h,
                backupDate: dateStr
            )
            manifest.backups[pid] = info
            saveManifest(manifest)
            return true
        }
        return false
    }
    
    func optimizeCover(pid: String, targetSize: Int) -> Bool {
        let manifest = loadManifest()
        guard let info = manifest.backups[pid] else {
            print("No backup info found for \(pid)")
            return false
        }
        
        let originalFile = backupFolder.appendingPathComponent("\(pid).\(info.originalFormat)")
        guard fileManager.fileExists(atPath: originalFile.path) else {
            print("Backup file not found at \(originalFile.path)")
            return false
        }
        
        // Skip resizing if original is already smaller or equal
        if info.originalWidth <= targetSize && info.originalHeight <= targetSize {
            // Just apply original directly, no resize needed
            return setTrackArtwork(pid: pid, imageURL: originalFile)
        }
        
        // Resize image
        guard let resizedData = resizeImage(at: originalFile, targetSize: CGFloat(targetSize)) else {
            print("Failed to resize image for \(pid)")
            return false
        }
        
        // Save to temp file
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(pid)_temp.jpg")
        do {
            try resizedData.write(to: tempURL)
        } catch {
            print("Failed to write temp file: \(error)")
            return false
        }
        
        defer {
            try? fileManager.removeItem(at: tempURL)
        }
        
        return setTrackArtwork(pid: pid, imageURL: tempURL)
    }
    
    func restoreCover(pid: String) -> Bool {
        let manifest = loadManifest()
        guard let info = manifest.backups[pid] else {
            print("No backup info found for \(pid)")
            return false
        }
        
        let originalFile = backupFolder.appendingPathComponent("\(pid).\(info.originalFormat)")
        guard fileManager.fileExists(atPath: originalFile.path) else {
            print("Backup file not found at \(originalFile.path)")
            return false
        }
        
        return setTrackArtwork(pid: pid, imageURL: originalFile)
    }
    
    private func setTrackArtwork(pid: String, imageURL: URL) -> Bool {
        let escPath = imageURL.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        
        let script = """
        tell application "\(appName)"
            try
                set t to (some track whose persistent ID is "\(pid)")
                set fileAlias to (POSIX file "\(escPath)") as alias
                set imgData to read fileAlias as picture
                
                tell t
                    try
                        set data of artwork 1 to imgData
                    on error
                        try
                            delete every artwork
                        end try
                        set data of artwork 1 to imgData
                    end try
                end tell
                return "SUCCESS"
            on error errMsg number errNum
                return "ERROR: " & errNum & " - " & errMsg
            end try
        end tell
        """
        
        guard let response = runScript(script) else { return false }
        if response == "SUCCESS" {
            return true
        } else {
            print("Failed to set track artwork: \(response)")
            return false
        }
    }
    
    private func resizeImage(at sourceURL: URL, targetSize: CGFloat) -> Data? {
        guard let image = NSImage(contentsOf: sourceURL) else { return nil }
        
        let originalSize = image.size
        var newSize = originalSize
        
        if originalSize.width > originalSize.height {
            if originalSize.width > targetSize {
                newSize = CGSize(width: targetSize, height: (originalSize.height * targetSize) / originalSize.width)
            }
        } else {
            if originalSize.height > targetSize {
                newSize = CGSize(width: (originalSize.width * targetSize) / originalSize.height, height: targetSize)
            }
        }
        
        let targetRect = NSRect(origin: .zero, size: newSize)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(newSize.width),
            pixelsHigh: Int(newSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        
        rep.size = newSize
        
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: targetRect, from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}
