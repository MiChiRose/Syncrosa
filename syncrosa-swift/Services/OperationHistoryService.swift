import Foundation

struct OperationHistoryEntry: Identifiable, Codable {
    let id: UUID
    let tool: String
    let title: String
    let status: String
    let message: String
    let createdAt: Date
    let affectedCount: Int
    let backupPath: String?
}

final class OperationHistoryService: ObservableObject {
    static let shared = OperationHistoryService()

    @Published private(set) var entries: [OperationHistoryEntry] = []

    private let queue = DispatchQueue(label: "com.michirose.syncrosa.operation-history")
    private let maxEntries = 250
    private var storedEntries: [OperationHistoryEntry] = []

    private var historyURL: URL {
        SyncrosaStorage.applicationSupportDirectory.appendingPathComponent("operation-history.json")
    }

    private init() {
        load()
    }

    func record(tool: String, title: String, status: String, message: String, affectedCount: Int = 0, backupPath: String? = nil) {
        let entry = OperationHistoryEntry(
            id: UUID(),
            tool: tool,
            title: title,
            status: status,
            message: message,
            createdAt: Date(),
            affectedCount: affectedCount,
            backupPath: backupPath
        )

        queue.async {
            var next = [entry] + self.storedEntries
            if next.count > self.maxEntries {
                next = Array(next.prefix(self.maxEntries))
            }
            self.storedEntries = next
            do {
                try SyncrosaStorage.ensureDirectory(SyncrosaStorage.applicationSupportDirectory)
                let data = try JSONEncoder.syncrosaHistory.encode(next)
                try data.write(to: self.historyURL, options: .atomic)
            } catch {
                print("Operation history write failed: \(error)")
            }

            DispatchQueue.main.async {
                self.entries = next
            }
        }
    }

    func entries(for tool: String) -> [OperationHistoryEntry] {
        if tool == "All" {
            return entries
        }
        return entries.filter { $0.tool == tool }
    }

    func clear() {
        queue.async {
            self.storedEntries = []
            try? FileManager.default.removeItem(at: self.historyURL)
            DispatchQueue.main.async {
                self.entries = []
            }
        }
    }

    private func load() {
        queue.async {
            let decoded: [OperationHistoryEntry]
            if let data = try? Data(contentsOf: self.historyURL),
               let entries = try? JSONDecoder.syncrosaHistory.decode([OperationHistoryEntry].self, from: data) {
                decoded = entries
            } else {
                decoded = []
            }
            self.storedEntries = decoded

            DispatchQueue.main.async {
                self.entries = decoded
            }
        }
    }
}

private extension JSONEncoder {
    static var syncrosaHistory: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var syncrosaHistory: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
