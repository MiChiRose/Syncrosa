import SwiftUI

struct OperationHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var lang = LocalizationService.shared
    @ObservedObject private var history = OperationHistoryService.shared
    @State private var selectedTool = "All"

    private let tools = [
        "All",
        "Overview",
        "Library Doctor",
        "Folder Fixer",
        "Filename Cleaner",
        "Info Eraser",
        "Media Fixer",
        "Covers Optimizer",
        "USB Export"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
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
                    options: tools.map { SyncrosaMenuOption(title: $0, value: $0) },
                    width: 220
                )
                Button(lang.selectedLanguage == "ru" ? "Очистить" : "Clear") {
                    history.clear()
                }
                .buttonStyle(SyncrosaSecondaryButtonStyle())

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
        .frame(minWidth: 720, minHeight: 480)
    }

    private var filteredEntries: [OperationHistoryEntry] {
        history.entries(for: selectedTool)
    }
}
