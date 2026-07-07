import SwiftUI

struct OfflinePlaylistGeneratorView: View {
    @ObservedObject var lang = LocalizationService.shared
    
    @State private var allTracks: [MusicTrack] = []
    @State private var genres: [String] = []
    @State private var selectedGenre: String = "All"
    @State private var yearFrom: Int? = nil
    @State private var yearTo: Int? = nil
    @State private var filterCover: Bool = false
    @State private var filterRating: Bool = false
    @State private var minimumRating: Double = 3.0 // 1 to 5 stars
    
    var yearsList: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array(1950...currentYear).reversed()
    }
    
    var filteredYearsTo: [Int] {
        let list = yearsList
        if let from = yearFrom {
            return list.filter { $0 >= from }
        }
        return list
    }

    var genreOptions: [SyncrosaMenuOption<String>] {
        [SyncrosaMenuOption(title: lang.selectedLanguage == "ru" ? "Все жанры" : "All Genres", value: "All")] +
        genres.map { SyncrosaMenuOption(title: $0, value: $0) }
    }

    var yearFromOptions: [SyncrosaMenuOption<Int?>] {
        [SyncrosaMenuOption<Int?>(title: lang.selectedLanguage == "ru" ? "Любой" : "Any", value: nil)] +
        yearsList.map { SyncrosaMenuOption<Int?>(title: String($0), value: $0) }
    }

    var yearToOptions: [SyncrosaMenuOption<Int?>] {
        [SyncrosaMenuOption<Int?>(title: lang.selectedLanguage == "ru" ? "Любой" : "Any", value: nil)] +
        filteredYearsTo.map { SyncrosaMenuOption<Int?>(title: String($0), value: $0) }
    }
    
    @State private var checkedDecades: [String: Bool] = [
        "60s": false,
        "70s": false,
        "80s": false,
        "90s": false,
        "2000s": false,
        "2010s": false,
        "Modern (2020+)": false
    ]
    
    @State private var playlistName: String = "Syncrosa Offline"
    @State private var isLoading: Bool = false
    @State private var isCreatingPlaylist: Bool = false
    @State private var isGeneratingEpochs: Bool = false
    @State private var activeNotification: NotificationMessage? = nil
    @State private var showAlert: Bool = false
    @State private var showEmptyAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var showHelp: Bool = false
    @State private var emptyLibraryMessage: String? = nil
    
    var body: some View {
        SyncrosaPage {
            SyncrosaPageHeader(
                title: lang.selectedLanguage == "ru" ? "Генератор офлайн плейлистов" : "Offline Playlist Generator",
                systemImage: "music.note.house",
                subtitle: lang.selectedLanguage == "ru" ? "Собирайте плейлисты локально, без обращения к AI." : "Build playlists locally without sending anything to AI.",
                helpAction: { showHelp = true }
            )
                
                if isLoading {
                    VStack(spacing: 15) {
                        ProgressView(lang.selectedLanguage == "ru" ? "Загрузка библиотеки..." : "Loading library...")
                        Text(lang.selectedLanguage == "ru" ? "Пожалуйста, подождите, пока мы считываем треки." : "Please wait while we read tracks from Music app.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .syncrosaCard()
                } else if let emptyLibraryMessage = emptyLibraryMessage {
                    SyncrosaEmptyState(
                        systemImage: "music.note.list",
                        title: emptyLibraryMessage,
                        message: lang.selectedLanguage == "ru" ? "Добавьте треки в Music и вернитесь сюда снова." : "Add tracks to Music, then return here."
                    )
                    .syncrosaCard(padding: 0)
                } else {
                    // Card 1: Custom Filters
                    VStack(alignment: .leading, spacing: 20) {
                        SyncrosaSectionLabel(text: lang.selectedLanguage == "ru" ? "НАСТРОЙКА ФИЛЬТРОВ" : "FILTER CONFIGURATION", systemImage: "slider.horizontal.3")
                        
                        // Genre Dropdown
                        VStack(alignment: .leading, spacing: 5) {
                            Text(lang.selectedLanguage == "ru" ? "Жанр:" : "Genre:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            SyncrosaGlassMenu(
                                selection: $selectedGenre,
                                options: genreOptions,
                                width: 240
                            )
                        }
                        
                        // Year Range
                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(lang.selectedLanguage == "ru" ? "Год с:" : "Year From:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                SyncrosaGlassMenu(
                                    selection: $yearFrom,
                                    options: yearFromOptions,
                                    width: 120
                                )
                            }
                            
                            VStack(alignment: .leading, spacing: 5) {
                                Text(lang.selectedLanguage == "ru" ? "по:" : "Year To:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                SyncrosaGlassMenu(
                                    selection: $yearTo,
                                    options: yearToOptions,
                                    width: 120
                                )
                            }
                        }
                        
                        // Cover Checkbox
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle(isOn: $filterCover) {
                                Text(lang.selectedLanguage == "ru" ? "Требовать наличие обложки" : "Require cover art")
                                    .font(.subheadline)
                            }
                            .toggleStyle(.checkbox)
                            
                            Text(lang.selectedLanguage == "ru" ? "(необязательно)" : "(optional)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.leading, 20)
                        }
                        
                        // Rating Filter Checkbox + Slider
                        VStack(alignment: .leading, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Toggle(isOn: $filterRating) {
                                    Text(lang.selectedLanguage == "ru" ? "Фильтровать по рейтингу" : "Filter by rating")
                                        .font(.subheadline)
                                }
                                .toggleStyle(.checkbox)
                                
                                Text(lang.selectedLanguage == "ru" ? "(необязательно)" : "(optional)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 20)
                            }
                            
                            if filterRating {
                                HStack(spacing: 12) {
                                    Slider(value: $minimumRating, in: 1...5, step: 1)
                                        .frame(width: 150)
                                    
                                    HStack(spacing: 2) {
                                        ForEach(1...5, id: \.self) { index in
                                            Image(systemName: "star.fill")
                                                .foregroundColor(index <= Int(minimumRating) ? .yellow : .gray.opacity(0.3))
                                                .font(.caption)
                                        }
                                    }
                                    
                                    Text(lang.selectedLanguage == "ru" ? "и более" : "& more")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.leading, 20)
                            }
                        }
                        
                        // Custom Playlist Name
                        VStack(alignment: .leading, spacing: 5) {
                            Text(lang.selectedLanguage == "ru" ? "Название плейлиста:" : "Playlist Name:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Syncrosa Offline", text: $playlistName)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Button(action: createFilteredPlaylist) {
                            if isCreatingPlaylist {
                                ProgressView().controlSize(.small)
                            } else {
                                Label(lang.selectedLanguage == "ru" ? "Создать плейлист" : "Create Playlist", systemImage: "plus.circle")
                            }
                        }
                        .buttonStyle(SyncrosaPrimaryButtonStyle())
                        .disabled(allTracks.isEmpty || isCreatingPlaylist || playlistName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .syncrosaCard()
                    
                    // Card 2: Decades Section
                    VStack(alignment: .leading, spacing: 20) {
                        SyncrosaSectionLabel(text: lang.selectedLanguage == "ru" ? "СОЗДАНИЕ ПО ЭПОХАМ (ДЕСЯТИЛЕТИЯ)" : "GENERATE BY EPOCHS (DECADES)", systemImage: "calendar")
                        
                        // Decades Checkboxes Grid
                        let decadeKeys = ["60s", "70s", "80s", "90s", "2000s", "2010s", "Modern (2020+)"]
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], alignment: .leading, spacing: 10) {
                            ForEach(decadeKeys, id: \.self) { decade in
                                Toggle(isOn: Binding(
                                    get: { checkedDecades[decade, default: false] },
                                    set: { checkedDecades[decade] = $0 }
                                )) {
                                    Text(decade)
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                        
                        Button(action: generatePlaylistsByEpochs) {
                            if isGeneratingEpochs {
                                ProgressView().controlSize(.small)
                            } else {
                                Label(lang.selectedLanguage == "ru" ? "Создать плейлисты по эпохам" : "Generate Playlists by Epochs", systemImage: "calendar.badge.plus")
                            }
                        }
                        .buttonStyle(SyncrosaSecondaryButtonStyle())
                        .disabled(allTracks.isEmpty || isGeneratingEpochs || !checkedDecades.values.contains(true))
                    }
                    .syncrosaCard()
                }
                
                Spacer()
        }
        .onAppear(perform: loadLibrary)
        .onChange(of: yearFrom) { oldValue, newValue in
            if let from = newValue, let to = yearTo, to < from {
                yearTo = from
            }
        }
        .notification(message: $activeNotification)
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text(lang.selectedLanguage == "ru" ? "Офлайн генератор" : "Offline Generator"),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert(isPresented: $showEmptyAlert) {
            Alert(
                title: Text(lang.selectedLanguage == "ru" ? "Нет подходящих треков" : "No matching tracks"),
                message: Text(lang.selectedLanguage == "ru" ?
                             "После применения фильтров список треков пуст. Хотите создать плейлист, проигнорировав фильтры, или отменить?" :
                             "No tracks match your filter settings. Do you want to ignore all filters and create the playlist with all tracks, or abort?"),
                primaryButton: .default(Text(lang.selectedLanguage == "ru" ? "Игнорировать" : "Ignore")) {
                    createPlaylistWithTracks(allTracks)
                },
                secondaryButton: .cancel(Text(lang.selectedLanguage == "ru" ? "Отмена" : "Abort"))
            )
        }
        .sheet(isPresented: $showHelp) {
            helpSheetView
        }
    }
    
    var helpSheetView: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(lang.selectedLanguage == "ru" ? "Инструкция: Офлайн генератор" : "Help: Offline Generator")
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
                         "Этот инструмент позволяет вам создавать плейлисты локально, без использования внешних облачных ИИ сервисов.\n\n" +
                         "Возможности фильтрации:\n" +
                         "• Жанр: Выбор конкретного жанра из тех, которые присутствуют в вашей медиатеке.\n" +
                         "• Год: Ограничение диапазона лет выпуска композиций.\n" +
                         "• Обложка: Возможность отбора только тех песен, у которых есть обложка альбома.\n" +
                         "• Рейтинг: Отбор треков по рейтингу (количеству звезд).\n\n" +
                         "Генерация по эпохам:\n" +
                         "Вы можете выбрать желаемые десятилетия, и система автоматически создаст плейлисты (например, 'Syncrosa - 90s') для каждого отмеченного десятилетия, если в медиатеке найдутся подходящие треки." :
                         
                         "This tool allows you to create playlists locally, without using external cloud AI services.\n\n" +
                         "Filtering Options:\n" +
                         "• Genre: Filter by a specific genre present in your library.\n" +
                         "• Year Range: Restrict tracks to a range of release years.\n" +
                         "• Cover Art: Select only tracks that have an embedded cover image.\n" +
                         "• Rating: Restrict tracks to those meeting or exceeding a star rating.\n\n" +
                         "Generate by Epochs (Decades):\n" +
                         "Select multiple decades, and the app will generate individual playlists (e.g., 'Syncrosa - 90s') for each checked epoch that has matching tracks."
                    )
                    .font(.body)
                }
            }
            .frame(minWidth: 450, minHeight: 300)
        }
        .padding()
    }
    
    func loadLibrary() {
        isLoading = true
        emptyLibraryMessage = nil
        DispatchQueue.global().async {
            guard let libraryCount = MusicService.shared.getLibraryTrackCount() else {
                DispatchQueue.main.async {
                    self.allTracks = []
                    self.genres = []
                    self.emptyLibraryMessage = lang.selectedLanguage == "ru" ? "Не удалось прочитать медиатеку Music, или она пуста." : "Could not read your Music library, or it may be empty."
                    self.isLoading = false
                }
                return
            }

            guard libraryCount > 0 else {
                DispatchQueue.main.async {
                    self.allTracks = []
                    self.genres = []
                    self.emptyLibraryMessage = lang.selectedLanguage == "ru" ? "В Music нет треков. Создавать офлайн-плейлисты пока не из чего." : "Music has no tracks. There is nothing to use for offline playlists yet."
                    self.isLoading = false
                }
                return
            }

            let tracks = MusicService.shared.getAllTracks { _, _ in }
            let uniqueGenres = Array(Set(tracks.map { $0.genre })).filter { !$0.isEmpty }.sorted()
            DispatchQueue.main.async {
                self.allTracks = tracks
                self.genres = uniqueGenres
                self.emptyLibraryMessage = tracks.isEmpty ? (lang.selectedLanguage == "ru" ? "В Music нет доступных треков." : "Music has no readable tracks.") : nil
                self.isLoading = false
            }
        }
    }
    
    func createFilteredPlaylist() {
        isCreatingPlaylist = true
        activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Фильтрация треков..." : "Filtering tracks...", isError: false)
        
        DispatchQueue.global().async {
            // Step 1: Filter by local cacheable properties first (genre, year)
            var filtered = allTracks.filter { track in
                if selectedGenre != "All" && track.genre != selectedGenre {
                    return false
                }
                
                if let fromYr = yearFrom, track.year < fromYr {
                    return false
                }
                
                if let toYr = yearTo, track.year > toYr {
                    return false
                }
                return true
            }
            
            // Step 2: Apply rating and cover filters via AppleScript on demand
            if filterCover || filterRating {
                var finalFiltered: [MusicTrack] = []
                for track in filtered {
                    if let info = MusicService.shared.checkTrackFilter(persistentID: track.persistentID) {
                        var keep = true
                        if filterCover && !info.hasArtwork {
                            keep = false
                        }
                        if filterRating {
                            // Star rating maps to 0-100: 1->20, 2->40, 3->60, 4->80, 5->100
                            let minRatingValue = Int(minimumRating) * 20
                            if info.rating < minRatingValue {
                                keep = false
                            }
                        }
                        if keep {
                            finalFiltered.append(track)
                        }
                    }
                }
                filtered = finalFiltered
            }
            
            DispatchQueue.main.async {
                self.isCreatingPlaylist = false
                self.activeNotification = nil
                
                if filtered.isEmpty {
                    self.showEmptyAlert = true
                } else {
                    self.createPlaylistWithTracks(filtered)
                }
            }
        }
    }
    
    func createPlaylistWithTracks(_ tracksToUse: [MusicTrack]) {
        guard !tracksToUse.isEmpty else {
            alertMessage = lang.selectedLanguage == "ru" ? "Плейлист не создан: список треков пуст." : "Playlist was not created because the track list is empty."
            showAlert = true
            activeNotification = nil
            return
        }

        isCreatingPlaylist = true
        activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Создание плейлиста в Музыке..." : "Creating playlist in Music...", isError: false)
        
        DispatchQueue.global().async {
            let ids = tracksToUse.map { $0.persistentID }
            let added = MusicService.shared.createPlaylist(name: playlistName, persistentIDs: ids)
            
            DispatchQueue.main.async {
                self.isCreatingPlaylist = false
                self.alertMessage = added > 0 ?
                    (lang.selectedLanguage == "ru" ?
                        "Успешно создано! Добавлено треков: \(added)" :
                        "Success! Created playlist with \(added) tracks.") :
                    (lang.selectedLanguage == "ru" ?
                        "Плейлист не создан: Music не нашел выбранные треки." :
                        "Playlist was not created: Music did not find the selected tracks.")
                self.showAlert = true
                self.activeNotification = nil
            }
        }
    }
    
    func generatePlaylistsByEpochs() {
        isGeneratingEpochs = true
        activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Генерация по эпохам..." : "Generating by epochs...", isError: false)
        
        DispatchQueue.global().async {
            var logs: [String] = []
            
            let decadesRange: [String: ClosedRange<Int>] = [
                "60s": 1960...1969,
                "70s": 1970...1979,
                "80s": 1980...1989,
                "90s": 1990...1999,
                "2000s": 2000...2009,
                "2010s": 2010...2019,
                "Modern (2020+)": 2020...9999
            ]
            
            for (decade, checked) in checkedDecades where checked {
                guard let range = decadesRange[decade] else { continue }
                let matching = allTracks.filter { range.contains($0.year) }
                
                if matching.isEmpty {
                    let logMsg = "Warning: No tracks match decade \(decade). Skipping playlist creation."
                    print(logMsg)
                    logs.append(lang.selectedLanguage == "ru" ?
                                "⚠️ \(decade): Нет треков, плейлист пропущен." :
                                "⚠️ \(decade): No tracks found, skipped.")
                    continue
                }
                
                let plName = "Syncrosa - \(decade)"
                let ids = matching.map { $0.persistentID }
                let added = MusicService.shared.createPlaylist(name: plName, persistentIDs: ids)
                if added > 0 {
                    logs.append(lang.selectedLanguage == "ru" ?
                                "✅ \(decade): создан '\(plName)' (\(added) треков)." :
                                "✅ \(decade): created '\(plName)' (\(added) tracks).")
                } else {
                    logs.append(lang.selectedLanguage == "ru" ?
                                "⚠️ \(decade): Music не нашел треки, плейлист не изменен." :
                                "⚠️ \(decade): Music did not find the tracks, playlist was not changed.")
                }
            }
            
            DispatchQueue.main.async {
                self.isGeneratingEpochs = false
                self.alertMessage = logs.joined(separator: "\n")
                self.showAlert = true
                self.activeNotification = nil
            }
        }
    }
}
