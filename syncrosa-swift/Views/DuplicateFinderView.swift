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

enum DuplicateAction: String, Hashable {
    case none
    case ignore
    case deleteTrack1
    case deleteTrack2
}

struct DuplicateFinderView: View {
    @ObservedObject var lang = LocalizationService.shared
    @State private var isScanning: Bool = false
    @State private var isApplying: Bool = false
    @State private var duplicatePairs: [DuplicatePair] = []
    @State private var pendingActions: [String: DuplicateAction] = [:]
    @State private var activeNotification: NotificationMessage? = nil
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var showHelp: Bool = false
    @State private var safetyPreview: SafetyPreviewRequest? = nil
    
    var body: some View {
        SyncrosaPage {
            SyncrosaPageHeader(
                title: lang.selectedLanguage == "ru" ? "Поиск дубликатов" : "Duplicate Finder",
                systemImage: "arrow.2.squarepath",
                subtitle: lang.selectedLanguage == "ru" ? "Сравнение повторяющихся треков и пакетное применение действий." : "Compare duplicate pairs and apply actions in one batch.",
                helpAction: { showHelp = true }
            )
                
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
                        .buttonStyle(SyncrosaPrimaryButtonStyle())
                        .disabled(isScanning || isApplying)

                        if !duplicatePairs.isEmpty {
                            Button(action: presentApplySafetyPreview) {
                                if isApplying {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label(lang.selectedLanguage == "ru" ? "Применить" : "Apply Selected", systemImage: "checkmark.circle")
                                }
                            }
                            .buttonStyle(SyncrosaPrimaryButtonStyle())
                            .disabled(isScanning || isApplying || selectedActionCount == 0)
                        }
                        
                        if !duplicatePairs.isEmpty {
                            Button(action: {
                                duplicatePairs.removeAll()
                                pendingActions.removeAll()
                            }) {
                                Text(lang.selectedLanguage == "ru" ? "Очистить список" : "Clear List")
                            }
                            .buttonStyle(SyncrosaSecondaryButtonStyle())
                            .disabled(isScanning || isApplying)
                        }
                    }
                }
                .syncrosaCard()
                
                // Card 2: Duplicate Pairs List
                VStack(alignment: .leading, spacing: 15) {
                    SyncrosaSectionLabel(text: lang.selectedLanguage == "ru" ? "НАЙДЕННЫЕ ДУБЛИКАТЫ" : "FOUND DUPLICATES", systemImage: "square.on.square")
                    
                    if duplicatePairs.isEmpty {
                        SyncrosaEmptyState(
                            systemImage: "square.on.square.dashed",
                            title: lang.selectedLanguage == "ru" ? "Нет дубликатов для показа." : "No duplicates to show.",
                            message: lang.selectedLanguage == "ru" ? "Нажмите сканировать, чтобы начать." : "Click scan to begin."
                        )
                    } else {
                        ForEach(duplicatePairs) { pair in
                            VStack(alignment: .leading, spacing: 12) {
                                // Track info comparison side by side
                                HStack(alignment: .top, spacing: 15) {
                                    trackColumn(pair.track1, sideNumber: 1)
                                    Divider()
                                    trackColumn(pair.track2, sideNumber: 2)
                                }
                                .padding()
                                .background(SyncrosaTheme.subtleBackground)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(SyncrosaTheme.panelBorder, lineWidth: 1)
                                )
                                
                                SyncrosaGlassSegmentedPicker(
                                    selection: actionBinding(for: pair.pairKey),
                                    options: duplicateActionOptions,
                                    minSegmentWidth: 86,
                                    isDisabled: isScanning || isApplying
                                )
                                .disabled(isScanning || isApplying)
                                .padding(.horizontal, 5)
                                
                                Divider()
                                    .padding(.top, 5)
                            }
                        }
                    }
                }
                .syncrosaCard()
                
                Spacer()
        }
        .notification(message: $activeNotification)
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text(lang.selectedLanguage == "ru" ? "Поиск дубликатов" : "Duplicate Finder"),
                message: Text(alertMessage),
                dismissButton: .default(Text(lang.t("close")))
            )
        }
        .sheet(isPresented: $showHelp) {
            helpSheetView
        }
        .sheet(item: $safetyPreview) { request in
            SafetyPreviewSheet(
                request: request,
                cancel: { safetyPreview = nil },
                confirm: {
                    safetyPreview = nil
                    applySelectedActions()
                }
            )
        }
    }
    
    @ViewBuilder
    func trackColumn(_ detailedTrack: DetailedTrack, sideNumber: Int) -> some View {
        let t = detailedTrack.track
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(lang.selectedLanguage == "ru" ? "Копия \(sideNumber)" : "Copy \(sideNumber)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                
                Spacer()
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
        SyncrosaHelpSheet(
            title: lang.t("duplicate_finder"),
            summary: lang.selectedLanguage == "ru"
                ? "Находит вероятные дубликаты в Music и позволяет принять решения одной подтверждаемой пачкой."
                : "Finds likely duplicates in Music and lets you apply reviewed decisions as one confirmed batch.",
            steps: lang.selectedLanguage == "ru" ? [
                "Запустите сканирование медиатеки.",
                "Сравните каждую пару по названию, формату, размеру и заполненности метаданных.",
                "Для пары выберите: игнорировать, удалить первый или удалить второй трек.",
                "Проверьте количество выбранных действий и нажмите «Применить»."
            ] : [
                "Scan the Music library.",
                "Compare each pair by title, format, size, and metadata completeness.",
                "Choose Ignore, Delete First, or Delete Second for each pair.",
                "Review the selected-action count and choose Apply."
            ],
            notes: lang.selectedLanguage == "ru" ? [
                "Syncrosa показывает кандидатов, а не гарантированно одинаковые аудиофайлы.",
                "Удаление выполняется только после общего подтверждения."
            ] : [
                "Syncrosa shows candidates, not guaranteed bit-identical audio files.",
                "Deletion runs only after the final batch confirmation."
            ],
            dismiss: { showHelp = false }
        )
    }
    
    func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    var selectedActionCount: Int {
        pendingActions.values.filter { $0 != .none }.count
    }

    var duplicateActionOptions: [SyncrosaMenuOption<DuplicateAction>] {
        [
            SyncrosaMenuOption(title: lang.selectedLanguage == "ru" ? "Не трогать" : "No Action", value: .none),
            SyncrosaMenuOption(title: lang.selectedLanguage == "ru" ? "Игнор" : "Ignore", value: .ignore),
            SyncrosaMenuOption(title: lang.selectedLanguage == "ru" ? "Удалить 1" : "Delete 1", value: .deleteTrack1),
            SyncrosaMenuOption(title: lang.selectedLanguage == "ru" ? "Удалить 2" : "Delete 2", value: .deleteTrack2)
        ]
    }

    func actionBinding(for pairKey: String) -> Binding<DuplicateAction> {
        Binding(
            get: { pendingActions[pairKey] ?? .none },
            set: { pendingActions[pairKey] = $0 }
        )
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
        if isApplying { return }
        isScanning = true
        pendingActions.removeAll()
        activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Сканирование медиатеки..." : "Scanning Music library...", isError: false)
        
        DispatchQueue.global().async {
            guard let libraryCount = MusicService.shared.getLibraryTrackCount() else {
                DispatchQueue.main.async {
                    self.duplicatePairs = []
                    self.isScanning = false
                    self.activeNotification = nil
                    self.alertMessage = lang.selectedLanguage == "ru" ? "Не удалось прочитать медиатеку Music, или она пуста." : "Could not read your Music library, or it may be empty."
                    self.showAlert = true
                }
                return
            }

            guard libraryCount > 0 else {
                DispatchQueue.main.async {
                    self.duplicatePairs = []
                    self.isScanning = false
                    self.activeNotification = nil
                    self.alertMessage = lang.selectedLanguage == "ru" ? "В Music нет треков. Дубликаты искать не из чего." : "Music has no tracks. There is nothing to scan for duplicates."
                    self.showAlert = true
                }
                return
            }

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

    func presentApplySafetyPreview() {
        let selected = pendingActions.filter { $0.value != .none }
        guard !selected.isEmpty else { return }
        let deleteCount = selected.values.filter { $0 == .deleteTrack1 || $0 == .deleteTrack2 }.count
        let ignoreCount = selected.values.filter { $0 == .ignore }.count
        safetyPreview = SafetyPreviewRequest(
            title: lang.selectedLanguage == "ru" ? "Применить действия к дубликатам?" : "Apply duplicate actions?",
            message: lang.selectedLanguage == "ru" ? "Syncrosa выполнит выбранные действия одной пачкой и после этого обновит список дубликатов." : "Syncrosa will run the selected actions as one batch, then refresh the duplicate list.",
            details: [
                SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Всего действий" : "Total actions", value: "\(selected.count)"),
                SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Игнорировать" : "Ignore", value: "\(ignoreCount)"),
                SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Удалить треки" : "Delete tracks", value: "\(deleteCount)")
            ],
            confirmTitle: lang.selectedLanguage == "ru" ? "Применить" : "Apply",
            isDestructive: deleteCount > 0
        )
    }

    func applySelectedActions() {
        let selected = pendingActions.filter { $0.value != .none }
        guard !selected.isEmpty else { return }
        let pairsByKey = Dictionary(uniqueKeysWithValues: duplicatePairs.map { ($0.pairKey, $0) })

        isApplying = true
        activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Применение действий..." : "Applying duplicate actions...", isError: false)
        let recoveryID = OperationRecoveryService.shared.begin(
            tool: "Duplicate Finder",
            title: "Apply Duplicate Actions",
            message: lang.selectedLanguage == "ru" ? "Пакетная обработка дубликатов была прервана. Проверьте Music и историю операций." : "Duplicate batch processing was interrupted. Check Music and Operation History.",
            affectedCount: selected.count
        )

        DispatchQueue.global(qos: .userInitiated).async {
            var ignoredList = UserDefaults.standard.stringArray(forKey: "SyncrosaIgnoredDuplicates") ?? []
            var ignoredSet = Set(ignoredList)
            var applied = 0
            var failed = 0

            for (pairKey, action) in selected {
                guard let pair = pairsByKey[pairKey] else { continue }
                switch action {
                case .none:
                    continue
                case .ignore:
                    if !ignoredSet.contains(pairKey) {
                        ignoredSet.insert(pairKey)
                        ignoredList.append(pairKey)
                    }
                    applied += 1
                case .deleteTrack1:
                    if MusicService.shared.deleteTrack(persistentID: pair.track1.id) {
                        applied += 1
                    } else {
                        failed += 1
                    }
                case .deleteTrack2:
                    if MusicService.shared.deleteTrack(persistentID: pair.track2.id) {
                        applied += 1
                    } else {
                        failed += 1
                    }
                }
            }

            UserDefaults.standard.set(ignoredList, forKey: "SyncrosaIgnoredDuplicates")

            DispatchQueue.main.async {
                OperationRecoveryService.shared.finish(recoveryID)
                self.pendingActions.removeAll()
                self.isApplying = false
                let message: String
                if failed > 0 {
                    message = self.lang.selectedLanguage == "ru" ? "Применено: \(applied), ошибок: \(failed)" : "Applied: \(applied), failed: \(failed)"
                    self.activeNotification = NotificationMessage(
                        text: message,
                        isError: true
                    )
                } else {
                    message = self.lang.selectedLanguage == "ru" ? "Применено: \(applied). Обновляю список..." : "Applied \(applied). Refreshing..."
                    self.activeNotification = NotificationMessage(
                        text: message,
                        isError: false
                    )
                }
                OperationHistoryService.shared.record(
                    tool: "Duplicate Finder",
                    title: "Apply Duplicate Actions",
                    status: failed > 0 ? "FAIL" : "OK",
                    message: message,
                    affectedCount: applied
                )
                self.scanForDuplicates()
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
