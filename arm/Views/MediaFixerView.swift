import SwiftUI

struct MediaFixerView: View {
    @ObservedObject var lang = LocalizationService.shared
    @State private var isAnalyzing: Bool = false
    @State private var activeNotification: NotificationMessage? = nil
    @State private var mergeCandidates: [MergeGroup] = []
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    
    struct MergeGroup: Identifiable {
        let id = UUID()
        let mainAlbum: String
        let artist: String
        let trackIDs: [String]
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                // Card 1: Controls
                VStack(alignment: .leading, spacing: 15) {
                    Label(lang.selectedLanguage == "ru" ? "Очистка медиатеки" : "Library Cleanup", systemImage: "bolt.shield")
                        .font(.headline)
                    
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
                        
                        Button(action: fixMetadata) {
                            Label(lang.selectedLanguage == "ru" ? "Исправить выбранное" : "Fix Selected", systemImage: "wrench.and.screwdriver")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(mergeCandidates.isEmpty)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
                
                // Card 2: Results
                VStack(alignment: .leading, spacing: 10) {
                    Text(lang.selectedLanguage == "ru" ? "РЕЗУЛЬТАТЫ АНАЛИЗА" : "ANALYSIS RESULTS")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if mergeCandidates.isEmpty {
                        VStack(spacing: 15) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 40))
                                .foregroundColor(.gray.opacity(0.3))
                            Text(lang.selectedLanguage == "ru" ? "Проблем пока не обнаружено." : "No issues detected yet.")
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
                    findMergeCandidates(tracks)
                    if mergeCandidates.isEmpty {
                        alertMessage = lang.selectedLanguage == "ru" ? "Анализ завершен. Ошибок не найдено." : "Analysis complete. No split albums found."
                        showAlert = true
                    }
                }
            }
        }
    }
    
    func findMergeCandidates(_ tracks: [MusicTrack]) {
        // Placeholder
    }
    
    func fixMetadata() {
        // Logic
    }
}
