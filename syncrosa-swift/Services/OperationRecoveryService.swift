import Foundation
import CryptoKit

struct ActiveOperationMarker: Identifiable, Codable, Equatable {
    let id: UUID
    let tool: String
    let title: String
    let message: String
    let startedAt: Date
    let affectedCount: Int
    let backupPath: String?
}

private struct RecoveryRecord: Codable {
    let schemaVersion: Int
    let marker: ActiveOperationMarker
}

final class OperationRecoveryService: ObservableObject {
    static let shared = OperationRecoveryService()

    @Published private(set) var activeOperation: ActiveOperationMarker?
    @Published private(set) var interruptedOperations: [ActiveOperationMarker] = []
    @Published private(set) var persistenceWarnings: [String] = []

    private let rootDirectory: URL
    private let lock = NSRecursiveLock()
    private var storedMarkers: [UUID: ActiveOperationMarker] = [:]
    private var runningIDs = Set<UUID>()
    private var loadWarnings: [String] = []
    private var writeWarnings: [String] = []
    private var publicationGeneration = 0
    private let maximumRecordSize = 1024 * 1024

    private var recordsDirectory: URL {
        rootDirectory.appendingPathComponent("Recovery Operations", isDirectory: true)
            .appendingPathComponent("Swift", isDirectory: true)
    }

    init(directory: URL = SyncrosaStorage.applicationSupportDirectory) {
        rootDirectory = directory
        refresh()
    }

    @discardableResult
    func begin(tool: String, title: String, message: String, affectedCount: Int = 0, backupPath: String? = nil) -> UUID {
        lock.lock()
        defer { lock.unlock() }
        let marker = ActiveOperationMarker(id: UUID(), tool: tool, title: title, message: message,
                                          startedAt: Date(), affectedCount: max(0, affectedCount), backupPath: backupPath)
        do { try persist(marker) }
        catch { warn("Could not save recovery information for \(title): \(error.localizedDescription)") }
        storedMarkers[marker.id] = marker
        runningIDs.insert(marker.id)
        publish()
        return marker.id
    }

    func finish(_ id: UUID?) {
        guard let id else { return }
        lock.lock()
        defer { lock.unlock() }
        runningIDs.remove(id)
        removeMarker(id)
        publish()
    }

    /// Forget only the selected interrupted marker, never a running operation.
    func clear(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        guard !runningIDs.contains(id) else {
            warn("A running operation cannot be removed from recovery.")
            publish()
            return
        }
        removeMarker(id)
        publish()
    }

    // Keep older callers scoped to one interrupted operation.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        if let marker = pendingMarkers().first { removeMarker(marker.id) }
        publish()
    }

    func refresh() {
        lock.lock()
        defer { lock.unlock() }
        loadWarnings = []
        let running = storedMarkers.filter { runningIDs.contains($0.key) }
        var loaded: [UUID: ActiveOperationMarker] = [:]
        let manager = FileManager.default
        if manager.fileExists(atPath: recordsDirectory.path) {
            do {
                try requireDirectory(rootDirectory)
                try requireDirectory(recordsDirectory.deletingLastPathComponent())
                try requireDirectory(recordsDirectory)
                for url in try manager.contentsOfDirectory(at: recordsDirectory, includingPropertiesForKeys: nil)
                where url.pathExtension == "json" {
                    do {
                        let data = try readRecordData(url)
                        let record = try JSONDecoder.syncrosaRecovery.decode(RecoveryRecord.self, from: data)
                        guard record.schemaVersion == 1,
                              UUID(uuidString: url.deletingPathExtension().lastPathComponent) == record.marker.id,
                              record.marker.affectedCount >= 0 else { throw RecoveryStorageError.invalidRecord }
                        loaded[record.marker.id] = record.marker
                    } catch {
                        loadWarnings.append("Recovery record \(url.lastPathComponent) could not be read; it was preserved.")
                    }
                }
            } catch {
                loadWarnings.append("Recovery records could not be loaded: \(error.localizedDescription)")
            }
        }
        storedMarkers = loaded.merging(running) { _, inMemory in inMemory }
        migrateLegacyMarker(named: "active-operation.json", propertyList: false)
        migrateLegacyMarker(named: "active-operation.plist", propertyList: true)
        publish()
    }

    private func pendingMarkers() -> [ActiveOperationMarker] {
        storedMarkers.values.filter { !runningIDs.contains($0.id) }
            .sorted { $0.startedAt == $1.startedAt ? $0.id.uuidString < $1.id.uuidString : $0.startedAt > $1.startedAt }
    }

    private func publish() {
        let markers = pendingMarkers()
        let warnings = Array(Set(loadWarnings + writeWarnings)).sorted()
        publicationGeneration += 1
        let generation = publicationGeneration
        let apply = {
            self.lock.lock()
            defer { self.lock.unlock() }
            guard generation == self.publicationGeneration else { return }
            self.interruptedOperations = markers
            self.activeOperation = markers.first
            self.persistenceWarnings = warnings
        }
        if Thread.isMainThread { apply() }
        else { DispatchQueue.main.async(execute: apply) }
    }

    private func warn(_ warning: String) {
        if !writeWarnings.contains(warning) { writeWarnings.append(warning) }
        if writeWarnings.count > 25 { writeWarnings.removeFirst(writeWarnings.count - 25) }
    }

    private func markerURL(_ id: UUID) -> URL {
        recordsDirectory.appendingPathComponent(id.uuidString + ".json")
    }

    private func requireDirectory(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw RecoveryStorageError.invalidDirectory }
    }

    private func readRecordData(_ url: URL) throws -> Data {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue <= maximumRecordSize else {
            throw RecoveryStorageError.invalidRecord
        }
        return try Data(contentsOf: url)
    }

    private func persist(_ marker: ActiveOperationMarker) throws {
        let manager = FileManager.default
        let parent = recordsDirectory.deletingLastPathComponent()
        try manager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try requireDirectory(rootDirectory)
        for directory in [parent, recordsDirectory] {
            if !manager.fileExists(atPath: directory.path) {
                try manager.createDirectory(at: directory, withIntermediateDirectories: false)
            }
            try requireDirectory(directory)
        }
        let destination = markerURL(marker.id)
        if manager.fileExists(atPath: destination.path) {
            let existing = try JSONDecoder.syncrosaRecovery.decode(RecoveryRecord.self, from: readRecordData(destination))
            guard existing.schemaVersion == 1, existing.marker == marker else { throw RecoveryStorageError.conflictingRecord }
            return
        }
        let data = try JSONEncoder.syncrosaRecovery.encode(RecoveryRecord(schemaVersion: 1, marker: marker))
        try data.write(to: destination, options: .atomic)
    }

    private func removeMarker(_ id: UUID) {
        guard storedMarkers[id] != nil else { return }
        let url = markerURL(id)
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try requireDirectory(rootDirectory)
                try requireDirectory(recordsDirectory.deletingLastPathComponent())
                try requireDirectory(recordsDirectory)
                let record = try JSONDecoder.syncrosaRecovery.decode(RecoveryRecord.self, from: readRecordData(url))
                guard record.schemaVersion == 1, record.marker.id == id else { throw RecoveryStorageError.invalidRecord }
                try FileManager.default.removeItem(at: url)
            }
            storedMarkers.removeValue(forKey: id)
        } catch {
            warn("Recovery information could not be cleared: \(error.localizedDescription)")
        }
    }

    private func migrateLegacyMarker(named name: String, propertyList: Bool) {
        let url = rootDirectory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try requireDirectory(rootDirectory)
            let data = try readRecordData(url)
            let value: Any
            if propertyList { value = try PropertyListSerialization.propertyList(from: data, format: nil) }
            else { value = try JSONSerialization.jsonObject(with: data) }
            guard let dictionary = value as? [String: Any],
                  let marker = legacyMarker(dictionary) else { throw RecoveryStorageError.invalidRecord }
            try persist(marker)
            storedMarkers[marker.id] = marker
            // Another process may have changed the old marker since it was read.
            guard try readRecordData(url) == data else { throw RecoveryStorageError.conflictingRecord }
            try FileManager.default.removeItem(at: url)
        } catch {
            loadWarnings.append("Previous recovery file \(name) could not be migrated; it was preserved.")
        }
    }

    private func legacyMarker(_ dictionary: [String: Any]) -> ActiveOperationMarker? {
        guard let identifier = dictionary["id"] as? String, !identifier.isEmpty,
              let tool = dictionary["tool"] as? String,
              let title = dictionary["title"] as? String,
              let message = dictionary["message"] as? String,
              let affected = dictionary["affectedCount"] as? NSNumber, affected.intValue >= 0 else { return nil }
        let date: Date
        if let timestamp = dictionary["startedAt"] as? NSNumber, timestamp.doubleValue.isFinite, timestamp.doubleValue >= 0 {
            date = Date(timeIntervalSince1970: timestamp.doubleValue)
        } else if let text = dictionary["startedAt"] as? String, let decoded = ISO8601DateFormatter().date(from: text) {
            date = decoded
        } else { return nil }
        let identifierUUID: UUID
        if let uuid = UUID(uuidString: identifier) { identifierUUID = uuid }
        else {
            let bytes = Array(SHA256.hash(data: Data(identifier.utf8)).prefix(16))
            identifierUUID = UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
        }
        return ActiveOperationMarker(id: identifierUUID, tool: tool, title: title, message: message,
                                     startedAt: date, affectedCount: affected.intValue, backupPath: dictionary["backupPath"] as? String)
    }
}

private enum RecoveryStorageError: LocalizedError {
    case invalidRecord, invalidDirectory, conflictingRecord
    var errorDescription: String? {
        switch self {
        case .invalidRecord: return "The recovery file is invalid or unreadable."
        case .invalidDirectory: return "The recovery location is not a regular directory."
        case .conflictingRecord: return "Recovery information changed while it was being processed."
        }
    }
}

private extension JSONEncoder {
    static var syncrosaRecovery: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var syncrosaRecovery: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
