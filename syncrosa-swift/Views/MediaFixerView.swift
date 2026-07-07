import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MediaFixerView: View {
    @ObservedObject var lang = LocalizationService.shared
    @State private var isAnalyzing: Bool = false
    @State private var activeNotification: NotificationMessage? = nil
    @State private var mergeCandidates: [MergeGroup] = []
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var showHelp: Bool = false
    
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
    
    struct MergeGroup: Identifiable {
        let id = UUID()
        let mainAlbum: String
        let artist: String
        let trackIDs: [String]
    }
    
    var body: some View {
        SyncrosaPage {
            SyncrosaPageHeader(
                title: lang.t("media_fixer"),
                systemImage: "wrench.and.screwdriver",
                subtitle: lang.selectedLanguage == "ru" ? "Исправление метаданных внутри Music с выбором конкретных тегов." : "Repair Music metadata while choosing exactly which tags may change.",
                helpAction: { showHelp = true }
            )
                
                // Checklist Card (New requirement)
                VStack(alignment: .leading, spacing: 15) {
                    SyncrosaSectionLabel(text: lang.selectedLanguage == "ru" ? "ВЫБЕРИТЕ ТЕГИ ДЛЯ ОБНОВЛЕНИЯ" : "SELECT TAGS TO UPDATE", systemImage: "checklist")
                    
                    Toggle(isOn: selectAllBinding) {
                        Text(lang.selectedLanguage == "ru" ? "Выбрать все" : "Select All")
                            .fontWeight(.bold)
                    }
                    .toggleStyle(SyncrosaCheckboxToggleStyle())
                    
                    Divider()
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], alignment: .leading, spacing: 12) {
                        Toggle(lang.selectedLanguage == "ru" ? "Альбом" : "Album", isOn: $fixAlbum)
                            .toggleStyle(SyncrosaCheckboxToggleStyle())
                        Toggle(lang.selectedLanguage == "ru" ? "Название" : "Title", isOn: $fixTitle)
                            .toggleStyle(SyncrosaCheckboxToggleStyle())
                        Toggle(lang.selectedLanguage == "ru" ? "Исполнитель" : "Artist", isOn: $fixArtist)
                            .toggleStyle(SyncrosaCheckboxToggleStyle())
                        Toggle(lang.selectedLanguage == "ru" ? "Жанр" : "Genre", isOn: $fixGenre)
                            .toggleStyle(SyncrosaCheckboxToggleStyle())
                        Toggle(lang.selectedLanguage == "ru" ? "Номер трека" : "Track Number", isOn: $fixTrackNumber)
                            .toggleStyle(SyncrosaCheckboxToggleStyle())
                        Toggle(lang.selectedLanguage == "ru" ? "Текст песен" : "Lyrics", isOn: $fixLyrics)
                            .toggleStyle(SyncrosaCheckboxToggleStyle())
                    }
                }
                .syncrosaCard()
                
                // Card 1: Controls
                VStack(alignment: .leading, spacing: 15) {
                    Text(lang.selectedLanguage == "ru" ? "Поиск разбитых альбомов и восстановление метаданных через iTunes Search API." : "Identify split albums and restore missing metadata via iTunes Search API.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    SyncrosaAdaptiveRow(spacing: 15) {
                        Button(action: analyzeLibrary) {
                            if isAnalyzing {
                                ProgressView().controlSize(.small)
                            } else {
                                Label(lang.selectedLanguage == "ru" ? "Анализ медиатеки" : "Analyze Library", systemImage: "magnifyingglass")
                            }
                        }
                        .buttonStyle(SyncrosaSecondaryButtonStyle())
                        .disabled(isAnalyzing)
                        
                        Button(action: updateMetadata) {
                            Label(lang.selectedLanguage == "ru" ? "Обновить метаданные" : "Update Metadata", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(SyncrosaPrimaryButtonStyle())
                        .disabled(isAnalyzing || (!fixAlbum && !fixTitle && !fixArtist && !fixGenre && !fixTrackNumber && !fixLyrics))
                        
                        Button(action: fixMetadata) {
                            Label(lang.selectedLanguage == "ru" ? "Объединить альбомы" : "Merge Selected", systemImage: "wrench.and.screwdriver")
                        }
                        .buttonStyle(SyncrosaSecondaryButtonStyle())
                        .disabled(mergeCandidates.isEmpty || isAnalyzing)
                    }
                }
                .syncrosaCard()

                FolderPlaylistImporterCard()
                
                // Card 2: Split Album Results
                VStack(alignment: .leading, spacing: 10) {
                    SyncrosaSectionLabel(text: lang.selectedLanguage == "ru" ? "РЕЗУЛЬТАТЫ ПОИСКА РАЗБИТЫХ АЛЬБОМОВ" : "SPLIT ALBUMS SEARCH RESULTS", systemImage: "rectangle.stack")
                    
                    if mergeCandidates.isEmpty {
                        SyncrosaEmptyState(
                            systemImage: "music.note.list",
                            title: lang.selectedLanguage == "ru" ? "Проблем с разбитыми альбомами не обнаружено." : "No split album issues detected yet.",
                            message: lang.selectedLanguage == "ru" ? "Запустите анализ, чтобы проверить медиатеку." : "Run analysis to scan your library."
                        )
                    } else {
                        ForEach(mergeCandidates) { group in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(group.mainAlbum)
                                        .fontWeight(.bold)
                                    Text(group.artist)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("\(group.trackIDs.count) tracks")
                                    .font(.system(size: 10))
                                    .padding(4)
                                    .background(SyncrosaTheme.accent.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                }
                .syncrosaCard()
                
                Spacer()
        }
        .notification(message: $activeNotification)
        .alert(isPresented: $showAlert) {
            Alert(title: Text(lang.t("media_fixer")), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $showHelp) {
            helpSheetView
        }
    }
    
    var helpSheetView: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(lang.selectedLanguage == "ru" ? "Инструкция: Очистка медиатеки" : "Help: Library Cleanup")
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
                         "Этот раздел предоставляет инструменты для исправления информации о песнях прямо в приложении «Музыка» (Apple Music).\n\n" +
                         "Инструкция по использованию:\n" +
                         "1. Выберите в панели тегов те свойства, которые вы хотите обновить (Альбом, Название, Исполнитель, Жанр, Номер трека, Текст песен).\n" +
                         "2. Нажмите «Обновить метаданные» для того чтобы для каждого трека в вашей библиотеке автоматически запросить корректную информацию из iTunes Search API и Lyrics API, после чего записать только выбранные теги.\n" +
                         "3. Для исправления разбитых альбомов нажмите «Анализ медиатеки». Если будут найдены треки одного альбома с разным написанием названия альбома, вы сможете объединить их, нажав «Объединить альбомы»." :
                         
                         "This section provides tools to correct song details directly inside your Music app (Apple Music).\n\n" +
                         "How to use:\n" +
                         "1. Check the checkboxes for the specific tags you want to update (Album, Title, Artist, Genre, Track Number, Lyrics).\n" +
                         "2. Click 'Update Metadata' to automatically scan your music library, query the iTunes Search API and Lyrics API for each track, and write only the checked tags back to the Music app.\n" +
                         "3. To fix split albums, click 'Analyze Library'. If different versions of the same album name are detected, you can merge them by clicking 'Merge Selected'."
                    )
                    .font(.body)
                }
            }
            .frame(minWidth: 450, minHeight: 300)
        }
        .padding()
    }
    
    func analyzeLibrary() {
        isAnalyzing = true
        activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Сканирование медиатеки..." : "Scanning Music Library...", isError: false)
        
        DispatchQueue.global().async {
            guard let libraryCount = MusicService.shared.getLibraryTrackCount() else {
                DispatchQueue.main.async {
                    isAnalyzing = false
                    alertMessage = lang.selectedLanguage == "ru" ? "Не удалось прочитать медиатеку Music, или она пуста." : "Could not read your Music library, or it may be empty."
                    showAlert = true
                    activeNotification = nil
                }
                return
            }

            guard libraryCount > 0 else {
                DispatchQueue.main.async {
                    isAnalyzing = false
                    alertMessage = lang.selectedLanguage == "ru" ? "В Music нет треков. Анализировать пока нечего." : "Music has no tracks. There is nothing to analyze yet."
                    showAlert = true
                    activeNotification = nil
                }
                return
            }

            let tracks = MusicService.shared.getAllTracks { current, total in
                DispatchQueue.main.async {
                    activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Сканирование: \(current)/\(total)" : "Scanning: \(current)/\(total)", isError: false)
                }
            }
            
            DispatchQueue.main.async {
                isAnalyzing = false
                if tracks.isEmpty {
                    alertMessage = lang.selectedLanguage == "ru" ? "Music прочитан, но доступных треков не вернул." : "Music was read, but no usable tracks were returned."
                    showAlert = true
                    activeNotification = nil
                } else {
                    self.mergeCandidates = findMergeCandidates(tracks)
                    if mergeCandidates.isEmpty {
                        alertMessage = lang.selectedLanguage == "ru" ? "Анализ завершен. Ошибок не найдено." : "Analysis complete. No split albums found."
                        showAlert = true
                        activeNotification = nil
                    } else {
                        activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Найдено проблем: \(mergeCandidates.count)" : "Found \(mergeCandidates.count) issues.", isError: false)
                    }
                }
            }
        }
    }
    
    func findMergeCandidates(_ tracks: [MusicTrack]) -> [MergeGroup] {
        var groups: [String: [MusicTrack]] = [:]
        
        for track in tracks {
            guard !track.album.isEmpty else { continue }
            let key = "\(track.artist.lowercased())|\(normalizeText(track.album))"
            groups[key, default: []].append(track)
        }
        
        var candidates: [MergeGroup] = []
        for (_, tracksInGroup) in groups {
            let albumVariants = Set(tracksInGroup.map { $0.album })
            if albumVariants.count > 1 {
                let counts = tracksInGroup.reduce(into: [:]) { $0[$1.album, default: 0] += 1 }
                let mainAlbum = counts.max(by: { $0.value < $1.value })?.key ?? tracksInGroup[0].album
                
                candidates.append(MergeGroup(
                    mainAlbum: mainAlbum,
                    artist: tracksInGroup[0].artist,
                    trackIDs: tracksInGroup.map { $0.persistentID }
                ))
            }
        }
        return candidates
    }
    
    func normalizeText(_ text: String) -> String {
        let mutableString = NSMutableString(string: text)
        CFStringTransform(mutableString as CFMutableString, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutableString as CFMutableString, nil, kCFStringTransformStripDiacritics, false)
        
        let lower = (mutableString as String).lowercased()
        let clean = lower.replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
        return clean.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
    
    func fixMetadata() {
        isAnalyzing = true
        let total = mergeCandidates.count
        var current = 0
        
        DispatchQueue.global().async {
            for group in mergeCandidates {
                for pid in group.trackIDs {
                    let script = "tell application \"Music\" to set album of (some track whose persistent ID is \"\(pid)\") to \"\(group.mainAlbum.replacingOccurrences(of: "\"", with: "\\\""))\""
                    _ = MusicService.shared.runAppleScript(script)
                }
                current += 1
                DispatchQueue.main.async {
                    activeNotification = NotificationMessage(text: "Fixing: \(current)/\(total)", isError: false)
                }
            }
            
            DispatchQueue.main.async {
                isAnalyzing = false
                mergeCandidates = []
                alertMessage = lang.selectedLanguage == "ru" ? "Все альбомы успешно объединены!" : "All albums successfully merged!"
                showAlert = true
                activeNotification = nil
            }
        }
    }
    
    func updateMetadata() {
        if UserDefaults.standard.bool(forKey: "only_local_mode") {
            alertMessage = lang.selectedLanguage == "ru" ? "Only Local Mode включён. Сетевое обновление метаданных пропущено." : "Only Local Mode is enabled. Online metadata update was skipped."
            showAlert = true
            OperationHistoryService.shared.record(
                tool: "Media Fixer",
                title: "Update Metadata",
                status: "WARN",
                message: alertMessage,
                affectedCount: 0
            )
            return
        }

        isAnalyzing = true
        activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Загрузка списка треков..." : "Loading track list...", isError: false)
        
        DispatchQueue.global().async {
            guard let libraryCount = MusicService.shared.getLibraryTrackCount() else {
                DispatchQueue.main.async {
                    isAnalyzing = false
                    alertMessage = lang.selectedLanguage == "ru" ? "Не удалось прочитать медиатеку Music, или она пуста." : "Could not read your Music library, or it may be empty."
                    showAlert = true
                    activeNotification = nil
                }
                return
            }

            guard libraryCount > 0 else {
                DispatchQueue.main.async {
                    isAnalyzing = false
                    alertMessage = lang.selectedLanguage == "ru" ? "В Music нет треков. Обновлять метаданные пока не у чего." : "Music has no tracks. There is no metadata to update."
                    showAlert = true
                    activeNotification = nil
                }
                return
            }

            let tracks = MusicService.shared.getAllTracks { _, _ in }
            guard !tracks.isEmpty else {
                DispatchQueue.main.async {
                    isAnalyzing = false
                    alertMessage = lang.selectedLanguage == "ru" ? "Music прочитан, но доступных треков не вернул." : "Music was read, but no usable tracks were returned."
                    showAlert = true
                    activeNotification = nil
                }
                return
            }
            
            let total = tracks.count
            var current = 0
            
            for track in tracks {
                current += 1
                DispatchQueue.main.async {
                    activeNotification = NotificationMessage(
                        text: lang.selectedLanguage == "ru" ? "Обновление: \(current)/\(total) (\(track.name))" : "Updating: \(current)/\(total) (\(track.name))",
                        isError: false
                    )
                }
                
                // Wrap each track's operation safely.
                let semaphore = DispatchSemaphore(value: 0)
                var propertiesToUpdate: [String: String] = [:]
                
                MetadataService.shared.fetchMetadata(for: track.name, artist: track.artist) { result in
                    if let res = result {
                        if fixAlbum, let album = res.collectionName {
                            propertiesToUpdate["album"] = album
                        }
                        if fixTitle, let name = res.trackName {
                            propertiesToUpdate["title"] = name
                        }
                        if fixArtist, let artist = res.artistName {
                            propertiesToUpdate["artist"] = artist
                        }
                        if fixGenre, let genre = res.primaryGenreName {
                            propertiesToUpdate["genre"] = genre
                        }
                        if fixTrackNumber, let trkNum = res.trackNumber {
                            propertiesToUpdate["trackNumber"] = "\(trkNum)"
                        }
                    }
                    semaphore.signal()
                }
                _ = semaphore.wait(timeout: .now() + 5.0)
                
                if fixLyrics {
                    let semLyrics = DispatchSemaphore(value: 0)
                    LyricsService.shared.fetchLyrics(artist: track.artist, title: track.name) { lyrics in
                        if let ly = lyrics, !ly.isEmpty {
                            propertiesToUpdate["lyrics"] = ly
                        }
                        semLyrics.signal()
                    }
                    _ = semLyrics.wait(timeout: .now() + 5.0)
                }
                
                if !propertiesToUpdate.isEmpty {
                    let success = MusicService.shared.updateTrack(persistentID: track.persistentID, properties: propertiesToUpdate)
                    if !success {
                        print("Warning: failed to update track \(track.name)")
                    }
                }
            }
            
            DispatchQueue.main.async {
                isAnalyzing = false
                alertMessage = lang.selectedLanguage == "ru" ? "Обновление метаданных завершено!" : "Metadata update complete!"
                showAlert = true
                activeNotification = nil
                OperationHistoryService.shared.record(
                    tool: "Media Fixer",
                    title: "Update Metadata",
                    status: "OK",
                    message: alertMessage,
                    affectedCount: total
                )
            }
        }
    }
}

private enum FolderPlaylistImportAction {
    case importFolder
    case importExternalSelection([FolderPlaylistTrack])
}

private struct FolderPlaylistImporterCard: View {
    @ObservedObject private var lang = LocalizationService.shared

    @State private var folderPath = ""
    @State private var tracks: [FolderPlaylistTrack] = []
    @State private var playlistName = ""
    @State private var isProcessing = false
    @State private var logLines: [String] = []
    @State private var importProgressText = ""
    @State private var activeNotification: NotificationMessage? = nil
    @State private var safetyPreview: SafetyPreviewRequest? = nil
    @State private var pendingAction: FolderPlaylistImportAction? = nil

    private var folderURL: URL? {
        folderPath.isEmpty ? nil : URL(fileURLWithPath: folderPath, isDirectory: true)
    }

    private var estimateText: String {
        guard !tracks.isEmpty else {
            return lang.selectedLanguage == "ru"
                ? "Выберите папку, чтобы увидеть оценку импорта."
                : "Select a folder to estimate import time."
        }
        let totalBytes = tracks.reduce(Int64(0)) { $0 + $1.fileSize }
        let seconds = FolderPlaylistImportService.shared.estimatedImportSeconds(
            fileCount: tracks.count,
            totalBytes: totalBytes,
            hddSafeMode: UserDefaults.standard.bool(forKey: "hdd_safe_mode")
        )
        let size = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        let unsupported = tracks.filter { $0.fileExtension.lowercased() == "flac" }.count
        let base = lang.selectedLanguage == "ru"
            ? "Найдено \(tracks.count) файлов (\(size)). Оценка импорта: ~\(seconds) сек."
            : "Found \(tracks.count) files (\(size)). Import estimate: ~\(seconds)s."
        guard unsupported > 0 else { return base }
        return base + (lang.selectedLanguage == "ru"
            ? " FLAC может быть пропущен Music.app."
            : " FLAC may be skipped by Music.app.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            SyncrosaSectionLabel(
                text: lang.selectedLanguage == "ru" ? "ИМПОРТ ПАПКИ КАК ПЛЕЙЛИСТ" : "IMPORT FOLDER AS PLAYLIST",
                systemImage: "square.and.arrow.down.on.square"
            )

            Text(lang.selectedLanguage == "ru"
                 ? "Создайте плейлист Music из локальной папки или экспортируйте JSON-манифест для внешнего AI-выбора."
                 : "Create a Music playlist from a local folder, or export a JSON manifest for an external AI selection.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            SyncrosaAdaptiveRow(spacing: 12) {
                TextField(lang.selectedLanguage == "ru" ? "Папка не выбрана" : "No folder selected", text: $folderPath)
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)

                Button(action: selectFolder) {
                    Label(lang.selectedLanguage == "ru" ? "Выбрать папку" : "Select Folder", systemImage: "folder")
                }
                .buttonStyle(SyncrosaSecondaryButtonStyle())
                .disabled(isProcessing)

                TextField(lang.selectedLanguage == "ru" ? "Название плейлиста" : "Playlist name", text: $playlistName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isProcessing)
            }

            SyncrosaAdaptiveRow(spacing: 12) {
                Button(action: exportManifest) {
                    Label("Export AI JSON", systemImage: "doc.badge.arrow.up")
                }
                .buttonStyle(SyncrosaSecondaryButtonStyle())
                .disabled(tracks.isEmpty || isProcessing)

                Button(action: importSelection) {
                    Label("Import AI JSON", systemImage: "doc.badge.arrow.down")
                }
                .buttonStyle(SyncrosaSecondaryButtonStyle())
                .disabled(tracks.isEmpty || isProcessing)

                Button(action: { presentSafetyPreview(.importFolder) }) {
                    Label(lang.selectedLanguage == "ru" ? "Create Playlist" : "Create Playlist", systemImage: "music.note.list")
                }
                .buttonStyle(SyncrosaPrimaryButtonStyle())
                .disabled(tracks.isEmpty || isProcessing || playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Text(estimateText)
                .font(.caption)
                .foregroundColor(.secondary)

            if !importProgressText.isEmpty {
                Text(importProgressText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !logLines.isEmpty {
                SyncrosaLogConsole(title: "FOLDER PLAYLIST LOG", lines: logLines, minHeight: 120)
            }
        }
        .syncrosaCard()
        .notification(message: $activeNotification)
        .sheet(item: $safetyPreview) { request in
            SafetyPreviewSheet(
                request: request,
                cancel: {
                    safetyPreview = nil
                    pendingAction = nil
                },
                confirm: {
                    let action = pendingAction
                    safetyPreview = nil
                    pendingAction = nil
                    run(action)
                }
            )
        }
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            folderPath = url.path
            scan(url)
        }
    }

    private func scan(_ url: URL) {
        tracks = FolderPlaylistImportService.shared.scanFolder(url)
        importProgressText = ""
        logLines.removeAll()
        appendLog("Scanned folder recursively: \(tracks.count) music files.")
        appendLog(estimateText)
        activeNotification = NotificationMessage(
            text: tracks.isEmpty
                ? (lang.selectedLanguage == "ru" ? "Музыкальные файлы не найдены." : "No music files found.")
                : (lang.selectedLanguage == "ru" ? "Файлов найдено: \(tracks.count)" : "Files found: \(tracks.count)"),
            isError: tracks.isEmpty
        )
    }

    private func exportManifest() {
        guard let folderURL, !tracks.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Syncrosa-\(folderURL.lastPathComponent)-AI-Manifest.json"
        panel.title = lang.selectedLanguage == "ru" ? "Сохранить JSON для внешнего AI" : "Save JSON for external AI"

        if panel.runModal() == .OK, let destination = panel.url {
            do {
                let manifest = FolderPlaylistImportService.shared.buildManifest(folderURL: folderURL, tracks: tracks)
                try FolderPlaylistImportService.shared.writeManifest(manifest, to: destination)
                logLines.removeAll()
                appendLog("Exported AI manifest: \(destination.path)")
                appendLog("Give this JSON to an AI assistant and ask it to return {\"playlistName\":\"...\",\"trackIDs\":[...]}.")
                activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "JSON для AI сохранён." : "AI JSON manifest saved.", isError: false)
            } catch {
                activeNotification = NotificationMessage(text: error.localizedDescription, isError: true)
            }
        }
    }

    private func importSelection() {
        guard !tracks.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.title = lang.selectedLanguage == "ru" ? "Выберите JSON с выбором треков" : "Choose playlist selection JSON"

        if panel.runModal() == .OK, let selectionURL = panel.url {
            do {
                let selection = try FolderPlaylistImportService.shared.readSelection(from: selectionURL)
                let selectedTracks = FolderPlaylistImportService.shared.selectedTracks(from: selection, availableTracks: tracks)
                if let name = selection.playlistName, playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    playlistName = name
                }
                guard !selectedTracks.isEmpty else {
                    activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "JSON не совпал с выбранной папкой." : "The JSON did not match the selected folder.", isError: true)
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

    private func presentSafetyPreview(_ action: FolderPlaylistImportAction) {
        guard let folderURL, !tracks.isEmpty else { return }
        pendingAction = action
        let cleanName = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch action {
        case .importFolder:
            safetyPreview = SafetyPreviewRequest(
                title: lang.selectedLanguage == "ru" ? "Создать плейлист из папки?" : "Create playlist from folder?",
                message: lang.selectedLanguage == "ru"
                    ? "Syncrosa импортирует поддерживаемые файлы в Music и создаст плейлист с указанным именем. Если такой плейлист уже существует, его содержимое будет очищено и заменено выбранными треками."
                    : "Syncrosa will import supported files into Music and create a playlist with the chosen name. If that playlist already exists, its contents will be cleared and replaced with the selected tracks.",
                details: [
                    SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Папка" : "Folder", value: folderURL.path),
                    SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Плейлист" : "Playlist", value: cleanName),
                    SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Файлов" : "Files", value: "\(tracks.count)"),
                    SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Оценка" : "Estimate", value: estimateText)
                ],
                confirmTitle: lang.selectedLanguage == "ru" ? "Создать / заменить" : "Create / Replace",
                isDestructive: true
            )
        case .importExternalSelection(let selectedTracks):
            safetyPreview = SafetyPreviewRequest(
                title: lang.selectedLanguage == "ru" ? "Создать AI-плейлист из JSON?" : "Create AI playlist from JSON?",
                message: lang.selectedLanguage == "ru"
                    ? "Syncrosa импортирует только треки, выбранные во внешнем JSON-файле. Если плейлист с таким именем уже существует, его содержимое будет очищено и заменено выбранными треками."
                    : "Syncrosa will import only the tracks selected in the external JSON file. If a playlist with this name already exists, its contents will be cleared and replaced with the selected tracks.",
                details: [
                    SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Папка" : "Folder", value: folderURL.path),
                    SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Плейлист" : "Playlist", value: cleanName),
                    SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Выбрано" : "Selected", value: "\(selectedTracks.count)")
                ],
                confirmTitle: lang.selectedLanguage == "ru" ? "Собрать / заменить" : "Build / Replace",
                isDestructive: true
            )
        }
    }

    private func run(_ action: FolderPlaylistImportAction?) {
        switch action {
        case .importFolder:
            importTracks(tracks, title: "Import Folder Playlist")
        case .importExternalSelection(let selectedTracks):
            importTracks(selectedTracks, title: "Import External AI Playlist")
        case .none:
            break
        }
    }

    private func importTracks(_ selectedTracks: [FolderPlaylistTrack], title: String) {
        guard let folderURL, !selectedTracks.isEmpty else { return }
        let cleanPlaylistName = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPlaylistName.isEmpty else { return }

        let resolved = FolderPlaylistImportService.shared.importableURLs(for: selectedTracks, folderURL: folderURL)
        guard !resolved.urls.isEmpty else {
            activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Нет поддерживаемых файлов для импорта в Music." : "No supported files to import into Music.", isError: true)
            return
        }

        isProcessing = true
        logLines.removeAll()
        importProgressText = ""
        appendLog("Starting playlist import: \(cleanPlaylistName)")
        appendLog("Files selected: \(selectedTracks.count). Importable: \(resolved.urls.count). Skipped before import: \(resolved.skipped.count).")
        activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Импортирую папку в Music..." : "Importing folder into Music...", isError: false)

        let recoveryID = OperationRecoveryService.shared.begin(
            tool: "Folder Playlist Importer",
            title: title,
            message: lang.selectedLanguage == "ru" ? "Импорт папки в Music был прерван. Проверьте Recovery Center и созданный плейлист." : "Folder import into Music was interrupted. Check Recovery Center and the created playlist.",
            affectedCount: resolved.urls.count,
            backupPath: folderURL.path
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
                backupPath: folderURL.path
            )
        }
    }

    private func appendLog(_ line: String) {
        logLines.append("> \(line)")
        if logLines.count > 160 {
            logLines.removeFirst(logLines.count - 160)
        }
    }
}
