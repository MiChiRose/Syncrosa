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
    
    var currentModel: String {
        if selectedProvider == "Gemini" { return geminiModel }
        if selectedProvider == "Groq" { return groqModel }
        return openrouterModel
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
                        
                        TextField("Enter name...", text: $playlistName)
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
                                
                                Stepper("", onIncrement: {
                                    if let val = Int(trackCount) { trackCount = "\(val + 1)" }
                                }, onDecrement: {
                                    if let val = Int(trackCount), val > 1 { trackCount = "\(val - 1)" }
                                })
                                .labelsHidden()
                            }
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            SyncrosaSectionLabel(text: "ACTIVE CONFIG", systemImage: "cpu")
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
                .disabled(prompt.isEmpty || playlistName.isEmpty || isGenerating)
                
                Spacer()
        }
        .notification(message: $activeNotification)
        .sheet(isPresented: $showHelp) {
            helpSheetView
        }
    }
    
    var helpSheetView: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(lang.selectedLanguage == "ru" ? "Инструкция: ИИ Плейлист" : "Help: AI Playlist")
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
                         "Этот инструмент использует передовые модели ИИ для автоматического создания плейлистов на основе вашего текстового описания (промпта) и содержимого вашей медиатеки.\n\n" +
                         "Шаги использования:\n" +
                         "1. Задайте имя создаваемому плейлисту.\n" +
                         "2. Опишите ваши пожелания к трекам (например, 'спокойная музыка для работы', 'энергичный рок из 90-х').\n" +
                         "3. Укажите количество треков.\n" +
                         "4. Нажмите «Сгенерировать плейлист». Система проанализирует вашу библиотеку, отправит запрос выбранной модели ИИ и автоматически добавит подходящие треки в новый плейлист в приложении «Музыка»." :
                         
                         "This tool uses advanced AI models to automatically generate playlists based on your text prompt and the content of your Music library.\n\n" +
                         "How to use:\n" +
                         "1. Enter a name for the new playlist.\n" +
                         "2. Describe the mood or style of music you want (e.g., 'calm acoustic music for studying', 'energetic 90s rock').\n" +
                         "3. Set the target track count.\n" +
                         "4. Click 'Generate Playlist'. The system will scan your library, consult the selected AI provider, and automatically compile the playlist in your Music app."
                    )
                    .font(.body)
                }
            }
            .frame(minWidth: 450, minHeight: 300)
        }
        .padding()
    }

    
    func generatePlaylist() {
        let account = selectedProvider.lowercased()
        let key = KeychainHelper.shared.readString(service: KeychainHelper.serviceName, account: account) ?? ""
        let model = selectedProvider == "Gemini" ? geminiModel : (selectedProvider == "Groq" ? groqModel : openrouterModel)
        
        guard !key.isEmpty else {
            activeNotification = NotificationMessage(text: lang.t("key_missing"), isError: true)
            return
        }
        
        isGenerating = true
        activeNotification = NotificationMessage(text: "Syncing library...", isError: false)
        
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
                    activeNotification = NotificationMessage(text: "Syncing: \(current)/\(total)", isError: false)
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
                activeNotification = NotificationMessage(text: "Asking AI Assistant...", isError: false)
            }
            
            AIService.shared.generatePlaylistSuggestions(
                provider: selectedProvider,
                apiKey: key,
                model: model,
                prompt: prompt,
                count: Int(trackCount) ?? 25,
                librarySample: limitedSample
            ) { persistentIDs in
                DispatchQueue.main.async {
                    if let ids = persistentIDs, !ids.isEmpty {
                        activeNotification = NotificationMessage(text: "Creating playlist in Music...", isError: false)
                        let added = MusicService.shared.createPlaylist(name: playlistName, persistentIDs: ids)
                        if added > 0 {
                            activeNotification = NotificationMessage(text: "Success! Added \(added) tracks.", isError: false)
                        } else {
                            activeNotification = NotificationMessage(
                                text: lang.selectedLanguage == "ru" ? "Плейлист не создан: Music не добавил ни одного трека." : "Playlist was not created: Music added zero tracks.",
                                isError: true
                            )
                        }
                    } else {
                        activeNotification = NotificationMessage(text: "AI failed to find matches.", isError: true)
                    }
                    isGenerating = false
                }
            }
        }
    }
}
