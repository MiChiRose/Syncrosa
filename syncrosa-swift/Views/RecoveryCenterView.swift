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
            reloadUndoPackages()
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
                "Выберите пакет отмены и внимательно проверьте детали перед восстановлением."
            ] : [
                "Check the interrupted-operation card after an unexpected app exit.",
                "Open history to review completed actions and affected file counts.",
                "Choose an undo package and review its details before restoring."
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

    @ViewBuilder
    private var interruptedOperationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SyncrosaSectionLabel(text: lang.selectedLanguage == "ru" ? "Прерванная операция" : "Interrupted Operation", systemImage: "bolt.trianglebadge.exclamationmark")

            if let marker = recovery.activeOperation {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(SyncrosaTheme.caution)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(marker.title)
                            .font(.headline)
                        Text(marker.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(marker.tool) · \(marker.startedAt.formatted(date: .abbreviated, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let backupPath = marker.backupPath, !backupPath.isEmpty {
                            Text(backupPath)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer()

                    Button(lang.selectedLanguage == "ru" ? "Очистить маркер" : "Clear Marker") {
                        recovery.clear()
                    }
                    .buttonStyle(SyncrosaSecondaryButtonStyle())
                }
            } else {
                SyncrosaEmptyState(
                    systemImage: "checkmark.shield",
                    title: lang.selectedLanguage == "ru" ? "Нет прерванных операций." : "No interrupted operations.",
                    message: lang.selectedLanguage == "ru" ? "Если приложение упадёт во время долгого процесса, Syncrosa покажет это здесь после запуска." : "If the app crashes during a long operation, Syncrosa will show it here after launch."
                )
                .padding(.vertical, -12)
            }
        }
        .syncrosaCard()
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
