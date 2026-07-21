import SwiftUI
import AppKit

enum InfoEraserStatus {
    case pending
    case processing
    case done
    case skipped
    case error
}

struct InfoEraserFileItem: Identifiable {
    let id = UUID()
    let url: URL
    var status: InfoEraserStatus = .pending
}

private enum InfoEraserSafetyAction {
    case backup
    case erase
    case restore
}

struct InfoEraserView: View {
    @ObservedObject var lang = LocalizationService.shared
    @State private var folderPath = ""
    @State private var fileItems: [InfoEraserFileItem] = []
    @State private var isProcessing = false
    @State private var progressValue = 0.0
    @State private var progressTotal = 1.0
    @State private var activeNotification: NotificationMessage? = nil
    @State private var logLines: [String] = []
    @State private var showHelp = false
    @State private var safetyPreview: SafetyPreviewRequest? = nil
    @State private var pendingSafetyAction: InfoEraserSafetyAction? = nil

    var body: some View {
        SyncrosaPage {
            SyncrosaPageHeader(
                title: lang.t("info_eraser"),
                systemImage: "eraser.line.dashed",
                subtitle: lang.selectedLanguage == "ru" ? "Деструктивная очистка локальных файлов с backup/restore." : "Destructive local-file cleanup with backup and restore.",
                helpAction: { showHelp = true }
            )

            SyncrosaWarningPanel(
                title: lang.selectedLanguage == "ru" ? "ВНИМАНИЕ" : "WARNING",
                message: lang.selectedLanguage == "ru" ? "Эта вкладка окончательно удаляет встроенную информацию и обложки из локальных музыкальных файлов. Работайте только с копией папки или сначала сохраните резервную копию." : "This tab permanently removes embedded song information and artwork from local music files. Work on a copied folder or create a backup first."
            )

                VStack(alignment: .leading, spacing: 14) {
                    SyncrosaAdaptiveRow(spacing: 12) {
                        TextField(lang.selectedLanguage == "ru" ? "Папка не выбрана" : "No folder selected", text: $folderPath)
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)
                        Button(action: selectFolder) {
                            Label(lang.selectedLanguage == "ru" ? "Выбрать папку" : "Select Folder", systemImage: "folder")
                        }
                        .buttonStyle(SyncrosaSecondaryButtonStyle())
                        .disabled(isProcessing)
                    }

                    SyncrosaAdaptiveRow(spacing: 10) {
                        Button(action: { presentSafetyPreview(.backup) }) {
                            Label(lang.selectedLanguage == "ru" ? "Сохранить исходную инфо" : "Backup Original Info", systemImage: "externaldrive.badge.plus")
                        }
                        .buttonStyle(SyncrosaSecondaryButtonStyle())
                        .disabled(fileItems.isEmpty || isProcessing)

                        Button(action: { presentSafetyPreview(.erase) }) {
                            Label(lang.selectedLanguage == "ru" ? "Очистить" : "Erase Info", systemImage: "eraser")
                        }
                        .buttonStyle(SyncrosaDestructiveButtonStyle())
                        .disabled(fileItems.isEmpty || isProcessing)

                        Button(action: { presentSafetyPreview(.restore) }) {
                            Label(lang.selectedLanguage == "ru" ? "Восстановить" : "Restore Info", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(SyncrosaSecondaryButtonStyle())
                        .disabled(!canRestoreOriginalInfo || isProcessing)
                    }

                    if !folderPath.isEmpty && !canRestoreOriginalInfo && !isProcessing {
                        SyncrosaDisabledReason(text: lang.selectedLanguage == "ru"
                            ? "Восстановление станет доступно после создания совместимого backup для этой папки."
                            : "Restore becomes available after a compatible backup is created for this folder.")
                    }

                    ProgressView(value: progressValue, total: progressTotal)
                        .opacity(isProcessing || progressValue > 0 ? 1 : 0.35)
                }
                .syncrosaCard()

                VStack(alignment: .leading, spacing: 10) {
                    SyncrosaSectionLabel(text: fileSummary, systemImage: "doc.text.magnifyingglass")

                    if fileItems.isEmpty {
                        SyncrosaEmptyState(
                            systemImage: "music.note.list",
                            title: lang.selectedLanguage == "ru" ? "Выберите папку с музыкой." : "Select a folder with music files."
                        )
                    } else {
                        ForEach(fileItems) { item in
                            HStack(spacing: 10) {
                                Text(item.url.lastPathComponent)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                statusIcon(item.status)
                            }
                            Divider()
                        }
                    }
                }
                .syncrosaCard()

            SyncrosaLogConsole(title: lang.t("log").uppercased(), lines: logLines, minHeight: 150, prefixLines: true)
        }
        .notification(message: $activeNotification)
        .sheet(isPresented: $showHelp) {
            helpSheet
        }
        .sheet(item: $safetyPreview) { request in
            SafetyPreviewSheet(
                request: request,
                cancel: {
                    safetyPreview = nil
                    pendingSafetyAction = nil
                },
                confirm: {
                    let action = pendingSafetyAction
                    safetyPreview = nil
                    pendingSafetyAction = nil
                    runSafetyAction(action)
                }
            )
        }
    }

    private var fileSummary: String {
        let supportedCount = fileItems.filter { isSupportedInfoExtension($0.url.pathExtension.lowercased()) }.count
        return lang.selectedLanguage == "ru" ? "Найдено файлов: \(fileItems.count). Поддерживается очистка MP3, M4A, MP4, AAC, ALAC: \(supportedCount)." : "Files found: \(fileItems.count). Supported for erasing MP3, M4A, MP4, AAC, ALAC: \(supportedCount)."
    }

    private var canRestoreOriginalInfo: Bool {
        guard !folderPath.isEmpty else { return false }
        return InfoEraserService.shared.hasRestoreBackup(for: URL(fileURLWithPath: folderPath))
    }

    private var helpSheet: some View {
        SyncrosaHelpSheet(
            title: lang.t("info_eraser"),
            summary: lang.selectedLanguage == "ru"
                ? "Безвозвратно удаляет встроенные теги и обложки из поддерживаемых файлов в выбранной локальной папке."
                : "Permanently removes embedded tags and artwork from supported files in a selected local folder.",
            steps: lang.selectedLanguage == "ru" ? [
                "Выберите папку и проверьте список найденных файлов.",
                "Сначала сохраните исходную информацию: будет создан локальный backup и его копия в Application Support.",
                "Нажмите «Очистить» и подтвердите операцию.",
                "Для возврата данных выберите ту же папку и нажмите «Восстановить»."
            ] : [
                "Select a folder and review the detected files.",
                "Back up the original information first; Syncrosa creates a local backup and an Application Support copy.",
                "Choose Erase and confirm the operation.",
                "To recover metadata, select the same folder and choose Restore."
            ],
            notes: lang.selectedLanguage == "ru" ? [
                "Изменяется только выбранная папка и её подпапки; медиатека Music напрямую не редактируется.",
                "Очистка поддерживается для MP3, M4A, MP4, AAC и ALAC без перекодирования аудио.",
                "Восстановление возможно только при наличии созданного Syncrosa backup."
            ] : [
                "Only the selected folder and subfolders are changed; the Music library is not edited directly.",
                "Erasing supports MP3, M4A, MP4, AAC, and ALAC without audio transcoding.",
                "Restore requires a backup previously created by Syncrosa."
            ],
            dismiss: { showHelp = false }
        )
    }

    private func isSupportedInfoExtension(_ ext: String) -> Bool {
        ["mp3", "m4a", "mp4", "aac", "alac"].contains(ext)
    }

    @ViewBuilder
    private func statusIcon(_ status: InfoEraserStatus) -> some View {
        switch status {
        case .pending:
            Text(lang.t("waiting").uppercased()).font(.caption2).foregroundColor(.secondary)
        case .processing:
            ProgressView().controlSize(.mini)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .skipped:
            Text(lang.t("skipped").uppercased()).font(.caption2).foregroundColor(.secondary)
        case .error:
            Image(systemName: "xmark.circle.fill").foregroundColor(.red)
        }
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            folderPath = url.path
            let files = InfoEraserService.shared.findMusicFiles(in: url)
            fileItems = files.map { InfoEraserFileItem(url: $0) }
            progressValue = 0
            progressTotal = Double(max(1, files.count))
            logLines.removeAll()
            appendLog("Scanned folder recursively: \(files.count) music files.")
            activeNotification = NotificationMessage(text: fileSummary, isError: files.isEmpty)
        }
    }

    private func presentSafetyPreview(_ action: InfoEraserSafetyAction) {
        guard !folderPath.isEmpty else { return }
        pendingSafetyAction = action

        let supportedCount = fileItems.filter { isSupportedInfoExtension($0.url.pathExtension.lowercased()) }.count
        let backupPath = URL(fileURLWithPath: folderPath)
            .appendingPathComponent(InfoEraserService.shared.backupDirectoryName, isDirectory: true)
            .path
        let details = [
            SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Папка" : "Folder", value: folderPath),
            SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Файлов найдено" : "Files found", value: "\(fileItems.count)"),
            SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Поддерживается" : "Supported", value: "\(supportedCount)"),
            SafetyPreviewDetail(title: "Backup", value: backupPath)
        ]

        switch action {
        case .backup:
            safetyPreview = SafetyPreviewRequest(
                title: lang.selectedLanguage == "ru" ? "Сохранить исходную информацию?" : "Back up original info?",
                message: lang.selectedLanguage == "ru" ? "Syncrosa сохранит теги и обложки поддерживаемых файлов в manifest + sidecar backup перед будущей очисткой." : "Syncrosa will save tags and artwork from supported files into a manifest + sidecar backup before future erasing.",
                details: details,
                confirmTitle: lang.selectedLanguage == "ru" ? "Сохранить" : "Back Up",
                isDestructive: false
            )
        case .erase:
            safetyPreview = SafetyPreviewRequest(
                title: lang.selectedLanguage == "ru" ? "Очистить встроенную информацию?" : "Erase embedded info?",
                message: lang.selectedLanguage == "ru" ? "Syncrosa удалит встроенные теги и обложки из поддерживаемых файлов. Это действие нельзя отменить без backup." : "Syncrosa will remove embedded tags and artwork from supported files. This cannot be undone without a backup.",
                details: details,
                confirmTitle: lang.selectedLanguage == "ru" ? "Очистить" : "Erase",
                isDestructive: true
            )
        case .restore:
            safetyPreview = SafetyPreviewRequest(
                title: lang.selectedLanguage == "ru" ? "Восстановить информацию?" : "Restore original info?",
                message: lang.selectedLanguage == "ru" ? "Syncrosa восстановит теги из найденного backup. Файлы без записи в manifest будут пропущены." : "Syncrosa will restore tags from the found backup. Files without a manifest entry will be skipped.",
                details: details,
                confirmTitle: lang.selectedLanguage == "ru" ? "Восстановить" : "Restore",
                isDestructive: false
            )
        }
    }

    private func runSafetyAction(_ action: InfoEraserSafetyAction?) {
        switch action {
        case .backup:
            backupOriginalInfo()
        case .erase:
            eraseInfo()
        case .restore:
            restoreOriginalInfo()
        case .none:
            break
        }
    }

    private func backupOriginalInfo() {
        runOperation(title: lang.selectedLanguage == "ru" ? "Сохраняю исходную информацию..." : "Backing up original info...") { folder, files, progress in
            let result = try InfoEraserService.shared.backupOriginalInfo(folder: folder, files: files, progress: progress)
            let supportPath = result.appSupportManifestURL?.path ?? ""
            return lang.selectedLanguage == "ru" ? "Backup сохранён: \(result.manifestURL.path). Копия: \(supportPath). Поддерживаемых файлов: \(result.supportedCount)." : "Backup saved: \(result.manifestURL.path). Copy: \(supportPath). Supported files: \(result.supportedCount)."
        }
    }

    private func eraseInfo() {
        runOperation(title: lang.selectedLanguage == "ru" ? "Очищаю информацию..." : "Erasing embedded info...") { _, files, progress in
            let result = try InfoEraserService.shared.eraseInfo(files: files, progress: progress)
            return lang.selectedLanguage == "ru" ? "Очистка завершена. Очищено файлов: \(result.erased). Пропущено/не поддержано: \(result.unsupported)." : "Erase finished. Files stripped: \(result.erased). Unsupported/skipped: \(result.unsupported)."
        }
    }

    private func restoreOriginalInfo() {
        runOperation(title: lang.selectedLanguage == "ru" ? "Восстанавливаю информацию..." : "Restoring original info...") { folder, _, progress in
            let result = try InfoEraserService.shared.restoreInfo(folder: folder, progress: progress)
            return lang.selectedLanguage == "ru" ? "Восстановление завершено. Восстановлено файлов: \(result.restored). Не найдено: \(result.missing)." : "Restore finished. Files restored: \(result.restored). Missing files: \(result.missing)."
        }
    }

    private func runOperation(title: String, worker: @escaping (URL, [URL], @escaping (Int, Int) -> Void) throws -> String) {
        guard !folderPath.isEmpty else { return }
        let folder = URL(fileURLWithPath: folderPath)
        isProcessing = true
        progressValue = 0
        progressTotal = Double(max(1, fileItems.count))
        activeNotification = NotificationMessage(text: title, isError: false)
        logLines.removeAll()
        appendLog(title)
        for index in fileItems.indices {
            fileItems[index].status = .pending
        }

        let files = fileItems.map(\.url)
        let backupPath = folder.appendingPathComponent(InfoEraserService.shared.backupDirectoryName, isDirectory: true).path
        let recoveryID = OperationRecoveryService.shared.begin(
            tool: "Info Eraser",
            title: title,
            message: lang.selectedLanguage == "ru" ? "Операция с локальными музыкальными файлами выполнялась, когда приложение было закрыто или упало." : "A local music file operation was running when the app closed or crashed.",
            affectedCount: files.count,
            backupPath: backupPath
        )
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let message = try worker(folder, files) { current, total in
                    DispatchQueue.main.async {
                        progressValue = Double(current)
                        progressTotal = Double(max(1, total))
                        let completedIndex = current - 1
                        if completedIndex >= fileItems.startIndex && completedIndex < fileItems.endIndex {
                            fileItems[completedIndex].status = .done
                        }
                    }
                }
                DispatchQueue.main.async {
                    OperationRecoveryService.shared.finish(recoveryID)
                    isProcessing = false
                    appendLog(message)
                    activeNotification = NotificationMessage(text: message, isError: false)
                    OperationHistoryService.shared.record(
                        tool: "Info Eraser",
                        title: title,
                        status: "OK",
                        message: message,
                        affectedCount: files.count,
                        backupPath: backupPath
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    OperationRecoveryService.shared.finish(recoveryID)
                    isProcessing = false
                    appendLog("ERROR: \(error.localizedDescription)")
                    activeNotification = NotificationMessage(text: error.localizedDescription, isError: true)
                    OperationHistoryService.shared.record(
                        tool: "Info Eraser",
                        title: title,
                        status: "FAIL",
                        message: error.localizedDescription,
                        affectedCount: files.count,
                        backupPath: backupPath
                    )
                }
            }
        }
    }

    private func appendLog(_ line: String) {
        logLines.append(line)
        if logLines.count > 160 {
            logLines.removeFirst(logLines.count - 160)
        }
    }
}
