import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import AudioTitleCore
#endif

struct FolderTitleEditor: View {
    private struct Row: Identifiable {
        let file: URL
        let path: String
        let snapshot: [AnyHashable: Any]?
        let original: String
        let suggestion: String
        var title: String
        var result: String?

        var id: URL { file }
        var isChanged: Bool { snapshot != nil && result == nil && title != original }
    }

    let folder: URL
    let russian: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [Row] = []
    @State private var isScanning = true
    @State private var isApplying = false
    @State private var status = ""
    @State private var backupFolder: URL?
    @State private var progress = 0
    @State private var total = 0

    private func local(_ ru: String, _ en: String) -> String { russian ? ru : en }

    private var proposed: [Row] { rows.filter(\.isChanged) }
    private var hasInvalidTitle: Bool { proposed.contains { !SRIsValidTrackTitle($0.title) } }
    private var canSuggest: Bool {
        rows.contains { $0.snapshot != nil && $0.result == nil && $0.title == $0.original && !$0.suggestion.isEmpty && $0.suggestion != $0.original }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(local("Исправить названия треков", "Correct Track Titles"))
                .font(.title2.weight(.semibold))
            Text(folder.path)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(folder.path)
            Text(local("Изменится поле «Название» в аудиофайле. Имена файлов останутся прежними. Работа идёт локально.",
                       "This edits the Title tag inside each audio file. File names stay the same. All edits are local."))
                .foregroundStyle(.secondary)

            if isScanning {
                ProgressView(local("Читаем названия…", "Reading track titles…"))
                    .frame(maxWidth: .infinity, minHeight: 250)
            } else if rows.isEmpty {
                ContentUnavailableView(local("Нет треков для предпросмотра", "No Tracks to Preview"),
                                       systemImage: "music.note.list",
                                       description: Text(status.isEmpty
                                        ? local("Выберите папку с аудиофайлами.", "Choose a folder with audio files.") : status))
                    .frame(minHeight: 250)
            } else {
                previewTable
            }

            if isApplying {
                ProgressView(local("Обработано \(progress) из \(total)", "Processed \(progress) of \(total)"),
                             value: Double(progress), total: Double(total))
            } else if !status.isEmpty && !rows.isEmpty {
                Text(status).font(.callout).foregroundStyle(.secondary)
            } else if hasInvalidTitle {
                Text(local("Введите непустые названия без управляющих символов.",
                           "Enter nonempty titles without control characters."))
                    .foregroundStyle(.red)
            }

            HStack {
                Button(local("Взять из имён файлов", "Use File Names"), action: useFilenames)
                    .disabled(isScanning || isApplying || !canSuggest)
                    .help(local("Берёт часть после «Исполнитель - » для строк, которые вы ещё не правили.",
                                "Uses the text after “Artist - ” for rows you have not edited."))
                if let backupFolder {
                    Button(local("Показать оригиналы", "Show Originals")) { NSWorkspace.shared.open(backupFolder) }
                }
                Spacer()
                Button(local("Закрыть", "Close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isApplying)
                Button(local("Применить (\(proposed.count))", "Apply (\(proposed.count))"), action: apply)
                    .buttonStyle(.borderedProminent)
                    .disabled(isScanning || isApplying || proposed.isEmpty || hasInvalidTitle)
            }
        }
        .padding(22)
        .frame(minWidth: 700, idealWidth: 820, minHeight: 420, idealHeight: 525)
        .interactiveDismissDisabled(isApplying)
        .onAppear(perform: scan)
    }

    private var previewTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text(local("Файл", "File")).frame(width: 190, alignment: .leading)
                Text(local("Текущее название", "Current title")).frame(maxWidth: .infinity, alignment: .leading)
                Text(local("Новое название", "New title")).frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.4))
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach($rows) { $row in
                        HStack(alignment: .center, spacing: 14) {
                            Text(row.path)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .frame(width: 190, alignment: .leading)
                                .help(row.file.path)
                            Text(row.original.isEmpty ? "—" : row.original)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .help(row.original)
                            Group {
                                if let result = row.result {
                                    Text(result)
                                        .foregroundStyle(.secondary)
                                } else if row.snapshot != nil {
                                    TextField(local("Новое название", "New title"), text: $row.title)
                                        .textFieldStyle(.roundedBorder)
                                        .accessibilityLabel(local("Новое название: \(row.path)", "New title: \(row.path)"))
                                        .disabled(isApplying)
                                } else {
                                    Text(local("Редактирование недоступно", "Editing unavailable"))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.callout)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        Divider()
                    }
                }
            }
        }
        .background(.background)
        .border(.quaternary)
        .frame(minHeight: 250, maxHeight: .infinity)
    }

    private func scan() {
        guard isScanning else { return }
        let root = folder.standardizedFileURL.path + (folder.standardizedFileURL.path.hasSuffix("/") ? "" : "/")
        DispatchQueue.global(qos: .utility).async {
            let scoped = folder.startAccessingSecurityScopedResource()
            defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
            var error: NSError?
            let items = SRScanTrackTitles(folder, &error) as? [[String: Any]]
            let scanned = (items ?? []).compactMap { item -> Row? in
                guard let file = item["file"] as? URL else { return nil }
                let path = file.standardizedFileURL.path
                let relative = path.hasPrefix(root) ? String(path.dropFirst(root.count)) : file.lastPathComponent
                let snapshot = item["snapshot"] as? [AnyHashable: Any]
                let title = snapshot?["title"] as? String ?? ""
                return Row(file: file, path: relative, snapshot: snapshot, original: title,
                           suggestion: item["suggestion"] as? String ?? "", title: title)
            }
            DispatchQueue.main.async {
                rows = scanned
                isScanning = false
                if items == nil {
                    status = local("Не удалось прочитать выбранную папку.", "The selected folder could not be read.")
                }
            }
        }
    }

    private func useFilenames() {
        for i in rows.indices where rows[i].snapshot != nil && rows[i].result == nil &&
            rows[i].title == rows[i].original && !rows[i].suggestion.isEmpty {
            rows[i].title = rows[i].suggestion
        }
    }

    private func apply() {
        let edits = proposed
        guard !isApplying, !edits.isEmpty, !hasInvalidTitle else { return }
        isApplying = true
        progress = 0
        total = edits.count
        status = ""
        let backups = SyncrosaStorage.backupsDirectory.appendingPathComponent("Track Titles", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let recovery = OperationRecoveryService.shared.begin(
            tool: "Folder Fixer", title: "Correct Track Titles",
            message: "Title editing stopped before all files were processed. Original files are stored in the backup folder.",
            affectedCount: edits.count, backupPath: backups.path
        )
        DispatchQueue.global(qos: .utility).async {
            let scoped = folder.startAccessingSecurityScopedResource()
            defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
            var report: [URL: String] = [:]
            var updated = 0
            for (index, item) in edits.enumerated() {
                autoreleasepool {
                    var error: NSError?
                    if let snapshot = item.snapshot,
                       SRReplaceTrackTitle(item.file, snapshot, item.title, backups, &error) != nil {
                        updated += 1
                        report[item.id] = item.title
                    } else {
                        report[item.id] = error?.code == 3
                            ? local("Файл изменился после просмотра", "File changed after preview")
                            : local("Не удалось сохранить оригинал или записать тег", "Could not back up or write tag")
                    }
                }
                DispatchQueue.main.async { progress = index + 1 }
            }
            let failed = edits.count - updated
            OperationHistoryService.shared.record(
                tool: "Folder Fixer", title: "Correct Track Titles",
                status: failed == 0 ? "OK" : (updated > 0 ? "WARN" : "ERROR"),
                message: "Updated \(updated); failed \(failed).", affectedCount: updated,
                backupPath: updated > 0 ? backups.path : nil
            )
            OperationRecoveryService.shared.finish(recovery)
            let copiedBackups = FileManager.default.fileExists(atPath: backups.path)
            DispatchQueue.main.async {
                for i in rows.indices {
                    if let result = report[rows[i].id] { rows[i].result = result }
                }
                if copiedBackups { backupFolder = backups }
                status = local("Изменено: \(updated). Ошибок: \(failed).", "Updated: \(updated). Failed: \(failed).")
                isApplying = false
            }
        }
    }
}
