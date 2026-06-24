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
    
    @State private var activeNotification: NotificationMessage? = nil
    @State private var isValidating: Bool = false
    
    let providers = ["Gemini", "Groq", "OpenRouter"]
    let geminiModels = ["gemini-1.5-flash", "gemini-1.5-pro", "gemini-1.0-pro"]
    let groqModels = ["llama3-8b-8192", "llama3-70b-8192", "mixtral-8x7b-32768", "gemma-7b-it"]
    @State private var openRouterModels: [String] = AIService.shared.cachedOpenRouterModels
    @State private var isSyncingModels: Bool = false
    @State private var isSyncingLibrary: Bool = false
    
    var isKeyEmpty: Bool {
        switch selectedProvider {
        case "Gemini": return geminiKey.trimmingCharacters(in: .whitespaces).isEmpty
        case "Groq": return groqKey.trimmingCharacters(in: .whitespaces).isEmpty
        case "OpenRouter": return openrouterKey.trimmingCharacters(in: .whitespaces).isEmpty
        default: return true
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                // Group 0: Language
                VStack(alignment: .leading, spacing: 10) {
                    Label(lang.t("lang_section"), systemImage: "globe")
                        .font(.headline)
                    
                    Picker("Select Language", selection: Binding(
                        get: { self.lang.selectedLanguage },
                        set: { self.lang.selectedLanguage = $0 }
                    )) {
                        Text("English").tag("en")
                        Text("Русский").tag("ru")
                        Text("Беларуская").tag("be")
                        Text("한국어").tag("ko")
                        Text("日本語").tag("ja")
                        Text("中文").tag("zh")
                        Text("Deutsch").tag("de")
                        Text("Polski").tag("pl")
                        Text("Eesti").tag("et")
                        Text("Español").tag("es")
                    }
                    .pickerStyle(.menu)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
                
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
                    .buttonStyle(.bordered)
                    .disabled(isSyncingLibrary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
                
                // Group 2: AI Configuration
                VStack(alignment: .leading, spacing: 15) {
                    Label(lang.t("provider"), systemImage: "cpu")
                        .font(.headline)
                    
                    Picker(lang.t("select_provider"), selection: $selectedProvider) {
                        ForEach(providers, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedProvider) { _, _ in isKeyValidated = false }
                    
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
                                    Picker("", selection: $openrouterModel) {
                                        ForEach(openRouterModels, id: \.self) { model in
                                            Text(model).tag(model)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(minWidth: 200)
                                    
                                    Button(action: syncModels) {
                                        if isSyncingModels {
                                            ProgressView().controlSize(.small)
                                        } else {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.system(size: 11, weight: .bold))
                                        }
                                    }
                                    .buttonStyle(.bordered)
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
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isValidating || isKeyEmpty)
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
                
                Spacer()
            }
            .padding(30)
        }
        .notification(message: $activeNotification)
        .onAppear {
            geminiKey = KeychainHelper.shared.readString(service: KeychainHelper.serviceName, account: "gemini") ?? ""
            groqKey = KeychainHelper.shared.readString(service: KeychainHelper.serviceName, account: "groq") ?? ""
            openrouterKey = KeychainHelper.shared.readString(service: KeychainHelper.serviceName, account: "openrouter") ?? ""
        }
    }
    
    @ViewBuilder
    func modelPicker(selection: Binding<String>, models: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(lang.t("select_model"))
                .font(.caption2)
                .foregroundColor(.secondary)
            Picker("", selection: selection) {
                ForEach(models, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            .labelsHidden()
            .frame(minWidth: 200)
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
            _ = MusicService.shared.getAllTracks { current, total in
                DispatchQueue.main.async {
                    self.activeNotification = NotificationMessage(text: lang.t("scanning", current, total), isError: false)
                }
            }
            DispatchQueue.main.async {
                isSyncingLibrary = false
                self.activeNotification = NotificationMessage(text: lang.t("msg_lib_synced"), isError: false)
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
