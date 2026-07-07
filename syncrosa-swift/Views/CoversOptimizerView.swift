import SwiftUI
import Foundation

final class CoversProcessingCancelToken {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        let value = cancelled
        lock.unlock()
        return value
    }
}

struct CoversOptimizerView: View {
    @ObservedObject var lang = LocalizationService.shared
    
    @State private var targetSize = 300
    @State private var logs: [String] = []
    @State private var progressValue: Double = 0.0
    @State private var progressMax: Double = 1.0
    @State private var isProcessing = false
    @State private var cancelToken = CoversProcessingCancelToken()
    @State private var showBackupAlert = false
    @State private var currentTrackName = ""
    @State private var showHelp = false
    
    let devices = [
        (name: "iPod Classic / Nano / Vintage (300x300)", size: 300),
        (name: "iPhone 4s / 6 / iOS 5-6 (600x600)", size: 600),
        (name: "Modern iOS / High-Res (1000x1000)", size: 1000)
    ]
    
    var body: some View {
        SyncrosaPage {
            SyncrosaPageHeader(
                title: lang.t("covers_optimizer"),
                systemImage: "photo.on.rectangle.angled",
                subtitle: lang.selectedLanguage == "ru" ? "Резервное копирование, сжатие и восстановление обложек." : "Back up, resize, and restore embedded cover art.",
                helpAction: { showHelp = true }
            )
                
                // Card 1: Configuration
                VStack(alignment: .leading, spacing: 20) {
                    SyncrosaAdaptiveRow(spacing: 15) {
                        Text(lang.t("select_device"))
                            .font(.body)
                        SyncrosaGlassMenu(
                            selection: $targetSize,
                            options: devices.map { SyncrosaMenuOption(title: $0.name, value: $0.size) },
                            width: 360
                        )
                        .disabled(isProcessing)
                    }
                    
                    // Action Buttons
                    SyncrosaAdaptiveRow(spacing: 15) {
                        Button(action: runBackup) {
                            Text(lang.t("btn_backup_covers"))
                                .frame(minWidth: 160)
                        }
                        .disabled(isProcessing)
                        
                        Button(action: { showBackupAlert = true }) {
                            Text(lang.t("btn_optimize_covers"))
                                .bold()
                                .frame(minWidth: 160)
                        }
                        .disabled(isProcessing)
                        
                        Button(action: runRestore) {
                            Text(lang.t("btn_restore_covers"))
                                .frame(minWidth: 160)
                        }
                        .disabled(isProcessing || !hasCoverBackup)

                        if isProcessing {
                            Button(action: {
                                cancelToken.cancel()
                                log(lang.selectedLanguage == "ru" ? "Остановка после текущего трека..." : "Stopping after current track...")
                            }) {
                                Label(lang.selectedLanguage == "ru" ? "Стоп" : "Stop", systemImage: "stop.circle")
                            }
                            .buttonStyle(SyncrosaSecondaryButtonStyle())
                        }
                    }
                }
                .syncrosaCard()
                
                // Current track/status
                if isProcessing {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(currentTrackName)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        ProgressView(value: progressValue, total: progressMax)
                            .progressViewStyle(LinearProgressViewStyle())
                    }
                    .syncrosaCard()
                }
                
                // Terminal Console Logs
            SyncrosaLogConsole(
                title: lang.selectedLanguage == "ru" ? "Лог консоли:" : "Console Log:",
                lines: logs,
                minHeight: 250
            )
        }
        .alert(isPresented: $showBackupAlert) {
            Alert(
                title: Text(lang.t("confirm_backup_title")),
                message: Text(lang.t("confirm_backup_msg")),
                primaryButton: .destructive(Text(lang.t("confirm_yes"))) {
                    runOptimize()
                },
                secondaryButton: .cancel(Text(lang.t("confirm_no")))
            )
        }
        .sheet(isPresented: $showHelp) {
            helpSheetView
        }
        .onAppear {
            CoversOptimizerService.shared.createBackupFolderIfNeeded()
        }
    }

    private var hasCoverBackup: Bool {
        CoversOptimizerService.shared.backupManifestCount() > 0
    }
    
    var helpSheetView: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(lang.selectedLanguage == "ru" ? "Инструкция: Оптимизатор обложек" : "Help: Covers Optimizer")
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
                         "Этот инструмент оптимизирует размер обложек ваших музыкальных альбомов для старых или портативных устройств (например, iPod Classic, iPhone 4s).\n\n" +
                         "Шаги использования:\n" +
                         "1. Сделайте резервную копию ваших обложек, нажав «Резервная копия обложек» (сохранит в Library/Application Support/Syncrosa/Backups/AlbumCovers).\n" +
                         "2. Выберите целевой размер обложки из выпадающего списка.\n" +
                         "3. Нажмите «Оптимизировать обложки» для запуска процесса сжатия.\n" +
                         "4. Если что-то пойдет не так, вы всегда сможете восстановить исходные обложки, нажав «Восстановить обложки»." :
                         
                         "This tool optimizes the size of your album cover art for older or vintage portable devices (like iPod Classic, iPhone 4s).\n\n" +
                         "How to use:\n" +
                         "1. Backup your original cover arts first by clicking 'Backup Original Covers' (saves them to Library/Application Support/Syncrosa/Backups/AlbumCovers).\n" +
                         "2. Select the target cover size from the dropdown.\n" +
                         "3. Click 'Optimize Covers' to compress the artwork for all tracks.\n" +
                         "4. If needed, restore the original high-resolution cover art by clicking 'Restore Original Covers'."
                    )
                    .font(.body)
                }
            }
            .frame(minWidth: 450, minHeight: 300)
        }
        .padding()
    }

    
    private func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let stamp = formatter.string(from: Date())
        logs.append("[\(stamp)] \(message)")
        if logs.count > 500 {
            logs.removeFirst(logs.count - 500)
        }
    }
    
    private func runBackup() {
        isProcessing = true
        let token = CoversProcessingCancelToken()
        cancelToken = token
        progressValue = 0
        progressMax = 1
        logs.removeAll()
        log(lang.t("log_backup_started"))
        
        DispatchQueue.global(qos: .userInitiated).async {
            let service = CoversOptimizerService.shared
            let tracks = service.getTracksWithCovers()
            
            if tracks.isEmpty {
                let libraryCount = MusicService.shared.getLibraryTrackCount()
                DispatchQueue.main.async {
                    if let count = libraryCount, count == 0 {
                        log(lang.selectedLanguage == "ru" ? "В Music нет треков. Резервировать обложки не из чего." : "Music has no tracks. There are no covers to back up.")
                    } else if libraryCount == nil {
                        log(lang.selectedLanguage == "ru" ? "Не удалось прочитать медиатеку Music, или она пуста." : "Could not read your Music library, or it may be empty.")
                    } else {
                        log(lang.t("no_covers_found"))
                    }
                    isProcessing = false
                }
                return
            }
            
            DispatchQueue.main.async {
                progressMax = Double(tracks.count)
            }
            
            var successCount = 0
            for (idx, track) in tracks.enumerated() {
                if token.isCancelled { break }
                DispatchQueue.main.async {
                    currentTrackName = "\(track.artist) - \(track.title)"
                    progressValue = Double(idx + 1)
                }
                
                let success = service.backupCover(pid: track.pid, title: track.title, artist: track.artist)
                if success {
                    successCount += 1
                }
            }
            
            DispatchQueue.main.async {
                if token.isCancelled {
                    log(lang.selectedLanguage == "ru" ? "Операция остановлена." : "Operation stopped.")
                } else {
                    log(lang.t("log_backup_finished", successCount))
                    OperationHistoryService.shared.record(
                        tool: "Covers Optimizer",
                        title: "Backup Original Covers",
                        status: "OK",
                        message: lang.t("log_backup_finished", successCount),
                        affectedCount: successCount,
                        backupPath: service.backupFolder.path
                    )
                }
                isProcessing = false
                currentTrackName = ""
            }
        }
    }
    
    private func runOptimize() {
        isProcessing = true
        let token = CoversProcessingCancelToken()
        cancelToken = token
        progressValue = 0
        progressMax = 1
        logs.removeAll()
        log(lang.t("log_optimize_started", targetSize))
        
        DispatchQueue.global(qos: .userInitiated).async {
            let service = CoversOptimizerService.shared
            let tracks = service.getTracksWithCovers()
            
            if tracks.isEmpty {
                let libraryCount = MusicService.shared.getLibraryTrackCount()
                DispatchQueue.main.async {
                    if let count = libraryCount, count == 0 {
                        log(lang.selectedLanguage == "ru" ? "В Music нет треков. Оптимизировать обложки не из чего." : "Music has no tracks. There are no covers to optimize.")
                    } else if libraryCount == nil {
                        log(lang.selectedLanguage == "ru" ? "Не удалось прочитать медиатеку Music, или она пуста." : "Could not read your Music library, or it may be empty.")
                    } else {
                        log(lang.t("no_covers_found"))
                    }
                    isProcessing = false
                }
                return
            }
            
            DispatchQueue.main.async {
                progressMax = Double(tracks.count)
            }
            
            var successCount = 0
            for (idx, track) in tracks.enumerated() {
                if token.isCancelled { break }
                DispatchQueue.main.async {
                    currentTrackName = "\(track.artist) - \(track.title)"
                    progressValue = Double(idx + 1)
                }
                
                // Back up if not already backed up
                _ = service.backupCover(pid: track.pid, title: track.title, artist: track.artist)
                
                let success = service.optimizeCover(pid: track.pid, targetSize: targetSize)
                if success {
                    successCount += 1
                    DispatchQueue.main.async {
                        log("Optimized: \(track.title)")
                    }
                } else {
                    DispatchQueue.main.async {
                        log(lang.t("error_processing", track.title))
                    }
                }
            }
            
            DispatchQueue.main.async {
                if token.isCancelled {
                    log(lang.selectedLanguage == "ru" ? "Операция остановлена." : "Operation stopped.")
                } else {
                    log(lang.t("log_optimize_finished", successCount))
                    OperationHistoryService.shared.record(
                        tool: "Covers Optimizer",
                        title: "Optimize Covers",
                        status: "OK",
                        message: lang.t("log_optimize_finished", successCount),
                        affectedCount: successCount,
                        backupPath: service.backupFolder.path
                    )
                }
                isProcessing = false
                currentTrackName = ""
            }
        }
    }
    
    private func runRestore() {
        isProcessing = true
        let token = CoversProcessingCancelToken()
        cancelToken = token
        progressValue = 0
        progressMax = 1
        logs.removeAll()
        log(lang.t("log_restore_started"))
        
        DispatchQueue.global(qos: .userInitiated).async {
            let service = CoversOptimizerService.shared
            let tracks = service.getTracksWithCovers()
            
            if tracks.isEmpty {
                let libraryCount = MusicService.shared.getLibraryTrackCount()
                DispatchQueue.main.async {
                    if let count = libraryCount, count == 0 {
                        log(lang.selectedLanguage == "ru" ? "В Music нет треков. Восстанавливать обложки некуда." : "Music has no tracks. There are no covers to restore into.")
                    } else if libraryCount == nil {
                        log(lang.selectedLanguage == "ru" ? "Не удалось прочитать медиатеку Music, или она пуста." : "Could not read your Music library, or it may be empty.")
                    } else {
                        log(lang.t("no_covers_found"))
                    }
                    isProcessing = false
                }
                return
            }
            
            DispatchQueue.main.async {
                progressMax = Double(tracks.count)
            }
            
            var successCount = 0
            for (idx, track) in tracks.enumerated() {
                if token.isCancelled { break }
                DispatchQueue.main.async {
                    currentTrackName = "\(track.artist) - \(track.title)"
                    progressValue = Double(idx + 1)
                }
                
                let success = service.restoreCover(pid: track.pid)
                if success {
                    successCount += 1
                    DispatchQueue.main.async {
                        log("Restored: \(track.title)")
                    }
                }
            }
            
            DispatchQueue.main.async {
                if token.isCancelled {
                    log(lang.selectedLanguage == "ru" ? "Операция остановлена." : "Operation stopped.")
                } else {
                    log(lang.t("log_restore_finished", successCount))
                    OperationHistoryService.shared.record(
                        tool: "Covers Optimizer",
                        title: "Restore Original Covers",
                        status: "OK",
                        message: lang.t("log_restore_finished", successCount),
                        affectedCount: successCount,
                        backupPath: service.backupFolder.path
                    )
                }
                isProcessing = false
                currentTrackName = ""
            }
        }
    }
}
