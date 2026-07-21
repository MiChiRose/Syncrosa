import Foundation

enum SyncrosaStorage {
    static var applicationSupportDirectory: URL {
        directory(for: .applicationSupportDirectory).appendingPathComponent("Syncrosa", isDirectory: true)
    }

    static var backupsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Backups", isDirectory: true)
    }

    static var cacheDirectory: URL {
        directory(for: .cachesDirectory).appendingPathComponent("Syncrosa", isDirectory: true)
    }

    static func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func backupDirectory(for tool: String) throws -> URL {
        let safeTool = tool
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let dir = backupsDirectory.appendingPathComponent(safeTool, isDirectory: true)
        try ensureDirectory(dir)
        return dir
    }

    static func temporaryOperationDirectory(for tool: String) throws -> URL {
        let dir = cacheDirectory.appendingPathComponent(tool, isDirectory: true)
        try ensureDirectory(dir)
        return dir
    }

    private static func directory(for searchPath: FileManager.SearchPathDirectory) -> URL {
        FileManager.default.urls(for: searchPath, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }
}
