import AudioTitleCore
import Foundation
import XCTest

final class FolderTitleRepairTests: XCTestCase {
    private func fixture(_ name: String, bytes: Data) throws -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("syncrosa-titles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent(name)
        try bytes.write(to: file)
        return (file, directory.appendingPathComponent("originals", isDirectory: true))
    }

    private func ascii(_ text: String) -> Data { Data(text.utf8) }

    private func big(_ n: Int) -> Data {
        Data((0..<4).reversed().map { UInt8(truncatingIfNeeded: n >> ($0 * 8)) })
    }

    private func little(_ n: Int) -> Data { Data(big(n).reversed()) }

    private func frame(_ name: String, _ body: Data) -> Data {
        ascii(name) + big(body.count) + Data([0, 0]) + body
    }

    private func box(_ kind: Data, _ body: Data) -> Data { big(8 + body.count) + kind + body }
    private func box(_ kind: String, _ body: Data) -> Data { box(ascii(kind), body) }

    private func comment(_ string: String) -> Data { little(string.utf8.count) + ascii(string) }

    private func title(_ file: URL) -> String? { SRReadTrackTitle(file, nil)?["title"] as? String }

    func testMP3ReplacesExistingTitleAndKeepsArtistArtworkAndAudioOffset() throws {
        let artist = frame("TPE1", Data([0]) + ascii("Artist"))
        let artwork = frame("APIC", Data([0, 1, 2, 3]))
        let chapter = frame("CHAP", ascii("chapter") + Data([0]) + big(0) + big(1000) + big(120) + big(240))
        let frames = frame("TIT2", Data([0]) + ascii("Incorrect")) + artist + artwork + chapter
        let oldBody = frames + Data(repeating: 0, count: 127 - frames.count)
        let header = ascii("ID3") + Data([3, 0, 0, 0, 0, 0, 127])
        let audio = Data([0xFF, 0xFB]) + Data(repeating: 0x56, count: 418)
        let original = header + oldBody + audio
        let (file, backups) = try fixture("Artist - Правильное название.mp3", bytes: original)
        let snapshot = try XCTUnwrap(SRReadTrackTitle(file, nil))
        XCTAssertEqual(snapshot["title"] as? String, "Incorrect")
        XCTAssertEqual(SRTitleFromFilename(file), "Правильное название")

        var error: NSError?
        let backup = try XCTUnwrap(SRReplaceTrackTitle(file, snapshot, "Правильное название", backups, &error),
                                   error?.localizedDescription ?? "")
        let written = try Data(contentsOf: file)
        XCTAssertEqual(title(file), "Правильное название")
        XCTAssertEqual(written.count, original.count)
        XCTAssertEqual(written.suffix(audio.count), audio)
        for preserved in [artist, artwork, chapter] {
            XCTAssertNotNil(written.range(of: preserved))
        }
        XCTAssertEqual(try Data(contentsOf: backup), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backups.appendingPathComponent(".original.partial").path))
    }

    func testFLACUpdatesTitleWhilePreservingOtherCommentsAndAudio() throws {
        let artist = comment("ARTIST=Example")
        let album = comment("ALBUM=Untouched")
        let metadata = comment("Encoder") + little(3) + comment("title=Wrong") + artist + album
        let streamInfo = Data([0, 0, 0, 34]) + Data(repeating: 0, count: 34)
        let audio = Data([0xFF, 0xF8, 4, 7, 12])
        let original = ascii("fLaC") + streamInfo + Data([0x84]) + big(metadata.count).suffix(3) + metadata + audio
        let (file, backups) = try fixture("Track.flac", bytes: original)
        let snapshot = try XCTUnwrap(SRReadTrackTitle(file, nil))
        XCTAssertEqual(snapshot["title"] as? String, "Wrong")

        var error: NSError?
        XCTAssertNotNil(SRReplaceTrackTitle(file, snapshot, "Correct ♫", backups, &error), error?.localizedDescription ?? "")
        let written = try Data(contentsOf: file)
        XCTAssertEqual(title(file), "Correct ♫")
        XCTAssertEqual(written.suffix(audio.count), audio)
        XCTAssertNotNil(written.range(of: artist + album))
        XCTAssertEqual(written.prefix(4 + streamInfo.count), ascii("fLaC") + streamInfo)
    }

    func testM4AGrowingTitleKeepsMediaBoxAtItsOriginalOffset() throws {
        let artistType = Data([0xA9]) + ascii("ART")
        let titleType = Data([0xA9]) + ascii("nam")
        let dataHeader = big(1) + big(0)
        let artist = box(artistType, box("data", dataHeader + ascii("Artist")))
        let oldTitle = box(titleType, box("data", dataHeader + ascii("Wrong")))
        let handler = box("hdlr", big(0) + big(0) + ascii("mdir") + Data(repeating: 0, count: 12))
        let ftyp = box("ftyp", ascii("M4A "))
        let moov = box("moov", box("udta", box("meta", big(0) + handler + box("ilst", artist + oldTitle))))
        let media = box("mdat", Data([3, 2, 1, 0]))
        let original = ftyp + moov + media
        let (file, backups) = try fixture("Track.m4a", bytes: original)
        let snapshot = try XCTUnwrap(SRReadTrackTitle(file, nil))
        XCTAssertEqual(snapshot["title"] as? String, "Wrong")

        var error: NSError?
        XCTAssertNotNil(SRReplaceTrackTitle(file, snapshot, "Название длиннее", backups, &error), error?.localizedDescription ?? "")
        let written = try Data(contentsOf: file)
        XCTAssertEqual(title(file), "Название длиннее")
        XCTAssertEqual(written.range(of: media), original.range(of: media))
        XCTAssertNotNil(written.range(of: artist))
        XCTAssertEqual(written.subdata(in: (ftyp.count + 4)..<(ftyp.count + 8)), ascii("free"))
    }

    func testChangedFileAndUnwritableBackupPreventReplacement() throws {
        let audio = Data([0xFF, 0xFB, 54, 10]) + Data(repeating: 0, count: 416)
        let (file, backups) = try fixture("Keep.mp3", bytes: audio)
        var error: NSError?
        let snapshot = try XCTUnwrap(SRReadTrackTitle(file, nil))
        let changed = audio + Data([0x1C])
        try changed.write(to: file, options: .atomic)
        XCTAssertNil(SRReplaceTrackTitle(file, snapshot, "New title", backups, &error))
        XCTAssertEqual(error?.code, 3)
        XCTAssertEqual(try Data(contentsOf: file), changed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backups.path))

        let current = try XCTUnwrap(SRReadTrackTitle(file, nil))
        try ascii("Not a directory").write(to: backups)
        XCTAssertNil(SRReplaceTrackTitle(file, current, "New title", backups, &error))
        XCTAssertEqual(error?.code, 6)
        XCTAssertEqual(try Data(contentsOf: file), changed)
        let link = file.deletingLastPathComponent().appendingPathComponent("Alias.mp3")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertNil(SRReadTrackTitle(link, nil))
    }
}
