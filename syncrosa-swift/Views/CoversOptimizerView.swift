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

private enum CoversSafetyAction {
    case backup
    case optimize
    case restore
}

struct CoversOptimizerView: View {
    @ObservedObject var lang = LocalizationService.shared
    
    @State private var targetSize = 300
    @State private var logs: [String] = []
    @State private var progressValue: Double = 0.0
    @State private var progressMax: Double = 1.0
    @State private var isProcessing = false
    @State private var cancelToken = CoversProcessingCancelToken()
    @State private var currentTrackName = ""
    @State private var showHelp = false
    @State private var safetyPreview: SafetyPreviewRequest? = nil
    @State private var pendingSafetyAction: CoversSafetyAction? = nil
    
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
                            minWidth: 300,
                            isDisabled: isProcessing
                        )
                    }
                    
                    // Action Buttons
                    SyncrosaAdaptiveRow(spacing: 15) {
                        Button(action: { presentSafetyPreview(.backup) }) {
                            Text(lang.t("btn_backup_covers"))
                                .frame(minWidth: 160)
                        }
                        .buttonStyle(SyncrosaSecondaryButtonStyle())
                        .disabled(isProcessing)
                        
                        Button(action: { presentSafetyPreview(.optimize) }) {
                            Text(lang.t("btn_optimize_covers"))
                                .bold()
                                .frame(minWidth: 160)
                        }
                        .buttonStyle(SyncrosaPrimaryButtonStyle())
                        .disabled(isProcessing)
                        
                        Button(action: { presentSafetyPreview(.restore) }) {
                            Text(lang.t("btn_restore_covers"))
                                .frame(minWidth: 160)
                        }
                        .buttonStyle(SyncrosaSecondaryButtonStyle())
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

                    if !hasCoverBackup && !isProcessing {
                        SyncrosaDisabledReason(text: lang.selectedLanguage == "ru"
                            ? "Восстановление станет доступно после создания резервной копии обложек."
                            : "Restore becomes available after you create a cover backup.")
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
        .sheet(isPresented: $showHelp) {
            helpSheetView
        }
        .sheet(item: $safetyPreview) { request in
            SafetyPreviewSheet(
                request: request,
                cancel: {
                    safetyPreview = nil
                    pendingSafetyAction = nil
                },
                confirm: {
                    let action = pendingSafetyAction
                    safetyPreview = nil
                    pendingSafetyAction = nil
                    runSafetyAction(action)
                }
            )
        }
        .onAppear {
            CoversOptimizerService.shared.createBackupFolderIfNeeded()
        }
    }

    private var hasCoverBackup: Bool {
        CoversOptimizerService.shared.backupManifestCount() > 0
    }
    
    var helpSheetView: some View {
        SyncrosaHelpSheet(
            title: lang.t("covers_optimizer"),
            summary: lang.selectedLanguage == "ru"
                ? "Уменьшает обложки для старых iPod, автомагнитол и устройств с ограниченной памятью."
                : "Downsizes artwork for older iPods, car stereos, and devices with limited memory.",
            steps: lang.selectedLanguage == "ru" ? [
                "Сначала создайте резервную копию исходных обложек.",
                "Выберите целевое разрешение для устройства.",
                "Запустите оптимизацию и дождитесь завершения журнала.",
                "При необходимости восстановите оригиналы из созданного backup."
            ] : [
                "Create a backup of original artwork first.",
                "Choose a target resolution for your device.",
                "Run optimization and wait for the log to finish.",
                "Restore the originals from the backup if needed."
            ],
            notes: lang.selectedLanguage == "ru" ? [
                "Backup хранится в Application Support/Syncrosa/Backups/AlbumCovers.",
                "Кнопка восстановления активна только когда найден совместимый backup."
            ] : [
                "Backups are stored in Application Support/Syncrosa/Backups/AlbumCovers.",
                "Restore is enabled only when a compatible backup exists."
            ],
            dismiss: { showHelp = false }
        )
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

    private func presentSafetyPreview(_ action: CoversSafetyAction) {
        pendingSafetyAction = action
        let backupPath = CoversOptimizerService.shared.backupFolder.path
        let details = [
            SafetyPreviewDetail(
                title: lang.selectedLanguage == "ru" ? "Медиатека" : "Library",
                value: lang.selectedLanguage == "ru" ? "Будет проверена после подтверждения" : "Checked after confirmation"
            ),
            SafetyPreviewDetail(title: lang.selectedLanguage == "ru" ? "Целевой размер" : "Target size", value: "\(targetSize)x\(targetSize)"),
            SafetyPreviewDetail(title: "Backup", value: backupPath)
        ]

        switch action {
        case .backup:
            safetyPreview = SafetyPreviewRequest(
                title: lang.selectedLanguage == "ru" ? "Сохранить оригинальные обложки?" : "Back up original covers?",
                message: lang.selectedLanguage == "ru" ? "Syncrosa просканирует треки Music и сохранит найденные обложки в backup manifest." : "Syncrosa will scan Music tracks and save found artwork into a backup manifest.",
                details: details,
                confirmTitle: lang.selectedLanguage == "ru" ? "Сохранить" : "Back Up",
                isDestructive: false
            )
        case .optimize:
            safetyPreview = SafetyPreviewRequest(
                title: lang.selectedLanguage == "ru" ? "Оптимизировать обложки?" : "Optimize covers?",
                message: lang.selectedLanguage == "ru" ? "Syncrosa создаст backup перед заменой обложек и затем уменьшит их до выбранного размера." : "Syncrosa will create a backup before replacing artwork, then resize covers to the selected size.",
                details: details,
                confirmTitle: lang.selectedLanguage == "ru" ? "Оптимизировать" : "Optimize",
                isDestructive: true
            )
        case .restore:
            safetyPreview = SafetyPreviewRequest(
                title: lang.selectedLanguage == "ru" ? "Восстановить оригинальные обложки?" : "Restore original covers?",
                message: lang.selectedLanguage == "ru" ? "Syncrosa попробует вернуть обложки из backup manifest. Треки без backup будут пропущены." : "Syncrosa will try to restore artwork from the backup manifest. Tracks without a backup will be skipped.",
                details: details,
                confirmTitle: lang.selectedLanguage == "ru" ? "Восстановить" : "Restore",
                isDestructive: false
            )
        }
    }

    private func runSafetyAction(_ action: CoversSafetyAction?) {
        switch action {
        case .backup:
            runBackup()
        case .optimize:
            runOptimize()
        case .restore:
            runRestore()
        case .none:
            break
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
        let recoveryID = OperationRecoveryService.shared.begin(
            tool: "Covers Optimizer",
            title: "Backup Original Covers",
            message: lang.selectedLanguage == "ru" ? "Backup обложек был прерван. Проверьте manifest в Recovery Center перед продолжением." : "Cover backup was interrupted. Check the manifest in Recovery Center before continuing.",
            backupPath: CoversOptimizerService.shared.backupFolder.path
        )
        
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
                    OperationRecoveryService.shared.finish(recoveryID)
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
                OperationRecoveryService.shared.finish(recoveryID)
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
        let recoveryID = OperationRecoveryService.shared.begin(
            tool: "Covers Optimizer",
            title: "Optimize Covers",
            message: lang.selectedLanguage == "ru" ? "Оптимизация обложек была прервана. Оригиналы можно проверить в Recovery Center." : "Cover optimization was interrupted. Originals can be checked in Recovery Center.",
            backupPath: CoversOptimizerService.shared.backupFolder.path
        )
        
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
                    OperationRecoveryService.shared.finish(recoveryID)
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
                OperationRecoveryService.shared.finish(recoveryID)
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
        let recoveryID = OperationRecoveryService.shared.begin(
            tool: "Covers Optimizer",
            title: "Restore Original Covers",
            message: lang.selectedLanguage == "ru" ? "Восстановление обложек было прервано. Проверьте последние записи в истории операций." : "Cover restore was interrupted. Check the latest Operation History records.",
            backupPath: CoversOptimizerService.shared.backupFolder.path
        )
        
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
                    OperationRecoveryService.shared.finish(recoveryID)
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
                OperationRecoveryService.shared.finish(recoveryID)
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
