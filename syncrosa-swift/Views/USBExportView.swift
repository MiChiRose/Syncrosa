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
                                ProgressView(value: Double(bytesCopied), total: Double(totalBytesToExport)) {
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
                            .disabled(isLoadingPlaylistDetails || tracksToExport.isEmpty)
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
                dismissButton: .default(Text("OK"))
            )
        }
        // Insufficient space action dialog
        .sheet(isPresented: $showSpaceAlert) {
            VStack(spacing: 20) {
                Text(lang.t("disk_full_title"))
                    .font(.headline)
                
                Text(lang.t("disk_full_msg", selectedPlaylistName, playlistTracksCount, formattedPlaylistSize, ByteCountFormatter.string(fromByteCount: selectedDrive?.freeSpace ?? 0, countStyle: .file)))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(spacing: 12) {
                    Button(action: {
                        showSpaceAlert = false
                        runExport(mode: .fitAvailable)
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
            loadPlaylists()
        }
    }
    
    var helpSheetView: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(lang.selectedLanguage == "ru" ? "Инструкция: USB Экспорт" : "Help: USB Export")
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
                         "Этот инструмент позволяет экспортировать выбранные плейлисты из Apple Music на ваш внешний USB-накопитель.\n\n" +
                         "Шаги использования:\n" +
                         "1. Вставьте USB-накопитель и выберите его в списке.\n" +
                         "2. Выберите плейлист, который хотите скопировать.\n" +
                         "3. Нажмите «Отправить на USB Flash». На накопителе будет создана папка с именем плейлиста, и треки будут скопированы внутрь неё.\n" +
                         "4. Включите .m3u/.m3u8, если устройству нужен отдельный файл плейлиста.\n" +
                         "5. iPod-safe names сокращает и чистит имена файлов для старых iPod, магнитол и FAT/exFAT накопителей.\n" +
                         "6. Если на накопителе недостаточно места, программа предложит скопировать случайную выборку песен, которая поместится на флешку." :
                         
                         "This tool allows you to export selected playlists from Apple Music to your external USB storage.\n\n" +
                         "How to use:\n" +
                         "1. Connect your USB drive and select it from the list.\n" +
                         "2. Choose the playlist you want to copy.\n" +
                         "3. Click 'Export to USB Flash'. A folder named after the playlist will be created on the drive, and tracks will be copied into it.\n" +
                         "4. Enable .m3u/.m3u8 when the target device expects a playlist file.\n" +
                         "5. iPod-safe names shortens and cleans filenames for older iPods, car stereos, and FAT/exFAT drives.\n" +
                         "6. If space is insufficient, you will be prompted to either cancel or copy a random subset that fits."
                    )
                    .font(.body)
                }
            }
            .frame(minWidth: 450, minHeight: 300)
        }
        .padding()
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
                    isDRM: isDRM
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
        guard let drive = selectedDrive else { return }
        guard !tracksToExport.isEmpty else {
            activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "В выбранном плейлисте нет доступных файлов для экспорта." : "The selected playlist has no available files to export.", isError: true)
            return
        }
        
        // 1. Check space
        let totalDRMSize = tracksToExport.filter { $0.isDRM }.reduce(0) { $0 + $1.fileSize }
        let estimatedSize = playlistSize - totalDRMSize
        
        if estimatedSize > drive.freeSpace {
            showSpaceAlert = true
        } else {
            runExport(mode: .all)
        }
    }
    
    private func runExport(mode: PlaylistExportService.ExportMode) {
        guard let drive = selectedDrive else { return }
        
        isExporting = true
        activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Запуск экспорта..." : "Starting export...", isError: false)
        
        PlaylistExportService.shared.exportToUSB(
            tracks: tracksToExport,
            destination: drive.volumeURL,
            playlistName: selectedPlaylistName,
            mode: mode,
            createM3U: createM3U,
            createM3U8: createM3U8,
            useIPodSafeNames: useIPodSafeNames
        ) { progressInfo in
            bytesCopied = progressInfo.bytesCopied
            totalBytesToExport = progressInfo.totalBytes
            currentTrackIndex = progressInfo.currentTrack
            totalTracksToExport = progressInfo.totalTracks
            currentTrackName = progressInfo.currentTrackName
        } completion: { result in
            DispatchQueue.main.async {
                isExporting = false
                
                let copied = result.copiedCount
                let drm = result.skippedDRM
                let missing = result.skippedNotDownloaded
                
                if !result.errors.isEmpty && result.errors.contains("Drive disconnected") {
                    activeNotification = NotificationMessage(text: lang.t("drive_disconnected"), isError: true)
                } else if !result.errors.isEmpty {
                    activeNotification = NotificationMessage(
                        text: lang.selectedLanguage == "ru"
                            ? "Экспортировано \(copied) треков в папку «\(selectedPlaylistName)». Ошибок: \(result.errors.count)."
                            : "Exported \(copied) tracks to the \"\(selectedPlaylistName)\" folder. Errors: \(result.errors.count).",
                        isError: copied == 0
                    )
                } else if drm > 0 || missing > 0 {
                    activeNotification = NotificationMessage(
                        text: lang.selectedLanguage == "ru"
                            ? "Экспортировано \(copied) треков в папку «\(selectedPlaylistName)». Пропущено: \(drm + missing)."
                            : "Exported \(copied) tracks to the \"\(selectedPlaylistName)\" folder. Skipped: \(drm + missing).",
                        isError: false
                    )
                } else {
                    activeNotification = NotificationMessage(
                        text: lang.selectedLanguage == "ru"
                            ? "Экспортировано \(copied) треков в папку «\(selectedPlaylistName)»."
                            : "Exported \(copied) tracks to the \"\(selectedPlaylistName)\" folder.",
                        isError: false
                    )
                }
                
                // Refresh drive list to show updated free space
                usbService.updateDrives()
            }
        }
    }
}
