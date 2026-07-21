import SwiftUI

struct OperationHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var lang = LocalizationService.shared
    @ObservedObject private var history = OperationHistoryService.shared
    @State private var selectedTool = "All"
    @State private var showClearConfirmation = false

    private var toolOptions: [SyncrosaMenuOption<String>] {
        let values = ["All", "Overview", "Library Doctor", "Folder Fixer", "Filename Cleaner", "Info Eraser", "Media Fixer", "Covers Optimizer", "USB Export"]
        let russian = ["Все", "Обзор", "Диагностика", "Фиксер папок", "Очистка имён", "Удаление информации", "Медиа-фиксер", "Оптимизатор обложек", "USB-экспорт"]
        return values.indices.map {
            SyncrosaMenuOption(title: lang.selectedLanguage == "ru" ? russian[$0] : values[$0], value: values[$0])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SyncrosaAdaptiveRow(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(SyncrosaTheme.accent)
                    Text(lang.selectedLanguage == "ru" ? "История операций" : "Operation History")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                Spacer()
                SyncrosaGlassMenu(
                    selection: $selectedTool,
                    options: toolOptions,
                    minWidth: 220
                )
                Button(lang.selectedLanguage == "ru" ? "Очистить" : "Clear") {
                    showClearConfirmation = true
                }
                .buttonStyle(SyncrosaSecondaryButtonStyle())
                .disabled(history.entries.isEmpty)

                Button(action: { dismiss() }) {
                    Label(lang.selectedLanguage == "ru" ? "Закрыть" : "Close", systemImage: "xmark")
                }
                .buttonStyle(SyncrosaSecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
            }

            if filteredEntries.isEmpty {
                SyncrosaEmptyState(
                    systemImage: "clock.arrow.circlepath",
                    title: lang.selectedLanguage == "ru" ? "История пока пустая." : "No operation history yet.",
                    message: lang.selectedLanguage == "ru" ? "Завершённые операции появятся здесь автоматически." : "Completed operations will appear here automatically."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredEntries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.title)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(entry.status)
                                .font(.caption)
                                .foregroundColor(entry.status == "OK" ? .green : .orange)
                        }
                        Text("\(entry.tool) · \(entry.createdAt.formatted(date: .abbreviated, time: .standard))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(entry.message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                        if let backupPath = entry.backupPath, !backupPath.isEmpty {
                            Text(backupPath)
                                .font(.caption2.monospaced())
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 620, idealWidth: 780, maxWidth: 940, minHeight: 480)
        .alert(lang.selectedLanguage == "ru" ? "Очистить историю операций?" : "Clear operation history?", isPresented: $showClearConfirmation) {
            Button(lang.selectedLanguage == "ru" ? "Отмена" : "Cancel", role: .cancel) {}
            Button(lang.selectedLanguage == "ru" ? "Очистить" : "Clear", role: .destructive) {
                history.clear()
            }
        } message: {
            Text(lang.selectedLanguage == "ru"
                 ? "Все записи истории будут удалены. Backup-файлы и пакеты восстановления останутся на месте."
                 : "All history entries will be removed. Backup files and recovery packages will not be deleted.")
        }
    }

    private var filteredEntries: [OperationHistoryEntry] {
        history.entries(for: selectedTool)
    }
}
