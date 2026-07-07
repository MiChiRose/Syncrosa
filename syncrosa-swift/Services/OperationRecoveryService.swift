import Foundation

struct ActiveOperationMarker: Identifiable, Codable, Equatable {
    let id: UUID
    let tool: String
    let title: String
    let message: String
    let startedAt: Date
    let affectedCount: Int
    let backupPath: String?
}

final class OperationRecoveryService: ObservableObject {
    static let shared = OperationRecoveryService()

    @Published private(set) var activeOperation: ActiveOperationMarker?

    private var markerURL: URL {
        SyncrosaStorage.applicationSupportDirectory.appendingPathComponent("active-operation.json")
    }

    private init() {
        load()
    }

    @discardableResult
    func begin(tool: String, title: String, message: String, affectedCount: Int = 0, backupPath: String? = nil) -> UUID {
        let marker = ActiveOperationMarker(
            id: UUID(),
            tool: tool,
            title: title,
            message: message,
            startedAt: Date(),
            affectedCount: affectedCount,
            backupPath: backupPath
        )
        activeOperation = marker
        save(marker)
        return marker.id
    }

    func finish(_ id: UUID?) {
        guard let id else { return }
        guard activeOperation?.id == id else { return }
        clear()
    }

    func clear() {
        activeOperation = nil
        try? FileManager.default.removeItem(at: markerURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: markerURL),
              let marker = try? JSONDecoder.syncrosaRecovery.decode(ActiveOperationMarker.self, from: data) else {
            activeOperation = nil
            return
        }
        activeOperation = marker
    }

    private func save(_ marker: ActiveOperationMarker) {
        do {
            try SyncrosaStorage.ensureDirectory(SyncrosaStorage.applicationSupportDirectory)
            let data = try JSONEncoder.syncrosaRecovery.encode(marker)
            try data.write(to: markerURL, options: .atomic)
        } catch {
            print("Operation recovery marker write failed: \(error)")
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
