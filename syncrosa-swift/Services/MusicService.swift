import Foundation

struct MusicTrack: Identifiable, Codable, Equatable {
    var id: String { persistentID }
    let persistentID: String
    let name: String
    let artist: String
    let album: String
    let genre: String
    let year: Int
}

class MusicService {
    static let shared = MusicService()
    private let scriptQueue = DispatchQueue(label: "com.michirose.syncrosa.scriptQueue")
    
    func runAppleScript(_ scriptSource: String) -> String? {
        var result: String?
        scriptQueue.sync {
            var error: NSDictionary?
            if let script = NSAppleScript(source: scriptSource) {
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
    
    func getAllTracks(progress: @escaping (Int, Int) -> Void) -> [MusicTrack] {
        let countScript = "tell application \"Music\" to count every track of library playlist 1"
        guard let countStr = runAppleScript(countScript), let total = Int(countStr) else { return [] }
        
        var allTracks: [MusicTrack] = []
        let chunkSize = 300
        
        for i in stride(from: 1, through: total, by: chunkSize) {
            let end = min(i + chunkSize - 1, total)
            let script = """
            set out to ""
            tell application "Music"
                set trks to (tracks \(i) thru \(end) of library playlist 1)
                repeat with t in trks
                    try
                        set pid to persistent ID of t
                        set art to artist of t
                        set nm to name of t
                        set alb to album of t
                        set gen to genre of t
                        set yr to year of t
                        set out to out & pid & "|" & art & "|" & nm & "|" & alb & "|" & gen & "|" & yr & "\\n"
                    end try
                end repeat
            end tell
            return out
            """
            
            if let result = runAppleScript(script) {
                let lines = result.components(separatedBy: .newlines)
                for line in lines where line.contains("|") {
                    let parts = line.components(separatedBy: "|")
                    if parts.count >= 6 {
                        let track = MusicTrack(
                            persistentID: parts[0],
                            name: parts[2],
                            artist: parts[1],
                            album: parts[3],
                            genre: parts[4],
                            year: Int(parts[5]) ?? 0
                        )
                        allTracks.append(track)
                    }
                }
            }
            progress(end, total)
        }
        return allTracks
    }

    func createPlaylist(name: String, persistentIDs: [String]) -> Int {
        let idsString = "{\"" + persistentIDs.joined(separator: "\", \"") + "\"}"
        let script = """
        tell application "Music"
            set plName to "\(name.replacingOccurrences(of: "\"", with: "\\\""))"
            if not (exists user playlist plName) then
                make new user playlist with properties {name:plName}
            end if
            set pl to user playlist plName
            delete every track of pl
            
            set addedCount to 0
            set idList to \(idsString)
            
            repeat with tid in idList
                try
                    set trk to (some track of library playlist 1 whose persistent ID is tid)
                    duplicate trk to pl
                    set addedCount to addedCount + 1
                end try
            end repeat
            return addedCount as string
        end tell
        """
        
        return Int(runAppleScript(script) ?? "0") ?? 0
    }
    
    func getUserPlaylists() -> [(name: String, trackCount: Int)] {
        let script = """
        tell application "Music"
            set output to ""
            repeat with pl in (every user playlist whose special kind is none)
                set plName to name of pl
                set plCount to count of tracks of pl
                set output to output & plName & "|" & plCount & "\\n"
            end repeat
            return output
        end tell
        """
        guard let result = runAppleScript(script) else { return [] }
        var playlists: [(name: String, trackCount: Int)] = []
        let lines = result.components(separatedBy: .newlines)
        for line in lines where line.contains("|") {
            let parts = line.components(separatedBy: "|")
            if parts.count >= 2 {
                let name = parts[0]
                let count = Int(parts[1]) ?? 0
                playlists.append((name: name, trackCount: count))
            }
        }
        return playlists
    }
    
    func getPlaylistTrackPaths(playlistName: String) -> [(name: String, artist: String, path: String, size: Int64)] {
        let escapedName = playlistName.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Music"
            set output to ""
            try
                set pl to user playlist "\(escapedName)"
                repeat with t in (every file track of pl)
                    try
                        set loc to location of t
                        if loc is not missing value then
                            set output to output & (name of t) & "|" & (artist of t) & "|" & (POSIX path of loc) & "\\n"
                        end if
                    end try
                end repeat
            end try
            return output
        end tell
        """
        guard let result = runAppleScript(script) else { return [] }
        var tracks: [(name: String, artist: String, path: String, size: Int64)] = []
        let lines = result.components(separatedBy: .newlines)
        let fm = FileManager.default
        for line in lines where line.contains("|") {
            let parts = line.components(separatedBy: "|")
            if parts.count >= 3 {
                let name = parts[0]
                let artist = parts[1]
                let path = parts[2]
                var size: Int64 = 0
                if let attrs = try? fm.attributesOfItem(atPath: path),
                   let fileSize = attrs[.size] as? Int64 {
                    size = fileSize
                }
                tracks.append((name: name, artist: artist, path: path, size: size))
            }
        }
        return tracks
    }
    
    private func escapeAppleScriptString(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
    
    func updateTrack(persistentID: String, properties: [String: String]) -> Bool {
        var scriptLines: [String] = []
        scriptLines.append("tell application \"Music\"")
        scriptLines.append("    try")
        scriptLines.append("        set t to (some track of library playlist 1 whose persistent ID is \"\(persistentID)\")")
        
        for (key, value) in properties {
            let cleanKey = key.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanKey == "genre" {
                let escaped = escapeAppleScriptString(value)
                scriptLines.append("        set genre of t to \"\(escaped)\"")
            } else if cleanKey == "year" {
                if let intVal = Int(value) {
                    scriptLines.append("        set year of t to \(intVal)")
                }
            } else if cleanKey == "tracknumber" || cleanKey == "track number" || cleanKey == "track" {
                if let intVal = Int(value) {
                    scriptLines.append("        set track number of t to \(intVal)")
                }
            } else if cleanKey == "lyrics" {
                let escaped = escapeAppleScriptString(value)
                scriptLines.append("        set lyrics of t to \"\(escaped)\"")
            } else if cleanKey == "album" {
                let escaped = escapeAppleScriptString(value)
                scriptLines.append("        set album of t to \"\(escaped)\"")
            } else if cleanKey == "artist" {
                let escaped = escapeAppleScriptString(value)
                scriptLines.append("        set artist of t to \"\(escaped)\"")
            } else if cleanKey == "name" || cleanKey == "title" {
                let escaped = escapeAppleScriptString(value)
                scriptLines.append("        set name of t to \"\(escaped)\"")
            }
        }
        
        scriptLines.append("        return \"success\"")
        scriptLines.append("    on error err")
        scriptLines.append("        return \"error: \" & err")
        scriptLines.append("    end try")
        scriptLines.append("end tell")
        
        let script = scriptLines.joined(separator: "\n")
        if let result = runAppleScript(script), result == "success" {
            return true
        }
        return false
    }
    
    func deleteTrack(persistentID: String) -> Bool {
        let script = """
        tell application "Music"
            try
                delete (some track of library playlist 1 whose persistent ID is "\(persistentID)")
                return "success"
            on error err
                return "error: " & err
            end try
        end tell
        """
        if let result = runAppleScript(script), result == "success" {
            return true
        }
        return false
    }
    
    func getTrackDetails(persistentID: String) -> (format: String, size: Int64)? {
        let script = """
        tell application "Music"
            try
                set t to (some track of library playlist 1 whose persistent ID is "\(persistentID)")
                set sz to size of t
                set k to kind of t
                try
                    set loc to location of t
                    if loc is not missing value then
                        set pth to POSIX path of loc
                        return (sz as string) & "|" & k & "|" & pth
                    end if
                end try
                return (sz as string) & "|" & k & "|"
            on error
                return ""
            end try
        end tell
        """
        guard let res = runAppleScript(script), !res.isEmpty else { return nil }
        let parts = res.components(separatedBy: "|")
        guard parts.count >= 2 else { return nil }
        
        let size = Int64(parts[0]) ?? 0
        let kind = parts[1]
        var format = "Unknown"
        if parts.count >= 3 && !parts[2].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let path = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            format = URL(fileURLWithPath: path).pathExtension.uppercased()
        }
        if format == "Unknown" || format.isEmpty {
            if kind.contains("AAC") || kind.contains("Apple Lossless") {
                format = "M4A"
            } else if kind.contains("MPEG") {
                format = "MP3"
            } else if kind.contains("AIFF") {
                format = "AIFF"
            } else if kind.contains("WAV") {
                format = "WAV"
            } else {
                format = kind.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return (format: format.isEmpty ? "Unknown" : format, size: size)
    }
    
    func checkTrackFilter(persistentID: String) -> (hasArtwork: Bool, rating: Int)? {
        let script = """
        tell application "Music"
            try
                set t to (some track of library playlist 1 whose persistent ID is "\(persistentID)")
                set hasArt to "false"
                try
                    if (count of artwork of t) > 0 then
                        set hasArt to "true"
                    end if
                end try
                set rt to rating of t as string
                return hasArt & "|" & rt
            on error
                return ""
            end try
        end tell
        """
        guard let res = runAppleScript(script), !res.isEmpty else { return nil }
        let parts = res.components(separatedBy: "|")
        guard parts.count >= 2 else { return nil }
        let hasArtwork = (parts[0] == "true")
        let rating = Int(parts[1]) ?? 0
        return (hasArtwork: hasArtwork, rating: rating)
    }
}


