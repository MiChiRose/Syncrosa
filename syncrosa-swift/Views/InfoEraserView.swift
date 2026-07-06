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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    Label("Info Eraser", systemImage: "eraser.line.dashed")
                        .font(.title2)
                        .fontWeight(.bold)
                    Button(action: { showHelp = true }) {
                        Image(systemName: "questionmark.circle")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(lang.selectedLanguage == "ru" ? "ВНИМАНИЕ" : "WARNING")
                        .font(.caption)
                        .fontWeight(.bold)
                    Text(lang.selectedLanguage == "ru" ? "Эта вкладка окончательно удаляет встроенную информацию и обложки из локальных музыкальных файлов. Работайте только с копией папки или сначала сохраните резервную копию." : "This tab permanently removes embedded song information and artwork from local music files. Work on a copied folder or create a backup first.")
                        .font(.subheadline)
                }
                .foregroundColor(Color(red: 0.55, green: 0, blue: 0.06))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.35), lineWidth: 1))
                .cornerRadius(8)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        TextField(lang.selectedLanguage == "ru" ? "Папка не выбрана" : "No folder selected", text: $folderPath)
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)
                        Button(action: selectFolder) {
                            Label(lang.selectedLanguage == "ru" ? "Выбрать папку" : "Select Folder", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isProcessing)
                    }

                    HStack(spacing: 10) {
                        Button(action: backupOriginalInfo) {
                            Label(lang.selectedLanguage == "ru" ? "Сохранить исходную инфо" : "Backup Original Info", systemImage: "externaldrive.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        .disabled(fileItems.isEmpty || isProcessing)

                        Button(action: confirmErase) {
                            Label(lang.selectedLanguage == "ru" ? "Очистить" : "Erase Info", systemImage: "eraser")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(fileItems.isEmpty || isProcessing)

                        Button(action: restoreOriginalInfo) {
                            Label(lang.selectedLanguage == "ru" ? "Восстановить" : "Restore Info", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.bordered)
                        .disabled(folderPath.isEmpty || isProcessing)
                    }

                    ProgressView(value: progressValue, total: progressTotal)
                        .opacity(isProcessing || progressValue > 0 ? 1 : 0.35)
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)

                VStack(alignment: .leading, spacing: 10) {
                    Text(fileSummary)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if fileItems.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 38))
                                .foregroundColor(.gray.opacity(0.35))
                            Text(lang.selectedLanguage == "ru" ? "Выберите папку с музыкой." : "Select a folder with music files.")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 34)
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
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("LOG")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(logLines.enumerated()), id: \.offset) { _, line in
                                Text("> \(line)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.green)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, minHeight: 130)
                    .background(Color.black)
                    .cornerRadius(6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(30)
        }
        .notification(message: $activeNotification)
        .sheet(isPresented: $showHelp) {
            helpSheet
        }
    }

    private var fileSummary: String {
        let supportedCount = fileItems.filter { isSupportedInfoExtension($0.url.pathExtension.lowercased()) }.count
        return lang.selectedLanguage == "ru" ? "Найдено файлов: \(fileItems.count). Поддерживается очистка MP3, M4A, MP4, AAC, ALAC: \(supportedCount)." : "Files found: \(fileItems.count). Supported for erasing MP3, M4A, MP4, AAC, ALAC: \(supportedCount)."
    }

    private var helpSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(lang.selectedLanguage == "ru" ? "Справка: Info Eraser" : "Help: Info Eraser", systemImage: "questionmark.circle")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
                Button(lang.selectedLanguage == "ru" ? "Закрыть" : "Close") {
                    showHelp = false
                }
                .keyboardShortcut(.cancelAction)
            }

            Text(lang.selectedLanguage == "ru" ?
                 "Info Eraser работает только с выбранной локальной папкой и её вложенными папками. Он не меняет медиатеку Music/iTunes напрямую." :
                 "Info Eraser works only with the selected local folder and its subfolders. It does not edit your Music/iTunes library directly.")

            Text(lang.selectedLanguage == "ru" ?
                 "Поддерживается очистка MP3 ID3-тегов и M4A/MP4/AAC/ALAC metadata atom. Для MP4-подобных файлов Syncrosa заменяет metadata atom на free-блок того же размера, не перекодируя аудио." :
                 "It can erase MP3 ID3 tags and the metadata atom in M4A/MP4/AAC/ALAC files. For MP4-like files, Syncrosa replaces the metadata atom with a same-size free atom without transcoding audio.")

            Text(lang.selectedLanguage == "ru" ?
                 "Кнопка Backup Original Info создаёт папку SyncrosaInfoEraserBackup с manifest.json и sidecar-файлами тегов. Restore возвращает информацию только из этого backup." :
                 "Backup Original Info creates a SyncrosaInfoEraserBackup folder with manifest.json and sidecar tag files. Restore uses only that backup.")
                .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(width: 520)
    }

    private func isSupportedInfoExtension(_ ext: String) -> Bool {
        ["mp3", "m4a", "mp4", "aac", "alac"].contains(ext)
    }

    @ViewBuilder
    private func statusIcon(_ status: InfoEraserStatus) -> some View {
        switch status {
        case .pending:
            Text("WAITING").font(.caption2).foregroundColor(.secondary)
        case .processing:
            ProgressView().controlSize(.mini)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .skipped:
            Text("SKIP").font(.caption2).foregroundColor(.secondary)
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

    private func confirmErase() {
        let alert = NSAlert()
        alert.messageText = lang.selectedLanguage == "ru" ? "Точно продолжить?" : "Are you sure?"
        alert.informativeText = lang.selectedLanguage == "ru" ? "Syncrosa удалит встроенные теги и обложки из поддерживаемых файлов. Это действие нельзя отменить без backup." : "Syncrosa will remove embedded tags and artwork from supported files. This cannot be undone without a backup."
        alert.addButton(withTitle: lang.selectedLanguage == "ru" ? "Продолжить" : "Continue")
        alert.addButton(withTitle: lang.selectedLanguage == "ru" ? "Отмена" : "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let finalAlert = NSAlert()
        finalAlert.messageText = lang.selectedLanguage == "ru" ? "Последнее предупреждение" : "Final Warning"
        finalAlert.informativeText = lang.selectedLanguage == "ru" ? "Запускайте очистку только если вы уже сохранили исходную информацию или работаете с копиями файлов." : "Run erasing only if you already backed up the original info or are working with copied files."
        finalAlert.addButton(withTitle: lang.selectedLanguage == "ru" ? "Очистить" : "Erase")
        finalAlert.addButton(withTitle: lang.selectedLanguage == "ru" ? "Отмена" : "Cancel")
        if finalAlert.runModal() == .alertFirstButtonReturn {
            eraseInfo()
        }
    }

    private func backupOriginalInfo() {
        runOperation(title: lang.selectedLanguage == "ru" ? "Сохраняю исходную информацию..." : "Backing up original info...") { folder, files, progress in
            let result = try InfoEraserService.shared.backupOriginalInfo(folder: folder, files: files, progress: progress)
            return lang.selectedLanguage == "ru" ? "Backup сохранён: \(result.manifestURL.path). Поддерживаемых файлов: \(result.supportedCount)." : "Backup saved: \(result.manifestURL.path). Supported files: \(result.supportedCount)."
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
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let message = try worker(folder, files) { current, total in
                    DispatchQueue.main.async {
                        progressValue = Double(current)
                        progressTotal = Double(max(1, total))
                        if current - 1 < fileItems.count {
                            fileItems[current - 1].status = .done
                        }
                    }
                }
                DispatchQueue.main.async {
                    isProcessing = false
                    appendLog(message)
                    activeNotification = NotificationMessage(text: message, isError: false)
                }
            } catch {
                DispatchQueue.main.async {
                    isProcessing = false
                    appendLog("ERROR: \(error.localizedDescription)")
                    activeNotification = NotificationMessage(text: error.localizedDescription, isError: true)
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
