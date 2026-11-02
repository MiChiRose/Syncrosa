import Foundation
import XCTest
@testable import Syncrosa

final class MusicLibraryExchangeTests: XCTestCase {
    private let firstID = "A1B2C3D4E5F67890"
    private let secondID = "0123456789ABCDEF"

    func testFullLibraryManifestDoesNotSampleLargeCatalog() {
        let tracks = (0..<1501).map { index in
            MusicTrack(persistentID: String(format: "%016llX", Int64(index)), name: "Track \(index)", artist: "Artist", album: "Album", genre: "Electronic", year: 2000)
        }
        let manifest = MusicLibraryExchangeService.shared.makeManifest(from: tracks)
        XCTAssertEqual(manifest.trackCount, 1501)
        XCTAssertEqual(manifest.tracks.map(\.id), tracks.map(\.persistentID))
        XCTAssertEqual(manifest.selectionExample.trackIDs, Array(tracks.prefix(2).map(\.persistentID)))
    }

    func testUnknownIDsRejectEntireReplyBeforeReplacement() {
        let selection = MusicLibraryAISelection(playlistName: "Mix", trackIDs: [firstID, secondID], selectedTrackIDs: nil, tracks: nil)
        XCTAssertThrowsError(try MusicLibraryExchangeService.shared.validatedTrackIDs(from: selection, availableTrackIDs: [firstID])) { error in
            guard case MusicLibraryExchangeError.unknownTracks(1) = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testMalformedIDsCannotSilentlyProducePartialPlaylist() {
        let selection = MusicLibraryAISelection(playlistName: "Mix", trackIDs: [firstID, "not-an-id"], selectedTrackIDs: nil, tracks: nil)
        XCTAssertThrowsError(try MusicLibraryExchangeService.shared.validatedTrackIDs(from: selection, availableTrackIDs: [firstID]))
        let malformedTrack = MusicLibraryAISelection(playlistName: "Mix", trackIDs: [firstID], selectedTrackIDs: nil, tracks: [MusicLibraryAISelectedTrack(id: nil, persistentID: nil)])
        XCTAssertThrowsError(try MusicLibraryExchangeService.shared.validatedTrackIDs(from: malformedTrack, availableTrackIDs: [firstID]))
    }

    func testSelectionPreservesAgentOrderAndNormalizesDuplicateIDs() throws {
        let selection = MusicLibraryAISelection(playlistName: "Mix", trackIDs: [secondID.lowercased(), firstID, secondID], selectedTrackIDs: nil, tracks: nil)
        XCTAssertEqual(try MusicLibraryExchangeService.shared.validatedTrackIDs(from: selection, availableTrackIDs: [firstID, secondID]), [secondID, firstID])
    }

    func testLibraryExportCannotBeMistakenForAISelection() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("syncrosa-catalog-selection-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let track = MusicTrack(persistentID: firstID, name: "Song", artist: "Artist", album: "Album", genre: "Rock", year: 2000)
        try MusicLibraryExchangeService.shared.writeManifest(MusicLibraryExchangeService.shared.makeManifest(from: [track]), to: url)
        XCTAssertThrowsError(try MusicLibraryExchangeService.shared.readSelection(from: url)) { error in
            guard case MusicLibraryExchangeError.catalogInsteadOfSelection = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testReplyFromPreviousCocoaInstructionsIsAccepted() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("syncrosa-cocoa-selection-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try JSONSerialization.data(withJSONObject: ["playlistName": "Mix", "persistentIDs": [firstID]])
        try data.write(to: url)
        let selection = try MusicLibraryExchangeService.shared.readSelection(from: url)
        XCTAssertEqual(try MusicLibraryExchangeService.shared.validatedTrackIDs(from: selection, availableTrackIDs: [firstID]), [firstID])
    }

    func testCatalogSchemaCannotBypassSelectionValidationUsingCaseOrType() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("syncrosa-schema-selection-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        for schema in ["SYNCROSA-MUSIC-LIBRARY-V1", "SYNCROSA-MANIFEST"] {
            try JSONSerialization.data(withJSONObject: ["schema": schema, "trackIDs": [firstID]]).write(to: url)
            XCTAssertThrowsError(try MusicLibraryExchangeService.shared.readSelection(from: url)) { error in
                guard case MusicLibraryExchangeError.catalogInsteadOfSelection = error else { return XCTFail("Unexpected error: \(error)") }
            }
        }
        try JSONSerialization.data(withJSONObject: ["schema": NSNull(), "trackIDs": [firstID]]).write(to: url)
        XCTAssertThrowsError(try MusicLibraryExchangeService.shared.readSelection(from: url))
    }
}
