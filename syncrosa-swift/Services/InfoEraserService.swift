import Foundation

struct InfoEraserManifest: Codable {
    var version: Int
    var createdAt: Int
    var format: String
    var items: [InfoEraserManifestItem]
}

struct InfoEraserManifestItem: Codable {
    var id: String
    var relativePath: String
    var `extension`: String
    var supported: Bool
    var id3v2File: String
    var id3v1File: String
    var id3v2Bytes: Int
    var id3v1Bytes: Int
    var mp4AtomFile: String?
    var mp4AtomOffset: Int?
    var mp4AtomBytes: Int?
    var mp4AtomType: String?
}

final class InfoEraserService {
    static let shared = InfoEraserService()

    let backupDirectoryName = "SyncrosaInfoEraserBackup"
    private let manifestName = "manifest.json"
    private let chunkSize = 256 * 1024
    private let musicExtensions: Set<String> = ["mp3", "m4a", "mp4", "aac", "flac", "wav", "aiff", "alac"]
    private let mp4Extensions: Set<String> = ["m4a", "mp4", "aac", "alac"]

    private struct MP4Atom {
        let type: String
        let offset: Int
        let size: Int
        let headerSize: Int
    }

    func findMusicFiles(in folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )
        var results: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent == backupDirectoryName {
                enumerator?.skipDescendants()
                continue
            }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true { continue }
            if musicExtensions.contains(url.pathExtension.lowercased()) {
                results.append(url)
            }
        }
        return results.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func backupOriginalInfo(folder: URL, files: [URL], progress: (Int, Int) -> Void) throws -> (manifestURL: URL, supportedCount: Int, appSupportManifestURL: URL?) {
        let backupDir = folder.appendingPathComponent(backupDirectoryName, isDirectory: true)
        let tagsDir = backupDir.appendingPathComponent("tags", isDirectory: true)
        try FileManager.default.createDirectory(at: tagsDir, withIntermediateDirectories: true)

        var manifest = InfoEraserManifest(
            version: 1,
            createdAt: Int(Date().timeIntervalSince1970),
            format: "syncrosa-info-eraser-sidecar-v2",
            items: []
        )

        for (index, fileURL) in files.enumerated() {
            let ext = fileURL.pathExtension.lowercased()
            var item = InfoEraserManifestItem(
                id: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
                relativePath: relativePath(fileURL, base: folder),
                extension: ext,
                supported: isSupportedExtension(ext),
                id3v2File: "",
                id3v1File: "",
                id3v2Bytes: 0,
                id3v1Bytes: 0,
                mp4AtomFile: nil,
                mp4AtomOffset: nil,
                mp4AtomBytes: nil,
                mp4AtomType: nil
            )

            if ext == "mp3" {
                let ranges = try mp3TagRanges(fileURL)
                let input = try FileHandle(forReadingFrom: fileURL)
                defer { try? input.close() }

                if ranges.id3v2Length > 0 {
                    try input.seek(toOffset: 0)
                    let data = input.readData(ofLength: ranges.id3v2Length)
                    let tagName = "\(item.id).id3v2"
                    try data.write(to: tagsDir.appendingPathComponent(tagName), options: .atomic)
                    item.id3v2File = "tags/\(tagName)"
                    item.id3v2Bytes = ranges.id3v2Length
                }

                if ranges.id3v1Length > 0 {
                    try input.seek(toOffset: UInt64(ranges.fileSize - 128))
                    let data = input.readData(ofLength: 128)
                    let tagName = "\(item.id).id3v1"
                    try data.write(to: tagsDir.appendingPathComponent(tagName), options: .atomic)
                    item.id3v1File = "tags/\(tagName)"
                    item.id3v1Bytes = 128
                }
            } else if mp4Extensions.contains(ext), let atom = try mp4MetadataAtom(fileURL) {
                let data = try readRange(from: fileURL, offset: atom.offset, length: atom.size)
                let tagName = "\(item.id).\(atom.type)"
                try data.write(to: tagsDir.appendingPathComponent(tagName), options: .atomic)
                item.mp4AtomFile = "tags/\(tagName)"
                item.mp4AtomOffset = atom.offset
                item.mp4AtomBytes = atom.size
                item.mp4AtomType = atom.type
            }

            manifest.items.append(item)
            progress(index + 1, files.count)
        }

        let manifestURL = backupDir.appendingPathComponent(manifestName)
        let data = try JSONEncoder.prettySorted.encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
        let supported = manifest.items.filter { $0.supported }.count
        let mirroredManifest = try mirrorBackupToApplicationSupport(backupDir: backupDir)
        return (manifestURL, supported, mirroredManifest)
    }

    func eraseInfo(files: [URL], progress: (Int, Int) -> Void) throws -> (erased: Int, unsupported: Int) {
        var erased = 0
        var unsupported = 0
        for (index, fileURL) in files.enumerated() {
            let ext = fileURL.pathExtension.lowercased()
            if ext == "mp3" {
                let ranges = try mp3TagRanges(fileURL)
                if ranges.id3v2Length > 0 || ranges.id3v1Length > 0 {
                    let temp = fileURL.deletingLastPathComponent().appendingPathComponent(".syncrosa-strip-\(UUID().uuidString)")
                    try copyRange(from: fileURL, to: temp, start: ranges.id3v2Length, end: ranges.fileSize - ranges.id3v1Length)
                    try replaceFile(original: fileURL, temp: temp)
                    erased += 1
                }
            } else if mp4Extensions.contains(ext) {
                if let atom = try mp4MetadataAtom(fileURL) {
                    try writeRange(to: fileURL, offset: atom.offset, data: freeAtomData(size: atom.size, headerSize: atom.headerSize))
                    erased += 1
                }
            } else {
                unsupported += 1
            }
            progress(index + 1, files.count)
        }
        return (erased, unsupported)
    }

    func restoreInfo(folder: URL, progress: (Int, Int) -> Void) throws -> (restored: Int, missing: Int) {
        let backupDir = restoreBackupDirectory(for: folder)
        let manifestURL = backupDir.appendingPathComponent(manifestName)
        let manifest = try JSONDecoder().decode(InfoEraserManifest.self, from: Data(contentsOf: manifestURL))

        var restored = 0
        var missing = 0
        for (index, item) in manifest.items.enumerated() {
            defer { progress(index + 1, manifest.items.count) }
            guard item.supported, let fileURL = safeURL(base: folder, relativePath: item.relativePath), FileManager.default.fileExists(atPath: fileURL.path) else {
                if item.supported { missing += 1 }
                continue
            }

            if item.extension == "mp3" {
                let id3v2Data = try readOptionalTag(base: backupDir, relativePath: item.id3v2File)
                let id3v1Data = try readOptionalTag(base: backupDir, relativePath: item.id3v1File)
                let ranges = try mp3TagRanges(fileURL)
                let bodyTemp = fileURL.deletingLastPathComponent().appendingPathComponent(".syncrosa-body-\(UUID().uuidString)")
                let finalTemp = fileURL.deletingLastPathComponent().appendingPathComponent(".syncrosa-restore-\(UUID().uuidString)")

                try copyRange(from: fileURL, to: bodyTemp, start: ranges.id3v2Length, end: ranges.fileSize - ranges.id3v1Length)
                FileManager.default.createFile(atPath: finalTemp.path, contents: nil)
                let output = try FileHandle(forWritingTo: finalTemp)
                defer { try? output.close() }

                if let id3v2Data, !id3v2Data.isEmpty {
                    try output.write(contentsOf: id3v2Data)
                }
                let body = try FileHandle(forReadingFrom: bodyTemp)
                while true {
                    let chunk = body.readData(ofLength: chunkSize)
                    if chunk.isEmpty { break }
                    try output.write(contentsOf: chunk)
                }
                try? body.close()
                if let id3v1Data, !id3v1Data.isEmpty {
                    try output.write(contentsOf: id3v1Data)
                }

                try FileManager.default.removeItem(at: bodyTemp)
                try replaceFile(original: fileURL, temp: finalTemp)
                restored += 1
            } else if mp4Extensions.contains(item.extension),
                      let atomFile = item.mp4AtomFile,
                      let atomOffset = item.mp4AtomOffset,
                      let atomBytes = item.mp4AtomBytes,
                      let atomData = try readOptionalTag(base: backupDir, relativePath: atomFile),
                      atomData.count == atomBytes {
                try writeRange(to: fileURL, offset: atomOffset, data: atomData)
                restored += 1
            }
        }

        return (restored, missing)
    }

    func hasRestoreBackup(for folder: URL) -> Bool {
        let backupDir = restoreBackupDirectory(for: folder)
        return FileManager.default.fileExists(atPath: backupDir.appendingPathComponent(manifestName).path)
    }

    private func isSupportedExtension(_ ext: String) -> Bool {
        ext == "mp3" || mp4Extensions.contains(ext)
    }

    private func mirrorBackupToApplicationSupport(backupDir: URL) throws -> URL? {
        do {
            let root = try SyncrosaStorage.backupDirectory(for: "InfoEraser")
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let folderName = "backup-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8))"
            let destination = root.appendingPathComponent(folderName, isDirectory: true)
            try FileManager.default.copyItem(at: backupDir, to: destination)
            pruneMirroredBackups(root: root, keep: 10)
            return destination.appendingPathComponent(manifestName)
        } catch {
            print("Info Eraser backup mirror failed: \(error)")
            return nil
        }
    }

    private func restoreBackupDirectory(for folder: URL) -> URL {
        let localBackupDir = folder.appendingPathComponent(backupDirectoryName, isDirectory: true)
        if FileManager.default.fileExists(atPath: localBackupDir.appendingPathComponent(manifestName).path) {
            return localBackupDir
        }
        guard let root = try? SyncrosaStorage.backupDirectory(for: "InfoEraser"),
              let candidates = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else {
            return localBackupDir
        }
        let sorted = candidates.filter { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory == true && FileManager.default.fileExists(atPath: url.appendingPathComponent(manifestName).path)
        }.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }
        return sorted.first ?? localBackupDir
    }

    private func pruneMirroredBackups(root: URL, keep: Int) {
        guard let candidates = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let sorted = candidates.filter { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory == true
        }.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }
        for stale in sorted.dropFirst(keep) {
            try? FileManager.default.removeItem(at: stale)
        }
    }

    private func readOptionalTag(base: URL, relativePath: String) throws -> Data? {
        guard !relativePath.isEmpty, let tagURL = safeURL(base: base, relativePath: relativePath), FileManager.default.fileExists(atPath: tagURL.path) else {
            return nil
        }
        return try Data(contentsOf: tagURL)
    }

    private func mp3TagRanges(_ url: URL) throws -> (id3v2Length: Int, id3v1Length: Int, fileSize: Int) {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attrs[.size] as? NSNumber)?.intValue ?? 0
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }

        var id3v2Length = 0
        let header = input.readData(ofLength: 10)
        if header.count == 10, header[0] == 0x49, header[1] == 0x44, header[2] == 0x33 {
            id3v2Length = 10 + syncsafeSize(header)
            if header[5] & 0x10 != 0 {
                id3v2Length += 10
            }
            if id3v2Length > fileSize {
                id3v2Length = 0
            }
        }

        var id3v1Length = 0
        if fileSize >= 128 {
            try input.seek(toOffset: UInt64(fileSize - 128))
            let tail = input.readData(ofLength: 3)
            if tail.count == 3, tail[0] == 0x54, tail[1] == 0x41, tail[2] == 0x47 {
                id3v1Length = 128
            }
        }

        return (id3v2Length, id3v1Length, fileSize)
    }

    private func syncsafeSize(_ header: Data) -> Int {
        (Int(header[6] & 0x7F) << 21) |
        (Int(header[7] & 0x7F) << 14) |
        (Int(header[8] & 0x7F) << 7) |
        Int(header[9] & 0x7F)
    }

    private func mp4MetadataAtom(_ url: URL) throws -> MP4Atom? {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attrs[.size] as? NSNumber)?.intValue ?? 0
        guard fileSize > 8 else { return nil }
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        return try findMP4Atom(handle: input, start: 0, end: fileSize, path: ["moov", "udta", "meta", "ilst"], index: 0)
    }

    private func findMP4Atom(handle: FileHandle, start: Int, end: Int, path: [String], index: Int) throws -> MP4Atom? {
        var cursor = start
        while cursor + 8 <= end {
            guard let atom = try readMP4AtomHeader(handle: handle, offset: cursor, parentEnd: end) else { break }
            if atom.size < atom.headerSize || atom.offset + atom.size > end { break }

            if atom.type == path[index] {
                if index == path.count - 1 {
                    return atom
                }
                let extraHeader = atom.type == "meta" ? 4 : 0
                let childStart = atom.offset + atom.headerSize + extraHeader
                if childStart < atom.offset + atom.size,
                   let found = try findMP4Atom(handle: handle, start: childStart, end: atom.offset + atom.size, path: path, index: index + 1) {
                    return found
                }
            }

            cursor += atom.size
        }
        return nil
    }

    private func readMP4AtomHeader(handle: FileHandle, offset: Int, parentEnd: Int) throws -> MP4Atom? {
        try handle.seek(toOffset: UInt64(offset))
        let header = handle.readData(ofLength: 16)
        guard header.count >= 8 else { return nil }

        let size32 = Int(readUInt32BE(header, 0))
        let type = String(bytes: header[4..<8], encoding: .macOSRoman) ?? ""
        var headerSize = 8
        var atomSize = size32

        if size32 == 1 {
            guard header.count >= 16 else { return nil }
            atomSize = Int(readUInt64BE(header, 8))
            headerSize = 16
        } else if size32 == 0 {
            atomSize = parentEnd - offset
        }

        guard atomSize >= headerSize, !type.isEmpty else { return nil }
        return MP4Atom(type: type, offset: offset, size: atomSize, headerSize: headerSize)
    }

    private func readUInt32BE(_ data: Data, _ offset: Int) -> UInt32 {
        (UInt32(data[offset]) << 24) |
        (UInt32(data[offset + 1]) << 16) |
        (UInt32(data[offset + 2]) << 8) |
        UInt32(data[offset + 3])
    }

    private func readUInt64BE(_ data: Data, _ offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value = (value << 8) | UInt64(data[offset + index])
        }
        return value
    }

    private func writeUInt32BE(_ value: UInt32, into data: inout Data, offset: Int) {
        data[offset] = UInt8((value >> 24) & 0xFF)
        data[offset + 1] = UInt8((value >> 16) & 0xFF)
        data[offset + 2] = UInt8((value >> 8) & 0xFF)
        data[offset + 3] = UInt8(value & 0xFF)
    }

    private func writeUInt64BE(_ value: UInt64, into data: inout Data, offset: Int) {
        for index in 0..<8 {
            let shift = UInt64((7 - index) * 8)
            data[offset + index] = UInt8((value >> shift) & 0xFF)
        }
    }

    private func readRange(from source: URL, offset: Int, length: Int) throws -> Data {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        try input.seek(toOffset: UInt64(offset))
        return input.readData(ofLength: length)
    }

    private func writeRange(to destination: URL, offset: Int, data: Data) throws {
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        try output.seek(toOffset: UInt64(offset))
        try output.write(contentsOf: data)
    }

    private func freeAtomData(size: Int, headerSize: Int) -> Data {
        var data = Data(repeating: 0, count: size)
        if headerSize == 16 {
            writeUInt32BE(1, into: &data, offset: 0)
            data.replaceSubrange(4..<8, with: Data("free".utf8))
            writeUInt64BE(UInt64(size), into: &data, offset: 8)
        } else {
            writeUInt32BE(UInt32(size), into: &data, offset: 0)
            data.replaceSubrange(4..<8, with: Data("free".utf8))
        }
        return data
    }

    private func copyRange(from source: URL, to destination: URL, start: Int, end: Int) throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: destination)
        defer {
            try? input.close()
            try? output.close()
        }

        try input.seek(toOffset: UInt64(start))
        var remaining = max(0, end - start)
        while remaining > 0 {
            let chunk = input.readData(ofLength: min(chunkSize, remaining))
            if chunk.isEmpty { break }
            try output.write(contentsOf: chunk)
            remaining -= chunk.count
        }

        guard remaining == 0 else {
            try? output.close()
            try? input.close()
            try? FileManager.default.removeItem(at: destination)
            throw NSError(domain: "SyncrosaInfoEraser", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not copy the full audio payload."
            ])
        }
    }

    private func replaceFile(original: URL, temp: URL) throws {
        let backup = original.deletingLastPathComponent().appendingPathComponent(".syncrosa-tmp-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: original, to: backup)
        do {
            try FileManager.default.moveItem(at: temp, to: original)
            try FileManager.default.removeItem(at: backup)
        } catch {
            if FileManager.default.fileExists(atPath: original.path) {
                try? FileManager.default.removeItem(at: original)
            }
            try? FileManager.default.moveItem(at: backup, to: original)
            throw error
        }
    }

    private func relativePath(_ url: URL, base: URL) -> String {
        let basePath = base.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(basePath + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(basePath.count + 1))
    }

    private func safeURL(base: URL, relativePath: String) -> URL? {
        let candidate = base.appendingPathComponent(relativePath).standardizedFileURL
        let basePath = base.standardizedFileURL.path
        let path = candidate.path
        guard path == basePath || path.hasPrefix(basePath + "/") else { return nil }
        return candidate
    }
}

private extension JSONEncoder {
    static var prettySorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
