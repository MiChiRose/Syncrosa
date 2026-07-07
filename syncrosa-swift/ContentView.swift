import SwiftUI
import AppKit

enum SyncrosaTheme {
    static let pageBackground = Color(nsColor: .windowBackgroundColor)
    static let panelBackground = Color(nsColor: .controlBackgroundColor)
    static let textBackground = Color(nsColor: .textBackgroundColor)
    static let subtleBackground = Color(nsColor: .separatorColor).opacity(0.10)
    static let panelBorder = Color(nsColor: .separatorColor)
    static let placeholderIcon = Color(nsColor: .tertiaryLabelColor)
    static let warningForeground = Color(nsColor: .systemRed)
    static let warningBackground = Color(nsColor: .systemRed).opacity(0.12)
    static let warningBorder = Color(nsColor: .systemRed).opacity(0.38)
    static let softShadow = Color.black.opacity(0.10)
}

enum MusicLibraryStatus: Equatable {
    case checking
    case available(Int)
    case empty
    case unavailable

    var shouldBlockLibraryTools: Bool {
        switch self {
        case .checking, .empty:
            return true
        case .available, .unavailable:
            return false
        }
    }

    var shouldShowLibraryNotice: Bool {
        switch self {
        case .checking, .empty, .unavailable:
            return true
        case .available:
            return false
        }
    }

    var isAvailable: Bool {
        if case .available(let count) = self {
            return count > 0
        }
        return false
    }
}

struct ContentView: View {
    @ObservedObject var lang = LocalizationService.shared
    
    @AppStorage("is_key_validated") private var isKeyValidated: Bool = false
    
    @ObservedObject var usbService = USBService.shared
    @State private var selectedTab: Tab? = nil
    @State private var showHelp: Bool = false
    @State private var musicLibraryStatus: MusicLibraryStatus = .checking
    @State private var isRefreshingLibraryStatus: Bool = false
    
    enum Tab: Hashable {
        case overview
        case playlist
        case offlinePlaylist
        case fixer
        case folderFix
        case infoEraser
        case recoveryCenter
        case libraryDoctor
        case duplicateFinder
        case usbExport
        case coversOptimizer
        case settings
    }
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Group {
                    NavigationLink(value: Tab.overview) {
                        Label("Overview", systemImage: "gauge.with.dots.needle.33percent")
                    }

                    NavigationLink(value: Tab.playlist) {
                        Label(lang.t("ai_playlist"), systemImage: "music.note.list")
                    }
                    .disabled(!isKeyValidated || musicLibraryStatus.shouldBlockLibraryTools)
                    .opacity((isKeyValidated && !musicLibraryStatus.shouldBlockLibraryTools) ? 1.0 : 0.5)
                    
                    NavigationLink(value: Tab.offlinePlaylist) {
                        Label(lang.selectedLanguage == "ru" ? "Офлайн плейлист" : "Offline Playlist", systemImage: "music.note.house")
                    }
                    .disabled(musicLibraryStatus.shouldBlockLibraryTools)
                    .opacity(musicLibraryStatus.shouldBlockLibraryTools ? 0.5 : 1.0)
                    
                    NavigationLink(value: Tab.fixer) {
                        Label(lang.t("media_fixer"), systemImage: "wrench.and.screwdriver")
                    }
                    .disabled(musicLibraryStatus.shouldBlockLibraryTools)
                    .opacity(musicLibraryStatus.shouldBlockLibraryTools ? 0.5 : 1.0)
                    
                    NavigationLink(value: Tab.folderFix) {
                        Label(lang.t("folder_fix"), systemImage: "folder.badge.gearshape")
                    }

                    NavigationLink(value: Tab.infoEraser) {
                        Label("Info Eraser", systemImage: "eraser.line.dashed")
                    }

                    NavigationLink(value: Tab.recoveryCenter) {
                        Label(lang.selectedLanguage == "ru" ? "Восстановление" : "Recovery Center", systemImage: "cross.case")
                    }

                    NavigationLink(value: Tab.libraryDoctor) {
                        Label("Library Doctor", systemImage: "stethoscope")
                    }
                    .disabled(musicLibraryStatus.shouldBlockLibraryTools)
                    .opacity(musicLibraryStatus.shouldBlockLibraryTools ? 0.5 : 1.0)
                    
                    NavigationLink(value: Tab.duplicateFinder) {
                        Label(lang.selectedLanguage == "ru" ? "Поиск дубликатов" : "Duplicate Finder", systemImage: "arrow.2.squarepath")
                    }
                    .disabled(musicLibraryStatus.shouldBlockLibraryTools)
                    .opacity(musicLibraryStatus.shouldBlockLibraryTools ? 0.5 : 1.0)
                    
                    NavigationLink(value: Tab.usbExport) {
                        Label(lang.t("usb_export"), systemImage: "externaldrive.fill")
                    }
                    .disabled(usbService.isSearching || musicLibraryStatus.shouldBlockLibraryTools)
                    .opacity((usbService.isSearching || musicLibraryStatus.shouldBlockLibraryTools) ? 0.5 : 1.0)
                    
                    NavigationLink(value: Tab.coversOptimizer) {
                        Label(lang.t("covers_optimizer"), systemImage: "photo.on.rectangle.angled")
                    }
                    .disabled(musicLibraryStatus.shouldBlockLibraryTools)
                    .opacity(musicLibraryStatus.shouldBlockLibraryTools ? 0.5 : 1.0)

                    if musicLibraryStatus.shouldShowLibraryNotice {
                        MusicLibrarySidebarStatusView(
                            status: musicLibraryStatus,
                            isRefreshing: isRefreshingLibraryStatus,
                            refreshAction: refreshMusicLibraryStatus
                        )
                    }
                }
                
                Divider()
                
                NavigationLink(value: Tab.settings) {
                    Label(lang.t("settings"), systemImage: "gear")
                }
            }
            .listStyle(SidebarListStyle())
            .navigationTitle("Syncrosa")
            .frame(minWidth: 200)
        } detail: {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    // Main Content
                    Group {
                        if !isKeyValidated && selectedTab == .playlist {
                            SetupRequiredView(selectedTab: $selectedTab)
                        } else {
                            switch selectedTab {
                            case .playlist: PlaylistGeneratorView()
                            case .offlinePlaylist: OfflinePlaylistGeneratorView()
                            case .fixer: MediaFixerView()
                            case .folderFix: FileMediaFixerView()
                            case .infoEraser: InfoEraserView()
                            case .recoveryCenter: RecoveryCenterView()
                            case .libraryDoctor: LibraryDoctorView()
                            case .duplicateFinder: DuplicateFinderView()
                            case .usbExport: USBExportView()
                            case .coversOptimizer: CoversOptimizerView()
                            case .overview:
                                OverviewView(
                                    libraryStatus: musicLibraryStatus,
                                    isRefreshingLibraryStatus: isRefreshingLibraryStatus,
                                    refreshLibraryStatus: refreshMusicLibraryStatus,
                                    openLibraryDoctor: openLibraryDoctorIfAvailable,
                                    openRecoveryCenter: { selectedTab = .recoveryCenter }
                                )
                            case .settings: SettingsView()
                            case .none:
                                if musicLibraryStatus.isAvailable {
                                    OverviewView(
                                    libraryStatus: musicLibraryStatus,
                                    isRefreshingLibraryStatus: isRefreshingLibraryStatus,
                                    refreshLibraryStatus: refreshMusicLibraryStatus,
                                    openLibraryDoctor: openLibraryDoctorIfAvailable,
                                    openRecoveryCenter: { selectedTab = .recoveryCenter }
                                )
                                } else {
                                    MusicLibraryUnavailableView(
                                        status: musicLibraryStatus,
                                        isRefreshing: isRefreshingLibraryStatus,
                                        refreshAction: refreshMusicLibraryStatus
                                    )
                                }
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                    
                    // Global Footer
                    VStack {
                        Divider()
                        Text(lang.t("footer"))
                            .font(.system(size: 10))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 12)
                    }
                    .background(VisualEffectView(material: .contentBackground, blendingMode: .withinWindow))
                }
                
                // Floating Help Button (Only for Settings)
                if selectedTab == .settings {
                    Button(action: { showHelp.toggle() }) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(SyncrosaGlassIconButtonStyle(size: 34, tint: SyncrosaTheme.accent))
                    .padding(20)
                    .popover(isPresented: $showHelp, arrowEdge: .trailing) {
                        HelpPopoverView()
                    }
                }
            }
            .background(SyncrosaTheme.pageBackground)
        }
        .onAppear {
            refreshMusicLibraryStatus()
            if !isKeyValidated {
                selectedTab = .settings
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshMusicLibraryStatus()
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    private func refreshMusicLibraryStatus() {
        guard !isRefreshingLibraryStatus else { return }
        isRefreshingLibraryStatus = true

        DispatchQueue.global(qos: .userInitiated).async {
            let count = MusicService.shared.getLibraryTrackCount()
            let newStatus: MusicLibraryStatus
            if let count = count {
                newStatus = count > 0 ? .available(count) : .empty
            } else {
                newStatus = .unavailable
            }

            DispatchQueue.main.async {
                musicLibraryStatus = newStatus
                isRefreshingLibraryStatus = false

                if requiresMusicLibrary(selectedTab) && newStatus == .empty {
                    selectedTab = nil
                } else if selectedTab == nil && newStatus.isAvailable && isKeyValidated {
                    selectedTab = .overview
                }
            }
        }
    }

    private func openLibraryDoctorIfAvailable() {
        if musicLibraryStatus.shouldBlockLibraryTools {
            refreshMusicLibraryStatus()
            return
        }
        selectedTab = .libraryDoctor
    }

    private func requiresMusicLibrary(_ tab: Tab?) -> Bool {
        switch tab {
        case .playlist, .offlinePlaylist, .fixer, .libraryDoctor, .duplicateFinder, .usbExport, .coversOptimizer:
            return true
        case .overview, .folderFix, .infoEraser, .recoveryCenter, .settings, .none:
            return false
        }
    }
}

struct MusicLibrarySidebarStatusView: View {
    @ObservedObject var lang = LocalizationService.shared
    let status: MusicLibraryStatus
    let isRefreshing: Bool
    let refreshAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundColor(.secondary)
            Text(shortMessage)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button(action: refreshAction) {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .buttonStyle(SyncrosaGlassIconButtonStyle(size: 24))
            .disabled(isRefreshing)
            .help(lang.selectedLanguage == "ru" ? "Проверить Music ещё раз" : "Check Music again")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    private var iconName: String {
        switch status {
        case .checking:
            return "music.note"
        case .empty:
            return "tray"
        case .unavailable:
            return "exclamationmark.triangle"
        case .available:
            return "checkmark.circle"
        }
    }

    private var shortMessage: String {
        switch status {
        case .checking:
            return lang.selectedLanguage == "ru" ? "Проверка Music..." : "Checking Music..."
        case .empty:
            return lang.selectedLanguage == "ru" ? "Music пуста" : "Music is empty"
        case .unavailable:
            return lang.selectedLanguage == "ru" ? "Music не удалось проверить" : "Music check failed"
        case .available:
            return ""
        }
    }
}

struct MusicLibraryUnavailableView: View {
    @ObservedObject var lang = LocalizationService.shared
    let status: MusicLibraryStatus
    let isRefreshing: Bool
    let refreshAction: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            if status == .checking || isRefreshing {
                ProgressView()
                    .controlSize(.large)
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(message)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            } else {
                SyncrosaEmptyState(
                    systemImage: status == .empty ? "tray" : "music.note.list",
                    title: title,
                    message: message
                )
            }

            Button(action: refreshAction) {
                Label(lang.selectedLanguage == "ru" ? "Проверить ещё раз" : "Check Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(SyncrosaSecondaryButtonStyle())
            .disabled(isRefreshing)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String {
        switch status {
        case .checking:
            return lang.selectedLanguage == "ru" ? "Проверяю медиатеку Music" : "Checking Music Library"
        case .empty:
            return lang.selectedLanguage == "ru" ? "В Music нет треков" : "Music Has No Tracks"
        case .unavailable:
            return lang.selectedLanguage == "ru" ? "Music не удалось проверить" : "Could Not Check Music"
        case .available:
            return ""
        }
    }

    private var message: String {
        switch status {
        case .checking:
            return lang.selectedLanguage == "ru" ? "Сейчас проверяю, есть ли треки в вашей медиатеке." : "Checking whether your library contains tracks."
        case .empty:
            return lang.selectedLanguage == "ru" ? "Вкладки, которые работают с треками Music, временно заблокированы. Добавьте музыку в Music и нажмите «Проверить ещё раз»." : "Tabs that work with Music tracks are temporarily disabled. Add music to Music, then click Check Again."
        case .unavailable:
            return lang.selectedLanguage == "ru" ? "Syncrosa не получила ответ от Music. Вкладки не заблокированы: попробуйте открыть нужный инструмент. Если macOS спросит доступ к Music, нажмите «Разрешить»." : "Syncrosa did not get a response from Music. The tabs are not blocked: try opening the tool you need. If macOS asks for Music access, click Allow."
        case .available:
            return ""
        }
    }
}

struct HelpPopoverView: View {
    @ObservedObject var lang = LocalizationService.shared
    @AppStorage("selected_provider") private var selectedProvider: String = "Gemini"
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Text(lang.t("help_title"))
                    .font(.headline)
                
                Divider()
                
                if selectedProvider == "Gemini" {
                    Text("Gemini (Google):")
                        .fontWeight(.bold)
                    Text("1. Go to aistudio.google.com\n2. Click 'Get API key' -> 'Create API key'.")
                } else if selectedProvider == "Groq" {
                    Text("Groq:")
                        .fontWeight(.bold)
                    Text("1. Go to console.groq.com\n2. Click 'API Keys' -> 'Create API Key'.")
                } else {
                    Text("OpenRouter (BEST FOR BYPASSING GEO-BLOCKS):")
                        .fontWeight(.bold)
                    Text("1. Go to openrouter.ai\n2. Click 'Keys' -> 'Create Key'.\nOpenRouter provides access to FREE models from Google and Meta, even if they are blocked in your country.")
                }
                
                Divider()
                
                Text(lang.t("note_sync"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .frame(width: 350, height: 250)
    }
}

struct SetupRequiredView: View {
    @ObservedObject var lang = LocalizationService.shared
    @Binding var selectedTab: ContentView.Tab?
    var body: some View {
        VStack(spacing: 20) {
            SyncrosaEmptyState(
                systemImage: "lock.shield",
                title: lang.t("setup_required"),
                message: lang.t("setup_instr")
            )
            Button(lang.t("go_settings")) {
                selectedTab = .settings
            }
            .buttonStyle(SyncrosaPrimaryButtonStyle())
        }
    }
}
