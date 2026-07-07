import SwiftUI

struct LibraryDoctorView: View {
    @ObservedObject var lang = LocalizationService.shared
    @State private var selectedTool = 0
    @State private var isRunning = false
    @State private var logs: [String] = []
    @State private var progress = 0.0
    @State private var progressMax = 1.0
    @State private var showHelp = false

    private let toolNames = ["Cover Restore", "Cover Audit", "Library Audit", "iPod Report", "Broken Tracks"]

    var body: some View {
        SyncrosaPage {
            SyncrosaPageHeader(
                title: "Library Doctor",
                systemImage: "stethoscope",
                subtitle: lang.selectedLanguage == "ru" ? "Быстрая диагностика медиатеки и восстановление обложек." : "Quick diagnostics for library health and cover restore tasks.",
                helpAction: { showHelp = true }
            )

                VStack(alignment: .leading, spacing: 12) {
                    SyncrosaGlassSegmentedPicker(
                        selection: $selectedTool,
                        options: toolNames.indices.map { SyncrosaMenuOption(title: toolNames[$0], value: $0) },
                        minSegmentWidth: 112
                    )

                    Text(descriptionText)
                        .foregroundColor(.secondary)

                    if !selectedToolCanRun, let message = disabledReasonText {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    SyncrosaAdaptiveRow(spacing: 12) {
                        Button(action: runSelectedTool) {
                            if isRunning {
                                ProgressView().controlSize(.small)
                            } else {
                                Label(buttonTitle, systemImage: selectedTool == 0 ? "arrow.uturn.backward.circle" : "checklist")
                            }
                        }
                        .buttonStyle(SyncrosaPrimaryButtonStyle())
                        .disabled(isRunning || !selectedToolCanRun)
                        ProgressView(value: progress, total: progressMax)
                            .opacity(isRunning || progress > 0 ? 1 : 0.35)
                    }
                }
                .syncrosaCard()

            SyncrosaLogConsole(title: "LOG", lines: logs, minHeight: 280)
        }
        .sheet(isPresented: $showHelp) {
            helpSheetView
        }
    }

    private var helpSheetView: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(lang.selectedLanguage == "ru" ? "Инструкция: Library Doctor" : "Help: Library Doctor")
                    .font(.headline)
                Spacer()
                Button(lang.selectedLanguage == "ru" ? "Закрыть" : "Close") {
                    showHelp = false
                }
                .buttonStyle(SyncrosaSecondaryButtonStyle())
            }

            Divider()

            ScrollView {
                Text(lang.selectedLanguage == "ru"
                     ? "Library Doctor проверяет состояние медиатеки Music без изменения треков, кроме режима восстановления обложек из уже созданного backup.\n\nCover Restore восстанавливает обложки из backup Covers Optimizer. Cover Audit показывает количество треков с обложками. Library Audit проверяет читаемость медиатеки. iPod Report ищет форматы, длинные имена и крупные файлы, которые могут мешать старым iPod/автомагнитолам. Broken Tracks ищет отсутствующие или нечитаемые файлы."
                     : "Library Doctor checks Music library health without changing tracks, except for restoring covers from an existing backup.\n\nCover Restore restores artwork from a Covers Optimizer backup. Cover Audit counts tracks with embedded artwork. Library Audit checks whether the library can be read. iPod Report flags formats, long filenames, and large files that may bother older iPods/car stereos. Broken Tracks finds missing or unreadable files.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 500, minHeight: 280)
        }
        .padding()
    }

    private var descriptionText: String {
        switch selectedTool {
        case 0:
            return lang.selectedLanguage == "ru" ? "Восстановить обложки из уже созданного backup оптимизатора." : "Restore covers from an existing Covers Optimizer backup."
        case 1:
            return lang.selectedLanguage == "ru" ? "Проверить сколько треков имеет встроенные обложки и сколько backup-файлов найдено." : "Check how many tracks have embedded covers and how many cover backups exist."
        default:
            if selectedTool == 3 {
                return lang.selectedLanguage == "ru" ? "Проверить форматы, размеры и имена файлов для старых iPod/автомагнитол." : "Check formats, sizes, and filenames for older iPods and car stereos."
            }
            if selectedTool == 4 {
                return lang.selectedLanguage == "ru" ? "Найти треки Music, у которых файл на диске отсутствует или путь не читается." : "Find Music tracks whose disk file is missing or unreadable."
            }
            return lang.selectedLanguage == "ru" ? "Быстрый аудит медиатеки Music: доступность, количество треков и читаемость чанков." : "Quick Music library audit: availability, track count, and chunk readability."
        }
    }

    private var selectedToolCanRun: Bool {
        if selectedTool == 0 {
            return CoversOptimizerService.shared.backupManifestCount() > 0
        }
        return true
    }

    private var disabledReasonText: String? {
        guard selectedTool == 0 else { return nil }
        return lang.selectedLanguage == "ru"
            ? "Сначала создайте backup обложек в Covers Optimizer."
            : "Create a cover backup in Covers Optimizer first."
    }

    private var buttonTitle: String {
        switch selectedTool {
        case 0:
            return lang.selectedLanguage == "ru" ? "Восстановить обложки" : "Restore Covers"
        case 1:
            return lang.selectedLanguage == "ru" ? "Проверить обложки" : "Audit Covers"
        default:
            if selectedTool == 3 {
                return lang.selectedLanguage == "ru" ? "iPod отчёт" : "Run iPod Report"
            }
            if selectedTool == 4 {
                return lang.selectedLanguage == "ru" ? "Найти битые треки" : "Find Broken Tracks"
            }
            return lang.selectedLanguage == "ru" ? "Проверить медиатеку" : "Audit Library"
        }
    }

    private func runSelectedTool() {
        guard selectedToolCanRun else { return }
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
            case 3:
                runIPodReport(selectedToolIndex: selectedToolIndex)
            case 4:
                runBrokenTracks(selectedToolIndex: selectedToolIndex)
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

    private func runIPodReport(selectedToolIndex: Int) {
        let references = MusicService.shared.getLibraryFileTrackReferences { current, total in
            DispatchQueue.main.async {
                progress = Double(current)
                progressMax = Double(max(1, total))
            }
        }
        let supported = Set(["mp3", "m4a", "mp4", "aac", "wav", "aiff", "aif"])
        var unsupported = 0
        var missing = 0
        var longNames = 0
        var hugeFiles = 0
        var totalBytes: Int64 = 0
        let fileManager = FileManager.default

        for track in references {
            totalBytes += track.size
            let ext = URL(fileURLWithPath: track.path).pathExtension.lowercased()
            if track.path.isEmpty || !fileManager.fileExists(atPath: track.path) || !fileManager.isReadableFile(atPath: track.path) {
                missing += 1
            }
            if !ext.isEmpty && !supported.contains(ext) {
                unsupported += 1
                DispatchQueue.main.async { appendLog("format warning: \(track.artist) - \(track.name) [\(ext.uppercased())]") }
            }
            if URL(fileURLWithPath: track.path).lastPathComponent.count > 80 {
                longNames += 1
            }
            if track.size > 100 * 1024 * 1024 {
                hugeFiles += 1
            }
        }

        let size = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        DispatchQueue.main.async {
            appendLog("file tracks scanned: \(references.count)")
            appendLog("total local size: \(size)")
            appendLog("unsupported format warnings: \(unsupported)")
            appendLog("missing/unreadable files: \(missing)")
            appendLog("long filenames (>80 chars): \(longNames)")
            appendLog("large files (>100 MB): \(hugeFiles)")
        }
        let status = (unsupported + missing + longNames + hugeFiles) > 0 ? "WARN" : "OK"
        let message = "iPod report complete. Scanned: \(references.count). Warnings: \(unsupported + missing + longNames + hugeFiles)."
        finish(selectedToolIndex: selectedToolIndex, status: status, message: message, affectedCount: unsupported + missing + longNames + hugeFiles)
    }

    private func runBrokenTracks(selectedToolIndex: Int) {
        let references = MusicService.shared.getLibraryFileTrackReferences { current, total in
            DispatchQueue.main.async {
                progress = Double(current)
                progressMax = Double(max(1, total))
            }
        }
        let fileManager = FileManager.default
        let broken = references.filter { ref in
            ref.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !fileManager.fileExists(atPath: ref.path) ||
            !fileManager.isReadableFile(atPath: ref.path)
        }
        DispatchQueue.main.async {
            appendLog("file tracks scanned: \(references.count)")
            if broken.isEmpty {
                appendLog("no missing file references found")
            } else {
                appendLog("missing/unreadable file references: \(broken.count)")
                for track in broken.prefix(80) {
                    appendLog("missing: \(track.artist) - \(track.name)")
                }
                if broken.count > 80 {
                    appendLog("...and \(broken.count - 80) more")
                }
            }
        }
        let status = broken.isEmpty ? "OK" : "WARN"
        let message = broken.isEmpty ? "Broken tracks scan complete. No missing files found." : "Broken tracks scan complete. Missing files: \(broken.count)."
        finish(selectedToolIndex: selectedToolIndex, status: status, message: message, affectedCount: broken.count)
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
