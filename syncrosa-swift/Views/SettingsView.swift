import SwiftUI

struct SettingsView: View {
    @ObservedObject var lang = LocalizationService.shared
    
    @State private var geminiKey: String = ""
    @State private var groqKey: String = ""
    @State private var openrouterKey: String = ""
    
    @AppStorage("selected_model_gemini") private var geminiModel: String = "gemini-1.5-flash"
    @AppStorage("selected_model_groq") private var groqModel: String = "llama3-8b-8192"
    @AppStorage("selected_model_openrouter") private var openrouterModel: String = "google/gemini-2.0-flash-exp:free"
    
    @AppStorage("selected_provider") private var selectedProvider: String = "Gemini"
    @AppStorage("is_key_validated") private var isKeyValidated: Bool = false
    @AppStorage("only_local_mode") private var onlyLocalMode: Bool = false
    
    @State private var activeNotification: NotificationMessage? = nil
    @State private var isValidating: Bool = false
    @State private var showHelp: Bool = false
    
    let providers = ["Gemini", "Groq", "OpenRouter"]
    let geminiModels = ["gemini-1.5-flash", "gemini-1.5-pro", "gemini-1.0-pro"]
    let groqModels = ["llama3-8b-8192", "llama3-70b-8192", "mixtral-8x7b-32768", "gemma-7b-it"]
    let languageOptions = [
        SyncrosaMenuOption(title: "English", value: "en"),
        SyncrosaMenuOption(title: "Русский", value: "ru"),
        SyncrosaMenuOption(title: "Беларуская", value: "be"),
        SyncrosaMenuOption(title: "한국어", value: "ko"),
        SyncrosaMenuOption(title: "日本語", value: "ja"),
        SyncrosaMenuOption(title: "中文", value: "zh"),
        SyncrosaMenuOption(title: "Deutsch", value: "de"),
        SyncrosaMenuOption(title: "Polski", value: "pl"),
        SyncrosaMenuOption(title: "Eesti", value: "et"),
        SyncrosaMenuOption(title: "Español", value: "es")
    ]
    @State private var openRouterModels: [String] = AIService.shared.cachedOpenRouterModels
    @State private var isSyncingModels: Bool = false
    @State private var isSyncingLibrary: Bool = false
    @State private var showHistory: Bool = false
    
    var isKeyEmpty: Bool {
        switch selectedProvider {
        case "Gemini": return geminiKey.trimmingCharacters(in: .whitespaces).isEmpty
        case "Groq": return groqKey.trimmingCharacters(in: .whitespaces).isEmpty
        case "OpenRouter": return openrouterKey.trimmingCharacters(in: .whitespaces).isEmpty
        default: return true
        }
    }
    
    var body: some View {
        SyncrosaPage {
            SyncrosaPageHeader(
                title: lang.t("settings"),
                systemImage: "gearshape",
                subtitle: lang.selectedLanguage == "ru" ? "Язык, безопасность процессов и подключение AI-провайдера." : "Language, process safety, and AI provider setup.",
                helpAction: { showHelp = true }
            )
                
                // Group 0: Language
                VStack(alignment: .leading, spacing: 10) {
                    Label(lang.t("lang_section"), systemImage: "globe")
                        .font(.headline)
                    
                    SyncrosaAdaptiveRow(spacing: 12) {
                        Text("Select Language")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        SyncrosaGlassMenu(selection: Binding(
                            get: { self.lang.selectedLanguage },
                            set: { self.lang.selectedLanguage = $0 }
                        ), options: languageOptions, width: 230)
                    }
                }
                .syncrosaCard()

                // Group 1a: Safety
                VStack(alignment: .leading, spacing: 10) {
                    Label(lang.selectedLanguage == "ru" ? "Безопасность процессов" : "Process Safety", systemImage: "shield.lefthalf.filled")
                        .font(.headline)

                    Toggle(isOn: $onlyLocalMode) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Only Local Mode")
                                .fontWeight(.semibold)
                            Text(lang.selectedLanguage == "ru" ? "Пропускать сетевые запросы метаданных и работать только с локальными файлами/медиатекой." : "Skip online metadata lookups and work only with local files/library data.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(SyncrosaSwitchToggleStyle())

                    Button(action: { showHistory = true }) {
                        Label(lang.selectedLanguage == "ru" ? "Открыть историю операций" : "Open Operation History", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(SyncrosaSecondaryButtonStyle())
                }
                .syncrosaCard()
                
                // Group 1: iTunes Library
                VStack(alignment: .leading, spacing: 10) {
                    Label(lang.t("lib_cleanup"), systemImage: "music.note.house")
                        .font(.headline)
                    
                    Text(lang.t("refresh_cache"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button(action: syncLibrary) {
                        if isSyncingLibrary {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(lang.t("sync_library"))
                        }
                    }
                    .buttonStyle(SyncrosaSecondaryButtonStyle())
                    .disabled(isSyncingLibrary)
                }
                .syncrosaCard()
                
                // Group 2: AI Configuration
                VStack(alignment: .leading, spacing: 15) {
                    Label(lang.t("provider"), systemImage: "cpu")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(lang.t("select_provider"))
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        SyncrosaGlassSegmentedPicker(
                            selection: $selectedProvider,
                            options: providers.map { SyncrosaMenuOption(title: $0, value: $0) },
                            minSegmentWidth: 104
                        )
                        .onChange(of: selectedProvider) { _, _ in isKeyValidated = false }
                    }
                    
                    VStack(alignment: .leading, spacing: 15) {
                        if selectedProvider == "Gemini" {
                            modelPicker(selection: $geminiModel, models: geminiModels)
                            keyField(title: lang.t("enter_key"), text: $geminiKey)
                        } else if selectedProvider == "Groq" {
                            modelPicker(selection: $groqModel, models: groqModels)
                            keyField(title: lang.t("enter_key"), text: $groqKey)
                        } else {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(lang.t("select_model"))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                HStack(alignment: .center, spacing: 10) {
                                    SyncrosaGlassMenu(
                                        selection: $openrouterModel,
                                        options: openRouterModels.map { SyncrosaMenuOption(title: $0, value: $0) },
                                        width: 360
                                    )
                                    
                                    Button(action: syncModels) {
                                        if isSyncingModels {
                                            ProgressView().controlSize(.small)
                                        } else {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.system(size: 11, weight: .bold))
                                        }
                                    }
                                    .buttonStyle(SyncrosaSecondaryButtonStyle())
                                    .controlSize(.regular)
                                    .disabled(isSyncingModels)
                                }
                            }
                            keyField(title: lang.t("enter_key"), text: $openrouterKey)
                        }
                    }
                    .padding(.vertical, 10)
                    .onChange(of: geminiKey) { _, _ in isKeyValidated = false }
                    .onChange(of: groqKey) { _, _ in isKeyValidated = false }
                    .onChange(of: openrouterKey) { _, _ in isKeyValidated = false }
                    
                    Button(action: validateKey) {
                        if isValidating {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(lang.t("validate_save"))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(SyncrosaPrimaryButtonStyle())
                    .controlSize(.large)
                    .disabled(isValidating || isKeyEmpty)
                }
                .syncrosaCard()
                
                Spacer()
        }
        .notification(message: $activeNotification)
        .onAppear {
            geminiKey = KeychainHelper.shared.readString(service: KeychainHelper.serviceName, account: "gemini") ?? ""
            groqKey = KeychainHelper.shared.readString(service: KeychainHelper.serviceName, account: "groq") ?? ""
            openrouterKey = KeychainHelper.shared.readString(service: KeychainHelper.serviceName, account: "openrouter") ?? ""
        }
        .sheet(isPresented: $showHelp) {
            helpSheetView
        }
        .sheet(isPresented: $showHistory) {
            OperationHistoryView()
        }
    }
    
    var helpSheetView: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(lang.selectedLanguage == "ru" ? "Инструкция: Настройки" : "Help: Settings")
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
                         "В разделе «Настройки» вы можете настроить язык приложения и параметры подключения к облачным провайдерам искусственного интеллекта (Gemini, Groq, OpenRouter).\n\n" +
                         "Ключевые шаги:\n" +
                         "1. Выберите язык интерфейса.\n" +
                         "2. Выберите нужного ИИ-провайдера и укажите его API-ключ.\n" +
                         "3. Нажмите кнопку «Проверить и сохранить» для сохранения ключа в безопасной системной связке ключей (Keychain).\n" +
                         "4. Используйте кнопку синхронизации моделей для автоматического обновления доступных нейросетей." :
                         
                         "In the Settings section, you can configure the interface language and connectivity options for AI providers (Gemini, Groq, OpenRouter).\n\n" +
                         "Key Steps:\n" +
                         "1. Select the interface language.\n" +
                         "2. Choose your preferred AI provider and enter your API Key.\n" +
                         "3. Click 'Validate & Save Key' to verify the API key and store it securely in the macOS Keychain.\n" +
                         "4. Use the sync buttons to update available models or manually refresh the local music database cache."
                    )
                    .font(.body)
                }
            }
            .frame(minWidth: 450, minHeight: 300)
        }
        .padding()
    }

    
    @ViewBuilder
    func modelPicker(selection: Binding<String>, models: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(lang.t("select_model"))
                .font(.caption2)
                .foregroundColor(.secondary)
            SyncrosaGlassMenu(
                selection: selection,
                options: models.map { SyncrosaMenuOption(title: $0, value: $0) },
                width: 300
            )
        }
    }
    
    @ViewBuilder
    func keyField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(lang.t("enter_key"))
                .font(.caption2)
                .foregroundColor(.secondary)
            SecureField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
    
    func syncModels() {
        isSyncingModels = true
        AIService.shared.fetchOpenRouterModels { models in
            DispatchQueue.main.async {
                if let models = models, !models.isEmpty {
                    self.openRouterModels = models
                    self.activeNotification = NotificationMessage(text: lang.t("sync_success"), isError: false)
                } else {
                    self.activeNotification = NotificationMessage(text: "Failed to sync models.", isError: true)
                }
                isSyncingModels = false
            }
        }
    }
    
    func syncLibrary() {
        isSyncingLibrary = true
        self.activeNotification = NotificationMessage(text: "Syncing...", isError: false)
        DispatchQueue.global().async {
            guard let libraryCount = MusicService.shared.getLibraryTrackCount() else {
                DispatchQueue.main.async {
                    isSyncingLibrary = false
                    self.activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Не удалось прочитать медиатеку Music, или она пуста." : "Could not read your Music library, or it may be empty.", isError: true)
                }
                return
            }

            guard libraryCount > 0 else {
                DispatchQueue.main.async {
                    isSyncingLibrary = false
                    self.activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Music прочитан, но треков в медиатеке нет." : "Music was read, but the library has no tracks.", isError: true)
                }
                return
            }

            let tracks = MusicService.shared.getAllTracks { current, total in
                DispatchQueue.main.async {
                    self.activeNotification = NotificationMessage(text: lang.t("scanning", current, total), isError: false)
                }
            }
            DispatchQueue.main.async {
                isSyncingLibrary = false
                if tracks.isEmpty {
                    self.activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Music прочитан, но доступных треков не вернул." : "Music was read, but no usable tracks were returned.", isError: true)
                } else {
                    self.activeNotification = NotificationMessage(text: lang.t("msg_lib_synced"), isError: false)
                }
            }
        }
    }
    
    func validateKey() {
        isValidating = true
        self.activeNotification = NotificationMessage(text: lang.t("checking"), isError: false)
        let key = selectedProvider == "Gemini" ? geminiKey : (selectedProvider == "Groq" ? groqKey : openrouterKey)
        let model = selectedProvider == "Gemini" ? geminiModel : (selectedProvider == "Groq" ? groqModel : openrouterModel)
        
        AIService.shared.validateAPIKey(provider: selectedProvider, apiKey: key, model: model) { success, message in
            DispatchQueue.main.async {
                isValidating = false
                if success {
                    isKeyValidated = true
                    
                    // Save to Keychain on success
                    let account = selectedProvider.lowercased()
                    KeychainHelper.shared.saveString(key, service: KeychainHelper.serviceName, account: account)
                    
                    self.activeNotification = NotificationMessage(text: lang.t("welcome"), isError: false)
                } else {
                    isKeyValidated = false
                    self.activeNotification = NotificationMessage(text: lang.t("val_failed", message), isError: true)
                }
            }
        }
    }
}
