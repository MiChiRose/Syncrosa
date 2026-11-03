import SwiftUI

struct USBExportView: View {
    @ObservedObject var lang = LocalizationService.shared
    @ObservedObject var usbService = USBService.shared
    
    @State private var selectedDriveId: String = ""
    @State private var playlists: [(name: String, trackCount: Int)] = []
    @State private var selectedPlaylistName: String = ""
    @State private var playlistTracksCount: Int = 0
    @State private var playlistSize: Int64 = 0
    @State private var tracksToExport: [PlaylistExportService.TrackFile] = []
    @State private var isLoadingPlaylistDetails: Bool = false
    
    @State private var serviceBusy = false
    @State private var cancelRequested = false
    @State private var pendingSpaceJobID: UUID?
    @State private var remainingCopyBytes: Int64 = 0
    @State private var isExporting: Bool = false
    @State private var currentTrackName: String = ""
    @State private var currentTrackIndex: Int = 0
    @State private var totalTracksToExport: Int = 0
    @State private var bytesCopied: Int64 = 0
    @State private var totalBytesToExport: Int64 = 0
    @State private var createM3U: Bool = false
    @State private var createM3U8: Bool = true
    @State private var useIPodSafeNames: Bool = false
    
    @State private var activeNotification: NotificationMessage? = nil
    @State private var showHelp: Bool = false
    
    // Alerts/Dialogs
    @State private var showSpaceAlert: Bool = false
    @State private var showFSWarning: Bool = false
    @State private var showResultAlert: Bool = false
    @State private var resultMessage: String = ""
    @State private var playlistMessage: String? = nil
    
    var selectedDrive: USBDrive? {
        usbService.availableDrives.first { $0.id == selectedDriveId }
    }

    var driveOptions: [SyncrosaMenuOption<String>] {
        [SyncrosaMenuOption(title: "-", value: "")] +
        usbService.availableDrives.map { drive in
            SyncrosaMenuOption(
                title: "\(drive.name) (\(drive.filesystemLabel)) - \(lang.t("free_space", ByteCountFormatter.string(fromByteCount: drive.freeSpace, countStyle: .file)))",
                value: drive.id
            )
        }
    }

    var playlistOptions: [SyncrosaMenuOption<String>] {
        [SyncrosaMenuOption(title: "-", value: "")] +
        playlists.map { playlist in
            SyncrosaMenuOption(title: "\(playlist.name) (\(lang.t("tracks_count", playlist.trackCount)))", value: playlist.name)
        }
    }
    
    var formattedPlaylistSize: String {
        ByteCountFormatter.string(fromByteCount: playlistSize, countStyle: .file)
    }
    
    var body: some View {
        SyncrosaPage {
            SyncrosaPageHeader(
                title: lang.t("usb_export"),
                systemImage: "externaldrive.fill",
                subtitle: lang.selectedLanguage == "ru" ? "Экспорт плейлистов на внешний накопитель с проверкой места." : "Export playlists to an external drive with space checks.",
                helpAction: { showHelp = true }
            )
                
                // Card 1: Select Volume & Playlist
                VStack(alignment: .leading, spacing: 20) {
                    
                    // Drive Picker
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(lang.t("select_drive"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: {
                                usbService.updateDrives()
                                loadPlaylists()
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(SyncrosaGlassIconButtonStyle(size: 24))
                            .disabled(usbService.isSearching)
                            .help(lang.selectedLanguage == "ru" ? "Обновить" : "Refresh")
                        }
                        
                        if usbService.isSearching {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(lang.selectedLanguage == "ru" ? "Поиск накопителей..." : "Searching for drives...")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                        } else if usbService.availableDrives.isEmpty {
                            HStack {
                                Image(systemName: "externaldrive.badge.exclamationmark")
                                    .foregroundColor(.red)
                                Text(lang.t("no_drives"))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                        } else {
                            SyncrosaGlassMenu(
                                selection: $selectedDriveId,
                                options: driveOptions,
                                width: 520
                            )
                            .onChange(of: selectedDriveId) { _, newId in
                                if let drive = usbService.availableDrives.first(where: { $0.id == newId }),
                                   !drive.isAndroidCompatible {
                                    showFSWarning = true
                                }
                            }
                        }
                    }
                    
                    // Playlist Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text(lang.t("select_playlist"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        if playlists.isEmpty {
                            HStack {
                                Image(systemName: "music.note.list")
                                    .foregroundColor(SyncrosaTheme.placeholderIcon)
                                Text(playlistMessage ?? lang.t("no_playlists"))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                        } else {
                            SyncrosaGlassMenu(
                                selection: $selectedPlaylistName,
                                options: playlistOptions,
                                width: 360
                            )
                            .onChange(of: selectedPlaylistName) { _, newName in
                                updatePlaylistDetails(newName)
                            }
                        }
                    }
                }
                .syncrosaCard()
                .disabled(isExporting || serviceBusy)
                
                // Card 2: Playlist Info & Export Button
                if !selectedPlaylistName.isEmpty && selectedDrive != nil {
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selectedPlaylistName)
                                    .font(.headline)
                                Text(isLoadingPlaylistDetails ? (lang.selectedLanguage == "ru" ? "Загрузка треков..." : "Loading tracks...") : "\(playlistTracksCount) tracks (\(formattedPlaylistSize))")
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        
                        if isExporting {
                            VStack(alignment: .leading, spacing: 8) {
                                ProgressView(value: Double(bytesCopied), total: Double(max(1, totalBytesToExport))) {
                                    Text(lang.t("exporting", currentTrackIndex, totalTracksToExport))
                                        .font(.caption2)
                                }
                                Text(currentTrackName)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .padding(.top, 10)
                            Button(action: {
                                cancelRequested = true
                                PlaylistExportService.shared.cancel()
                            }) {
                                Text(lang.selectedLanguage == "ru" ? "Приостановить" : "Pause Export")
                            }
                            .buttonStyle(SyncrosaSecondaryButtonStyle())
                            .disabled(cancelRequested)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                SyncrosaSectionLabel(
                                    text: lang.selectedLanguage == "ru" ? "ОПЦИИ ПЛЕЙЛИСТА" : "PLAYLIST FILE OPTIONS",
                                    systemImage: "list.bullet.rectangle"
                                )
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170))], alignment: .leading, spacing: 10) {
                                    Toggle(".m3u", isOn: $createM3U)
                                        .toggleStyle(SyncrosaCheckboxToggleStyle())
                                    Toggle(".m3u8", isOn: $createM3U8)
                                        .toggleStyle(SyncrosaCheckboxToggleStyle())
                                    HStack(spacing: 6) {
                                        Toggle(lang.selectedLanguage == "ru" ? "iPod-safe names" : "iPod-safe names", isOn: $useIPodSafeNames)
                                            .toggleStyle(SyncrosaCheckboxToggleStyle())
                                        Button(action: {
                                            activeNotification = NotificationMessage(
                                                text: lang.selectedLanguage == "ru"
                                                    ? "iPod-safe names сокращает и чистит имена файлов для старых iPod, магнитол и FAT/exFAT накопителей."
                                                    : "iPod-safe names shortens and cleans filenames for older iPods, car stereos, and FAT/exFAT drives.",
                                                isError: false
                                            )
                                        }) {
                                            Image(systemName: "questionmark.circle")
                                        }
                                        .buttonStyle(SyncrosaGlassIconButtonStyle(size: 22))
                                    }
                                }
                            }

                            Button(action: startExportProcess) {
                                Text(lang.t("export_button"))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SyncrosaPrimaryButtonStyle())
                            .controlSize(.large)
                            .disabled(isLoadingPlaylistDetails || tracksToExport.isEmpty || serviceBusy)
                        }
                    }
                    .syncrosaCard()
                }
                
                Spacer()
        }
        .notification(message: $activeNotification)
        // Incompatible filesystem warning dialog
        .alert(isPresented: $showFSWarning) {
            Alert(
                title: Text(lang.selectedLanguage == "ru" ? "Внимание" : "Warning"),
                message: Text(lang.t("incompatible_fs", selectedDrive?.filesystemLabel ?? "")),
                dismissButton: .default(Text(lang.t("close")))
            )
        }
        // Insufficient space action dialog
        .sheet(isPresented: $showSpaceAlert) {
            VStack(spacing: 20) {
                Text(lang.t("disk_full_title"))
                    .font(.headline)
                
                Text(lang.selectedLanguage == "ru"
                    ? "Для оставшихся файлов нужно: \(ByteCountFormatter.string(fromByteCount: remainingCopyBytes, countStyle: .file)). Уже перенесённые треки не занимают место повторно."
                    : "Remaining files need \(ByteCountFormatter.string(fromByteCount: remainingCopyBytes, countStyle: .file)). Existing verified tracks will not be copied again.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(spacing: 12) {
                    Button(action: {
                        showSpaceAlert = false
                        runExport(mode: .fitAvailable, resumeJobID: pendingSpaceJobID)
                    }) {
                        Text(lang.t("fit_available"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SyncrosaPrimaryButtonStyle())
                    
                    Button(action: {
                        showSpaceAlert = false
                    }) {
                        Text(lang.t("cancel"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SyncrosaSecondaryButtonStyle())
                }
                .padding()
            }
            .padding()
            .frame(width: 380, height: 260)
        }
        .sheet(isPresented: $showHelp) {
            helpSheetView
        }
        .onAppear {
            serviceBusy = PlaylistExportService.shared.isRunning
            loadPlaylists()
        }
        .onReceive(NotificationCenter.default.publisher(for: PlaylistExportService.jobsDidChangeNotification)) { _ in
            serviceBusy = PlaylistExportService.shared.isRunning
        }
    }
    
    var helpSheetView: some View {
        SyncrosaHelpSheet(
            title: lang.t("usb_export"),
            summary: lang.selectedLanguage == "ru"
                ? "Копирует локальные треки выбранного плейлиста в отдельную папку на USB-накопителе."
                : "Copies local tracks from a selected playlist into its own folder on a USB drive.",
            steps: lang.selectedLanguage == "ru" ? [
                "Подключите накопитель и выберите его в списке.",
                "Выберите плейлист и режим экспорта.",
                "При необходимости включите M3U/M3U8 и безопасные имена для старых устройств.",
                "Проверьте расчёт размера и запустите экспорт."
            ] : [
                "Connect a drive and choose it from the list.",
                "Choose a playlist and export mode.",
                "Enable M3U/M3U8 and legacy-safe filenames when the target device needs them.",
                "Review the size estimate and start export."
            ],
            notes: lang.selectedLanguage == "ru" ? [
                "Треки копируются в папку с именем плейлиста, а не в корень накопителя.",
                "Облачные треки без локального файла не копируются.",
                "Повторный экспорт проверяет содержимое и пропускает уже перенесённые файлы. После паузы или сбоя продолжите задачу в Центре восстановления."
            ] : [
                "Tracks go into a folder named after the playlist, not the drive root.",
                "Cloud-only tracks without a local file are skipped.",
                "Repeated exports verify and reuse existing files. After a pause or interruption, continue the job in Recovery Center."
            ],
            dismiss: { showHelp = false }
        )
    }

    
    private func loadPlaylists() {
        playlistMessage = lang.selectedLanguage == "ru" ? "Загрузка плейлистов..." : "Loading playlists..."
        DispatchQueue.global(qos: .userInitiated).async {
            let list = MusicService.shared.getUserPlaylists()
            let libraryCount = list.isEmpty ? MusicService.shared.getLibraryTrackCount() : nil
            DispatchQueue.main.async {
                self.playlists = list
                if !self.selectedPlaylistName.isEmpty,
                   !list.contains(where: { $0.name == self.selectedPlaylistName }) {
                    self.selectedPlaylistName = ""
                    self.playlistTracksCount = 0
                    self.playlistSize = 0
                    self.tracksToExport = []
                    self.isLoadingPlaylistDetails = false
                }
                if list.isEmpty {
                    if let count = libraryCount, count == 0 {
                        self.playlistMessage = self.lang.selectedLanguage == "ru" ? "В Music нет треков и доступных плейлистов." : "Music has no tracks or playlists to export."
                    } else if libraryCount == nil {
                        self.playlistMessage = self.lang.selectedLanguage == "ru" ? "Не удалось прочитать плейлисты Music." : "Could not read Music playlists."
                    } else {
                        self.playlistMessage = self.lang.t("no_playlists")
                    }
                } else {
                    self.playlistMessage = nil
                }
            }
        }
    }
    
    private func updatePlaylistDetails(_ playlistName: String) {
        guard !playlistName.isEmpty else {
            playlistTracksCount = 0
            playlistSize = 0
            tracksToExport = []
            isLoadingPlaylistDetails = false
            return
        }

        isLoadingPlaylistDetails = true
        playlistTracksCount = 0
        playlistSize = 0
        tracksToExport = []
        
        DispatchQueue.global(qos: .userInitiated).async {
            let rawTracks = MusicService.shared.getPlaylistTrackPaths(playlistName: playlistName)
            let count = rawTracks.count
            let size = rawTracks.reduce(0) { $0 + $1.size }
            let mapped = rawTracks.map { track in
                let pathExtension = URL(fileURLWithPath: track.path).pathExtension.lowercased()
                let isDRM = pathExtension == "m4p"
                return PlaylistExportService.TrackFile(
                    name: track.name,
                    artist: track.artist,
                    filePath: track.path,
                    fileSize: track.size,
                    isDRM: isDRM,
                    persistentID: track.persistentID
                )
            }
            
            DispatchQueue.main.async {
                guard self.selectedPlaylistName == playlistName else { return }
                self.playlistTracksCount = count
                self.playlistSize = size
                self.tracksToExport = mapped
                self.isLoadingPlaylistDetails = false
            }
        }
    }
    
    private func startExportProcess() {
        guard selectedDrive != nil, !tracksToExport.isEmpty else { return }
        pendingSpaceJobID = nil
        runExport(mode: .all)
    }

    private func runExport(mode: PlaylistExportService.ExportMode, resumeJobID: UUID? = nil) {
        guard let drive = selectedDrive else { return }
        isExporting = true
        cancelRequested = false
        bytesCopied = 0
        totalBytesToExport = 1
        activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Проверка уже перенесённых файлов..." : "Checking previously exported files...", isError: false)
        let progress: (PlaylistExportService.ExportProgress) -> Void = { value in
            bytesCopied = value.bytesCopied
            totalBytesToExport = value.totalBytes
            currentTrackIndex = value.currentTrack
            totalTracksToExport = value.totalTracks
            currentTrackName = value.currentTrackName
        }
        let completion: (PlaylistExportService.ExportResult) -> Void = { result in
            isExporting = false
            serviceBusy = false
            if result.insufficientSpace {
                pendingSpaceJobID = result.jobID
                remainingCopyBytes = result.remainingBytesToCopy
                showSpaceAlert = true
            }
            let russian = lang.selectedLanguage == "ru"
            let skipped = result.skippedDRM + result.skippedNotDownloaded + result.skippedForSpace
            var message = russian
                ? "Скопировано: \(result.copiedCount). Уже на диске: \(result.existingCount). Пропущено: \(skipped). Записано: \(ByteCountFormatter.string(fromByteCount: result.totalBytesCopied, countStyle: .file))."
                : "Copied: \(result.copiedCount). Already on drive: \(result.existingCount). Skipped: \(skipped). Written: \(ByteCountFormatter.string(fromByteCount: result.totalBytesCopied, countStyle: .file))."
            if result.wasCancelled || !result.errors.isEmpty {
                message += russian ? " Продолжение доступно в Центре восстановления." : "Continue this job in Recovery Center."
            }
            if !result.errors.isEmpty { message += "\n" + result.errors.prefix(3).joined(separator: "\n") }
            activeNotification = NotificationMessage(text: message, isError: !result.errors.isEmpty && !result.insufficientSpace)
            OperationHistoryService.shared.record(tool: "USB Export", title: selectedPlaylistName,
                status: result.wasCancelled ? "PAUSED" : (result.insufficientSpace ? "WARN" : (result.errors.isEmpty ? "OK" : "ERROR")),
                message: message, affectedCount: result.copiedCount)
            usbService.updateDrives()
        }
        if let resumeJobID {
            PlaylistExportService.shared.resume(jobID: resumeJobID, destination: drive.volumeURL, mode: mode, progress: progress, completion: completion)
        } else {
            PlaylistExportService.shared.exportToUSB(tracks: tracksToExport, destination: drive.volumeURL, playlistName: selectedPlaylistName, mode: mode, createM3U: createM3U, createM3U8: createM3U8, useIPodSafeNames: useIPodSafeNames, progress: progress, completion: completion)
        }
    }
}
