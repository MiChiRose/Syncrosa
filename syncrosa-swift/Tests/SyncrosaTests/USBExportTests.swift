import XCTest
import CryptoKit
@testable import Syncrosa

final class USBExportTests: XCTestCase {
    private final class Fixture {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("syncrosa-usb-test-\(UUID().uuidString)")
        var sources: URL { root.appendingPathComponent("sources") }
        var drive: URL { root.appendingPathComponent("drive") }
        var journals: URL { root.appendingPathComponent("journals") }
        var folder: URL { drive.appendingPathComponent("Mix") }
        init() throws {
            for path in [sources, drive, journals] { try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true) }
        }
        deinit { try? FileManager.default.removeItem(at: root) }
        func track(_ name: String, bytes: Data = Data("music".utf8), artist: String = "Artist") throws -> PlaylistExportService.TrackFile {
            let path = sources.appendingPathComponent(name + ".mp3")
            try bytes.write(to: path)
            return .init(name: name, artist: artist, filePath: path.path, fileSize: 0, isDRM: false)
        }
        func service(capacity: Int64 = 1_000_000_000, identity: String = "test-volume", fault: ((String, URL) throws -> Void)? = nil) -> PlaylistExportService {
            PlaylistExportService(journalDirectory: journals, volumeIdentity: { _ in identity }, availableCapacity: { _ in capacity }, fault: fault)
        }
        func musicFiles() throws -> [URL] {
            try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "mp3" }
        }
        func json(_ url: URL) throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]) }
        func save(_ object: [String: Any], to url: URL) throws { try JSONSerialization.data(withJSONObject: object).write(to: url, options: .atomic) }
    }
    private enum Injected: Error { case interruption }

    func testDestinationURLCreatedBeforeDirectoryExistsUsesFilesystemPathIdentity() throws {
        let f = try Fixture(); let track = try f.track("Song")
        let destination = URL(fileURLWithPath: f.root.path + "/new-drive")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let result = f.service().exportSynchronously(tracks: [track], destination: destination, playlistName: "Mix")
        XCTAssertTrue(result.errors.isEmpty, result.errors.joined(separator: ";")); XCTAssertEqual(result.copiedCount, 1)
    }

    func testOwnedPartialIsRemovedBeforeMissingSourceAndCapacityPlanning() throws {
        let f = try Fixture(); let missing = try f.track("Missing", bytes: Data(repeating: 9, count: 3 * 1024 * 1024)); let healthy = try f.track("Healthy", bytes: Data("valid".utf8))
        var identity = "original-volume"
        let initialService = PlaylistExportService(journalDirectory: f.journals, volumeIdentity: { _ in identity }, availableCapacity: { _ in 1_000_000_000 })
        let paused = initialService.exportSynchronously(tracks: [missing, healthy], destination: f.drive, playlistName: "Mix") { progress in
            if progress.bytesCopied > 0 { initialService.cancel(); identity = "disconnected" }
        }
        XCTAssertTrue(paused.wasCancelled)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.folder.path).contains { $0.hasSuffix(".part") })
        try FileManager.default.removeItem(atPath: missing.filePath)
        identity = "original-volume"
        let resumedService = PlaylistExportService(journalDirectory: f.journals, volumeIdentity: { _ in identity }, availableCapacity: { _ in
            let partialStillOccupiesSpace = try FileManager.default.contentsOfDirectory(atPath: f.folder.path).contains { $0.hasSuffix(".part") }
            return partialStillOccupiesSpace ? 0 : 5
        })
        let resumed = resumedService.resumeSynchronously(jobID: try XCTUnwrap(paused.jobID), destination: f.drive)
        XCTAssertFalse(resumed.insufficientSpace, resumed.errors.joined(separator: ";")); XCTAssertEqual(resumed.copiedCount, 1); XCTAssertEqual(resumed.skippedNotDownloaded, 1)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: f.folder.path).contains { $0.hasSuffix(".part") })
        XCTAssertEqual(resumedService.loadPendingJobs().jobs.count, 1)
    }

    func testRepeatedExportDoesNotRewriteOrDuplicateIdenticalFiles() throws {
        let f = try Fixture(); let track = try f.track("Song")
        let first = f.service().exportSynchronously(tracks: [track], destination: f.drive, playlistName: "Mix", createM3U8: true)
        XCTAssertTrue(first.errors.isEmpty, first.errors.joined(separator: ";")); XCTAssertEqual(first.copiedCount, 1)
        let original = try XCTUnwrap(f.musicFiles().first)
        let inode = try FileManager.default.attributesOfItem(atPath: original.path)[.systemFileNumber] as? NSNumber
        let second = f.service().exportSynchronously(tracks: [track], destination: f.drive, playlistName: "Mix", createM3U8: true)
        XCTAssertTrue(second.errors.isEmpty, second.errors.joined(separator: ";")); XCTAssertEqual(second.copiedCount, 0); XCTAssertEqual(second.existingCount, 1); XCTAssertEqual(second.totalBytesCopied, 0)
        XCTAssertEqual(try f.musicFiles().count, 1)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: original.path)[.systemFileNumber] as? NSNumber, inode)
    }

    func testLegacyExportsWithoutManifestAreAdoptedAfterContentVerification() throws {
        let f = try Fixture(); let track = try f.track("Song")
        try FileManager.default.createDirectory(at: f.folder, withIntermediateDirectories: true)
        try Data("other".utf8).write(to: f.folder.appendingPathComponent("Artist - Song.mp3"))
        try Data("music".utf8).write(to: f.folder.appendingPathComponent("Artist - Song_3.mp3"))
        let result = f.service().exportSynchronously(tracks: [track], destination: f.drive, playlistName: "Mix")
        XCTAssertTrue(result.errors.isEmpty); XCTAssertEqual(result.copiedCount, 0); XCTAssertEqual(result.existingCount, 1); XCTAssertEqual(try f.musicFiles().count, 2)
    }

    func testSameSizeSourceChangesCreateNewVersionWithoutOverwritingOldFile() throws {
        let f = try Fixture(); let track = try f.track("Song", bytes: Data("AAAA".utf8))
        XCTAssertEqual(f.service().exportSynchronously(tracks: [track], destination: f.drive, playlistName: "Mix").copiedCount, 1)
        try Data("BBBB".utf8).write(to: URL(fileURLWithPath: track.filePath))
        let changed = f.service().exportSynchronously(tracks: [track], destination: f.drive, playlistName: "Mix")
        XCTAssertTrue(changed.errors.isEmpty); XCTAssertEqual(changed.copiedCount, 1); XCTAssertEqual(changed.existingCount, 0)
        XCTAssertEqual(try Data(contentsOf: f.folder.appendingPathComponent("Artist - Song.mp3")), Data("AAAA".utf8))
        XCTAssertEqual(f.service().exportSynchronously(tracks: [track], destination: f.drive, playlistName: "Mix").copiedCount, 0)
    }

    func testTamperedManifestCannotMakeDifferentSameSizeDestinationLookValid() throws {
        let f = try Fixture(); let track = try f.track("Song", bytes: Data("AAAA".utf8))
        _ = f.service().exportSynchronously(tracks: [track], destination: f.drive, playlistName: "Mix")
        let target = f.folder.appendingPathComponent("Artist - Song.mp3")
        try Data("BBBB".utf8).write(to: target)
        let manifestURL = f.folder.appendingPathComponent(".syncrosa-export.json")
        var manifest = try f.json(manifestURL)
        var entries = try XCTUnwrap(manifest["entries"] as? [[String: Any]])
        entries[0]["sha256"] = SHA256.hash(data: Data("BBBB".utf8)).map { String(format: "%02x", $0) }.joined()
        manifest["entries"] = entries; try f.save(manifest, to: manifestURL)
        let result = f.service().exportSynchronously(tracks: [track], destination: f.drive, playlistName: "Mix")
        XCTAssertEqual(result.copiedCount, 1); XCTAssertEqual(result.existingCount, 0)
        XCTAssertEqual(try Data(contentsOf: target), Data("BBBB".utf8))
    }

    func testPauseKeepsCompletedPlaylistAndResumeCopiesOnlyRemainingFiles() throws {
        let f = try Fixture(); let first = try f.track("First", bytes: Data("first".utf8)); let second = try f.track("Second", bytes: Data(repeating: 7, count: 3 * 1024 * 1024))
        let service = f.service()
        let paused = service.exportSynchronously(tracks: [first, second], destination: f.drive, playlistName: "Mix", createM3U8: true) { progress in
            if progress.currentTrack == 2 && progress.bytesCopied > 5 { service.cancel() }
        }
        XCTAssertTrue(paused.wasCancelled); XCTAssertEqual(paused.copiedCount, 1)
        let playlist = try String(contentsOf: f.folder.appendingPathComponent("Mix.m3u8"))
        XCTAssertTrue(playlist.contains("Artist - First.mp3")); XCTAssertFalse(playlist.contains("Second")); XCTAssertFalse(playlist.contains(".part"))
        XCTAssertEqual(service.loadPendingJobs().jobs.count, 1)
        let resumed = f.service().resumeSynchronously(jobID: try XCTUnwrap(paused.jobID), destination: f.drive)
        XCTAssertTrue(resumed.errors.isEmpty, resumed.errors.joined(separator: ";")); XCTAssertEqual(resumed.copiedCount, 1); XCTAssertEqual(resumed.existingCount, 1)
        XCTAssertEqual(try f.musicFiles().count, 2)
        XCTAssertTrue(try String(contentsOf: f.folder.appendingPathComponent("Mix.m3u8")).contains("Artist - Second.mp3"))
        XCTAssertTrue(f.service().loadPendingJobs().jobs.isEmpty)
    }

    func testCrashAfterPromotionIsRecoveredWithoutCopyingCompletedFileAgain() throws {
        let f = try Fixture(); let tracks = [try f.track("First"), try f.track("Second", bytes: Data("other".utf8))]
        let interrupted = f.service(fault: { event, _ in if event == "afterPromotion" { throw Injected.interruption } }).exportSynchronously(tracks: tracks, destination: f.drive, playlistName: "Mix")
        XCTAssertFalse(interrupted.errors.isEmpty); XCTAssertEqual(try f.musicFiles().count, 1)
        let resumed = f.service().resumeSynchronously(jobID: try XCTUnwrap(interrupted.jobID), destination: f.drive)
        XCTAssertTrue(resumed.errors.isEmpty, resumed.errors.joined(separator: ";")); XCTAssertEqual(resumed.copiedCount, 1); XCTAssertEqual(resumed.existingCount, 1); XCTAssertEqual(try f.musicFiles().count, 2)
    }

    func testExistingFilesDoNotNeedAvailableCopySpace() throws {
        let f = try Fixture(); let track = try f.track("Song")
        _ = f.service().exportSynchronously(tracks: [track], destination: f.drive, playlistName: "Mix")
        let second = f.service(capacity: 0).exportSynchronously(tracks: [track], destination: f.drive, playlistName: "Mix")
        XCTAssertTrue(second.errors.isEmpty); XCTAssertFalse(second.insufficientSpace); XCTAssertEqual(second.existingCount, 1); XCTAssertEqual(second.copiedCount, 0)
    }

    func testInsufficientSpaceCanContinueSameJournalWithFitMode() throws {
        let f = try Fixture(); let tracks = [try f.track("First", bytes: Data("1111".utf8)), try f.track("Second", bytes: Data("2222".utf8))]
        let initial = f.service(capacity: 4).exportSynchronously(tracks: tracks, destination: f.drive, playlistName: "Mix")
        XCTAssertTrue(initial.insufficientSpace)
        let fitted = f.service(capacity: 4).resumeSynchronously(jobID: try XCTUnwrap(initial.jobID), destination: f.drive, mode: .fitAvailable)
        XCTAssertTrue(fitted.errors.isEmpty); XCTAssertEqual(fitted.copiedCount, 1); XCTAssertEqual(fitted.skippedForSpace, 1)
    }

    func testFitSelectionDoesNotChangeAfterInterruptionWhenMoreSpaceAppears() throws {
        let f = try Fixture(); let tracks = [try f.track("First", bytes: Data("1111".utf8)), try f.track("Second", bytes: Data("2222".utf8)), try f.track("Third", bytes: Data("3333".utf8))]
        let first = f.service(capacity: 4, fault: { event, _ in if event == "afterPromotion" { throw Injected.interruption } }).exportSynchronously(tracks: tracks, destination: f.drive, playlistName: "Mix", mode: .fitAvailable)
        let resumed = f.service(capacity: 100).resumeSynchronously(jobID: try XCTUnwrap(first.jobID), destination: f.drive)
        XCTAssertTrue(resumed.errors.isEmpty); XCTAssertEqual(try f.musicFiles().count, 1); XCTAssertEqual(resumed.skippedForSpace, 2)
    }

    func testWrongDriveAndReplacedFolderAreRejectedBeforeWriting() throws {
        let f = try Fixture(); let track = try f.track("Song")
        let interrupted = f.service(fault: { _, _ in throw Injected.interruption }).exportSynchronously(tracks: [track], destination: f.drive, playlistName: "Mix")
        let jobID = try XCTUnwrap(interrupted.jobID)
        let wrong = f.service(identity: "different-drive").resumeSynchronously(jobID: jobID, destination: f.drive)
        XCTAssertFalse(wrong.errors.isEmpty); XCTAssertTrue(try f.musicFiles().isEmpty)
        let manifest = f.folder.appendingPathComponent(".syncrosa-export.json")
        var body = try f.json(manifest); body["folderID"] = UUID().uuidString; try f.save(body, to: manifest)
        XCTAssertFalse(f.service().resumeSynchronously(jobID: jobID, destination: f.drive).errors.isEmpty)
    }

    func testDisconnectedMountPathIsNotRecreatedOnResume() throws {
        let f = try Fixture(); let track = try f.track("Song")
        let interrupted = f.service(fault: { _, _ in throw Injected.interruption }).exportSynchronously(tracks: [track], destination: f.drive, playlistName: "Mix")
        try FileManager.default.moveItem(at: f.drive, to: f.root.appendingPathComponent("unmounted"))
        let result = f.service().resumeSynchronously(jobID: try XCTUnwrap(interrupted.jobID), destination: f.drive)
        XCTAssertFalse(result.errors.isEmpty); XCTAssertFalse(FileManager.default.fileExists(atPath: f.drive.path))
    }

    func testTraversalManifestAndSymlinkFolderNeverTouchOutsideFiles() throws {
        let f = try Fixture(); let track = try f.track("Song")
        try FileManager.default.createDirectory(at: f.folder, withIntermediateDirectories: true)
        let victim = f.root.appendingPathComponent("victim.mp3"); try Data("safe".utf8).write(to: victim)
        try f.save(["schemaVersion": 1, "folderID": UUID().uuidString, "entries": [["sourceKey": "x", "filename": "../victim.mp3", "size": 4, "sha256": String(repeating: "0", count: 64)]]], to: f.folder.appendingPathComponent(".syncrosa-export.json"))
        XCTAssertFalse(f.service().exportSynchronously(tracks: [track], destination: f.drive, playlistName: "Mix").errors.isEmpty)
        XCTAssertEqual(try Data(contentsOf: victim), Data("safe".utf8))
        try FileManager.default.removeItem(at: f.folder)
        try FileManager.default.createSymbolicLink(at: f.folder, withDestinationURL: f.sources)
        XCTAssertFalse(f.service().exportSynchronously(tracks: [track], destination: f.drive, playlistName: "Mix").errors.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: f.sources.path), ["Song.mp3"])
    }

    func testSymlinkDestinationIsPreservedAndNotMistakenForAnExistingCopy() throws {
        let f = try Fixture(); let track = try f.track("Song")
        try FileManager.default.createDirectory(at: f.folder, withIntermediateDirectories: true)
        let link = f.folder.appendingPathComponent("Artist - Song.mp3")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: track.filePath))
        let result = f.service().exportSynchronously(tracks: [track], destination: f.drive, playlistName: "Mix")
        XCTAssertTrue(result.errors.isEmpty); XCTAssertEqual(result.copiedCount, 1); XCTAssertEqual(result.existingCount, 0)
        XCTAssertNotNil(try FileManager.default.destinationOfSymbolicLink(atPath: link.path))
    }

    func testMissingSourceRemainsPendingAndCorruptJournalIsVisible() throws {
        let f = try Fixture(); let track = try f.track("Song")
        try FileManager.default.removeItem(atPath: track.filePath)
        let result = f.service().exportSynchronously(tracks: [track], destination: f.drive, playlistName: "Mix")
        XCTAssertFalse(result.errors.isEmpty); XCTAssertEqual(result.skippedNotDownloaded, 1); XCTAssertEqual(f.service().loadPendingJobs().jobs.count, 1)
        try Data("broken json".utf8).write(to: f.journals.appendingPathComponent("swift-\(UUID().uuidString).json"))
        XCTAssertEqual(f.service().loadPendingJobs().errors.count, 1)
    }

    func testRepeatedPlaylistEntryCopiesOnceAndRetainsPlaylistOrder() throws {
        let f = try Fixture(); var first = try f.track("Song", bytes: Data("song".utf8)); first.persistentID = "0123456789ABCDEF"
        let result = f.service(capacity: 4).exportSynchronously(tracks: [first, first], destination: f.drive, playlistName: "Mix", createM3U8: true)
        XCTAssertTrue(result.errors.isEmpty, result.errors.joined(separator: ";")); XCTAssertEqual(result.copiedCount, 1); XCTAssertEqual(result.existingCount, 1)
        XCTAssertEqual(try f.musicFiles().count, 1)
        let lines = try String(contentsOf: f.folder.appendingPathComponent("Mix.m3u8")).split(separator: "\n")
        XCTAssertEqual(lines.count, 3); XCTAssertEqual(lines[1], lines[2])
    }

    func testPartialCleanupDoesNotFollowReplacedExportFolderSymlink() throws {
        let f = try Fixture(); let track = try f.track("Large", bytes: Data(repeating: 7, count: 2 * 1024 * 1024))
        let moved = f.root.appendingPathComponent("moved-export")
        let outside = f.root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        var linked: URL?
        var replaced = false
        let service = f.service(fault: { event, partial in
            guard event == "afterChunk", !replaced else { return }
            replaced = true
            try FileManager.default.moveItem(at: f.folder, to: moved)
            let outsideFile = outside.appendingPathComponent(partial.lastPathComponent)
            try FileManager.default.linkItem(at: moved.appendingPathComponent(partial.lastPathComponent), to: outsideFile)
            linked = outsideFile
            try FileManager.default.createSymbolicLink(at: f.folder, withDestinationURL: outside)
        })
        let result = service.exportSynchronously(tracks: [track], destination: f.drive, playlistName: "Mix")
        XCTAssertFalse(result.errors.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(linked).path))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: track.filePath)).count, 2 * 1024 * 1024)
    }

    func testMissingFirstSourceDoesNotBlockHealthyTracksAndCanResumeLater() throws {
        let f = try Fixture(); let missing = try f.track("Missing"); let valid = try f.track("Valid", bytes: Data("valid".utf8))
        try FileManager.default.removeItem(atPath: missing.filePath)
        let first = f.service().exportSynchronously(tracks: [missing, valid], destination: f.drive, playlistName: "Mix", createM3U8: true)
        XCTAssertFalse(first.errors.isEmpty); XCTAssertEqual(first.copiedCount, 1); XCTAssertEqual(first.skippedNotDownloaded, 1)
        XCTAssertEqual(f.service().loadPendingJobs().jobs.count, 1)
        try Data("music".utf8).write(to: URL(fileURLWithPath: missing.filePath))
        let resumed = f.service().resumeSynchronously(jobID: try XCTUnwrap(first.jobID), destination: f.drive)
        XCTAssertTrue(resumed.errors.isEmpty, resumed.errors.joined(separator: ";")); XCTAssertEqual(resumed.copiedCount, 1); XCTAssertEqual(resumed.existingCount, 1)
        XCTAssertEqual(try f.musicFiles().count, 2)
    }

    func testResumeRejectsCopiedExportFolderOnSameVolume() throws {
        let f = try Fixture(); let track = try f.track("Song")
        let paused = f.service(fault: { _, _ in throw Injected.interruption }).exportSynchronously(tracks: [track], destination: f.drive, playlistName: "Mix")
        let other = f.root.appendingPathComponent("other-root")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: f.folder, to: other.appendingPathComponent("Mix"))
        let result = f.service().resumeSynchronously(jobID: try XCTUnwrap(paused.jobID), destination: other)
        XCTAssertFalse(result.errors.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: other.appendingPathComponent("Mix"), includingPropertiesForKeys: nil).filter { $0.pathExtension == "mp3" }.isEmpty)
    }

    func testPersistentIDKeepsIdentityAfterSourcePathAndTitleChange() throws {
        let f = try Fixture(); var track = try f.track("Original")
        track.persistentID = "0123456789ABCDEF"
        _ = f.service().exportSynchronously(tracks: [track], destination: f.drive, playlistName: "Mix")
        let moved = f.sources.appendingPathComponent("Renamed.mp3")
        try FileManager.default.moveItem(at: URL(fileURLWithPath: track.filePath), to: moved)
        let renamed = PlaylistExportService.TrackFile(name: "New Title", artist: "Artist", filePath: moved.path, fileSize: 0, isDRM: false, persistentID: track.persistentID)
        let result = f.service().exportSynchronously(tracks: [renamed], destination: f.drive, playlistName: "Mix")
        XCTAssertTrue(result.errors.isEmpty); XCTAssertEqual(result.copiedCount, 0); XCTAssertEqual(result.existingCount, 1); XCTAssertEqual(try f.musicFiles().count, 1)
    }

    func testTornLastCheckpointCanBeContinuedWithoutLosingEarlierCompletions() throws {
        let f = try Fixture(); let tracks = [try f.track("First"), try f.track("Second", bytes: Data("other".utf8))]
        let interrupted = f.service(fault: { event, _ in if event == "afterPromotion" { throw Injected.interruption } }).exportSynchronously(tracks: tracks, destination: f.drive, playlistName: "Mix")
        let id = try XCTUnwrap(interrupted.jobID)
        let path = f.journals.appendingPathComponent("swift-\(id.uuidString).json.checkpoints")
        let handle = try FileHandle(forWritingTo: path); try handle.seekToEnd(); try handle.write(contentsOf: Data("{\"incomplete\":".utf8)); try handle.close()
        XCTAssertTrue(f.service().loadPendingJobs().errors.isEmpty)
        let resumed = f.service().resumeSynchronously(jobID: id, destination: f.drive)
        XCTAssertTrue(resumed.errors.isEmpty, resumed.errors.joined(separator: ";")); XCTAssertEqual(try f.musicFiles().count, 2)
    }

    func testUnrelatedPlaylistFileIsPreservedAndRepeatedExportDoesNotMultiplyPlaylists() throws {
        let f = try Fixture(); let track = try f.track("Song")
        try FileManager.default.createDirectory(at: f.folder, withIntermediateDirectories: true)
        let unrelated = f.folder.appendingPathComponent("Mix.m3u8"); try Data("personal playlist".utf8).write(to: unrelated)
        _ = f.service().exportSynchronously(tracks: [track], destination: f.drive, playlistName: "Mix", createM3U8: true)
        _ = f.service().exportSynchronously(tracks: [track], destination: f.drive, playlistName: "Mix", createM3U8: true)
        XCTAssertEqual(try String(contentsOf: unrelated), "personal playlist")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: f.folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "m3u8" }.count, 2)
    }
}
