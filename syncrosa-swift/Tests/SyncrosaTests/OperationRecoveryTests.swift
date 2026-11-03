import XCTest
@testable import Syncrosa

final class OperationRecoveryTests: XCTestCase {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("syncrosa-recovery-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testFinishingOneOperationDoesNotEraseOtherInterruptedOperations() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let firstSession = OperationRecoveryService(directory: root)
        let first = firstSession.begin(tool: "First", title: "One", message: "Interrupted")
        let second = firstSession.begin(tool: "Second", title: "Two", message: "Interrupted")
        let restored = OperationRecoveryService(directory: root)
        XCTAssertEqual(Set(restored.interruptedOperations.map(\.id)), [first, second])
        let current = restored.begin(tool: "Third", title: "Three", message: "Running")
        XCTAssertEqual(restored.interruptedOperations.count, 2)
        restored.finish(current)
        XCTAssertEqual(Set(OperationRecoveryService(directory: root).interruptedOperations.map(\.id)), [first, second])
        restored.clear(id: first)
        XCTAssertEqual(OperationRecoveryService(directory: root).interruptedOperations.map(\.id), [second])
    }

    func testRunningOperationsCannotBeDiscardedAsInterrupted() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = OperationRecoveryService(directory: root)
        let current = service.begin(tool: "Tool", title: "Work", message: "Running")
        XCTAssertNil(service.activeOperation)
        service.clear(id: current)
        XCTAssertFalse(service.persistenceWarnings.isEmpty)
        XCTAssertEqual(OperationRecoveryService(directory: root).interruptedOperations.map(\.id), [current])
        service.finish(current)
        XCTAssertTrue(OperationRecoveryService(directory: root).interruptedOperations.isEmpty)
    }

    func testCorruptRecoveryRecordRemainsVisibleAsWarningAndIsPreserved() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Recovery Operations/Swift", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let invalid = directory.appendingPathComponent("broken.json")
        let bytes = Data("unfinished record".utf8)
        try bytes.write(to: invalid)
        let service = OperationRecoveryService(directory: root)
        XCTAssertFalse(service.persistenceWarnings.isEmpty)
        service.clear()
        XCTAssertEqual(try Data(contentsOf: invalid), bytes)
    }

    func testLegacySwiftMarkerMigratesBeforeOldRecordIsRemoved() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let identifier = UUID()
        let old = root.appendingPathComponent("active-operation.json")
        let marker: [String: Any] = ["id": identifier.uuidString, "tool": "Folder Fixer", "title": "Rename", "message": "Interrupted", "startedAt": "2026-11-03T10:00:00Z", "affectedCount": 3, "backupPath": "/kept/backup"]
        try JSONSerialization.data(withJSONObject: marker).write(to: old)
        let service = OperationRecoveryService(directory: root)
        XCTAssertEqual(service.interruptedOperations.first?.id, identifier)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertEqual(OperationRecoveryService(directory: root).interruptedOperations.first?.backupPath, "/kept/backup")
        service.clear(id: identifier)
        XCTAssertTrue(OperationRecoveryService(directory: root).interruptedOperations.isEmpty)
    }

    func testLegacyCocoaMarkerAndCorruptLegacyFileAreHandledWithoutLoss() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("active-operation.plist")
        let marker: [String: Any] = ["id": "old-host_1234_5678", "tool": "Info Eraser", "title": "Backup", "message": "Interrupted", "startedAt": 1_762_165_200, "affectedCount": 2]
        try PropertyListSerialization.data(fromPropertyList: marker, format: .binary, options: 0).write(to: old)
        let service = OperationRecoveryService(directory: root)
        XCTAssertEqual(service.interruptedOperations.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        let identifier = try XCTUnwrap(service.interruptedOperations.first?.id)
        XCTAssertEqual(OperationRecoveryService(directory: root).interruptedOperations.first?.id, identifier)
        let corrupt = root.appendingPathComponent("active-operation.json")
        try Data("broken legacy".utf8).write(to: corrupt)
        service.refresh()
        XCTAssertFalse(service.persistenceWarnings.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: corrupt.path))
        XCTAssertEqual(service.interruptedOperations.map(\.id), [identifier])
    }

    func testRecoveryPersistenceFailureIsReportedWithoutRemovingLegacyFile() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("not a directory".utf8).write(to: root.appendingPathComponent("Recovery Operations"))
        let legacy = root.appendingPathComponent("active-operation.json")
        let marker: [String: Any] = ["id": UUID().uuidString, "tool": "Tool", "title": "Work", "message": "Interrupted", "startedAt": "2026-11-03T10:00:00Z", "affectedCount": 1]
        try JSONSerialization.data(withJSONObject: marker).write(to: legacy)
        let service = OperationRecoveryService(directory: root)
        XCTAssertFalse(service.persistenceWarnings.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
        _ = service.begin(tool: "Tool", title: "Another operation", message: "Running")
        XCTAssertFalse(service.persistenceWarnings.isEmpty)
    }
}
