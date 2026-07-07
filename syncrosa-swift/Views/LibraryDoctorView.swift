import SwiftUI

struct LibraryDoctorView: View {
    @ObservedObject var lang = LocalizationService.shared
    @State private var selectedTool = 0
    @State private var isRunning = false
    @State private var logs: [String] = []
    @State private var progress = 0.0
    @State private var progressMax = 1.0

    private let toolNames = ["Cover Restore", "Cover Audit", "Library Audit"]

    var body: some View {
        SyncrosaPage {
            SyncrosaPageHeader(
                title: "Library Doctor",
                systemImage: "stethoscope",
                subtitle: lang.selectedLanguage == "ru" ? "Быстрая диагностика медиатеки и восстановление обложек." : "Quick diagnostics for library health and cover restore tasks."
            )

                VStack(alignment: .leading, spacing: 12) {
                    SyncrosaGlassSegmentedPicker(
                        selection: $selectedTool,
                        options: toolNames.indices.map { SyncrosaMenuOption(title: toolNames[$0], value: $0) },
                        minSegmentWidth: 112
                    )

                    Text(descriptionText)
                        .foregroundColor(.secondary)
                    SyncrosaAdaptiveRow(spacing: 12) {
                        Button(action: runSelectedTool) {
                            if isRunning {
                                ProgressView().controlSize(.small)
                            } else {
                                Label(buttonTitle, systemImage: selectedTool == 0 ? "arrow.uturn.backward.circle" : "checklist")
                            }
                        }
                        .buttonStyle(SyncrosaPrimaryButtonStyle())
                        .disabled(isRunning)
                        ProgressView(value: progress, total: progressMax)
                            .opacity(isRunning || progress > 0 ? 1 : 0.35)
                    }
                }
                .syncrosaCard()

            SyncrosaLogConsole(title: "LOG", lines: logs, minHeight: 280)
        }
    }

    private var descriptionText: String {
        switch selectedTool {
        case 0:
            return lang.selectedLanguage == "ru" ? "Восстановить обложки из уже созданного backup оптимизатора." : "Restore covers from an existing Covers Optimizer backup."
        case 1:
            return lang.selectedLanguage == "ru" ? "Проверить сколько треков имеет встроенные обложки и сколько backup-файлов найдено." : "Check how many tracks have embedded covers and how many cover backups exist."
        default:
            return lang.selectedLanguage == "ru" ? "Быстрый аудит медиатеки Music: доступность, количество треков и читаемость чанков." : "Quick Music library audit: availability, track count, and chunk readability."
        }
    }

    private var buttonTitle: String {
        switch selectedTool {
        case 0:
            return lang.selectedLanguage == "ru" ? "Восстановить обложки" : "Restore Covers"
        case 1:
            return lang.selectedLanguage == "ru" ? "Проверить обложки" : "Audit Covers"
        default:
            return lang.selectedLanguage == "ru" ? "Проверить медиатеку" : "Audit Library"
        }
    }

    private func runSelectedTool() {
        let selectedToolIndex = selectedTool
        logs.removeAll()
        progress = 0
        progressMax = 1
        isRunning = true
        appendLog("[start] \(toolNames[selectedToolIndex])")

        DispatchQueue.global(qos: .userInitiated).async {
            switch selectedToolIndex {
            case 0:
                runCoverRestore(selectedToolIndex: selectedToolIndex)
            case 1:
                runCoverAudit(selectedToolIndex: selectedToolIndex)
            default:
                runLibraryAudit(selectedToolIndex: selectedToolIndex)
            }
        }
    }

    private func runCoverRestore(selectedToolIndex: Int) {
        let service = CoversOptimizerService.shared
        let tracks = service.backupManifestEntries()
        DispatchQueue.main.async {
            progressMax = Double(max(1, tracks.count))
            if tracks.isEmpty {
                appendLog("no cover backup manifest entries found")
            }
        }
        var restored = 0
        for (index, track) in tracks.enumerated() {
            if service.restoreCover(pid: track.pid) {
                restored += 1
            }
            DispatchQueue.main.async {
                progress = Double(index + 1)
                appendLog("restore \(index + 1)/\(tracks.count): \(track.artist) - \(track.title)")
            }
        }
        finish(selectedToolIndex: selectedToolIndex, status: "OK", message: "Restored \(restored) covers.", affectedCount: restored)
    }

    private func runCoverAudit(selectedToolIndex: Int) {
        let service = CoversOptimizerService.shared
        let coveredTracks = service.getTracksWithCovers()
        let backupCount = service.backupManifestCount()
        DispatchQueue.main.async {
            progress = 1
            progressMax = 1
            appendLog("tracks with embedded covers: \(coveredTracks.count)")
            appendLog("cover backup manifest entries: \(backupCount)")
        }
        finish(selectedToolIndex: selectedToolIndex, status: "OK", message: "Cover audit complete. Tracks with covers: \(coveredTracks.count). Backup entries: \(backupCount).", affectedCount: coveredTracks.count)
    }

    private func runLibraryAudit(selectedToolIndex: Int) {
        guard let count = MusicService.shared.getLibraryTrackCount() else {
            finish(selectedToolIndex: selectedToolIndex, status: "WARN", message: "Music library could not be read.", affectedCount: 0)
            return
        }
        DispatchQueue.main.async {
            appendLog("Music library track count: \(count)")
        }
        let sample = MusicService.shared.getAllTracks { current, total in
            DispatchQueue.main.async {
                progress = Double(current)
                progressMax = Double(max(1, total))
            }
        }
        DispatchQueue.main.async {
            appendLog("readable track rows: \(sample.count)")
        }
        finish(selectedToolIndex: selectedToolIndex, status: "OK", message: "Library audit complete. Count: \(count). Readable rows: \(sample.count).", affectedCount: sample.count)
    }

    private func finish(selectedToolIndex: Int, status: String, message: String, affectedCount: Int) {
        DispatchQueue.main.async {
            appendLog("[finish] \(message)")
            isRunning = false
            OperationHistoryService.shared.record(
                tool: "Library Doctor",
                title: toolNames[selectedToolIndex],
                status: status,
                message: message,
                affectedCount: affectedCount
            )
        }
    }

    private func appendLog(_ line: String) {
        logs.append("> \(line)")
        if logs.count > 300 {
            logs.removeFirst(logs.count - 300)
        }
    }
}
