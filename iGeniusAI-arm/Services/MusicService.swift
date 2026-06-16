import Foundation

struct MusicTrack: Identifiable, Codable {
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
    private let scriptQueue = DispatchQueue(label: "com.igeniusai.scriptQueue")
    
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
}
