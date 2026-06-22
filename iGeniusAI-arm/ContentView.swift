import SwiftUI

struct ContentView: View {
    @ObservedObject var lang = LocalizationService.shared
    
    @AppStorage("is_key_validated") private var isKeyValidated: Bool = false
    
    @State private var selectedTab: Tab? = nil
    @State private var showHelp: Bool = false
    
    enum Tab: Hashable {
        case playlist
        case fixer
        case folderFix
        case usbExport
        case settings
    }
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Group {
                    NavigationLink(value: Tab.playlist) {
                        Label(lang.t("ai_playlist"), systemImage: "music.note.list")
                    }
                    .disabled(!isKeyValidated)
                    .opacity(isKeyValidated ? 1.0 : 0.5)
                    
                    NavigationLink(value: Tab.fixer) {
                        Label(lang.t("media_fixer"), systemImage: "wrench.and.screwdriver")
                    }
                    
                    NavigationLink(value: Tab.folderFix) {
                        Label(lang.t("folder_fix"), systemImage: "folder.badge.gearshape")
                    }
                    
                    NavigationLink(value: Tab.usbExport) {
                        Label(lang.t("usb_export"), systemImage: "externaldrive.fill")
                    }
                }
                
                Divider()
                
                NavigationLink(value: Tab.settings) {
                    Label(lang.t("settings"), systemImage: "gear")
                }
            }
            .listStyle(SidebarListStyle())
            .navigationTitle("iGeniusAI")
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
                            case .fixer: MediaFixerView()
                            case .folderFix: FileMediaFixerView()
                            case .usbExport: USBExportView()
                            case .settings: SettingsView()
                            case .none: Text(lang.t("select_folder_msg")).foregroundColor(.secondary)
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
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 24))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .padding(20)
                    .popover(isPresented: $showHelp, arrowEdge: .trailing) {
                        HelpPopoverView()
                    }
                }
            }
        }
        .onAppear {
            if !isKeyValidated {
                selectedTab = .settings
            } else if selectedTab == nil {
                selectedTab = .playlist
            }
        }
        .frame(minWidth: 800, minHeight: 600)
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
            Image(systemName: "lock.shield")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text(lang.t("setup_required"))
                .font(.title)
            Text(lang.t("setup_instr"))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            Button(lang.t("go_settings")) {
                selectedTab = .settings
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
