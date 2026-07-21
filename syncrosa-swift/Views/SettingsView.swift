import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var lang = LocalizationService.shared
    @ObservedObject private var appearance = SyncrosaAppearanceService.shared
    
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
    @State private var isCheckingUpdates: Bool = false
    @State private var isUpdateAvailable: Bool = false
    @State private var updateStatusText: String = ""
    @State private var updateURL: URL? = nil
    @State private var latestReleaseTitle: String = ""
    @State private var latestReleaseNotes: String = ""
    @State private var showReleaseNotes: Bool = false
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
                subtitle: lang.selectedLanguage == "ru" ? "Оформление, язык, безопасность процессов и подключение AI-провайдера." : "Appearance, language, process safety, and AI provider setup.",
                helpAction: { showHelp = true }
            )

                VStack(alignment: .leading, spacing: 14) {
                    Label(lang.selectedLanguage == "ru" ? "Оформление" : "Appearance", systemImage: "paintpalette")
                        .font(.headline)

                    Text(lang.selectedLanguage == "ru"
                         ? "Системный режим автоматически повторяет светлую или тёмную тему macOS, включая переключение по расписанию."
                         : "System mode automatically follows the macOS light or dark appearance, including scheduled changes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    SyncrosaGlassSegmentedPicker(
                        selection: Binding(
                            get: { appearance.appearanceMode },
                            set: { appearance.appearanceMode = $0 }
                        ),
                        options: SyncrosaAppearanceMode.allCases.map {
                            SyncrosaMenuOption(title: $0.displayName(language: lang.selectedLanguage), value: $0)
                        },
                        minSegmentWidth: 104
                    )

                    Divider()

                    SyncrosaSectionLabel(
                        text: lang.selectedLanguage == "ru" ? "ЦВЕТОВАЯ ТЕМА" : "COLOR THEME",
                        systemImage: "swatchpalette"
                    )

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 10)], spacing: 10) {
                        ForEach(SyncrosaThemeChoice.allCases) { theme in
                            SyncrosaThemeChoiceButton(
                                theme: theme,
                                selectedTheme: appearance.selectedTheme,
                                language: lang.selectedLanguage,
                                action: { appearance.selectedTheme = theme }
                            )
                        }
                    }
                }
                .syncrosaCard()
                
                // Group 0: Language
                VStack(alignment: .leading, spacing: 10) {
                    Label(lang.t("lang_section"), systemImage: "globe")
                        .font(.headline)
                    
                    SyncrosaAdaptiveRow(spacing: 12) {
                        Text(lang.t("select_language"))
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
                    Label(lang.t("process_safety"), systemImage: "shield.lefthalf.filled")
                        .font(.headline)

                    Toggle(isOn: $onlyLocalMode) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(lang.t("only_local_mode"))
                                .fontWeight(.semibold)
                            Text(lang.selectedLanguage == "ru" ? "Пропускать сетевые запросы метаданных и работать только с локальными файлами/медиатекой." : "Skip online metadata lookups and work only with local files/library data.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(SyncrosaSwitchToggleStyle())

                    Button(action: { showHistory = true }) {
                        Label(lang.t("operation_history"), systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(SyncrosaSecondaryButtonStyle())
                }
                .syncrosaCard()
                
                // Group 1b: Updates
                VStack(alignment: .leading, spacing: 12) {
                    Label(lang.t("updates"), systemImage: "arrow.down.circle")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(lang.selectedLanguage == "ru" ? "Текущая версия: \(currentAppVersion)" : "Current version: \(currentAppVersion)")
                            .fontWeight(.semibold)
                        Text(updateStatusText.isEmpty ? (lang.selectedLanguage == "ru" ? "Проверяйте релизы и скачивайте правильный архив для SwiftUI-версии." : "Check releases and open the correct SwiftUI download.") : updateStatusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    SyncrosaAdaptiveRow(spacing: 10) {
                        Button(action: checkForUpdates) {
                            if isCheckingUpdates {
                                ProgressView().controlSize(.small)
                            } else {
                                Label(lang.t("check_updates"), systemImage: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(SyncrosaSecondaryButtonStyle())
                        .disabled(isCheckingUpdates)

                        Button(action: openUpdateURL) {
                            Label(lang.t("update_app"), systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(SyncrosaPrimaryButtonStyle())
                        .disabled(!isUpdateAvailable)

                        Button(action: { showReleaseNotes = true }) {
                            Label(lang.t("release_notes"), systemImage: "doc.text")
                        }
                        .buttonStyle(SyncrosaSecondaryButtonStyle())
                        .disabled(latestReleaseNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
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
        .sheet(isPresented: $showReleaseNotes) {
            releaseNotesSheet
        }
    }
    
    var helpSheetView: some View {
        SyncrosaHelpSheet(
            title: lang.selectedLanguage == "ru" ? "Настройки" : "Settings",
            summary: lang.selectedLanguage == "ru"
                ? "Здесь настраиваются оформление, язык, безопасный локальный режим, обновления и подключение к AI-провайдерам."
                : "Configure appearance, language, local-only safety, updates, and AI provider access.",
            steps: lang.selectedLanguage == "ru" ? [
                "Выберите системную, светлую или тёмную схему и цветовой акцент.",
                "Выберите язык интерфейса.",
                "Включите локальный режим, если сетевые запросы метаданных не нужны.",
                "Выберите AI-провайдера, модель и введите API-ключ.",
                "Проверьте ключ. После успешной проверки он сохраняется в macOS Keychain."
            ] : [
                "Choose system, light, or dark appearance and a color accent.",
                "Choose the interface language.",
                "Enable local-only mode when online metadata lookups are not needed.",
                "Choose an AI provider and model, then enter its API key.",
                "Validate the key. A valid key is stored securely in macOS Keychain."
            ],
            notes: lang.selectedLanguage == "ru" ? [
                "Кнопка обновления становится активной только после обнаружения более новой версии.",
                "Sync Library перечитывает Music и может занять время на большой медиатеке."
            ] : [
                "Update App becomes available only after a newer version is found.",
                "Sync Library rereads Music and can take time for a large library."
            ],
            dismiss: { showHelp = false }
        )
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

    var currentAppVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        if let version = version, !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return version
        }
        return "Development"
    }

    func checkForUpdates() {
        guard !isCheckingUpdates else { return }
        isCheckingUpdates = true
        isUpdateAvailable = false
        updateURL = nil
        latestReleaseTitle = ""
        latestReleaseNotes = ""
        updateStatusText = lang.selectedLanguage == "ru" ? "Проверяю обновления Syncrosa..." : "Checking Syncrosa updates..."

        guard let url = URL(string: "https://syncrosa-updates.telegraphica.workers.dev/v1/update-manifest?platform=macos&track=swiftui&channel=stable") else {
            isCheckingUpdates = false
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        request.setValue("Syncrosa/\(currentAppVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let result = self.parseUpdateResponse(data: data, response: response as? HTTPURLResponse, error: error)
            DispatchQueue.main.async {
                self.isCheckingUpdates = false
                self.isUpdateAvailable = result.available
                self.updateURL = result.available ? result.url : nil
                self.updateStatusText = result.message
                self.latestReleaseTitle = result.releaseTitle
                self.latestReleaseNotes = result.releaseNotes
                self.activeNotification = NotificationMessage(text: result.message, isError: result.isError)
            }
        }.resume()
    }

    var releaseNotesSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(latestReleaseTitle.isEmpty ? "Syncrosa Release Notes" : latestReleaseTitle, systemImage: "doc.text")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
                Button(lang.t("close")) {
                    showReleaseNotes = false
                }
                .buttonStyle(SyncrosaSecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                ReleaseNotesMarkdownView(markdown: normalizedReleaseNotesMarkdown(latestReleaseNotes))
                    .padding(2)
            }
            .frame(minHeight: 320)
        }
        .padding(24)
        .frame(minWidth: 520, idealWidth: 680, maxWidth: 840, minHeight: 380, idealHeight: 460, maxHeight: 640)
    }

    var releaseNotesAttributed: AttributedString {
        let markdown = normalizedReleaseNotesMarkdown(latestReleaseNotes)
        if let attributed = try? AttributedString(markdown: markdown) {
            return attributed
        }
        return AttributedString(stripMarkdownFallback(markdown))
    }

    func normalizedReleaseNotesMarkdown(_ raw: String) -> String {
        var output: [String] = []
        var insideFence = false
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("```") {
                insideFence.toggle()
                continue
            }
            output.append(insideFence ? "    \(line)" : line)
        }
        return output.joined(separator: "\n")
    }

    func stripMarkdownFallback(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "### ", with: "")
            .replacingOccurrences(of: "## ", with: "")
            .replacingOccurrences(of: "# ", with: "")
    }

    func parseUpdateResponse(data: Data?, response: HTTPURLResponse?, error: Error?) -> (message: String, url: URL?, available: Bool, isError: Bool, releaseTitle: String, releaseNotes: String) {
        if error != nil {
            let message = lang.selectedLanguage == "ru" ? "Не удалось проверить обновления Syncrosa." : "Could not check Syncrosa updates."
            return (message, nil, false, true, "", "")
        }

        if let response, !(200...299).contains(response.statusCode) {
            let message = lang.selectedLanguage == "ru"
                ? "Сервис обновлений временно недоступен. Попробуйте позже."
                : "The update service is temporarily unavailable. Try again later."
            return (message, nil, false, true, "", "")
        }

        guard let data = data,
              let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else {
            let message = lang.selectedLanguage == "ru" ? "Сервис обновлений вернул неожиданный ответ." : "The update service returned an unexpected response."
            return (message, nil, false, true, "", "")
        }

        let latestVersion = ((json["tag_name"] as? String) ?? (json["name"] as? String) ?? "").replacingOccurrences(of: "v", with: "")
        let releaseTitle = (json["name"] as? String) ?? "Syncrosa \(latestVersion)"
        let releaseNotes = (json["body"] as? String) ?? ""
        let htmlURL = URL(string: (json["html_url"] as? String) ?? (json["release_url"] as? String) ?? "https://github.com/MiChiRose/Syncrosa/releases/latest")
        let manifestDownload = URL(string: (json["download_url"] as? String) ?? (json["downloadURL"] as? String) ?? "")
        var assetURL: URL? = nil
        if let assets = json["assets"] as? [[String: Any]] {
            for asset in assets {
                let name = asset["name"] as? String ?? ""
                if name.contains("Syncrosa_SwiftUI_v"), let download = (asset["browser_download_url"] as? String) ?? (asset["download_url"] as? String) {
                    assetURL = URL(string: download)
                    break
                }
            }
        }

        if latestVersion.isEmpty {
            let message = lang.selectedLanguage == "ru" ? "Не удалось определить последнюю версию." : "Could not read the latest version."
            return (message, nil, false, true, releaseTitle, releaseNotes)
        }

        if currentAppVersion == "Development" {
            let message = lang.selectedLanguage == "ru" ? "Последний релиз: Syncrosa \(latestVersion). Это dev-сборка." : "Latest release: Syncrosa \(latestVersion). This is a development build."
            return (message, nil, false, false, releaseTitle, releaseNotes)
        }

        let comparison = compareVersions(latestVersion, currentAppVersion)
        if comparison == .orderedDescending {
            let message = lang.selectedLanguage == "ru" ? "Доступна Syncrosa \(latestVersion). Нажмите Update App." : "Syncrosa \(latestVersion) is available. Click Update App."
            return (message, assetURL ?? manifestDownload ?? htmlURL, true, false, releaseTitle, releaseNotes)
        }

        let message = lang.selectedLanguage == "ru" ? "У вас актуальная версия Syncrosa \(currentAppVersion)." : "You are up to date on Syncrosa \(currentAppVersion)."
        return (message, nil, false, false, releaseTitle, releaseNotes)
    }

    func openUpdateURL() {
        guard isUpdateAvailable, let updateURL else { return }
        NSWorkspace.shared.open(updateURL)
    }

    func compareVersions(_ left: String, _ right: String) -> ComparisonResult {
        let l = versionParts(left)
        let r = versionParts(right)
        for index in 0..<max(l.count, r.count) {
            let lv = index < l.count ? l[index] : 0
            let rv = index < r.count ? r[index] : 0
            if lv > rv { return .orderedDescending }
            if lv < rv { return .orderedAscending }
        }
        return .orderedSame
    }

    func versionParts(_ version: String) -> [Int] {
        version
            .replacingOccurrences(of: "v", with: "")
            .split { !$0.isNumber }
            .compactMap { Int($0) }
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

private struct SyncrosaThemeChoiceButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let theme: SyncrosaThemeChoice
    let selectedTheme: SyncrosaThemeChoice
    let language: String
    let action: () -> Void

    private var isSelected: Bool { theme == selectedTheme }

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                action()
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(theme.secondaryAccent)
                        .frame(width: 24, height: 24)
                        .offset(x: 5, y: -2)
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 24, height: 24)
                        .offset(x: -5, y: 2)
                        .overlay(Circle().stroke(Color.white.opacity(0.38), lineWidth: 1).offset(x: -5, y: 2))
                }
                .frame(width: 34, height: 30)

                Text(theme.displayName(language: language))
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? theme.accent : Color.secondary.opacity(0.45))
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                isSelected ? theme.accent.opacity(0.12) : SyncrosaTheme.panelBackground.opacity(0.45),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? theme.accent.opacity(0.72) : SyncrosaTheme.panelBorder.opacity(0.62), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.displayName(language: language))
        .accessibilityValue(isSelected ? (language == "ru" ? "Выбрано" : "Selected") : "")
    }
}

private struct ReleaseNotesMarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private var blocks: [ReleaseNotesBlock] {
        var output: [ReleaseNotesBlock] = []
        var paragraph: [String] = []
        var inCode = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            output.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll()
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("```") {
                flushParagraph()
                inCode.toggle()
                continue
            }
            if inCode {
                if !line.isEmpty {
                    output.append(.code(rawLine))
                }
                continue
            }
            if line.isEmpty {
                flushParagraph()
                continue
            }
            if line.hasPrefix("#") {
                flushParagraph()
                let level = line.prefix { $0 == "#" }.count
                let title = cleanInlineMarkdown(String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces))
                output.append(.heading(title, min(level, 3)))
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                output.append(.bullet(cleanInlineMarkdown(String(line.dropFirst(2)))))
                continue
            }
            paragraph.append(cleanInlineMarkdown(line))
        }
        flushParagraph()
        return output
    }

    @ViewBuilder
    private func blockView(_ block: ReleaseNotesBlock) -> some View {
        switch block {
        case .heading(let text, let level):
            Text(text)
                .font(level == 1 ? .title3.weight(.bold) : .headline.weight(.bold))
                .padding(.top, level == 1 ? 4 : 10)
        case .paragraph(let text):
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let text):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.system(size: 13, weight: .bold))
                Text(text)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .code(let text):
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SyncrosaTheme.subtleBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func cleanInlineMarkdown(_ value: String) -> String {
        value
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum ReleaseNotesBlock {
    case heading(String, Int)
    case paragraph(String)
    case bullet(String)
    case code(String)
}
