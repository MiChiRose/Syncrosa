import AppKit
import SwiftUI

struct RecoveryCenterView: View {
    @ObservedObject var lang = LocalizationService.shared
    @ObservedObject private var recovery = OperationRecoveryService.shared
    @ObservedObject private var history = OperationHistoryService.shared
    @State private var showHistory = false

    var body: some View {
        SyncrosaPage {
            SyncrosaPageHeader(
                title: lang.selectedLanguage == "ru" ? "Центр восстановления" : "Recovery Center",
                systemImage: "cross.case",
                subtitle: lang.selectedLanguage == "ru" ? "Backup-папки, прерванные операции и история действий." : "Backup folders, interrupted operations, and operation history."
            ) {
                Button(action: { showHistory = true }) {
                    Label(lang.selectedLanguage == "ru" ? "История" : "History", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(SyncrosaSecondaryButtonStyle())
            }

            interruptedOperationCard

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
        .sheet(isPresented: $showHistory) {
            OperationHistoryView()
        }
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
}
