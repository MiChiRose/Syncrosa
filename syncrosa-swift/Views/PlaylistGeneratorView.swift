import SwiftUI

struct PlaylistGeneratorView: View {
    @ObservedObject var lang = LocalizationService.shared
    @State private var playlistName: String = "AI Playlist"
    @State private var prompt: String = ""
    @State private var isGenerating: Bool = false
    @State private var activeNotification: NotificationMessage? = nil
    @State private var trackCount: String = "25"
    @State private var showHelp: Bool = false
    
    @AppStorage("selected_provider") private var selectedProvider: String = "Gemini"
    @AppStorage("selected_model_gemini") private var geminiModel: String = "gemini-1.5-flash"
    @AppStorage("selected_model_groq") private var groqModel: String = "llama3-8b-8192"
    @AppStorage("selected_model_openrouter") private var openrouterModel: String = "google/gemini-2.0-flash-exp:free"
    
    let nameLimit = 30
    let promptLimit = 150
    let maximumTrackCount = 200
    
    var currentModel: String {
        if selectedProvider == "Gemini" { return geminiModel }
        if selectedProvider == "Groq" { return groqModel }
        return openrouterModel
    }

    var canGeneratePlaylist: Bool {
        let trimmedName = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedPrompt.isEmpty, !isGenerating else { return false }
        guard let count = Int(trackCount.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return (1...maximumTrackCount).contains(count)
    }
    
    var body: some View {
        SyncrosaPage {
            SyncrosaPageHeader(
                title: lang.t("ai_playlist"),
                systemImage: "music.note.list",
                subtitle: lang.selectedLanguage == "ru" ? "Создавайте плейлист по настроению из уже существующей медиатеки." : "Create a mood-based playlist from tracks already in your library.",
                helpAction: { showHelp = true }
            )
                
                // Card 1: Configuration
                VStack(alignment: .leading, spacing: 20) {

                    
                    // Playlist Name Input
                    VStack(alignment: .leading, spacing: 5) {
                        Text(lang.t("pl_name"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        TextField(lang.selectedLanguage == "ru" ? "Название плейлиста" : "Playlist name", text: $playlistName)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: playlistName) { oldValue, newValue in
                                if newValue.count > nameLimit {
                                    playlistName = String(newValue.prefix(nameLimit))
                                }
                            }
                        
                        HStack {
                            Spacer()
                            Text("\(playlistName.count)/\(nameLimit)")
                                .font(.system(size: 9))
                                .foregroundColor(playlistName.count >= nameLimit ? .red : .secondary)
                        }
                    }
                    
                    // Prompt Input
                    VStack(alignment: .leading, spacing: 5) {
                        Text(lang.t("pl_mood"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        TextEditor(text: $prompt)
                            .font(.system(size: 14))
                            .padding(8)
                            .frame(height: 80)
                            .background(SyncrosaTheme.textBackground)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(SyncrosaTheme.panelBorder, lineWidth: 1)
                            )
                            .onChange(of: prompt) { oldValue, newValue in
                                if newValue.count > promptLimit {
                                    prompt = String(newValue.prefix(promptLimit))
                                }
                            }
                        
                        HStack {
                            Spacer()
                            Text("\(prompt.count)/\(promptLimit)")
                                .font(.system(size: 9))
                                .foregroundColor(prompt.count >= promptLimit ? .red : .secondary)
                        }
                    }
                    
                    HStack(alignment: .bottom, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(lang.t("track_count"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                TextField("25", text: $trackCount)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                                    .onChange(of: trackCount) { _, newValue in
                                        let digits = newValue.filter(\.isNumber)
                                        if digits != newValue {
                                            trackCount = digits
                                        } else if let value = Int(digits), value > maximumTrackCount {
                                            trackCount = "\(maximumTrackCount)"
                                        }
                                    }
                                
                                Stepper("", onIncrement: {
                                    let value = Int(trackCount) ?? 0
                                    trackCount = "\(min(maximumTrackCount, value + 1))"
                                }, onDecrement: {
                                    if let val = Int(trackCount), val > 1 { trackCount = "\(val - 1)" }
                                })
                                .labelsHidden()
                            }
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            SyncrosaSectionLabel(text: lang.t("active_config"), systemImage: "cpu")
                            Text("\(selectedProvider)")
                                .font(.caption)
                                .fontWeight(.bold)
                            Text(currentModel)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .syncrosaCard()
                
                // Action Button
                Button(action: generatePlaylist) {
                    if isGenerating {
                        ProgressView().controlSize(.small)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(lang.t("generate_playlist"))
                            .frame(maxWidth: .infinity)
                            .fontWeight(.bold)
                    }
                }
                .buttonStyle(SyncrosaPrimaryButtonStyle())
                .controlSize(.large)
                .disabled(!canGeneratePlaylist)

                if let disabledReason = generateDisabledReason, !isGenerating {
                    SyncrosaDisabledReason(text: disabledReason)
                }
                
                Spacer()
        }
        .notification(message: $activeNotification)
        .sheet(isPresented: $showHelp) {
            helpSheetView
        }
    }

    private var generateDisabledReason: String? {
        if playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return lang.selectedLanguage == "ru" ? "Введите название плейлиста." : "Enter a playlist name."
        }
        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return lang.selectedLanguage == "ru" ? "Опишите настроение или стиль музыки." : "Describe the mood or music style."
        }
        guard let count = Int(trackCount), (1...maximumTrackCount).contains(count) else {
            return lang.selectedLanguage == "ru" ? "Количество треков должно быть от 1 до \(maximumTrackCount)." : "Track count must be between 1 and \(maximumTrackCount)."
        }
        return nil
    }
    
    var helpSheetView: some View {
        SyncrosaHelpSheet(
            title: lang.t("ai_playlist"),
            summary: lang.selectedLanguage == "ru"
                ? "Создаёт плейлист из уже существующих треков Music по вашему описанию настроения или жанра."
                : "Builds a playlist from tracks already in Music using your mood or genre description.",
            steps: lang.selectedLanguage == "ru" ? [
                "В настройках выберите AI-провайдера, модель и сохраните действующий API-ключ.",
                "Введите название плейлиста и опишите желаемую музыку.",
                "Укажите количество треков от 1 до 200.",
                "Запустите генерацию и дождитесь завершения сканирования, AI-подбора и создания плейлиста."
            ] : [
                "Choose an AI provider and model in Settings, then save a valid API key.",
                "Enter a playlist name and describe the music you want.",
                "Choose a track count from 1 to 200.",
                "Start generation and wait for library scan, AI selection, and playlist creation to finish."
            ],
            notes: lang.selectedLanguage == "ru" ? [
                "Syncrosa отправляет AI только текстовый список доступных треков, не аудиофайлы.",
                "Music должен содержать локально доступные треки."
            ] : [
                "Syncrosa sends the AI a text list of available tracks, never the audio files.",
                "Music must contain locally available tracks."
            ],
            dismiss: { showHelp = false }
        )
    }

    
    func generatePlaylist() {
        let account = selectedProvider.lowercased()
        let key = KeychainHelper.shared.readString(service: KeychainHelper.serviceName, account: account) ?? ""
        let model = selectedProvider == "Gemini" ? geminiModel : (selectedProvider == "Groq" ? groqModel : openrouterModel)
        let requestedName = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedCount = min(max(Int(trackCount) ?? 25, 1), maximumTrackCount)
        
        guard !key.isEmpty else {
            activeNotification = NotificationMessage(text: lang.t("key_missing"), isError: true)
            return
        }
        
        isGenerating = true
        activeNotification = NotificationMessage(text: lang.t("scanning"), isError: false)
        
        DispatchQueue.global().async {
            guard let libraryCount = MusicService.shared.getLibraryTrackCount() else {
                DispatchQueue.main.async {
                    isGenerating = false
                    activeNotification = NotificationMessage(
                        text: lang.selectedLanguage == "ru" ? "Не удалось прочитать медиатеку Music, или она пуста." : "Could not read your Music library, or it may be empty.",
                        isError: true
                    )
                }
                return
            }

            guard libraryCount > 0 else {
                DispatchQueue.main.async {
                    isGenerating = false
                    activeNotification = NotificationMessage(
                        text: lang.selectedLanguage == "ru" ? "В Music нет треков. Нечего добавлять в ИИ-плейлист." : "Music has no tracks. There is nothing to add to an AI playlist.",
                        isError: true
                    )
                }
                return
            }

            let tracks = MusicService.shared.getAllTracks { current, total in
                DispatchQueue.main.async {
                    activeNotification = NotificationMessage(text: "\(lang.t("scanning")) \(current)/\(total)", isError: false)
                }
            }
            
            guard !tracks.isEmpty else {
                DispatchQueue.main.async {
                    isGenerating = false
                    activeNotification = NotificationMessage(
                        text: lang.selectedLanguage == "ru" ? "Music прочитан, но доступных треков не вернул." : "Music was read, but no usable tracks were returned.",
                        isError: true
                    )
                }
                return
            }
            
            let librarySample = tracks.map { track -> String in
                let cleanArtist = track.artist.replacingOccurrences(of: "\t", with: " ")
                let cleanName = track.name.replacingOccurrences(of: "\t", with: " ")
                let cleanAlbum = track.album.replacingOccurrences(of: "\t", with: " ")
                let cleanGenre = track.genre.replacingOccurrences(of: "\t", with: " ")
                return "\(track.persistentID)\t\(cleanArtist)\t\(cleanName)\t\(cleanAlbum)\t\(cleanGenre)\t\(track.year)"
            }
            let limitedSample = Array(librarySample.shuffled().prefix(500))
            
            DispatchQueue.main.async {
                activeNotification = NotificationMessage(text: lang.t("asking_ai"), isError: false)
            }
            
            AIService.shared.generatePlaylistSuggestions(
                provider: selectedProvider,
                apiKey: key,
                model: model,
                prompt: requestedPrompt,
                count: requestedCount,
                librarySample: limitedSample
            ) { persistentIDs in
                guard let ids = persistentIDs, !ids.isEmpty else {
                    DispatchQueue.main.async {
                        activeNotification = NotificationMessage(text: lang.t("ai_fail"), isError: true)
                        isGenerating = false
                    }
                    return
                }

                DispatchQueue.main.async {
                    activeNotification = NotificationMessage(text: lang.t("creating_playlist"), isError: false)
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    let added = MusicService.shared.createPlaylist(name: requestedName, persistentIDs: ids)
                    DispatchQueue.main.async {
                        if added > 0 {
                            activeNotification = NotificationMessage(text: lang.t("success_added", added), isError: false)
                        } else {
                            activeNotification = NotificationMessage(
                                text: lang.selectedLanguage == "ru" ? "Плейлист не создан: Music не добавил ни одного трека." : "Playlist was not created: Music added zero tracks.",
                                isError: true
                            )
                        }
                        isGenerating = false
                    }
                }
            }
        }
    }
}
