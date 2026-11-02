import XCTest
@testable import Syncrosa

final class MetadataRepairTests: XCTestCase {
    private func candidate(title: String = "Song", artist: String = "Artist", album: String = "Album", genre: String = "Rock", number: Int = 1) -> iTunesResult {
        iTunesResult(trackName: title, artistName: artist, collectionName: album, primaryGenreName: genre, releaseDate: nil, trackNumber: number, artworkUrl100: nil)
    }

    func testSearchDoesNotChooseFirstWrongArtist() {
        let wrong = candidate(artist: "Another Artist")
        let right = candidate()
        guard case .matched(let result) = MetadataService.selectMatch(from: [wrong, right], title: "Song", artist: "Artist") else { return XCTFail("Expected the matching recording") }
        XCTAssertEqual(result.artistName, "Artist")
    }

    func testSearchPreservesLiveRemixAndRemasterVersions() {
        for version in ["Live", "Remix", "2011 Remaster"] {
            if case .notFound = MetadataService.selectMatch(from: [candidate(title: "Song (\(version))")], title: "Song", artist: "Artist") {} else { XCTFail("Must not replace a studio recording with \(version)") }
            if case .notFound = MetadataService.selectMatch(from: [candidate()], title: "Song (\(version))", artist: "Artist") {} else { XCTFail("Must preserve requested \(version)") }
        }
    }

    func testSearchAcceptsPunctuationCaseAndDiacriticDifferences() {
        guard case .matched = MetadataService.selectMatch(from: [candidate(title: "Déjà Vu!", artist: "AC/DC")], title: "deja vu", artist: "ac dc") else { return XCTFail("Equivalent spelling should match") }
    }

    func testUnknownAlbumRejectsConflictingEditions() {
        let editions = [candidate(), candidate(album: "Greatest Hits", number: 8)]
        if case .ambiguous = MetadataService.selectMatch(from: editions, title: "Song", artist: "Artist") {} else { XCTFail("An unknown album cannot select an edition safely") }
    }

    func testKnownAlbumDisambiguatesTrackNumber() {
        let editions = [candidate(album: "Greatest Hits", number: 8), candidate()]
        guard case .matched(let result) = MetadataService.selectMatch(from: editions, title: "Song", artist: "Artist", album: "Album") else { return XCTFail("Known album should identify the edition") }
        XCTAssertEqual(result.trackNumber, 1)
    }

    func testConflictingTagsWithinSameAlbumAreNotApplied() {
        if case .ambiguous = MetadataService.selectMatch(from: [candidate(), candidate(number: 9)], title: "Song", artist: "Artist", album: "Album") {} else { XCTFail("Conflicting catalog records need review") }
    }

    func testMissingGenreDoesNotOverwriteExistingLyricsOrOtherTags() {
        let track = MetadataRepairTrack(persistentID: "AABBCCDDEEFF0011", title: "Song", artist: "Artist", album: "My Edition", genre: "", trackNumber: 7, hasLyrics: true)
        let changes = track.changes(selected: ["title", "artist", "album", "genre", "trackNumber", "lyrics"], metadata: candidate(), lyrics: "Replacement lyrics")
        XCTAssertEqual(changes, ["genre": "Rock"])
    }

    func testUnreadableLyricsAndTrackNumberArePreserved() {
        let track = MetadataRepairTrack(persistentID: "AABBCCDDEEFF0011", title: "Song", artist: "Artist", album: "Album", genre: "Rock", trackNumber: nil, hasLyrics: nil)
        XCTAssertTrue(track.changes(selected: ["lyrics", "trackNumber"], metadata: candidate(), lyrics: "Replacement lyrics").isEmpty)
    }

    func testOnlySelectedMissingFieldsCanBeFilled() {
        let track = MetadataRepairTrack(persistentID: "AABBCCDDEEFF0011", title: "Song", artist: "Artist", album: "", genre: "", trackNumber: 0, hasLyrics: false)
        XCTAssertEqual(track.changes(selected: ["genre"], metadata: candidate(), lyrics: "Found lyrics"), ["genre": "Rock"])
    }

    func testSummaryUsesActualChangesAndReportsPartialErrors() {
        var summary = MetadataRepairSummary()
        summary.record(skipped: true)
        summary.record(noMatch: true)
        summary.record(changed: true)
        summary.record(changed: true, failed: true)
        XCTAssertEqual(summary.updated, 2)
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(summary.notFound, 1)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.status, "WARN")
        var failed = MetadataRepairSummary()
        failed.record(failed: true)
        XCTAssertEqual(failed.status, "ERROR")
    }

    func testCatalogHTTPFailureIsNotReportedAsNoMatch() async {
        let session = stubSession(status: 429, body: "{}")
        defer { session.invalidateAndCancel() }
        if case .failed = await MetadataService(session: session).lookupMetadata(for: "Song", artist: "Artist") {} else { XCTFail("Rate limiting is an error, not an empty catalog") }
    }

    func testEmptyCatalogAndMalformedResponseAreDistinguished() async {
        let empty = stubSession(status: 200, body: "{\"results\":[]}")
        if case .notFound = await MetadataService(session: empty).lookupMetadata(for: "Song", artist: "Artist") {} else { XCTFail("Empty results mean no match") }
        empty.invalidateAndCancel()
        let malformed = stubSession(status: 200, body: "not json")
        defer { malformed.invalidateAndCancel() }
        if case .failed = await MetadataService(session: malformed).lookupMetadata(for: "Song", artist: "Artist") {} else { XCTFail("Malformed response is an error") }
    }

    func testLyricsNotFoundIsDifferentFromServiceFailure() async {
        let missing = stubSession(status: 404, body: "{}")
        if case .notFound = await LyricsService(session: missing).lookupLyrics(artist: "Artist", title: "Song") {} else { XCTFail("404 means lyrics are missing") }
        missing.invalidateAndCancel()
        let failed = stubSession(status: 503, body: "{}")
        defer { failed.invalidateAndCancel() }
        if case .failed = await LyricsService(session: failed).lookupLyrics(artist: "Artist", title: "Song") {} else { XCTFail("503 must remain visible as an error") }
    }

    private func stubSession(status: Int, body: String) -> URLSession {
        MetadataStubProtocol.status = status
        MetadataStubProtocol.body = Data(body.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MetadataStubProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class MetadataStubProtocol: URLProtocol {
    static var status = 200
    static var body = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
