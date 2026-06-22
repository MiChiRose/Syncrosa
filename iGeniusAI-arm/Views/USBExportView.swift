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
    
    @State private var isExporting: Bool = false
    @State private var currentTrackName: String = ""
    @State private var currentTrackIndex: Int = 0
    @State private var totalTracksToExport: Int = 0
    @State private var bytesCopied: Int64 = 0
    @State private var totalBytesToExport: Int64 = 0
    
    @State private var activeNotification: NotificationMessage? = nil
    
    // Alerts/Dialogs
    @State private var showSpaceAlert: Bool = false
    @State private var showFSWarning: Bool = false
    @State private var showResultAlert: Bool = false
    @State private var resultMessage: String = ""
    
    var selectedDrive: USBDrive? {
        usbService.availableDrives.first { $0.id == selectedDriveId }
    }
    
    var formattedPlaylistSize: String {
        ByteCountFormatter.string(fromByteCount: playlistSize, countStyle: .file)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                // Card 1: Select Volume & Playlist
                VStack(alignment: .leading, spacing: 20) {
                    Label(lang.t("usb_export"), systemImage: "externaldrive.badge.gearshape")
                        .font(.headline)
                    
                    // Drive Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text(lang.t("select_drive"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        if usbService.availableDrives.isEmpty {
                            HStack {
                                Image(systemName: "externaldrive.badge.exclamationmark")
                                    .foregroundColor(.red)
                                Text(lang.t("no_drives"))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                        } else {
                            Picker("", selection: $selectedDriveId) {
                                Text("-").tag("")
                                ForEach(usbService.availableDrives) { drive in
                                    Text("\(drive.name) (\(drive.filesystemLabel)) - \(lang.t("free_space", ByteCountFormatter.string(fromByteCount: drive.freeSpace, countStyle: .file)))").tag(drive.id)
                                }
                            }
                            .labelsHidden()
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
                                    .foregroundColor(.gray)
                                Text(lang.t("no_playlists"))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                        } else {
                            Picker("", selection: $selectedPlaylistName) {
                                Text("-").tag("")
                                ForEach(playlists, id: \.name) { pl in
                                    Text("\(pl.name) (\(lang.t("tracks_count", pl.trackCount)))").tag(pl.name)
                                }
                            }
                            .labelsHidden()
                            .onChange(of: selectedPlaylistName) { _, newName in
                                updatePlaylistDetails(newName)
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
                
                // Card 2: Playlist Info & Export Button
                if !selectedPlaylistName.isEmpty && selectedDrive != nil {
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selectedPlaylistName)
                                    .font(.headline)
                                Text("\(playlistTracksCount) tracks (\(formattedPlaylistSize))")
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
                            Button(action: startExportProcess) {
                                Text(lang.t("export_button"))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(12)
                }
                
                Spacer()
            }
            .padding(30)
        }
        .notification(message: $activeNotification)
        .onAppear {
            loadPlaylists()
        }
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
                    .buttonStyle(.borderedProminent)
                    
                    Button(action: {
                        showSpaceAlert = false
                    }) {
                        Text(lang.t("cancel"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .padding()
            .frame(width: 380, height: 260)
        }
    }
    
    private func loadPlaylists() {
        playlists = MusicService.shared.getUserPlaylists()
    }
    
    private func updatePlaylistDetails(_ playlistName: String) {
        guard !playlistName.isEmpty else {
            playlistTracksCount = 0
            playlistSize = 0
            tracksToExport = []
            return
        }
        
        let rawTracks = MusicService.shared.getPlaylistTrackPaths(playlistName: playlistName)
        playlistTracksCount = rawTracks.count
        playlistSize = rawTracks.reduce(0) { $0 + $1.size }
        
        // Map to PlaylistExportService.TrackFile
        tracksToExport = rawTracks.map { track in
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
    }
    
    private func startExportProcess() {
        guard let drive = selectedDrive else { return }
        
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
            mode: mode
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
                } else if drm > 0 || missing > 0 {
                    activeNotification = NotificationMessage(
                        text: lang.t("export_partial", copied, copied + drm + missing, drm + missing),
                        isError: false
                    )
                } else {
                    activeNotification = NotificationMessage(
                        text: lang.t("export_success", copied),
                        isError: false
                    )
                }
                
                // Refresh drive list to show updated free space
                usbService.updateDrives()
            }
        }
    }
}
