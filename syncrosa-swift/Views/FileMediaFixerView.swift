import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
    case applyRenameTemplate
    case importFolderPlaylist
    case importExternalSelection([FolderPlaylistTrack])
}

private enum FileRenameFormat: String, CaseIterable, Hashable {
    case artistTitle
    case trackArtistTitle
    case albumTrackTitle

    var template: String {
        switch self {
        case .artistTitle:
            return "{artist} - {title}"
        case .trackArtistTitle:
            return "{track} {artist} - {title}"
        case .albumTrackTitle:
            return "{album} - {track} {title}"
        }
    }

    func title(language: String) -> String {
        switch self {
        case .artistTitle:
            return language == "ru" ? "Исполнитель - Название" : "Artist - Title"
        case .trackArtistTitle:
            return language == "ru" ? "Номер. Исполнитель - Название" : "Track. Artist - Title"
        case .albumTrackTitle:
            return language == "ru" ? "Альбом - Номер. Название" : "Album - Track. Title"
        }
    }
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
    @State private var folderPlaylistTracks: [FolderPlaylistTrack] = []
    @State private var playlistName: String = ""
    @State private var importProgressText: String = ""
    @State private var renameFormat: FileRenameFormat = .artistTitle
    
    // Checkbox checklist states
    @State private var fixTitle: Bool = true
    @State private var fixArtist: Bool = true
    
    // Select All Binding
    var selectAllBinding: Binding<Bool> {
        Binding<Bool>(
            get: { fixTitle && fixArtist },
            set: { newValue in
                fixTitle = newValue
                fixArtist = newValue
            }
        )
    }

    var folderImportEstimateText: String {
        guard !folderPlaylistTracks.isEmpty else {
            return lang.selectedLanguage == "ru"
                ? "Выберите папку, чтобы увидеть оценку импорта."
                : "Select a folder to estimate import time."
        }
        let totalBytes = folderPlaylistTracks.reduce(Int64(0)) { $0 + $1.fileSize }
        let seconds = FolderPlaylistImportService.shared.estimatedImportSeconds(
            fileCount: folderPlaylistTracks.count,
            totalBytes: totalBytes,
            hddSafeMode: UserDefaults.standard.bool(forKey: "hdd_safe_mode")
        )
        let size = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        let unsupported = folderPlaylistTracks.filter { $0.fileExtension.lowercased() == "flac" }.count
        let base = lang.selectedLanguage == "ru"
            ? "Найдено \(folderPlaylistTracks.count) файлов (\(size)). Оценка импорта: ~\(seconds) сек."
            : "Found \(folderPlaylistTracks.count) files (\(size)). Import estimate: ~\(seconds)s."
        guard unsupported > 0 else { return base }
        return base + (lang.selectedLanguage == "ru"
            ? " FLAC может быть пропущен Music.app."
            : " FLAC may be skipped by Music.app.")
    }

    private var renameTemplate: String {
        renameFormat.template
    }

    private var renameFormatTitle: String {
        renameFormat.title(language: lang.selectedLanguage)
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
                    SyncrosaSectionLabel(text: lang.selectedLanguage == "ru" ? "ДАННЫЕ ДЛЯ ИМЕНИ ФАЙЛА" : "DATA USED FOR FILENAMES", systemImage: "checklist")

                    Text(lang.selectedLanguage == "ru"
                         ? "Syncrosa ищет исполнителя и название, затем безопасно переименовывает файл. Встроенные аудиотеги этой операцией не перезаписываются."
                         : "Syncrosa looks up artist and title, then safely renames the file. This operation does not rewrite embedded audio tags.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Toggle(isOn: selectAllBinding) {
                        Text(lang.selectedLanguage == "ru" ? "Выбрать все" : "Select All")
                            .fontWeight(.bold)
                    }
                    .toggleStyle(SyncrosaCheckboxToggleStyle())
                    
                    Divider()
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], alignment: .leading, spacing: 12) {
                        Toggle(lang.selectedLanguage == "ru" ? "Название" : "Title", isOn: $fixTitle)
                            .toggleStyle(SyncrosaCheckboxToggleStyle())
                        Toggle(lang.selectedLanguage == "ru" ? "Исполнитель" : "Artist", isOn: $fixArtist)
                            .toggleStyle(SyncrosaCheckboxToggleStyle())
                    }
                }
                .syncrosaCard()

                VStack(alignment: .leading, spacing: 14) {
                    SyncrosaSectionLabel(text: lang.t("rename_format").uppercased(), systemImage: "textformat.abc")
                    Text(lang.selectedLanguage == "ru"
                         ? "Выберите готовый безопасный формат. Syncrosa сохранит расширение каждого файла."
                         : "Choose a safe, ready-made format. Syncrosa keeps each file extension.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    SyncrosaGlassMenu(
                        selection: $renameFormat,
                        options: FileRenameFormat.allCases.map {
                            SyncrosaMenuOption(title: $0.title(language: lang.selectedLanguage), value: $0)
                        },
                        minWidth: 280,
                        isDisabled: isProcessing
                    )

                    if let preview = renameTemplatePreview {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(lang.selectedLanguage == "ru" ? "Предварительный просмотр" : "Preview")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(preview.old)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.down")
                                    .foregroundStyle(.secondary)
                                Text(preview.new)
                                    .font(.caption.monospaced())
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .padding(12)
                        .background(SyncrosaTheme.subtleBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    Button(action: { presentSafetyPreview(.applyRenameTemplate) }) {
                        Label(lang.t("apply_rename"), systemImage: "checkmark.shield")
                    }
                    .buttonStyle(SyncrosaPrimaryButtonStyle())
                    .disabled(fileItems.isEmpty || isProcessing)
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
                            Label(lang.selectedLanguage == "ru" ? "Найти данные и переименовать" : "Look Up & Rename", systemImage: "wrench.and.screwdriver")
                        }
                        .buttonStyle(SyncrosaPrimaryButtonStyle())
                        .disabled(fileItems.isEmpty || isProcessing || (!fixTitle && !fixArtist))

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
                    .toggleStyle(SyncrosaCheckboxToggleStyle())
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

                    SyncrosaLogConsole(title: lang.t("log").uppercased(), lines: logLines, minHeight: 130)
                
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

    var renameTemplatePreview: (old: String, new: String)? {
        guard let item = fileItems.first,
              let newPath = LibraryToolkitService.shared.renamedPath(
                for: localSnapshot(for: item.url),
                template: renameTemplate
              ) else {
            return nil
        }
        return (item.url.lastPathComponent, URL(fileURLWithPath: newPath).lastPathComponent)
    }
    
    var helpSheetView: some View {
        SyncrosaHelpSheet(
            title: lang.t("folder_fix"),
            summary: lang.selectedLanguage == "ru"
                ? "Исправляет метаданные и имена локальных музыкальных файлов только в выбранной папке и её подпапках."
                : "Repairs metadata and filenames only inside the selected local folder and its subfolders.",
            steps: lang.selectedLanguage == "ru" ? [
                "Выберите, использовать ли найденного исполнителя и название в новом имени файла.",
                "Выберите папку. Syncrosa покажет найденные музыкальные файлы.",
                "Для метаданных нажмите «Исправить все файлы»; для подчёркиваний используйте отдельную очистку имён.",
                "Для пакетного переименования выберите понятный формат и проверьте пример перед подтверждением."
            ] : [
                "Choose whether the discovered artist and title should be used in the new filename.",
                "Select a folder. Syncrosa lists the music files it finds.",
                "Use Fix All Files for metadata; use Clean Filenames separately for accidental underscores.",
                "For batch renaming, choose a named format and review the example before confirming."
            ],
            notes: lang.selectedLanguage == "ru" ? [
                "Работайте с копией папки или заранее сделайте backup.",
                "Переименование создаёт пакет отмены в Recovery Center.",
                "FLAC поддерживается не всеми действиями Music и системными метаданными."
            ] : [
                "Work on a copied folder or make a backup first.",
                "Renaming creates an undo package in Recovery Center.",
                "FLAC is not supported by every Music or system metadata operation."
            ],
            dismiss: { showHelp = false }
        )
    }
    
    @ViewBuilder
    func statusIcon(for status: FileStatus) -> some View {
        switch status {
        case .pending:
            Text(lang.t("waiting").uppercased())
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
        isProcessing = true
        activeNotification = NotificationMessage(
            text: lang.selectedLanguage == "ru" ? "Сканирование папки..." : "Scanning folder...",
            isError: false
        )
        DispatchQueue.global(qos: .utility).async {
            let scannedTracks = FolderPlaylistImportService.shared.scanFolder(url)
            let matches = scannedTracks.map { FileItem(url: url.appendingPathComponent($0.relativePath)) }
            DispatchQueue.main.async {
                self.fileItems = matches
                self.folderPlaylistTracks = scannedTracks
                self.importProgressText = ""
                self.logLines.removeAll()
                self.appendLog("Scanned folder recursively: \(matches.count) music files.")
                self.isProcessing = false

                if matches.isEmpty {
                    self.activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Музыкальные файлы не найдены." : "No music files found.", isError: true)
                } else {
                    self.activeNotification = NotificationMessage(text: lang.t("files_to_process", matches.count), isError: false)
                }
            }
        }
    }

    private func presentSafetyPreview(_ action: FileFixerSafetyAction) {
        guard !fileItems.isEmpty else { return }
        pendingSafetyAction = action
        let checkedTags = [
            fixTitle ? (lang.selectedLanguage == "ru" ? "Название" : "Title") : nil,
            fixArtist ? (lang.selectedLanguage == "ru" ? "Исполнитель" : "Artist") : nil
        ].compactMap { $0 }.joined(separator: ", ")

        switch action {
        case .fixMetadata:
            safetyPreview = SafetyPreviewRequest(
                title: lang.selectedLanguage == "ru" ? "Найти данные и переименовать файлы?" : "Look up data and rename files?",
                message: lang.selectedLanguage == "ru" ? "Syncrosa найдёт исполнителя и название, затем переименует файлы. Встроенные аудиотеги не перезаписываются. Работайте с копией или заранее сделайте backup." : "Syncrosa will look up artist and title, then rename files. Embedded audio tags are not rewritten. Work on a copy or make a backup first.",
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
        case .applyRenameTemplate:
            let examples = fileItems.prefix(5).compactMap { item -> String? in
                guard let newPath = LibraryToolkitService.shared.renamedPath(for: localSnapshot(for: item.url), template: renameTemplate) else { return nil }
                return "\(item.url.lastPathComponent) -> \(URL(fileURLWithPath: newPath).lastPathComponent)"
            }.joined(separator: "\n")
            safetyPreview = SafetyPreviewRequest(
                title: lang.selectedLanguage == "ru" ? "Применить шаблон переименования?" : "Apply rename template?",
                message: lang.selectedLanguage == "ru" ? "Syncrosa переименует локальные файлы по шаблону. Перед изменением будет создан undo package в Recovery Center." : "Syncrosa will rename local files from the template. An undo package will be created in Recovery Center before changes.",
                details: [
                    SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Папка" : "Folder", value: folderPath),
                    SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Файлов" : "Files", value: "\(fileItems.count)"),
                    SafetyPreviewDetail(title: lang.t("rename_format"), value: renameFormatTitle),
                    SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Пример" : "Example", value: examples.isEmpty ? "-" : examples)
                ],
                confirmTitle: lang.selectedLanguage == "ru" ? "Переименовать" : "Rename",
                isDestructive: true
            )
        case .importFolderPlaylist:
            let selectedName = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
            safetyPreview = SafetyPreviewRequest(
                title: lang.selectedLanguage == "ru" ? "Создать плейлист из папки?" : "Create playlist from folder?",
                message: lang.selectedLanguage == "ru" ? "Syncrosa импортирует поддерживаемые файлы в Music и создаст/обновит плейлист с указанным именем." : "Syncrosa will import supported files into Music and create/update a playlist with the chosen name.",
                details: [
                    SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Папка" : "Folder", value: folderPath),
                    SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Плейлист" : "Playlist", value: selectedName),
                    SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Файлов" : "Files", value: "\(folderPlaylistTracks.count)"),
                    SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Оценка" : "Estimate", value: folderImportEstimateText)
                ],
                confirmTitle: lang.selectedLanguage == "ru" ? "Создать" : "Create",
                isDestructive: false
            )
        case .importExternalSelection(let selectedTracks):
            let selectedName = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
            safetyPreview = SafetyPreviewRequest(
                title: lang.selectedLanguage == "ru" ? "Создать AI-плейлист из JSON?" : "Create AI playlist from JSON?",
                message: lang.selectedLanguage == "ru" ? "Syncrosa импортирует только треки, выбранные во внешнем JSON-файле." : "Syncrosa will import only the tracks selected in the external JSON file.",
                details: [
                    SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Папка" : "Folder", value: folderPath),
                    SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Плейлист" : "Playlist", value: selectedName),
                    SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Выбрано" : "Selected", value: "\(selectedTracks.count)")
                ],
                confirmTitle: lang.selectedLanguage == "ru" ? "Собрать" : "Build",
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
        case .applyRenameTemplate:
            applyRenameTemplate()
        case .importFolderPlaylist:
            importPlaylistFromFolder(tracks: folderPlaylistTracks, title: "Import Folder Playlist")
        case .importExternalSelection(let selectedTracks):
            importPlaylistFromFolder(tracks: selectedTracks, title: "Import External AI Playlist")
        case .none:
            break
        }
    }

    private func localSnapshot(for url: URL) -> LibraryToolkitTrackSnapshot {
        let parsed = parseFilename(url.deletingPathExtension().lastPathComponent)
        return LibraryToolkitTrackSnapshot(
            persistentID: url.path,
            title: parsed.title,
            artist: parsed.artist,
            album: "",
            albumArtist: "",
            genre: "",
            composer: "",
            comments: "",
            path: url.path,
            kind: url.pathExtension.uppercased(),
            year: 0,
            trackNumber: parsed.trackNumber,
            discNumber: 0,
            bpm: 0,
            rating: 0,
            size: (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0,
            hasArtwork: false,
            fileExists: FileManager.default.fileExists(atPath: url.path)
        )
    }

    private func parseFilename(_ name: String) -> (artist: String, title: String, trackNumber: Int) {
        let cleaned = name.replacingOccurrences(of: "_", with: " ")
        let scanner = Scanner(string: cleaned)
        var number = 0
        if scanner.scanInt(&number), number > 0 {
            let rest = String(cleaned[scanner.currentIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return splitArtistTitle(rest, trackNumber: number)
        }
        return splitArtistTitle(cleaned, trackNumber: 0)
    }

    private func splitArtistTitle(_ value: String, trackNumber: Int) -> (artist: String, title: String, trackNumber: Int) {
        for separator in [" - ", " – ", " — "] where value.contains(separator) {
            let parts = value.components(separatedBy: separator)
            if parts.count >= 2 {
                return (
                    parts[0].trimmingCharacters(in: .whitespacesAndNewlines),
                    parts.dropFirst().joined(separator: separator).trimmingCharacters(in: .whitespacesAndNewlines),
                    trackNumber
                )
            }
        }
        return ("", value.trimmingCharacters(in: .whitespacesAndNewlines), trackNumber)
    }

    private func applyRenameTemplate() {
        isProcessing = true
        logLines.removeAll()
        appendLog("Applying rename format: \(renameFormatTitle)")
        let previews = fileItems.compactMap { item -> LibraryToolkitChangePreview? in
            let snapshot = localSnapshot(for: item.url)
            guard let newPath = LibraryToolkitService.shared.renamedPath(for: snapshot, template: renameTemplate),
                  newPath != item.url.path else {
                return nil
            }
            return LibraryToolkitChangePreview(
                id: UUID(),
                trackID: item.url.path,
                trackTitle: item.url.lastPathComponent,
                field: "filename",
                oldValue: item.url.path,
                newValue: newPath,
                source: "Folder Rename Template",
                risk: "medium",
                path: item.url.path
            )
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let package = try LibraryToolkitService.shared.applyRenamePreviews(previews)
                DispatchQueue.main.async {
                    appendLog("Renamed files: \(package.operations.count)")
                    activeNotification = NotificationMessage(text: "Rename template applied.", isError: false)
                    OperationHistoryService.shared.record(
                        tool: "Folder Fixer",
                        title: "Apply Rename Template",
                        status: "OK",
                        message: "Renamed \(package.operations.count) files.",
                        affectedCount: package.operations.count,
                        backupPath: folderPath
                    )
                    if !folderPath.isEmpty {
                        scanFolder(URL(fileURLWithPath: folderPath, isDirectory: true))
                    } else {
                        isProcessing = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    appendLog("ERROR: \(error.localizedDescription)")
                    activeNotification = NotificationMessage(text: error.localizedDescription, isError: true)
                    isProcessing = false
                }
            }
        }
    }

    func exportFolderManifest() {
        guard !folderPath.isEmpty, !folderPlaylistTracks.isEmpty else { return }
        let folderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Syncrosa-\(folderURL.lastPathComponent)-AI-Manifest.json"
        panel.title = lang.selectedLanguage == "ru" ? "Сохранить JSON для внешнего AI" : "Save JSON for external AI"
        if panel.runModal() == .OK, let destination = panel.url {
            do {
                let manifest = FolderPlaylistImportService.shared.buildManifest(folderURL: folderURL, tracks: folderPlaylistTracks)
                try FolderPlaylistImportService.shared.writeManifest(manifest, to: destination)
                logLines.removeAll()
                appendLog("Exported AI manifest: \(destination.path)")
                appendLog("Give the saved manifest to an AI assistant and ask it to return a Syncrosa playlist selection file.")
                activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "JSON для AI сохранён." : "AI JSON manifest saved.", isError: false)
            } catch {
                activeNotification = NotificationMessage(text: error.localizedDescription, isError: true)
            }
        }
    }

    func importAISelection() {
        guard !folderPlaylistTracks.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.title = lang.selectedLanguage == "ru" ? "Выберите JSON с выбором треков" : "Choose playlist selection JSON"
        if panel.runModal() == .OK, let selectionURL = panel.url {
            do {
                let selection = try FolderPlaylistImportService.shared.readSelection(from: selectionURL)
                let selectedTracks = FolderPlaylistImportService.shared.selectedTracks(from: selection, availableTracks: folderPlaylistTracks)
                if let name = selection.playlistName, playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    playlistName = name
                }
                guard !selectedTracks.isEmpty else {
                    activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "JSON не содержит треки, которые совпали с выбранной папкой." : "The JSON did not match any tracks in the selected folder.", isError: true)
                    return
                }
                guard !playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Введите название плейлиста." : "Enter a playlist name.", isError: true)
                    return
                }
                presentSafetyPreview(.importExternalSelection(selectedTracks))
            } catch {
                activeNotification = NotificationMessage(text: error.localizedDescription, isError: true)
            }
        }
    }

    func importPlaylistFromFolder(tracks: [FolderPlaylistTrack], title: String) {
        guard !folderPath.isEmpty, !tracks.isEmpty else { return }
        let folderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
        let cleanPlaylistName = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPlaylistName.isEmpty else { return }

        let resolved = FolderPlaylistImportService.shared.importableURLs(for: tracks, folderURL: folderURL)
        guard !resolved.urls.isEmpty else {
            activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Нет поддерживаемых файлов для импорта в Music." : "No supported files to import into Music.", isError: true)
            return
        }

        isProcessing = true
        logLines.removeAll()
        importProgressText = ""
        appendLog("Starting playlist import: \(cleanPlaylistName)")
        appendLog("Files selected: \(tracks.count). Importable: \(resolved.urls.count). Skipped before import: \(resolved.skipped.count).")
        activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Импортирую папку в Music..." : "Importing folder into Music...", isError: false)

        let recoveryID = OperationRecoveryService.shared.begin(
            tool: "Folder Playlist Importer",
            title: title,
            message: lang.selectedLanguage == "ru" ? "Импорт папки в Music был прерван. Проверьте Recovery Center и созданный плейлист." : "Folder import into Music was interrupted. Check Recovery Center and the created playlist.",
            affectedCount: resolved.urls.count,
            backupPath: folderPath
        )

        FolderPlaylistImportService.shared.importFolderTracks(
            playlistName: cleanPlaylistName,
            fileURLs: resolved.urls,
            hddSafeMode: UserDefaults.standard.bool(forKey: "hdd_safe_mode")
        ) { progress in
            importProgressText = lang.selectedLanguage == "ru"
                ? "Импорт \(progress.current)/\(progress.total): \(progress.fileName)"
                : "Import \(progress.current)/\(progress.total): \(progress.fileName)"
            appendLog(importProgressText)
        } completion: { result in
            OperationRecoveryService.shared.finish(recoveryID)
            isProcessing = false
            let message = lang.selectedLanguage == "ru"
                ? "Плейлист «\(cleanPlaylistName)» готов. Добавлено: \(result.importedCount), пропущено: \(result.skippedCount + resolved.skipped.count), ошибок: \(result.errors.count)."
                : "Playlist \"\(cleanPlaylistName)\" is ready. Added: \(result.importedCount), skipped: \(result.skippedCount + resolved.skipped.count), errors: \(result.errors.count)."
            appendLog(message)
            for error in result.errors.prefix(12) {
                appendLog("ERROR: \(error)")
            }
            activeNotification = NotificationMessage(text: message, isError: result.importedCount == 0)
            OperationHistoryService.shared.record(
                tool: "Folder Playlist Importer",
                title: title,
                status: result.errors.isEmpty ? "OK" : "WARN",
                message: message,
                affectedCount: result.importedCount,
                backupPath: folderPath
            )
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
            "album": downloadCovers,
            "title": fixTitle,
            "artist": fixArtist,
            "genre": false,
            "trackNumber": false,
            "lyrics": false
        ]
        let recoveryID = OperationRecoveryService.shared.begin(
            tool: "Folder Fixer",
            title: "Fix Folder Metadata",
            message: lang.selectedLanguage == "ru" ? "Исправление метаданных файлов было прервано. Проверьте папку и историю операций." : "Local metadata repair was interrupted. Check the folder and Operation History.",
            affectedCount: fileItems.count,
            backupPath: folderPath
        )
        DispatchQueue.global().async {
            var succeeded = 0
            var failed = 0
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
                if result.success {
                    succeeded += 1
                } else {
                    failed += 1
                }
                
                DispatchQueue.main.async {
                    fileItems[index].status = result.success ? .done : .error
                    appendLog(result.success ? "OK: \(fileItems[index].url.lastPathComponent)" : "ERROR: \(fileItems[index].url.lastPathComponent)")
                }
            }
            
            DispatchQueue.main.async {
                OperationRecoveryService.shared.finish(recoveryID)
                isProcessing = false
                let message = failed == 0
                    ? (lang.selectedLanguage == "ru" ? "Готово. Переименовано файлов: \(succeeded)." : "Done. Renamed files: \(succeeded).")
                    : (lang.selectedLanguage == "ru" ? "Завершено. Успешно: \(succeeded), ошибок: \(failed)." : "Finished. Successful: \(succeeded), failed: \(failed).")
                appendLog(message)
                activeNotification = NotificationMessage(text: message, isError: failed > 0)
                OperationHistoryService.shared.record(
                    tool: "Folder Fixer",
                    title: "Look Up and Rename Files",
                    status: failed == 0 ? "OK" : "WARN",
                    message: message,
                    affectedCount: succeeded
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
