import XCTest
@testable import Syncrosa

final class LibraryToolkitServiceTests: XCTestCase {
    func testAppearanceOptionsAreStableAndComplete() {
        XCTAssertEqual(SyncrosaAppearanceMode.system.preferredColorScheme, nil)
        XCTAssertEqual(SyncrosaAppearanceMode.light.preferredColorScheme, .light)
        XCTAssertEqual(SyncrosaAppearanceMode.dark.preferredColorScheme, .dark)
        XCTAssertEqual(Set(SyncrosaThemeChoice.allCases.map(\.rawValue)).count, SyncrosaThemeChoice.allCases.count)
        XCTAssertEqual(SyncrosaThemeChoice.allCases.count, 7)

        for theme in SyncrosaThemeChoice.allCases {
            XCTAssertFalse(theme.displayName(language: "en").isEmpty)
            XCTAssertFalse(theme.displayName(language: "ru").isEmpty)
        }
    }

    func testMusicLibraryManifestContainsOnlyCatalogMetadata() {
        let tracks = [
            MusicTrack(
                persistentID: "A1B2C3D4E5F67890",
                name: "Children",
                artist: "Robert Miles",
                album: "Dreamland",
                genre: "Electronic",
                year: 1996
            )
        ]

        let manifest = MusicLibraryExchangeService.shared.makeManifest(from: tracks)

        XCTAssertEqual(manifest.schema, "syncrosa-music-library-v1")
        XCTAssertEqual(manifest.tracks.count, 1)
        XCTAssertEqual(manifest.tracks.first?.id, "A1B2C3D4E5F67890")
        XCTAssertEqual(manifest.tracks.first?.title, "Children")
        XCTAssertFalse(manifest.instructions.isEmpty)
    }

    func testMusicLibrarySelectionRejectsInvalidAndDuplicateIDs() {
        let selection = MusicLibraryAISelection(
            playlistName: "Night Drive",
            trackIDs: ["a1b2c3d4e5f67890", "not-an-id", "A1B2C3D4E5F67890"],
            selectedTrackIDs: ["0123456789abcdef"],
            tracks: [MusicLibraryAISelectedTrack(id: "FFFFFFFFFFFFFFFF", persistentID: nil)]
        )

        XCTAssertEqual(
            MusicLibraryExchangeService.shared.validatedTrackIDs(from: selection),
            ["A1B2C3D4E5F67890", "0123456789ABCDEF", "FFFFFFFFFFFFFFFF"]
        )
    }

    func testMusicLibraryManifestWritesARestrictedRoundTripJSON() throws {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("syncrosa-library-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: output) }

        let manifest = MusicLibraryExchangeService.shared.makeManifest(from: [
            MusicTrack(
                persistentID: "A1B2C3D4E5F67890",
                name: "Children",
                artist: "Robert Miles",
                album: "Dreamland",
                genre: "Electronic",
                year: 1996
            )
        ])

        try MusicLibraryExchangeService.shared.writeManifest(manifest, to: output)

        let data = try Data(contentsOf: output)
        let decoded = try JSONDecoder().decode(MusicLibraryAIManifest.self, from: data)
        XCTAssertEqual(decoded, manifest)

        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tracks = try XCTUnwrap(root["tracks"] as? [[String: Any]])
        XCTAssertEqual(Set(tracks[0].keys), Set(["id", "title", "artist", "album", "genre", "year"]))
        XCTAssertNil(root["apiKey"])
        XCTAssertNil(tracks[0]["path"])
    }

    func testMetadataSearchURLPreservesSpecialCharactersInQuery() throws {
        let url = try XCTUnwrap(MetadataService.shared.searchURL(for: "Rock & Roll?", artist: "AC/DC"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(query["term"], "Rock & Roll? AC/DC")
        XCTAssertEqual(query["entity"], "song")
        XCTAssertEqual(query["limit"], "1")
    }

    func testSharedInterfaceKeysAreLocalizedForEverySupportedLanguage() {
        let service = LocalizationService.shared
        let previous = service.selectedLanguage
        defer { service.selectedLanguage = previous }
        let expectedClose = [
            "en": "Close", "ru": "Закрыть", "be": "Закрыць", "ko": "닫기", "ja": "閉じる",
            "zh": "关闭", "de": "Schließen", "pl": "Zamknij", "et": "Sulge", "es": "Cerrar"
        ]

        for (language, expected) in expectedClose {
            service.selectedLanguage = language
            XCTAssertEqual(service.t("close"), expected, "Missing close translation for \(language)")
            XCTAssertNotEqual(service.t("operation_history"), "operation_history")
            XCTAssertNotEqual(service.t("rename_format"), "rename_format")
        }
    }

    func testCompletenessScoreTracksMissingFields() {
        let track = makeTrack(
            title: "Song",
            artist: "",
            album: "",
            genre: "Electronic",
            year: 0,
            hasArtwork: false,
            fileExists: false
        )

        XCTAssertEqual(track.missingFields, ["artist", "album", "year", "artwork", "linked file"])
        XCTAssertEqual(track.completenessScore, 28)
    }

    func testRenameTemplateBuildsSanitizedFilename() {
        let track = makeTrack(
            title: "Children: Dream Version",
            artist: "Robert Miles",
            album: "Dreamland",
            genre: "Electronic",
            year: 1996,
            trackNumber: 3,
            path: "/tmp/Robert_Miles_-_Children_Dream_Version.mp3"
        )

        let renamed = LibraryToolkitService.shared.renamedPath(
            for: track,
            template: "{track} {artist} - {title}"
        )

        XCTAssertEqual(renamed, "/tmp/03 Robert Miles - Children- Dream Version.mp3")
    }

    func testRenameTemplateRejectsUnknownPlaceholder() {
        let track = makeTrack(
            title: "Children",
            artist: "Robert Miles",
            album: "Dreamland",
            genre: "Electronic",
            year: 1996
        )

        XCTAssertNil(
            LibraryToolkitService.shared.renamedPath(
                for: track,
                template: "{artist} - {unsupported} - {title}"
            )
        )
    }

    func testRenameTemplateNormalizesRepeatedWhitespace() {
        let track = makeTrack(
            title: "Children",
            artist: "Robert   Miles",
            album: "Dreamland",
            genre: "Electronic",
            year: 1996
        )

        let renamed = LibraryToolkitService.shared.renamedPath(
            for: track,
            template: "{artist}     -     {title}"
        )

        XCTAssertEqual(renamed, "/tmp/Robert Miles - Children.mp3")
    }

    func testRenameConflictDoesNotMoveSourceFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("syncrosa-rename-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("source.mp3")
        let destination = directory.appendingPathComponent("destination.mp3")
        try Data("source".utf8).write(to: source)
        try Data("destination".utf8).write(to: destination)

        let preview = LibraryToolkitChangePreview(
            id: UUID(),
            trackID: source.path,
            trackTitle: "Source",
            field: "filename",
            oldValue: source.path,
            newValue: destination.path,
            source: "Test",
            risk: "medium",
            path: source.path
        )

        XCTAssertThrowsError(try LibraryToolkitService.shared.applyRenamePreviews([preview]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: source), "source")
        XCTAssertEqual(try String(contentsOf: destination), "destination")
    }

    func testReportIncludesAuditSummary() {
        let complete = makeTrack(title: "A", artist: "Artist", album: "Album", genre: "Pop", year: 2020)
        let missing = makeTrack(title: "B", artist: "", album: "", genre: "", year: 0, hasArtwork: false, fileExists: false, path: "/tmp/B.m4a")
        let preset = LibraryToolkitPreset.defaults[0]
        let report = LibraryToolkitService.shared.createReport(
            tracks: [complete, missing],
            previews: [
                LibraryToolkitChangePreview(
                    id: UUID(),
                    trackID: "2",
                    trackTitle: "B",
                    field: "artist",
                    oldValue: "",
                    newValue: "Artist",
                    source: "Local Filename",
                    risk: "low",
                    path: "/tmp/B.m4a"
                )
            ],
            unlinkedFiles: [URL(fileURLWithPath: "/tmp/unlinked.mp3")],
            preset: preset
        )

        XCTAssertEqual(report.totalTracks, 2)
        XCTAssertEqual(report.missingFiles, 1)
        XCTAssertEqual(report.missingArtwork, 1)
        XCTAssertEqual(report.unlinkedFolderFiles, 1)
        XCTAssertEqual(report.missingFieldCounts["artist"], 1)
        XCTAssertEqual(report.formatCounts["MP3"], 1)
        XCTAssertEqual(report.formatCounts["M4A"], 1)
        XCTAssertEqual(report.previews.count, 1)
        XCTAssertEqual(report.enabledSources, ["Local Filename", "Music Library"])
    }

    func testCSVExportQuotesCommas() throws {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("syncrosa-toolkit-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: output) }

        let track = makeTrack(
            title: "Hello, World",
            artist: "Artist",
            album: "Album",
            genre: "Pop",
            year: 2024
        )

        try LibraryToolkitService.shared.writeCSVReport(tracks: [track], to: output)
        let contents = try String(contentsOf: output, encoding: .utf8)

        XCTAssertTrue(contents.contains("\"Hello, World\""))
        XCTAssertTrue(contents.contains("\"Artist\""))
        XCTAssertTrue(contents.contains(",100,"))
    }

    private func makeTrack(
        title: String,
        artist: String,
        album: String,
        genre: String,
        year: Int,
        trackNumber: Int = 1,
        hasArtwork: Bool = true,
        fileExists: Bool = true,
        path: String = "/tmp/sample.mp3"
    ) -> LibraryToolkitTrackSnapshot {
        LibraryToolkitTrackSnapshot(
            persistentID: UUID().uuidString,
            title: title,
            artist: artist,
            album: album,
            albumArtist: artist,
            genre: genre,
            composer: "",
            comments: "",
            path: path,
            kind: URL(fileURLWithPath: path).pathExtension.uppercased(),
            year: year,
            trackNumber: trackNumber,
            discNumber: 0,
            bpm: 0,
            rating: 0,
            size: 1234,
            hasArtwork: hasArtwork,
            fileExists: fileExists
        )
    }
}
