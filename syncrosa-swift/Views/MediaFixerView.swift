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

                    if !fixAlbum && !fixTitle && !fixArtist && !fixGenre && !fixTrackNumber && !fixLyrics {
                        SyncrosaDisabledReason(text: lang.selectedLanguage == "ru"
                            ? "Отметьте хотя бы одно поле для обновления метаданных."
                            : "Select at least one field before updating metadata.")
                    }
                }
                .syncrosaCard()

                MusicLibraryAIExchangeCard()

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
            Alert(title: Text(lang.t("media_fixer")), message: Text(alertMessage), dismissButton: .default(Text(lang.t("close"))))
        }
        .sheet(isPresented: $showHelp) {
            helpSheetView
        }
    }
    
    var helpSheetView: some View {
        SyncrosaHelpSheet(
            title: lang.t("media_fixer"),
            summary: lang.selectedLanguage == "ru"
                ? "Исправляет выбранные поля треков непосредственно в медиатеке Music и объединяет ошибочно разделённые альбомы."
                : "Repairs selected fields directly in Music and merges albums split by inconsistent naming.",
            steps: lang.selectedLanguage == "ru" ? [
                "Отметьте только те поля, которые разрешено обновлять.",
                "Запустите обновление метаданных и дождитесь завершения сканирования и сетевых запросов.",
                "Для разделённых альбомов сначала выполните анализ медиатеки.",
                "Просмотрите кандидатов и подтвердите объединение выбранных групп."
            ] : [
                "Select only the fields Syncrosa may update.",
                "Start metadata update and wait for scanning and online lookups to finish.",
                "For split albums, analyze the library first.",
                "Review the candidates and confirm the selected album groups."
            ],
            notes: lang.selectedLanguage == "ru" ? [
                "Операция изменяет данные в Music, поэтому выбирайте поля внимательно.",
                "В локальном режиме сетевое восстановление метаданных недоступно."
            ] : [
                "This operation changes Music data, so review the selected fields carefully.",
                "Online metadata recovery is unavailable in local-only mode."
            ],
            dismiss: { showHelp = false }
        )
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
            var failedTracks = 0
            for group in mergeCandidates {
                for pid in group.trackIDs {
                    if !MusicService.shared.updateTrackAlbum(persistentID: pid, album: group.mainAlbum) {
                        failedTracks += 1
                    }
                }
                current += 1
                DispatchQueue.main.async {
                    activeNotification = NotificationMessage(text: "Fixing: \(current)/\(total)", isError: false)
                }
            }
            
            DispatchQueue.main.async {
                isAnalyzing = false
                mergeCandidates = []
                if failedTracks == 0 {
                    alertMessage = lang.selectedLanguage == "ru" ? "Все альбомы успешно объединены!" : "All albums successfully merged!"
                } else {
                    alertMessage = lang.selectedLanguage == "ru"
                        ? "Объединение завершено, но Music не обновил треков: \(failedTracks)."
                        : "Merge finished, but Music did not update \(failedTracks) tracks."
                }
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

private struct MusicLibraryAIExchangeCard: View {
    @ObservedObject private var lang = LocalizationService.shared

    @State private var isProcessing = false
    @State private var progressText = ""
    @State private var activeNotification: NotificationMessage? = nil
    @State private var pendingTrackIDs: [String] = []
    @State private var playlistName = ""
    @State private var showNamePrompt = false
    @State private var safetyPreview: SafetyPreviewRequest? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SyncrosaSectionLabel(
                text: lang.selectedLanguage == "ru" ? "МЕДИАТЕКА MUSIC И ВНЕШНИЙ AI" : "MUSIC LIBRARY & EXTERNAL AI",
                systemImage: "point.3.connected.trianglepath.dotted"
            )

            Text(lang.selectedLanguage == "ru"
                 ? "Передайте каталог своей музыки выбранному AI-агенту и импортируйте полученный список обратно как плейлист. Аудиофайлы и API-ключ в JSON не попадают."
                 : "Give your music catalog to an AI assistant, then import its selection as a playlist. Audio files and your API key are never included in the JSON.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    exchangeStep(number: 1, icon: "square.and.arrow.up", text: lang.selectedLanguage == "ru" ? "Экспортируйте каталог" : "Export catalog")
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    exchangeStep(number: 2, icon: "sparkles", text: lang.selectedLanguage == "ru" ? "Выберите треки с AI" : "Choose with AI")
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    exchangeStep(number: 3, icon: "music.note.list", text: lang.selectedLanguage == "ru" ? "Импортируйте плейлист" : "Import playlist")
                }

                VStack(alignment: .leading, spacing: 8) {
                    exchangeStep(number: 1, icon: "square.and.arrow.up", text: lang.selectedLanguage == "ru" ? "Экспортируйте каталог" : "Export catalog")
                    exchangeStep(number: 2, icon: "sparkles", text: lang.selectedLanguage == "ru" ? "Выберите треки с AI" : "Choose with AI")
                    exchangeStep(number: 3, icon: "music.note.list", text: lang.selectedLanguage == "ru" ? "Импортируйте плейлист" : "Import playlist")
                }
            }

            SyncrosaAdaptiveRow(spacing: 12) {
                Button(action: exportLibrary) {
                    if isProcessing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(lang.selectedLanguage == "ru" ? "Экспорт медиатеки JSON" : "Export Library JSON", systemImage: "doc.badge.arrow.up")
                    }
                }
                .buttonStyle(SyncrosaPrimaryButtonStyle())
                .disabled(isProcessing)

                Button(action: importAISelection) {
                    Label(lang.selectedLanguage == "ru" ? "Импорт AI-плейлиста" : "Import AI Playlist", systemImage: "doc.badge.arrow.down")
                }
                .buttonStyle(SyncrosaSecondaryButtonStyle())
                .disabled(isProcessing)
            }

            if !progressText.isEmpty {
                Text(progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .syncrosaCard()
        .notification(message: $activeNotification)
        .alert(lang.selectedLanguage == "ru" ? "Название нового плейлиста" : "Name the new playlist", isPresented: $showNamePrompt) {
            TextField(lang.selectedLanguage == "ru" ? "Название плейлиста" : "Playlist name", text: $playlistName)
            Button(lang.t("cancel"), role: .cancel) {
                pendingTrackIDs = []
            }
            Button(lang.selectedLanguage == "ru" ? "Продолжить" : "Continue") {
                presentImportSafetyPreview()
            }
            .disabled(playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text(lang.selectedLanguage == "ru"
                 ? "Syncrosa создаст плейлист из идентификаторов, которые вернул внешний AI."
                 : "Syncrosa will create a playlist from the identifiers returned by the external AI.")
        }
        .sheet(item: $safetyPreview) { request in
            SafetyPreviewSheet(
                request: request,
                cancel: {
                    safetyPreview = nil
                    pendingTrackIDs = []
                },
                confirm: {
                    safetyPreview = nil
                    createImportedPlaylist()
                }
            )
        }
    }

    private func exchangeStep(number: Int, icon: String, text: String) -> some View {
        HStack(spacing: 7) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(SyncrosaTheme.accent)
                .frame(width: 22, height: 22)
                .background(SyncrosaTheme.accent.opacity(0.12), in: Circle())
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption.weight(.medium))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func exportLibrary() {
        isProcessing = true
        progressText = lang.selectedLanguage == "ru" ? "Читаю медиатеку Music..." : "Reading Music library..."

        DispatchQueue.global(qos: .userInitiated).async {
            guard let count = MusicService.shared.getLibraryTrackCount(), count > 0 else {
                DispatchQueue.main.async {
                    isProcessing = false
                    progressText = ""
                    activeNotification = NotificationMessage(
                        text: lang.selectedLanguage == "ru" ? "Медиатека Music пуста или недоступна." : "The Music library is empty or unavailable.",
                        isError: true
                    )
                }
                return
            }

            let tracks = MusicService.shared.getAllTracks { current, total in
                DispatchQueue.main.async {
                    progressText = lang.selectedLanguage == "ru"
                        ? "Читаю медиатеку: \(current)/\(total)"
                        : "Reading library: \(current)/\(total)"
                }
            }
            guard !tracks.isEmpty else {
                DispatchQueue.main.async {
                    isProcessing = false
                    progressText = ""
                    activeNotification = NotificationMessage(
                        text: lang.selectedLanguage == "ru" ? "Music не вернул доступные треки." : "Music returned no readable tracks.",
                        isError: true
                    )
                }
                return
            }

            let manifest = MusicLibraryExchangeService.shared.makeManifest(from: tracks)
            DispatchQueue.main.async {
                chooseManifestDestination(manifest)
            }
        }
    }

    private func chooseManifestDestination(_ manifest: MusicLibraryAIManifest) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Syncrosa-Music-Library.json"
        panel.title = lang.selectedLanguage == "ru" ? "Сохранить медиатеку для внешнего AI" : "Save library for external AI"

        guard panel.runModal() == .OK, let destination = panel.url else {
            isProcessing = false
            progressText = ""
            return
        }

        DispatchQueue.global(qos: .utility).async {
            do {
                try MusicLibraryExchangeService.shared.writeManifest(manifest, to: destination)
                DispatchQueue.main.async {
                    isProcessing = false
                    progressText = lang.selectedLanguage == "ru"
                        ? "Экспортировано треков: \(manifest.tracks.count)"
                        : "Exported tracks: \(manifest.tracks.count)"
                    activeNotification = NotificationMessage(
                        text: lang.selectedLanguage == "ru" ? "JSON медиатеки сохранён." : "Library JSON saved.",
                        isError: false
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    isProcessing = false
                    progressText = ""
                    activeNotification = NotificationMessage(text: error.localizedDescription, isError: true)
                }
            }
        }
    }

    private func importAISelection() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.title = lang.selectedLanguage == "ru" ? "Выберите JSON от внешнего AI" : "Choose JSON from external AI"

        guard panel.runModal() == .OK, let source = panel.url else { return }
        do {
            let selection = try MusicLibraryExchangeService.shared.readSelection(from: source)
            let ids = MusicLibraryExchangeService.shared.validatedTrackIDs(from: selection)
            guard !ids.isEmpty else {
                activeNotification = NotificationMessage(
                    text: lang.selectedLanguage == "ru" ? "В JSON нет корректных идентификаторов треков Syncrosa." : "The JSON contains no valid Syncrosa track identifiers.",
                    isError: true
                )
                return
            }
            pendingTrackIDs = ids
            playlistName = selection.playlistName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            showNamePrompt = true
        } catch {
            activeNotification = NotificationMessage(
                text: lang.selectedLanguage == "ru" ? "Не удалось прочитать JSON выбора. Проверьте формат файла." : "Could not read the selection JSON. Check its format.",
                isError: true
            )
        }
    }

    private func presentImportSafetyPreview() {
        let cleanName = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !pendingTrackIDs.isEmpty else { return }
        safetyPreview = SafetyPreviewRequest(
            title: lang.selectedLanguage == "ru" ? "Создать AI-плейлист?" : "Create AI playlist?",
            message: lang.selectedLanguage == "ru"
                ? "Будут добавлены только треки с корректными идентификаторами. Если плейлист с таким именем уже существует, его содержимое будет заменено."
                : "Only tracks with valid identifiers will be added. If a playlist with this name already exists, its contents will be replaced.",
            details: [
                SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Плейлист" : "Playlist", value: cleanName),
                SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Выбрано AI" : "Selected by AI", value: "\(pendingTrackIDs.count)")
            ],
            confirmTitle: lang.selectedLanguage == "ru" ? "Создать / заменить" : "Create / Replace",
            isDestructive: true
        )
    }

    private func createImportedPlaylist() {
        let cleanName = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
        let ids = pendingTrackIDs
        guard !cleanName.isEmpty, !ids.isEmpty else { return }

        isProcessing = true
        progressText = lang.selectedLanguage == "ru" ? "Создаю плейлист в Music..." : "Creating playlist in Music..."
        DispatchQueue.global(qos: .userInitiated).async {
            let added = MusicService.shared.createPlaylist(name: cleanName, persistentIDs: ids)
            DispatchQueue.main.async {
                isProcessing = false
                pendingTrackIDs = []
                let success = added > 0
                progressText = success
                    ? (lang.selectedLanguage == "ru" ? "Добавлено треков: \(added)" : "Added tracks: \(added)")
                    : ""
                let message = success
                    ? (lang.selectedLanguage == "ru" ? "Плейлист «\(cleanName)» создан. Добавлено: \(added)." : "Playlist \"\(cleanName)\" created with \(added) tracks.")
                    : (lang.selectedLanguage == "ru" ? "Music не смог создать плейлист из выбранных треков." : "Music could not create a playlist from the selected tracks.")
                activeNotification = NotificationMessage(text: message, isError: !success)
                OperationHistoryService.shared.record(
                    tool: "Music Library AI Exchange",
                    title: "Import AI Playlist",
                    status: success ? "OK" : "FAIL",
                    message: message,
                    affectedCount: added
                )
            }
        }
    }
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
                    Label(lang.selectedLanguage == "ru" ? "Экспорт JSON для AI" : "Export JSON for AI", systemImage: "doc.badge.arrow.up")
                }
                .buttonStyle(SyncrosaSecondaryButtonStyle())
                .disabled(tracks.isEmpty || isProcessing)

                Button(action: importSelection) {
                    Label(lang.selectedLanguage == "ru" ? "Импорт JSON от AI" : "Import JSON from AI", systemImage: "doc.badge.arrow.down")
                }
                .buttonStyle(SyncrosaSecondaryButtonStyle())
                .disabled(tracks.isEmpty || isProcessing)

                Button(action: { presentSafetyPreview(.importFolder) }) {
                    Label(lang.selectedLanguage == "ru" ? "Создать плейлист" : "Create Playlist", systemImage: "music.note.list")
                }
                .buttonStyle(SyncrosaPrimaryButtonStyle())
                .disabled(tracks.isEmpty || isProcessing || playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if tracks.isEmpty && !isProcessing {
                SyncrosaDisabledReason(text: lang.selectedLanguage == "ru"
                    ? "JSON этого раздела строится по локальной папке. Сначала выберите папку; для всей медиатеки используйте раздел выше."
                    : "This section builds JSON from a local folder. Select a folder first; use the section above for your whole Music library.")
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
        isProcessing = true
        tracks = []
        importProgressText = ""
        logLines.removeAll()
        importProgressText = lang.selectedLanguage == "ru" ? "Сканирую папку..." : "Scanning folder..."
        DispatchQueue.global(qos: .utility).async {
            let matches = FolderPlaylistImportService.shared.scanFolder(url)
            DispatchQueue.main.async {
                tracks = matches
                isProcessing = false
                importProgressText = ""
                appendLog("Scanned folder recursively: \(matches.count) music files.")
                appendLog(estimateText)
                activeNotification = NotificationMessage(
                    text: matches.isEmpty
                        ? (lang.selectedLanguage == "ru" ? "Музыкальные файлы не найдены." : "No music files found.")
                        : (lang.selectedLanguage == "ru" ? "Файлов найдено: \(matches.count)" : "Files found: \(matches.count)"),
                    isError: matches.isEmpty
                )
            }
        }
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
