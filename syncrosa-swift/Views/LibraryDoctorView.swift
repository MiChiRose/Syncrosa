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
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    Label("Library Doctor", systemImage: "stethoscope")
                        .font(.title2)
                        .fontWeight(.bold)
                    Spacer()
                    Picker("", selection: $selectedTool) {
                        ForEach(0..<toolNames.count, id: \.self) { index in
                            Text(toolNames[index]).tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 430)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(descriptionText)
                        .foregroundColor(.secondary)
                    HStack(spacing: 12) {
                        Button(action: runSelectedTool) {
                            if isRunning {
                                ProgressView().controlSize(.small)
                            } else {
                                Label(buttonTitle, systemImage: selectedTool == 0 ? "arrow.uturn.backward.circle" : "checklist")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRunning)
                        ProgressView(value: progress, total: progressMax)
                            .opacity(isRunning || progress > 0 ? 1 : 0.35)
                    }
                }
                .padding()
                .background(SyncrosaTheme.panelBackground)
                .cornerRadius(10)

                VStack(alignment: .leading, spacing: 8) {
                    Text("LOG")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(logs.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.green)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 280)
                    .background(Color.black)
                    .cornerRadius(8)
                }
            }
            .padding(30)
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
        logs.removeAll()
        progress = 0
        progressMax = 1
        isRunning = true
        appendLog("[start] \(toolNames[selectedTool])")

        DispatchQueue.global(qos: .userInitiated).async {
            switch selectedTool {
            case 0:
                runCoverRestore()
            case 1:
                runCoverAudit()
            default:
                runLibraryAudit()
            }
        }
    }

    private func runCoverRestore() {
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
        finish(status: "OK", message: "Restored \(restored) covers.", affectedCount: restored)
    }

    private func runCoverAudit() {
        let service = CoversOptimizerService.shared
        let coveredTracks = service.getTracksWithCovers()
        let backupCount = service.backupManifestCount()
        DispatchQueue.main.async {
            progress = 1
            progressMax = 1
            appendLog("tracks with embedded covers: \(coveredTracks.count)")
            appendLog("cover backup manifest entries: \(backupCount)")
        }
        finish(status: "OK", message: "Cover audit complete. Tracks with covers: \(coveredTracks.count). Backup entries: \(backupCount).", affectedCount: coveredTracks.count)
    }

    private func runLibraryAudit() {
        guard let count = MusicService.shared.getLibraryTrackCount() else {
            finish(status: "WARN", message: "Music library could not be read.", affectedCount: 0)
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
        finish(status: "OK", message: "Library audit complete. Count: \(count). Readable rows: \(sample.count).", affectedCount: sample.count)
    }

    private func finish(status: String, message: String, affectedCount: Int) {
        DispatchQueue.main.async {
            appendLog("[finish] \(message)")
            isRunning = false
            OperationHistoryService.shared.record(
                tool: "Library Doctor",
                title: toolNames[selectedTool],
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
