import Foundation
import XCTest
@testable import Syncrosa

final class OpenRouterCatalogTests: XCTestCase {
    func testCatalogPreservesAvailableSelectionAndRejectsPaidOrIncompatibleModels() throws {
        let free = ["prompt": "0", "completion": "0.0", "request": "0"]
        let data = try JSONSerialization.data(withJSONObject: ["data": [
            ["id": "example/text:free", "pricing": free],
            ["id": "example/text:free", "pricing": free],
            ["id": "example/image:free", "pricing": free,
             "architecture": ["output_modalities": ["image"]]],
            ["id": "example/paid:free", "pricing": ["prompt": "0", "completion": "0.1"]],
            ["id": "example/request:free", "pricing": ["prompt": "0", "completion": "0", "request": "0.01"]],
            ["id": "example/regular", "pricing": free],
            ["id": "example/missing-price:free"],
            ["id": "example/bad-price:free", "pricing": ["prompt": "0", "completion": false]]
        ] as [[String: Any]]])

        let models = try XCTUnwrap(AIService.freeOpenRouterModels(from: data))
        XCTAssertEqual(models, ["openrouter/free", "example/text:free"])
        XCTAssertEqual(AIService.preferredOpenRouterModel("example/text:free", in: models), "example/text:free")
        XCTAssertEqual(AIService.preferredOpenRouterModel("example/retired:free", in: models), "openrouter/free")
    }

    func testErrorPageCannotReplaceLastCatalog() {
        let error = Data(#"{"error":{"message":"temporarily unavailable"}}"#.utf8)
        XCTAssertNil(AIService.freeOpenRouterModels(from: error))
        XCTAssertNil(AIService.freeOpenRouterModels(from: Data(#"{"data":[]}"#.utf8)))
    }
}
