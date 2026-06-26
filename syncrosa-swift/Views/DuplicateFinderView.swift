import SwiftUI

struct DetailedTrack: Identifiable, Equatable {
    var id: String { track.persistentID }
    let track: MusicTrack
    let format: String
    let size: Int64
    let completeness: Int
}

struct DuplicatePair: Identifiable, Equatable {
    var id: String { pairKey }
    let track1: DetailedTrack
    let track2: DetailedTrack
    let pairKey: String
}

struct DuplicateFinderView: View {
    @ObservedObject var lang = LocalizationService.shared
    @State private var isScanning: Bool = false
    @State private var duplicatePairs: [DuplicatePair] = []
    @State private var activeNotification: NotificationMessage? = nil
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var showHelp: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                // Title with Help Button
                HStack(alignment: .center, spacing: 10) {
                    Label(lang.selectedLanguage == "ru" ? "Поиск дубликатов" : "Duplicate Finder", systemImage: "arrow.2.squarepath")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Button(action: { showHelp = true }) {
                        Image(systemName: "questionmark.circle")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                // Card 1: Controls
                VStack(alignment: .leading, spacing: 15) {
                    Text(lang.selectedLanguage == "ru" ? "Сканируйте медиатеку для поиска дубликатов по исполнителю и названию." : "Scan your library to find duplicate pairs by artist and title.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 15) {
                        Button(action: scanForDuplicates) {
                            if isScanning {
                                ProgressView().controlSize(.small)
                            } else {
                                Label(lang.selectedLanguage == "ru" ? "Показать дубликаты" : "Show Duplicates", systemImage: "magnifyingglass")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isScanning)
                        
                        if !duplicatePairs.isEmpty {
                            Button(action: { duplicatePairs.removeAll() }) {
                                Text(lang.selectedLanguage == "ru" ? "Очистить список" : "Clear List")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isScanning)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
                
                // Card 2: Duplicate Pairs List
                VStack(alignment: .leading, spacing: 15) {
                    Text(lang.selectedLanguage == "ru" ? "НАЙДЕННЫЕ ДУБЛИКАТЫ" : "FOUND DUPLICATES")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if duplicatePairs.isEmpty {
                        VStack(spacing: 15) {
                            Image(systemName: "square.on.square.dashed")
                                .font(.system(size: 40))
                                .foregroundColor(.gray.opacity(0.3))
                            Text(lang.selectedLanguage == "ru" ? "Нет дубликатов для показа. Нажмите сканировать." : "No duplicates to show. Click scan to begin.")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(duplicatePairs) { pair in
                            VStack(alignment: .leading, spacing: 12) {
                                // Track info comparison side by side
                                HStack(alignment: .top, spacing: 15) {
                                    trackColumn(pair.track1, sideNumber: 1, pairKey: pair.pairKey)
                                    Divider()
                                    trackColumn(pair.track2, sideNumber: 2, pairKey: pair.pairKey)
                                }
                                .padding()
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                                )
                                
                                // Ignore pair button
                                HStack {
                                    Spacer()
                                    Button(action: { ignorePair(pair) }) {
                                        Label(lang.selectedLanguage == "ru" ? "Игнорировать пару" : "Ignore Pair", systemImage: "eye.slash")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                .padding(.horizontal, 5)
                                
                                Divider()
                                    .padding(.top, 5)
                            }
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
            Alert(
                title: Text(lang.selectedLanguage == "ru" ? "Поиск дубликатов" : "Duplicate Finder"),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: $showHelp) {
            helpSheetView
        }
    }
    
    @ViewBuilder
    func trackColumn(_ detailedTrack: DetailedTrack, sideNumber: Int, pairKey: String) -> some View {
        let t = detailedTrack.track
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(lang.selectedLanguage == "ru" ? "Копия \(sideNumber)" : "Copy \(sideNumber)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                
                Spacer()
                
                Button(action: { deleteTrackCopy(detailedTrack.id, pairKey: pairKey) }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help(lang.selectedLanguage == "ru" ? "Удалить эту копию" : "Delete this copy")
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    Text(lang.selectedLanguage == "ru" ? "Название: \(t.name)" : "Title: \(t.name)")
                    Text(lang.selectedLanguage == "ru" ? "Исполнитель: \(t.artist)" : "Artist: \(t.artist)")
                    Text(lang.selectedLanguage == "ru" ? "Альбом: \(t.album.isEmpty ? "-" : t.album)" : "Album: \(t.album.isEmpty ? "-" : t.album)")
                    Text(lang.selectedLanguage == "ru" ? "Жанр: \(t.genre.isEmpty ? "-" : t.genre)" : "Genre: \(t.genre.isEmpty ? "-" : t.genre)")
                    Text(lang.selectedLanguage == "ru" ? "Год: \(t.year == 0 ? "-" : "\(t.year)")" : "Year: \(t.year == 0 ? "-" : "\(t.year)")")
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
                
                HStack(spacing: 12) {
                    Text(lang.selectedLanguage == "ru" ? "Формат: \(detailedTrack.format)" : "Format: \(detailedTrack.format)")
                    Text(lang.selectedLanguage == "ru" ? "Размер: \(formatSize(detailedTrack.size))" : "Size: \(formatSize(detailedTrack.size))")
                }
                .font(.system(size: 11, weight: .semibold))
                
                HStack(spacing: 5) {
                    Text(lang.selectedLanguage == "ru" ? "Метаданные:" : "Metadata:")
                    Text("\(detailedTrack.completeness)%")
                        .foregroundColor(detailedTrack.completeness >= 80 ? .green : (detailedTrack.completeness >= 50 ? .orange : .red))
                        .fontWeight(.bold)
                }
                .font(.system(size: 11))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var helpSheetView: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(lang.selectedLanguage == "ru" ? "Инструкция: Поиск дубликатов" : "Help: Duplicate Finder")
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
                         "Этот модуль помогает находить и устранять дублирующиеся треки в вашей медиатеке Apple Music.\n\n" +
                         "Шаги использования:\n" +
                         "1. Нажмите «Показать дубликаты» для сканирования вашей библиотеки.\n" +
                         "2. Просмотрите найденные пары дубликатов side-by-side.\n" +
                         "3. Вы можете сравнить размер, формат файлов и полноту метаданных.\n" +
                         "4. Нажмите «Игнорировать пару», чтобы скрыть данную пару из будущих сканирований.\n" +
                         "5. Нажмите иконку корзины, чтобы удалить конкретную копию трека из приложения «Музыка»." :
                         
                         "This module helps you find and resolve duplicate tracks in your Apple Music library.\n\n" +
                         "How to use:\n" +
                         "1. Click 'Show Duplicates' to scan your library.\n" +
                         "2. View the duplicate pairs side-by-side.\n" +
                         "3. Compare the file format, size, and metadata completeness percentages.\n" +
                         "4. Click 'Ignore Pair' to remove a pair from the results and prevent it from appearing again.\n" +
                         "5. Click the trash icon to delete a specific track copy from your Music application."
                    )
                    .font(.body)
                }
            }
            .frame(minWidth: 450, minHeight: 300)
        }
        .padding()
    }
    
    func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    func calculateCompleteness(_ track: MusicTrack) -> Int {
        var score = 0
        if !track.name.isEmpty { score += 20 }
        if !track.artist.isEmpty { score += 20 }
        if !track.album.isEmpty { score += 20 }
        if !track.genre.isEmpty { score += 20 }
        if track.year > 0 { score += 20 }
        return score
    }
    
    func scanForDuplicates() {
        isScanning = true
        activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Сканирование медиатеки..." : "Scanning Music library...", isError: false)
        
        DispatchQueue.global().async {
            let tracks = MusicService.shared.getAllTracks { current, total in
                DispatchQueue.main.async {
                    activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Сканирование: \(current)/\(total)" : "Scanning: \(current)/\(total)", isError: false)
                }
            }
            
            var trackGroups: [String: [MusicTrack]] = [:]
            for track in tracks {
                let cleanArtist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let cleanName = track.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !cleanArtist.isEmpty && !cleanName.isEmpty else { continue }
                let key = "\(cleanArtist)|\(cleanName)"
                trackGroups[key, default: []].append(track)
            }
            
            let ignoredList = UserDefaults.standard.stringArray(forKey: "SyncrosaIgnoredDuplicates") ?? []
            let ignoredSet = Set(ignoredList)
            
            var pairs: [DuplicatePair] = []
            
            for (_, groupTracks) in trackGroups where groupTracks.count >= 2 {
                for i in 0..<groupTracks.count {
                    for j in (i + 1)..<groupTracks.count {
                        let t1 = groupTracks[i]
                        let t2 = groupTracks[j]
                        let pairKey = [t1.persistentID, t2.persistentID].sorted().joined(separator: "-")
                        
                        if ignoredSet.contains(pairKey) {
                            continue
                        }
                        
                        guard let details1 = MusicService.shared.getTrackDetails(persistentID: t1.persistentID),
                              let details2 = MusicService.shared.getTrackDetails(persistentID: t2.persistentID) else {
                            continue
                        }
                        
                        let c1 = calculateCompleteness(t1)
                        let c2 = calculateCompleteness(t2)
                        
                        let p = DuplicatePair(
                            track1: DetailedTrack(track: t1, format: details1.format, size: details1.size, completeness: c1),
                            track2: DetailedTrack(track: t2, format: details2.format, size: details2.size, completeness: c2),
                            pairKey: pairKey
                        )
                        pairs.append(p)
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.duplicatePairs = pairs
                self.isScanning = false
                self.activeNotification = nil
                if pairs.isEmpty {
                    self.alertMessage = lang.selectedLanguage == "ru" ? "Дубликаты не найдены." : "No duplicate pairs found."
                    self.showAlert = true
                }
            }
        }
    }
    
    func ignorePair(_ pair: DuplicatePair) {
        var ignoredList = UserDefaults.standard.stringArray(forKey: "SyncrosaIgnoredDuplicates") ?? []
        ignoredList.append(pair.pairKey)
        UserDefaults.standard.set(ignoredList, forKey: "SyncrosaIgnoredDuplicates")
        
        withAnimation {
            duplicatePairs.removeAll { $0.pairKey == pair.pairKey }
        }
        
        activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Пара добавлена в список игнорируемых" : "Pair ignored", isError: false)
    }
    
    func deleteTrackCopy(_ pid: String, pairKey: String) {
        activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Удаление трека..." : "Deleting track...", isError: false)
        
        DispatchQueue.global().async {
            let success = MusicService.shared.deleteTrack(persistentID: pid)
            DispatchQueue.main.async {
                if success {
                    withAnimation {
                        duplicatePairs.removeAll { $0.pairKey == pairKey }
                    }
                    activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Трек успешно удален!" : "Track deleted successfully!", isError: false)
                } else {
                    activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Не удалось удалить трек из Музыки." : "Could not delete track from Music app.", isError: true)
                }
            }
        }
    }
}
