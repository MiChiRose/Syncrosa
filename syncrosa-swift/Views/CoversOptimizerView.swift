import SwiftUI

struct CoversOptimizerView: View {
    @ObservedObject var lang = LocalizationService.shared
    
    @State private var targetSize = 300
    @State private var logs: [String] = []
    @State private var progressValue: Double = 0.0
    @State private var progressMax: Double = 1.0
    @State private var isProcessing = false
    @State private var showBackupAlert = false
    @State private var currentTrackName = ""
    
    let devices = [
        (name: "iPod Classic / Nano / Vintage (300x300)", size: 300),
        (name: "iPhone 4s / 6 / iOS 5-6 (600x600)", size: 600),
        (name: "Modern iOS / High-Res (1000x1000)", size: 1000)
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            Text(lang.t("covers_optimizer"))
                .font(.title)
                .bold()
                .padding(.top, 10)
            
            // Picker
            HStack {
                Text(lang.t("select_device"))
                    .font(.body)
                Picker("", selection: $targetSize) {
                    ForEach(devices, id: \.size) { device in
                        Text(device.name).tag(device.size)
                    }
                }
                .pickerStyle(DefaultPickerStyle())
                .frame(width: 320)
                .disabled(isProcessing)
            }
            .padding(.horizontal)
            
            // Action Buttons
            HStack(spacing: 15) {
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
                .disabled(isProcessing)
            }
            
            // Current track/status
            if isProcessing {
                VStack(spacing: 5) {
                    Text(currentTrackName)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    ProgressView(value: progressValue, total: progressMax)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(height: 10)
                        .padding(.horizontal)
                }
            }
            
            // Terminal Console Logs
            VStack(alignment: .leading, spacing: 5) {
                Text("Console Log:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ScrollView {
                    ScrollViewReader { proxy in
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(0..<logs.count, id: \.self) { idx in
                                Text(logs[idx])
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.green)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(idx)
                            }
                        }
                        .padding(10)
                        .onChange(of: logs.count) { _ in
                            if logs.count > 0 {
                                proxy.scrollTo(logs.count - 1, anchor: .bottom)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .cornerRadius(6)
                .border(Color.gray.opacity(0.3), width: 1)
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
        .padding()
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
    }
    
    private func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let stamp = formatter.string(from: Date())
        logs.append("[\(stamp)] \(message)")
    }
    
    private func runBackup() {
        isProcessing = true
        progressValue = 0
        progressMax = 1
        logs.removeAll()
        log(lang.t("log_backup_started"))
        
        DispatchQueue.global(qos: .userInitiated).async {
            let service = CoversOptimizerService.shared
            let tracks = service.getTracksWithCovers()
            
            if tracks.isEmpty {
                DispatchQueue.main.async {
                    log(lang.t("no_covers_found"))
                    isProcessing = false
                }
                return
            }
            
            DispatchQueue.main.async {
                progressMax = Double(tracks.count)
            }
            
            var successCount = 0
            for (idx, track) in tracks.enumerated() {
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
                log(lang.t("log_backup_finished", successCount))
                isProcessing = false
                currentTrackName = ""
            }
        }
    }
    
    private func runOptimize() {
        isProcessing = true
        progressValue = 0
        progressMax = 1
        logs.removeAll()
        log(lang.t("log_optimize_started", targetSize))
        
        DispatchQueue.global(qos: .userInitiated).async {
            let service = CoversOptimizerService.shared
            let tracks = service.getTracksWithCovers()
            
            if tracks.isEmpty {
                DispatchQueue.main.async {
                    log(lang.t("no_covers_found"))
                    isProcessing = false
                }
                return
            }
            
            DispatchQueue.main.async {
                progressMax = Double(tracks.count)
            }
            
            var successCount = 0
            for (idx, track) in tracks.enumerated() {
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
                log(lang.t("log_optimize_finished", successCount))
                isProcessing = false
                currentTrackName = ""
            }
        }
    }
    
    private func runRestore() {
        isProcessing = true
        progressValue = 0
        progressMax = 1
        logs.removeAll()
        log(lang.t("log_restore_started"))
        
        DispatchQueue.global(qos: .userInitiated).async {
            let service = CoversOptimizerService.shared
            let tracks = service.getTracksWithCovers()
            
            if tracks.isEmpty {
                DispatchQueue.main.async {
                    log(lang.t("no_covers_found"))
                    isProcessing = false
                }
                return
            }
            
            DispatchQueue.main.async {
                progressMax = Double(tracks.count)
            }
            
            var successCount = 0
            for (idx, track) in tracks.enumerated() {
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
                log(lang.t("log_restore_finished", successCount))
                isProcessing = false
                currentTrackName = ""
            }
        }
    }
}
