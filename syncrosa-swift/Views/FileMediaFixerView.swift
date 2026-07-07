import SwiftUI
import AppKit

enum FileStatus {
    case pending
    case processing
    case done
    case error
}

struct FileItem: Identifiable {
    let id = UUID()
    let url: URL
    var status: FileStatus = .pending
}

private enum FileFixerSafetyAction {
    case fixMetadata
    case cleanFilenames
}

struct FileMediaFixerView: View {
    @ObservedObject var lang = LocalizationService.shared
    @State private var folderPath: String = ""
    @State private var fileItems: [FileItem] = []
    @State private var isProcessing: Bool = false
    @State private var activeNotification: NotificationMessage? = nil
    @State private var downloadCovers: Bool = true
    @State private var logLines: [String] = []
    @State private var showHelp: Bool = false
    @State private var safetyPreview: SafetyPreviewRequest? = nil
    @State private var pendingSafetyAction: FileFixerSafetyAction? = nil
    
    // Checkbox checklist states
    @State private var fixAlbum: Bool = true
    @State private var fixTitle: Bool = true
    @State private var fixArtist: Bool = true
    @State private var fixGenre: Bool = true
    @State private var fixTrackNumber: Bool = true
    @State private var fixLyrics: Bool = true
    
    // Select All Binding
    var selectAllBinding: Binding<Bool> {
        Binding<Bool>(
            get: { fixAlbum && fixTitle && fixArtist && fixGenre && fixTrackNumber && fixLyrics },
            set: { newValue in
                fixAlbum = newValue
                fixTitle = newValue
                fixArtist = newValue
                fixGenre = newValue
                fixTrackNumber = newValue
                fixLyrics = newValue
            }
        )
    }
    
    var body: some View {
        SyncrosaPage {
            SyncrosaPageHeader(
                title: lang.t("folder_fix"),
                systemImage: "folder.badge.gearshape",
                subtitle: lang.selectedLanguage == "ru" ? "Работа с локальными файлами в выбранной папке." : "Repair local music files inside a selected folder.",
                helpAction: { showHelp = true }
            )
                
                // Checklist Card
                VStack(alignment: .leading, spacing: 15) {
                    SyncrosaSectionLabel(text: lang.selectedLanguage == "ru" ? "ПРИМЕНЯТЬ ТОЛЬКО ОТМЕЧЕННЫЕ ТЕГИ" : "APPLY ONLY CHECKED TAGS", systemImage: "checklist")
                    
                    Toggle(isOn: selectAllBinding) {
                        Text(lang.selectedLanguage == "ru" ? "Выбрать все" : "Select All")
                            .fontWeight(.bold)
                    }
                    .toggleStyle(.checkbox)
                    
                    Divider()
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], alignment: .leading, spacing: 12) {
                        Toggle(lang.selectedLanguage == "ru" ? "Альбом" : "Album", isOn: $fixAlbum)
                            .toggleStyle(.checkbox)
                        Toggle(lang.selectedLanguage == "ru" ? "Название" : "Title", isOn: $fixTitle)
                            .toggleStyle(.checkbox)
                        Toggle(lang.selectedLanguage == "ru" ? "Исполнитель" : "Artist", isOn: $fixArtist)
                            .toggleStyle(.checkbox)
                        Toggle(lang.selectedLanguage == "ru" ? "Жанр" : "Genre", isOn: $fixGenre)
                            .toggleStyle(.checkbox)
                        Toggle(lang.selectedLanguage == "ru" ? "Номер трека" : "Track Number", isOn: $fixTrackNumber)
                            .toggleStyle(.checkbox)
                        Toggle(lang.selectedLanguage == "ru" ? "Текст песен" : "Lyrics", isOn: $fixLyrics)
                            .toggleStyle(.checkbox)
                    }
                }
                .syncrosaCard()
                
                // Card 1: Folder Selection & Controls
                VStack(alignment: .leading, spacing: 15) {
                    Text(lang.t("file_instr"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    SyncrosaAdaptiveRow(spacing: 15) {
                        TextField(lang.t("no_folder"), text: $folderPath)
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)
                        
                        Button(action: selectFolder) {
                            Label(lang.t("select_folder"), systemImage: "folder")
                        }
                        .buttonStyle(SyncrosaSecondaryButtonStyle())
                        .disabled(isProcessing)
                        
                        Button(action: { presentSafetyPreview(.fixMetadata) }) {
                            Label(lang.t("fix_all"), systemImage: "wrench.and.screwdriver")
                        }
                        .buttonStyle(SyncrosaPrimaryButtonStyle())
                        .disabled(fileItems.isEmpty || isProcessing || (!fixAlbum && !fixTitle && !fixArtist && !fixGenre && !fixTrackNumber && !fixLyrics))

                        Button(action: { presentSafetyPreview(.cleanFilenames) }) {
                            Label(lang.selectedLanguage == "ru" ? "Clean Filenames" : "Clean Filenames", systemImage: "textformat")
                        }
                        .buttonStyle(SyncrosaSecondaryButtonStyle())
                        .disabled(fileItems.isEmpty || isProcessing)
                    }
                    
                    Toggle(isOn: $downloadCovers) {
                        Text(lang.selectedLanguage == "ru" ? "Скачивать обложки альбомов в папку" : "Download album covers into the folder")
                            .font(.caption)
                    }
                    .toggleStyle(.checkbox)
                }
                .syncrosaCard()
                
                // Card 2: File List
                VStack(alignment: .leading, spacing: 10) {
                    SyncrosaSectionLabel(text: lang.t("files_to_process", fileItems.count), systemImage: "doc.text")
                    
                    if fileItems.isEmpty {
                        SyncrosaEmptyState(
                            systemImage: "music.note.list",
                            title: lang.t("select_folder_msg")
                        )
                    } else {
                        ForEach(fileItems) { item in
                            HStack {
                                Text(item.url.lastPathComponent)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                
                                Spacer()
                                
                                statusIcon(for: item.status)
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                }
                .syncrosaCard()

                SyncrosaLogConsole(title: "LOG", lines: logLines, minHeight: 130)
                
                Spacer()
        }
        .notification(message: $activeNotification)
        .sheet(isPresented: $showHelp) {
            helpSheetView
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
    
    var helpSheetView: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(lang.selectedLanguage == "ru" ? "Инструкция: Работа с файлами" : "Help: Folder Fixer")
                    .font(.headline)
                Spacer()
                Button(lang.selectedLanguage == "ru" ? "Закрыть" : "Close") {
                    showHelp = false
                }
                .buttonStyle(SyncrosaSecondaryButtonStyle())
            }
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(lang.selectedLanguage == "ru" ?
                         "Этот инструмент предназначен для прямого переименования и упорядочивания музыкальных файлов (MP3, FLAC, M4A и др.) в выбранной папке на диске.\n\n" +
                         "Инструкция по использованию:\n" +
                         "1. Выберите в панели тегов те свойства, которые вы хотите применить к переименованию файлов.\n" +
                         "2. Укажите, нужно ли автоматически скачивать обложку альбома в ту же папку.\n" +
                         "3. Нажмите «Выбрать папку» и укажите директорию с вашей музыкой.\n" +
                         "4. Для отдельной чистки имён файлов используйте кнопку Clean Filenames. Она заменяет подчёркивания на пробелы отдельным процессом.\n" +
                         "5. Нажмите «Исправить все файлы». Программа запросит корректные данные из iTunes Search API и переименует файлы по шаблону «Исполнитель - Название.расширение», применяя только выбранные теги." :
                         
                         "This tool is designed to directly rename and organize music files (MP3, FLAC, M4A, etc.) in a folder on your disk.\n\n" +
                         "How to use:\n" +
                         "1. Select the specific tags in the tags panel that you wish to apply to the file processing/renaming.\n" +
                         "2. Select whether to download album covers to the folder.\n" +
                         "3. Click 'Select Folder' and choose the directory containing your music files.\n" +
                         "4. Use Clean Filenames as a separate process when you only want underscores converted to spaces.\n" +
                         "5. Click 'Fix All Files' to process the files. The app will search iTunes Search API and rename files to '[Artist] - [Title].[ext]' based only on the checked tags."
                    )
                    .font(.body)
                }
            }
            .frame(minWidth: 450, minHeight: 300)
        }
        .padding()
    }
    
    @ViewBuilder
    func statusIcon(for status: FileStatus) -> some View {
        switch status {
        case .pending:
            Text("WAITING")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
                .padding(4)
                .background(SyncrosaTheme.subtleBackground)
                .cornerRadius(4)
        case .processing:
            ProgressView()
                .controlSize(.mini)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 14))
        case .error:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.system(size: 14))
        }
    }
    
    func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                folderPath = url.path
                scanFolder(url)
            }
        }
    }
    
    func scanFolder(_ url: URL) {
        let musicExtensions = ["mp3", "wav", "flac", "alac", "m4a", "aiff"]
        var matches: [FileItem] = []
        
        let fm = FileManager.default
        let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) { url, error in
            return true
        }
        
        while let fileUrl = enumerator?.nextObject() as? URL {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: fileUrl.path, isDirectory: &isDir), !isDir.boolValue {
                if musicExtensions.contains(fileUrl.pathExtension.lowercased()) {
                    matches.append(FileItem(url: fileUrl))
                }
            }
        }
        
        self.fileItems = matches
        logLines.removeAll()
        appendLog("Scanned folder recursively: \(matches.count) music files.")
        
        if fileItems.isEmpty {
            activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Музыкальные файлы не найдены." : "No music files found.", isError: true)
        } else {
            activeNotification = NotificationMessage(text: lang.t("files_to_process", fileItems.count), isError: false)
        }
    }

    private func presentSafetyPreview(_ action: FileFixerSafetyAction) {
        guard !fileItems.isEmpty else { return }
        pendingSafetyAction = action
        let checkedTags = [
            fixAlbum ? (lang.selectedLanguage == "ru" ? "Альбом" : "Album") : nil,
            fixTitle ? (lang.selectedLanguage == "ru" ? "Название" : "Title") : nil,
            fixArtist ? (lang.selectedLanguage == "ru" ? "Исполнитель" : "Artist") : nil,
            fixGenre ? (lang.selectedLanguage == "ru" ? "Жанр" : "Genre") : nil,
            fixTrackNumber ? (lang.selectedLanguage == "ru" ? "Номер трека" : "Track Number") : nil,
            fixLyrics ? (lang.selectedLanguage == "ru" ? "Текст песен" : "Lyrics") : nil
        ].compactMap { $0 }.joined(separator: ", ")

        switch action {
        case .fixMetadata:
            safetyPreview = SafetyPreviewRequest(
                title: lang.selectedLanguage == "ru" ? "Исправить метаданные файлов?" : "Fix local file metadata?",
                message: lang.selectedLanguage == "ru" ? "Syncrosa обработает выбранную папку и применит только отмеченные теги. Для файлов лучше иметь backup или работать с копией." : "Syncrosa will process the selected folder and apply only checked tags. Keep a backup or work on a copy.",
                details: [
                    SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Папка" : "Folder", value: folderPath),
                    SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Файлов" : "Files", value: "\(fileItems.count)"),
                    SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Теги" : "Tags", value: checkedTags.isEmpty ? "-" : checkedTags),
                    SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Обложки" : "Covers", value: downloadCovers ? "On" : "Off")
                ],
                confirmTitle: lang.selectedLanguage == "ru" ? "Исправить" : "Fix",
                isDestructive: true
            )
        case .cleanFilenames:
            safetyPreview = SafetyPreviewRequest(
                title: lang.selectedLanguage == "ru" ? "Очистить имена файлов?" : "Clean filenames?",
                message: lang.selectedLanguage == "ru" ? "Syncrosa заменит вероятно случайные подчёркивания на пробелы. Если встретится ошибка, этот процесс остановится и не затронет другие функции вкладки." : "Syncrosa will convert likely accidental underscores to spaces. If an error happens, this process stops without touching other tab functions.",
                details: [
                    SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Папка" : "Folder", value: folderPath),
                    SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Файлов" : "Files", value: "\(fileItems.count)")
                ],
                confirmTitle: lang.selectedLanguage == "ru" ? "Очистить имена" : "Clean Names",
                isDestructive: false
            )
        }
    }

    private func runSafetyAction(_ action: FileFixerSafetyAction?) {
        switch action {
        case .fixMetadata:
            fixFolderMetadata()
        case .cleanFilenames:
            cleanFilenames()
        case .none:
            break
        }
    }
    
    func fixFolderMetadata() {
        isProcessing = true
        logLines.removeAll()
        appendLog("Starting Folder Fixer metadata process...")
        activeNotification = NotificationMessage(text: lang.t("processing_files"), isError: false)
        
        for i in fileItems.indices {
            fileItems[i].status = .pending
        }
        
        let tagsMap: [String: Bool] = [
            "album": fixAlbum,
            "title": fixTitle,
            "artist": fixArtist,
            "genre": fixGenre,
            "trackNumber": fixTrackNumber,
            "lyrics": fixLyrics
        ]
        let recoveryID = OperationRecoveryService.shared.begin(
            tool: "Folder Fixer",
            title: "Fix Folder Metadata",
            message: lang.selectedLanguage == "ru" ? "Исправление метаданных файлов было прервано. Проверьте папку и историю операций." : "Local metadata repair was interrupted. Check the folder and Operation History.",
            affectedCount: fileItems.count,
            backupPath: folderPath
        )
        DispatchQueue.global().async {
            for index in fileItems.indices {
                DispatchQueue.main.async {
                    fileItems[index].status = .processing
                    appendLog("Processing: \(fileItems[index].url.lastPathComponent)")
                }
                
                let result = FileMetadataService.shared.fixFile(
                    url: fileItems[index].url,
                    downloadCover: downloadCovers,
                    checkedTags: tagsMap,
                    normalizeUnderscores: false
                )
                
                DispatchQueue.main.async {
                    fileItems[index].status = result.success ? .done : .error
                    appendLog(result.success ? "OK: \(fileItems[index].url.lastPathComponent)" : "ERROR: \(fileItems[index].url.lastPathComponent)")
                }
            }
            
            DispatchQueue.main.async {
                OperationRecoveryService.shared.finish(recoveryID)
                isProcessing = false
                let message = lang.t("done")
                appendLog(message)
                activeNotification = NotificationMessage(text: message, isError: false)
                OperationHistoryService.shared.record(
                    tool: "Folder Fixer",
                    title: "Fix Folder Metadata",
                    status: "OK",
                    message: message,
                    affectedCount: fileItems.count
                )
            }
        }
    }

    func cleanFilenames() {
        isProcessing = true
        logLines.removeAll()
        appendLog("Starting filename cleaner...")
        activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Чищу имена файлов..." : "Cleaning filenames...", isError: false)
        for i in fileItems.indices {
            fileItems[i].status = .pending
        }
        let recoveryID = OperationRecoveryService.shared.begin(
            tool: "Filename Cleaner",
            title: "Clean Filenames",
            message: lang.selectedLanguage == "ru" ? "Очистка имён файлов была прервана. Уже переименованные файлы останутся в папке." : "Filename cleanup was interrupted. Already renamed files remain in the folder.",
            affectedCount: fileItems.count,
            backupPath: folderPath
        )

        DispatchQueue.global(qos: .userInitiated).async {
            var renamed = 0
            var failed = false
            var updatedItems = fileItems

            for index in updatedItems.indices {
                if failed { break }
                DispatchQueue.main.async {
                    fileItems[index].status = .processing
                    appendLog("Checking: \(fileItems[index].url.lastPathComponent)")
                }

                do {
                    let newURL = try cleanFilenameURL(updatedItems[index].url)
                    if newURL.path != updatedItems[index].url.path {
                        renamed += 1
                        updatedItems[index] = FileItem(url: newURL, status: .done)
                    } else {
                        updatedItems[index].status = .done
                    }
                    DispatchQueue.main.async {
                        fileItems[index].status = .done
                        appendLog("OK: \(newURL.lastPathComponent)")
                    }
                } catch {
                    failed = true
                    DispatchQueue.main.async {
                        fileItems[index].status = .error
                        appendLog("ERROR: \(error.localizedDescription)")
                    }
                }
            }

            DispatchQueue.main.async {
                OperationRecoveryService.shared.finish(recoveryID)
                fileItems = updatedItems
                isProcessing = false
                let message = failed
                    ? (lang.selectedLanguage == "ru" ? "Filename Cleaner остановлен после ошибки. Остальные функции вкладки не затронуты." : "Filename Cleaner stopped after an error. Other tab functions were not affected.")
                    : (lang.selectedLanguage == "ru" ? "Filename Cleaner завершён. Переименовано: \(renamed)." : "Filename Cleaner finished. Renamed: \(renamed).")
                appendLog(message)
                activeNotification = NotificationMessage(text: message, isError: failed)
                OperationHistoryService.shared.record(
                    tool: "Filename Cleaner",
                    title: "Clean Filenames",
                    status: failed ? "FAIL" : "OK",
                    message: message,
                    affectedCount: renamed
                )
            }
        }
    }

    private func cleanFilenameURL(_ url: URL) throws -> URL {
        let baseName = url.deletingPathExtension().lastPathComponent
        let underscoreCount = baseName.filter { $0 == "_" }.count
        guard underscoreCount >= 2 || baseName.contains("_-_") || baseName.contains("__") else { return url }
        let cleanedBase = baseName
            .replacingOccurrences(of: "_+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedBase.isEmpty, cleanedBase != baseName else { return url }
        let newName = url.pathExtension.isEmpty ? cleanedBase : "\(cleanedBase).\(url.pathExtension)"
        let desiredURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        let destination = uniqueDestinationURL(for: desiredURL, originalURL: url)
        if destination.standardized.path == url.standardized.path { return url }
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }

    private func uniqueDestinationURL(for desiredURL: URL, originalURL: URL) -> URL {
        if originalURL.standardized.path == desiredURL.standardized.path ||
            originalURL.path.lowercased() == desiredURL.path.lowercased() {
            return desiredURL
        }
        if !FileManager.default.fileExists(atPath: desiredURL.path) {
            return desiredURL
        }
        let folder = desiredURL.deletingLastPathComponent()
        let base = desiredURL.deletingPathExtension().lastPathComponent
        let ext = desiredURL.pathExtension
        var suffix = 2
        while true {
            let candidateName = ext.isEmpty ? "\(base) \(suffix)" : "\(base) \(suffix).\(ext)"
            let candidate = folder.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }

    private func appendLog(_ line: String) {
        logLines.append("> \(line)")
        if logLines.count > 250 {
            logLines.removeFirst(logLines.count - 250)
        }
    }
}
