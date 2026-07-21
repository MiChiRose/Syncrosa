import SwiftUI

struct LibraryDoctorView: View {
    @ObservedObject var lang = LocalizationService.shared
    @State private var selectedTool = 0
    @State private var isRunning = false
    @State private var logs: [String] = []
    @State private var progress = 0.0
    @State private var progressMax = 1.0
    @State private var showHelp = false
    @State private var compareFolder: URL? = nil
    @State private var activeNotification: NotificationMessage? = nil

    private var toolNames: [String] {
        if lang.selectedLanguage == "ru" {
            return ["Восстановление обложек", "Аудит обложек", "Аудит медиатеки", "Отчёт для iPod", "Битые треки", "Оценка тегов", "Аудит связей", "Экспорт отчёта"]
        }
        return ["Cover Restore", "Cover Audit", "Library Audit", "iPod Report", "Broken Tracks", "Tag Score", "Link Audit", "Export Report"]
    }

    var body: some View {
        SyncrosaPage {
            SyncrosaPageHeader(
                title: lang.t("library_doctor"),
                systemImage: "stethoscope",
                subtitle: lang.selectedLanguage == "ru" ? "Быстрая диагностика медиатеки и восстановление обложек." : "Quick diagnostics for library health and cover restore tasks.",
                helpAction: { showHelp = true }
            )

                VStack(alignment: .leading, spacing: 12) {
                    SyncrosaGlassMenu(
                        selection: $selectedTool,
                        options: toolNames.indices.map { SyncrosaMenuOption(title: toolNames[$0], value: $0) },
                        minWidth: 260
                    )

                    Text(descriptionText)
                        .foregroundColor(.secondary)

                    if !selectedToolCanRun, let message = disabledReasonText {
                        SyncrosaDisabledReason(text: message)
                    }

                    if selectedTool == 6, let compareFolder {
                        Text(compareFolder.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }

                    SyncrosaAdaptiveRow(spacing: 12) {
                        if selectedTool == 6 {
                            Button(action: chooseCompareFolder) {
                                Label(
                                    compareFolder == nil
                                        ? (lang.selectedLanguage == "ru" ? "Выбрать папку для сравнения" : "Choose Compare Folder")
                                        : (lang.selectedLanguage == "ru" ? "Изменить папку" : "Change Compare Folder"),
                                    systemImage: "folder"
                                )
                            }
                            .buttonStyle(SyncrosaSecondaryButtonStyle())
                            .disabled(isRunning)
                        }

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

            SyncrosaLogConsole(title: lang.t("log").uppercased(), lines: logs, minHeight: 280)
        }
        .notification(message: $activeNotification)
        .sheet(isPresented: $showHelp) {
            helpSheetView
        }
    }

    private var helpSheetView: some View {
        SyncrosaHelpSheet(
            title: lang.t("library_doctor"),
            summary: lang.selectedLanguage == "ru"
                ? "Проверяет здоровье медиатеки Music и создаёт отчёты; изменения выполняются только в режиме восстановления обложек."
                : "Audits Music library health and exports reports; only cover restore changes library content.",
            steps: lang.selectedLanguage == "ru" ? [
                "Выберите тип проверки в меню.",
                "Прочитайте описание и, если требуется, выберите папку для сравнения.",
                "Запустите проверку и дождитесь заполнения журнала.",
                "Для Export Report выберите формат и место сохранения отчёта."
            ] : [
                "Choose an audit type from the menu.",
                "Read its description and select a comparison folder when required.",
                "Run the audit and wait for the log to finish.",
                "For Export Report, choose the report format and save location."
            ],
            notes: lang.selectedLanguage == "ru" ? [
                "Cover Restore требует backup, созданный Covers Optimizer.",
                "iPod Report оценивает совместимость форматов, размеров и имён файлов со старыми устройствами.",
                "Link Audit не удаляет и не переносит файлы."
            ] : [
                "Cover Restore requires a backup created by Covers Optimizer.",
                "iPod Report checks formats, sizes, and filenames for older devices.",
                "Link Audit never deletes or moves files."
            ],
            dismiss: { showHelp = false }
        )
    }

    private var descriptionText: String {
        switch selectedTool {
        case 0:
            return lang.selectedLanguage == "ru" ? "Восстановить обложки из уже созданного backup оптимизатора." : "Restore covers from an existing Covers Optimizer backup."
        case 1:
            return lang.selectedLanguage == "ru" ? "Проверить сколько треков имеет встроенные обложки и сколько backup-файлов найдено." : "Check how many tracks have embedded covers and how many cover backups exist."
        default:
            if selectedTool == 5 {
                return lang.selectedLanguage == "ru" ? "Оценить заполненность тегов: название, артист, альбом, жанр, год, обложка и путь к файлу." : "Score tag completeness: title, artist, album, genre, year, artwork, and linked file path."
            }
            if selectedTool == 6 {
                return lang.selectedLanguage == "ru" ? "Проверить отсутствующие файлы Music и музыку во внешней папке, не привязанную к медиатеке." : "Find missing Music files and outside-folder files not linked in the library."
            }
            if selectedTool == 7 {
                return lang.selectedLanguage == "ru" ? "Сохранить подробный JSON или CSV отчёт по медиатеке." : "Export a detailed JSON or CSV library audit report."
            }
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
            if selectedTool == 5 {
                return lang.selectedLanguage == "ru" ? "Оценить теги" : "Score Tags"
            }
            if selectedTool == 6 {
                return lang.selectedLanguage == "ru" ? "Проверить связи" : "Run Link Audit"
            }
            if selectedTool == 7 {
                return lang.selectedLanguage == "ru" ? "Экспорт отчёта" : "Export Report"
            }
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
            case 5:
                runTagScore(selectedToolIndex: selectedToolIndex)
            case 6:
                runLinkAudit(selectedToolIndex: selectedToolIndex)
            case 7:
                runExportReport(selectedToolIndex: selectedToolIndex)
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

    private func runTagScore(selectedToolIndex: Int) {
        let tracks = LibraryToolkitService.shared.loadTracks { current, total in
            DispatchQueue.main.async {
                progress = Double(current)
                progressMax = Double(max(1, total))
            }
        }
        let average = tracks.isEmpty ? 0 : tracks.map(\.completenessScore).reduce(0, +) / tracks.count
        var fieldCounts: [String: Int] = [:]
        for track in tracks {
            for field in track.missingFields {
                fieldCounts[field, default: 0] += 1
            }
        }
        DispatchQueue.main.async {
            appendLog("tracks scored: \(tracks.count)")
            appendLog("average completeness: \(average)%")
            for (field, count) in fieldCounts.sorted(by: { $0.key < $1.key }) {
                appendLog("missing \(field): \(count)")
            }
            let weak = tracks.sorted { $0.completenessScore < $1.completenessScore }.prefix(25)
            if !weak.isEmpty {
                appendLog("lowest score sample:")
                for track in weak {
                    appendLog("\(track.completenessScore)% - \(track.artist) - \(track.title)")
                }
            }
        }
        let status = average >= 80 ? "OK" : "WARN"
        finish(selectedToolIndex: selectedToolIndex, status: status, message: "Tag score complete. Average completeness: \(average)%.", affectedCount: tracks.count)
    }

    private func runLinkAudit(selectedToolIndex: Int) {
        let service = LibraryToolkitService.shared
        let tracks = service.loadTracks { current, total in
            DispatchQueue.main.async {
                progress = Double(current)
                progressMax = Double(max(1, total))
            }
        }
        let missing = tracks.filter { !$0.fileExists }
        let unlinked = compareFolder.map { service.scanUnlinkedFiles(in: $0, linkedTracks: tracks) } ?? []
        DispatchQueue.main.async {
            appendLog("tracks scanned: \(tracks.count)")
            appendLog("missing Music file links: \(missing.count)")
            if let compareFolder {
                appendLog("compare folder: \(compareFolder.path)")
                appendLog("folder files not linked in Music: \(unlinked.count)")
            } else {
                appendLog("no compare folder selected; only Music links were checked")
            }
            for track in missing.prefix(40) {
                appendLog("missing: \(track.artist) - \(track.title)")
            }
            for file in unlinked.prefix(40) {
                appendLog("unlinked: \(file.lastPathComponent)")
            }
        }
        let warningCount = missing.count + unlinked.count
        finish(selectedToolIndex: selectedToolIndex, status: warningCount == 0 ? "OK" : "WARN", message: "Link audit complete. Warnings: \(warningCount).", affectedCount: warningCount)
    }

    private func runExportReport(selectedToolIndex: Int) {
        DispatchQueue.main.async {
            isRunning = false
            presentReportSavePanel(selectedToolIndex: selectedToolIndex)
        }
    }

    private func chooseCompareFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            compareFolder = panel.url
        }
    }

    private func presentReportSavePanel(selectedToolIndex: Int) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json, .commaSeparatedText]
        panel.nameFieldStringValue = "Syncrosa-Library-Doctor-Report.json"
        guard panel.runModal() == .OK, let url = panel.url else {
            appendLog("[cancel] report export cancelled")
            return
        }

        logs.removeAll()
        progress = 0
        progressMax = 1
        isRunning = true
        appendLog("[start] export report")

        DispatchQueue.global(qos: .userInitiated).async {
            let service = LibraryToolkitService.shared
            let tracks = service.loadTracks { current, total in
                DispatchQueue.main.async {
                    progress = Double(current)
                    progressMax = Double(max(1, total))
                }
            }
            guard let preset = LibraryToolkitPreset.defaults.first else {
                DispatchQueue.main.async {
                    appendLog("[error] no audit preset is available")
                    isRunning = false
                }
                return
            }
            let previews = service.makePreviews(tracks: tracks, preset: preset, renameTemplate: preset.renameTemplate)
            let unlinked = compareFolder.map { service.scanUnlinkedFiles(in: $0, linkedTracks: tracks) } ?? []

            do {
                if url.pathExtension.lowercased() == "csv" {
                    try service.writeCSVReport(tracks: tracks, to: url)
                } else {
                    let report = service.createReport(tracks: tracks, previews: previews, unlinkedFiles: unlinked, preset: preset)
                    try service.writeReport(report, to: url)
                }
                DispatchQueue.main.async {
                    appendLog("report saved: \(url.path)")
                    activeNotification = NotificationMessage(text: "Library report exported.", isError: false)
                    finish(selectedToolIndex: selectedToolIndex, status: "OK", message: "Library report exported.", affectedCount: tracks.count)
                }
            } catch {
                DispatchQueue.main.async {
                    appendLog("report export failed: \(error.localizedDescription)")
                    activeNotification = NotificationMessage(text: error.localizedDescription, isError: true)
                    finish(selectedToolIndex: selectedToolIndex, status: "FAIL", message: "Report export failed.", affectedCount: 0)
                }
            }
        }
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
