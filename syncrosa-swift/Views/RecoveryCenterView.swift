import AppKit
import SwiftUI

struct RecoveryCenterView: View {
    @ObservedObject var lang = LocalizationService.shared
    @ObservedObject private var recovery = OperationRecoveryService.shared
    @ObservedObject private var history = OperationHistoryService.shared
    @State private var showHistory = false
    @State private var showHelp = false
    @State private var undoPackages: [LibraryToolkitUndoPackage] = []
    @State private var selectedUndoID: UUID? = nil
    @State private var safetyPreview: SafetyPreviewRequest? = nil
    @State private var pendingUndoPackage: LibraryToolkitUndoPackage? = nil
    @State private var activeNotification: NotificationMessage? = nil
    @State private var usbJobs: [USBExportJobSummary] = []
    @State private var usbWarnings: [String] = []
    @State private var isResumingUSB = false
    @State private var usbProgressText = ""
    @State private var sourceAccessURL: URL?
    @State private var pendingRemoval: RecoveryRecordRemoval?
    @State private var showRemovalConfirmation = false

    var body: some View {
        SyncrosaPage {
            SyncrosaPageHeader(
                title: lang.selectedLanguage == "ru" ? "Центр восстановления" : "Recovery Center",
                systemImage: "cross.case",
                subtitle: lang.selectedLanguage == "ru" ? "Backup-папки, прерванные операции и история действий." : "Backup folders, interrupted operations, and operation history.",
                helpAction: { showHelp = true }
            ) {
                Button(action: { showHistory = true }) {
                    Label(lang.selectedLanguage == "ru" ? "История" : "History", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(SyncrosaSecondaryButtonStyle())
            }

            interruptedOperationCard
            usbRecoveryCard
            undoPackagesCard

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                locationCard(
                    title: lang.selectedLanguage == "ru" ? "Все backup" : "All Backups",
                    path: SyncrosaStorage.backupsDirectory.path,
                    icon: "externaldrive.badge.plus"
                )
                locationCard(
                    title: "Album Covers",
                    path: SyncrosaStorage.backupsDirectory.appendingPathComponent("AlbumCovers", isDirectory: true).path,
                    icon: "photo.stack"
                )
                locationCard(
                    title: "Info Eraser",
                    path: SyncrosaStorage.backupsDirectory.appendingPathComponent("InfoEraser", isDirectory: true).path,
                    icon: "eraser.line.dashed"
                )
                locationCard(
                    title: lang.selectedLanguage == "ru" ? "Данные Syncrosa" : "Syncrosa Data",
                    path: SyncrosaStorage.applicationSupportDirectory.path,
                    icon: "folder.badge.gearshape"
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                SyncrosaSectionLabel(text: lang.selectedLanguage == "ru" ? "Последние операции" : "Recent Operations", systemImage: "list.bullet.rectangle")

                if history.entries.isEmpty {
                    SyncrosaEmptyState(
                        systemImage: "clock",
                        title: lang.selectedLanguage == "ru" ? "История пока пустая." : "No history yet.",
                        message: lang.selectedLanguage == "ru" ? "После первых операций здесь появятся короткие записи." : "Short records will appear here after operations finish."
                    )
                } else {
                    ForEach(history.entries.prefix(6)) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.title)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Spacer()
                                SyncrosaStatusBadge(text: entry.status, color: entry.status == "OK" ? SyncrosaTheme.success : SyncrosaTheme.caution)
                            }
                            Text("\(entry.tool) · \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let backupPath = entry.backupPath, !backupPath.isEmpty {
                                Text(backupPath)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
            }
            .syncrosaCard()
        }
        .onAppear {
            refreshRecoveryData()
        }
        .onReceive(NotificationCenter.default.publisher(for: PlaylistExportService.jobsDidChangeNotification)) { _ in
            reloadUSBJobs()
        }
        .alert(lang.selectedLanguage == "ru" ? "Убрать запись восстановления?" : "Remove recovery record?", isPresented: $showRemovalConfirmation) {
            Button(lang.t("cancel"), role: .cancel) { pendingRemoval = nil }
            Button(lang.selectedLanguage == "ru" ? "Убрать запись" : "Remove Record", role: .destructive) {
                removePendingRecord()
            }
        } message: {
            Text(lang.selectedLanguage == "ru"
                 ? "Будет удалена только выбранная запись. Музыка, готовые копии на USB и резервные копии сохранятся."
                 : "Only the selected record is removed. Music, completed USB copies and backups are kept.")
        }
        .notification(message: $activeNotification)
        .sheet(isPresented: $showHistory) {
            OperationHistoryView()
        }
        .sheet(isPresented: $showHelp) {
            helpSheetView
        }
        .sheet(item: $safetyPreview) { request in
            SafetyPreviewSheet(
                request: request,
                cancel: {
                    pendingUndoPackage = nil
                    safetyPreview = nil
                },
                confirm: {
                    let package = pendingUndoPackage
                    pendingUndoPackage = nil
                    safetyPreview = nil
                    restoreUndoPackage(package)
                }
            )
        }
    }

    private var helpSheetView: some View {
        SyncrosaHelpSheet(
            title: lang.t("recovery_center"),
            summary: lang.selectedLanguage == "ru"
                ? "Показывает незавершённые операции, сохранённые backup и доступные пакеты отмены."
                : "Shows interrupted operations, stored backups, and available undo packages.",
            steps: lang.selectedLanguage == "ru" ? [
                "Проверьте блок прерванной операции после неожиданного закрытия приложения.",
                "Откройте историю, чтобы увидеть завершённые действия и число затронутых файлов.",
                "Для USB-задачи подключите тот же накопитель, нажмите «Продолжить» и выберите его заново.",
                "Для других изменений выберите доступный пакет отмены или покажите резервную копию."
            ] : [
                "Check the interrupted-operation card after an unexpected app exit.",
                "Open history to review completed actions and affected file counts.",
                "For a USB task, reconnect the same drive, choose Resume and select the drive again.",
                "For other changes, choose an available undo package or show the backup."
            ],
            notes: lang.selectedLanguage == "ru" ? [
                "Маркер прерванной операции сам по себе ничего не откатывает.",
                "Не удаляйте backup, пока не убедитесь, что результат операции правильный."
            ] : [
                "An interrupted-operation marker does not roll anything back by itself.",
                "Keep backups until you have verified the operation result."
            ],
            dismiss: { showHelp = false }
        )
    }

    private var interruptedOperationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SyncrosaSectionLabel(text: lang.selectedLanguage == "ru" ? "Прерванные операции" : "Interrupted Operations", systemImage: "bolt.trianglebadge.exclamationmark")
                Spacer()
                Button(lang.selectedLanguage == "ru" ? "Обновить" : "Refresh", action: refreshRecoveryData)
                    .buttonStyle(SyncrosaSecondaryButtonStyle())
            }
            ForEach(recovery.persistenceWarnings, id: \.self) { warning in
                Text(warning).font(.caption).foregroundStyle(SyncrosaTheme.caution)
            }
            if recovery.interruptedOperations.isEmpty {
                SyncrosaEmptyState(
                    systemImage: "checkmark.shield",
                    title: lang.selectedLanguage == "ru" ? "Нет прерванных операций." : "No interrupted operations.",
                    message: lang.selectedLanguage == "ru"
                        ? "Незавершённые задачи сохраняются отдельно и остаются здесь после перезапуска."
                        : "Unfinished tasks are saved separately and remain available after restarting."
                ).padding(.vertical, -12)
            } else {
                ForEach(recovery.interruptedOperations) { marker in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(marker.title).font(.headline)
                        Text(marker.message).font(.subheadline).foregroundStyle(.secondary)
                        Text("\(marker.tool) · \(marker.startedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            if let path = marker.backupPath, !path.isEmpty {
                                Button(lang.selectedLanguage == "ru" ? "Показать backup" : "Show Backup") {
                                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                                }.buttonStyle(SyncrosaSecondaryButtonStyle())
                            }
                            Button(lang.selectedLanguage == "ru" ? "Убрать запись" : "Remove Record") {
                                pendingRemoval = .marker(marker.id)
                                showRemovalConfirmation = true
                            }.buttonStyle(SyncrosaSecondaryButtonStyle())
                        }
                        Divider()
                    }
                }
            }
        }.syncrosaCard()
    }

    private var usbRecoveryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SyncrosaSectionLabel(text: lang.selectedLanguage == "ru" ? "Продолжить USB-экспорт" : "Resume USB Export", systemImage: "externaldrive.badge.checkmark")
            Text(lang.selectedLanguage == "ru"
                 ? "Подключите тот же накопитель и выберите его заново. Готовые файлы проверяются по содержимому; копируются только оставшиеся треки."
                 : "Reconnect the same drive and select it again. Completed files are checked by content; only remaining tracks are copied.")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Button(lang.selectedLanguage == "ru" ? "Доступ к исходной папке…" : "Source Folder Access…", action: selectSourceAccessFolder)
                    .buttonStyle(SyncrosaSecondaryButtonStyle())
                    .disabled(isResumingUSB)
                if let sourceAccessURL {
                    Text(sourceAccessURL.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(lang.selectedLanguage == "ru"
                 ? "Если исходная музыка недоступна после перезапуска, разрешите доступ к папке, в которой она хранится."
                 : "If source music cannot be read after restarting, grant access to the folder where it is stored.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(usbWarnings, id: \.self) { warning in
                Text(warning).font(.caption).foregroundStyle(SyncrosaTheme.caution)
            }
            if !usbProgressText.isEmpty {
                Text(usbProgressText).font(.caption).textSelection(.enabled)
            }
            if isResumingUSB {
                HStack {
                    ProgressView().controlSize(.small)
                    Button(lang.selectedLanguage == "ru" ? "Остановить" : "Stop") {
                        PlaylistExportService.shared.cancel()
                    }.buttonStyle(SyncrosaSecondaryButtonStyle())
                }
            }
            if usbJobs.isEmpty {
                Text(lang.selectedLanguage == "ru" ? "Незавершённых USB-задач нет." : "No unfinished USB exports.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(usbJobs, id: \.id) { job in
                VStack(alignment: .leading, spacing: 8) {
                    Text(job.playlistName).font(.headline)
                    if let message = job.lastError, !message.isEmpty {
                        Text(message).font(.caption).foregroundStyle(SyncrosaTheme.caution)
                    }
                    Text("\(job.destinationName) · \(job.completedCount)/\(job.totalCount) · \(job.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(lang.selectedLanguage == "ru" ? "Продолжить…" : "Resume…") { resumeUSB(job) }
                            .buttonStyle(SyncrosaPrimaryButtonStyle())
                            .disabled(isResumingUSB || PlaylistExportService.shared.isRunning)
                        Button(lang.selectedLanguage == "ru" ? "Убрать запись" : "Remove Record") {
                            pendingRemoval = .usb(job.id)
                            showRemovalConfirmation = true
                        }.buttonStyle(SyncrosaSecondaryButtonStyle())
                            .disabled(isResumingUSB || PlaylistExportService.shared.isRunning)
                    }
                    Divider()
                }
            }
        }.syncrosaCard()
    }

    private func refreshRecoveryData() {
        recovery.refresh()
        reloadUndoPackages()
        reloadUSBJobs()
    }

    private func reloadUSBJobs() {
        let result = PlaylistExportService.shared.loadPendingJobs()
        usbJobs = result.jobs
        usbWarnings = result.errors
    }

    private func removePendingRecord() {
        defer { pendingRemoval = nil }
        switch pendingRemoval {
        case .marker(let id): recovery.clear(id: id)
        case .usb(let id):
            do { try PlaylistExportService.shared.discardJob(id) }
            catch { activeNotification = NotificationMessage(text: error.localizedDescription, isError: true) }
        case nil: break
        }
        refreshRecoveryData()
    }

    private func selectSourceAccessFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = lang.selectedLanguage == "ru" ? "Папка с исходной музыкой" : "Source Music Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        sourceAccessURL = url
    }

    private func resumeUSB(_ job: USBExportJobSummary) {
        guard !PlaylistExportService.shared.isRunning else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = lang.selectedLanguage == "ru" ? "Выберите тот же USB-накопитель" : "Select the same USB drive"
        panel.prompt = lang.selectedLanguage == "ru" ? "Продолжить" : "Resume"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let sourceGrant = sourceAccessURL
        let scopedSource = sourceGrant?.startAccessingSecurityScopedResource() ?? false
        isResumingUSB = true
        usbProgressText = lang.selectedLanguage == "ru" ? "Проверка сохранённых файлов…" : "Checking saved files…"
        PlaylistExportService.shared.resume(jobID: job.id, destination: destination, progress: { progress in
            usbProgressText = "\(progress.currentTrack)/\(progress.totalTracks) · \(progress.currentTrackName)"
        }, completion: { result in
            if scopedSource { sourceGrant?.stopAccessingSecurityScopedResource() }
            isResumingUSB = false
            let russian = lang.selectedLanguage == "ru"
            let summary = russian
                ? "Скопировано: \(result.copiedCount). Уже перенесено: \(result.existingCount). Ошибок: \(result.errors.count)."
                : "Copied: \(result.copiedCount). Already present: \(result.existingCount). Errors: \(result.errors.count)."
            usbProgressText = (result.wasCancelled ? (russian ? "Остановлено. " : "Stopped. ") : "") + summary
            activeNotification = NotificationMessage(text: usbProgressText, isError: !result.errors.isEmpty)
            OperationHistoryService.shared.record(tool: "USB Export", title: "Resume USB Export", status: result.errors.isEmpty && !result.wasCancelled ? "OK" : "WARN", message: usbProgressText + (result.errors.isEmpty ? "" : "\n" + result.errors.joined(separator: "\n")), affectedCount: result.copiedCount)
            reloadUSBJobs()
        })
    }

    private var undoPackagesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SyncrosaSectionLabel(text: lang.selectedLanguage == "ru" ? "Пакеты отката" : "Undo Packages", systemImage: "arrow.uturn.backward.circle")

            if undoPackages.isEmpty {
                SyncrosaEmptyState(
                    systemImage: "clock.arrow.circlepath",
                    title: lang.selectedLanguage == "ru" ? "Пакетов отката пока нет." : "No undo packages yet.",
                    message: lang.selectedLanguage == "ru" ? "Переименование файлов и некоторые операции с тегами будут сохранять undo package здесь." : "File renames and some metadata operations will save undo packages here."
                )
                .padding(.vertical, -12)
            } else {
                SyncrosaAdaptiveRow(spacing: 12) {
                    SyncrosaGlassMenu(
                        selection: Binding(
                            get: { selectedUndoID ?? undoPackages.first?.id ?? UUID() },
                            set: { selectedUndoID = $0 }
                        ),
                        options: undoPackages.map {
                            SyncrosaMenuOption(title: "\($0.name) - \($0.operations.count) ops", value: $0.id)
                        },
                        width: 320
                    )

                    Button(lang.selectedLanguage == "ru" ? "Восстановить" : "Restore") {
                        if let package = selectedUndoPackage {
                            presentUndoSafety(package)
                        }
                    }
                    .buttonStyle(SyncrosaPrimaryButtonStyle())
                    .disabled(selectedUndoPackage?.operations.isEmpty ?? true)

                    Button(lang.selectedLanguage == "ru" ? "Обновить" : "Refresh") {
                        reloadUndoPackages()
                    }
                    .buttonStyle(SyncrosaSecondaryButtonStyle())
                }

                if let package = selectedUndoPackage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(package.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(Array(package.operations.prefix(6))) { operation in
                            HStack(spacing: 8) {
                                SyncrosaStatusBadge(text: operation.action.replacingOccurrences(of: "metadata:", with: "metadata "))
                                Text(operation.currentPath)
                                    .font(.caption.monospaced())
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Image(systemName: "arrow.uturn.backward")
                                    .foregroundStyle(.secondary)
                                Text(operation.originalPath.isEmpty ? "empty" : operation.originalPath)
                                    .font(.caption.monospaced())
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                    .padding(12)
                    .background(SyncrosaTheme.subtleBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .syncrosaCard()
    }

    private var selectedUndoPackage: LibraryToolkitUndoPackage? {
        let id = selectedUndoID ?? undoPackages.first?.id
        return undoPackages.first(where: { $0.id == id })
    }

    private func locationCard(title: String, path: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(SyncrosaTheme.accent)
            Text(title)
                .font(.headline)
            Text(path)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
            Button(lang.selectedLanguage == "ru" ? "Открыть" : "Open") {
                NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
            }
            .buttonStyle(SyncrosaSecondaryButtonStyle())
        }
        .syncrosaCard()
    }

    private func reloadUndoPackages() {
        undoPackages = LibraryToolkitService.shared.loadUndoPackages()
        if selectedUndoID == nil {
            selectedUndoID = undoPackages.first?.id
        }
    }

    private func presentUndoSafety(_ package: LibraryToolkitUndoPackage) {
        pendingUndoPackage = package
        safetyPreview = SafetyPreviewRequest(
            title: lang.selectedLanguage == "ru" ? "Восстановить пакет отката?" : "Restore undo package?",
            message: lang.selectedLanguage == "ru" ? "Syncrosa попробует вернуть файлы или теги к прежним значениям. Уже занятые пути будут пропущены." : "Syncrosa will try to restore files or tags to their previous values. Occupied paths will be skipped.",
            details: [
                SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Пакет" : "Package", value: package.name),
                SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Операций" : "Operations", value: "\(package.operations.count)")
            ],
            confirmTitle: lang.selectedLanguage == "ru" ? "Восстановить" : "Restore",
            isDestructive: true
        )
    }

    private func restoreUndoPackage(_ package: LibraryToolkitUndoPackage?) {
        guard let package else { return }
        do {
            let restored = try LibraryToolkitService.shared.restoreUndoPackage(package)
            reloadUndoPackages()
            activeNotification = NotificationMessage(text: "Restored \(restored) operations.", isError: false)
            OperationHistoryService.shared.record(
                tool: "Recovery Center",
                title: "Restore Undo Package",
                status: "OK",
                message: "Restored \(restored) operations from \(package.name).",
                affectedCount: restored
            )
        } catch {
            activeNotification = NotificationMessage(text: error.localizedDescription, isError: true)
        }
    }
}

private enum RecoveryRecordRemoval {
    case marker(UUID)
    case usb(UUID)
}
