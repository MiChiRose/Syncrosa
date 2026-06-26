import SwiftUI

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
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                // Title with Help Button
                HStack(alignment: .center, spacing: 10) {
                    Label(lang.selectedLanguage == "ru" ? "Очистка медиатеки" : "Library Cleanup", systemImage: "bolt.shield")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Button(action: { showHelp = true }) {
                        Image(systemName: "questionmark.circle")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                // Checklist Card (New requirement)
                VStack(alignment: .leading, spacing: 15) {
                    Text(lang.selectedLanguage == "ru" ? "ВЫБЕРИТЕ ТЕГИ ДЛЯ ОБНОВЛЕНИЯ" : "SELECT TAGS TO UPDATE")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
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
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
                
                // Card 1: Controls
                VStack(alignment: .leading, spacing: 15) {
                    Text(lang.selectedLanguage == "ru" ? "Поиск разбитых альбомов и восстановление метаданных через iTunes Search API." : "Identify split albums and restore missing metadata via iTunes Search API.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 15) {
                        Button(action: analyzeLibrary) {
                            if isAnalyzing {
                                ProgressView().controlSize(.small)
                            } else {
                                Label(lang.selectedLanguage == "ru" ? "Анализ медиатеки" : "Analyze Library", systemImage: "magnifyingglass")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isAnalyzing)
                        
                        Button(action: updateMetadata) {
                            Label(lang.selectedLanguage == "ru" ? "Обновить метаданные" : "Update Metadata", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isAnalyzing || (!fixAlbum && !fixTitle && !fixArtist && !fixGenre && !fixTrackNumber && !fixLyrics))
                        
                        Button(action: fixMetadata) {
                            Label(lang.selectedLanguage == "ru" ? "Объединить альбомы" : "Merge Selected", systemImage: "wrench.and.screwdriver")
                        }
                        .buttonStyle(.bordered)
                        .disabled(mergeCandidates.isEmpty || isAnalyzing)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
                
                // Card 2: Split Album Results
                VStack(alignment: .leading, spacing: 10) {
                    Text(lang.selectedLanguage == "ru" ? "РЕЗУЛЬТАТЫ ПОИСКА РАЗБИТЫХ АЛЬБОМОВ" : "SPLIT ALBUMS SEARCH RESULTS")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if mergeCandidates.isEmpty {
                        VStack(spacing: 15) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 40))
                                .foregroundColor(.gray.opacity(0.3))
                            Text(lang.selectedLanguage == "ru" ? "Проблем с разбитыми альбомами не обнаружено." : "No split album issues detected yet.")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
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
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
                
                Spacer()
            }
            .padding(30)
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
                .buttonStyle(.bordered)
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
            let tracks = MusicService.shared.getAllTracks { current, total in
                DispatchQueue.main.async {
                    activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Сканирование: \(current)/\(total)" : "Scanning: \(current)/\(total)", isError: false)
                }
            }
            
            DispatchQueue.main.async {
                isAnalyzing = false
                if tracks.isEmpty {
                    alertMessage = lang.selectedLanguage == "ru" ? "Медиатека пуста или недоступна." : "Your Music library is empty or could not be read."
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
        isAnalyzing = true
        activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Загрузка списка треков..." : "Loading track list...", isError: false)
        
        DispatchQueue.global().async {
            let tracks = MusicService.shared.getAllTracks { _, _ in }
            guard !tracks.isEmpty else {
                DispatchQueue.main.async {
                    isAnalyzing = false
                    alertMessage = lang.selectedLanguage == "ru" ? "Медиатека пуста." : "Library is empty."
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
            }
        }
    }
}
