import SwiftUI
import AppKit

enum FileStatus {
    case pending
    case processing
    case done
    case error
}

struct FileItem: Identifiable {
    let id = UUID()
    var url: URL
    var status: FileStatus = .pending
    var message: String = ""
}

struct FileMediaFixerView: View {
    @ObservedObject var lang = LocalizationService.shared
    @State private var folderPath: String = ""
    @State private var fileItems: [FileItem] = []
    @State private var isProcessing: Bool = false
    @State private var downloadCovers: Bool = true
    @State private var activeNotification: NotificationMessage? = nil
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                // Card 1: Folder Selection & Controls
                VStack(alignment: .leading, spacing: 15) {
                    Label(lang.t("file_fixing"), systemImage: "folder.badge.gearshape")
                        .font(.headline)
                    
                    Text(lang.t("file_instr"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 15) {
                        TextField(lang.t("no_folder"), text: $folderPath)
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)
                        
                        Button(action: selectFolder) {
                            Label(lang.t("select_folder"), systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isProcessing)
                    }
                    
                    Toggle(lang.selectedLanguage == "ru" ? "Загружать обложки" : "Download Covers", isOn: $downloadCovers)
                        .disabled(isProcessing)
                    
                    Button(action: fixFolderMetadata) {
                        Label(lang.t("fix_all"), systemImage: "wrench.and.screwdriver")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(fileItems.isEmpty || isProcessing)
                    .frame(maxWidth: .infinity)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
                
                // Card 2: File List (Terminal style matching MediaFixerView)
                VStack(alignment: .leading, spacing: 10) {
                    Text(lang.t("files_to_process", fileItems.count))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if fileItems.isEmpty {
                        VStack(spacing: 15) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 40))
                                .foregroundColor(.gray.opacity(0.3))
                            Text(lang.t("select_folder_msg"))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(fileItems) { item in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.url.lastPathComponent)
                                        .font(.system(size: 11, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    
                                    if !item.message.isEmpty {
                                        Text(item.message)
                                            .font(.system(size: 9))
                                            .foregroundColor(item.status == .error ? .red : .blue)
                                    }
                                }
                                
                                Spacer()
                                
                                statusIcon(for: item.status)
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
    }
    
    @ViewBuilder
    func statusIcon(for status: FileStatus) -> some View {
        switch status {
        case .pending:
            Text("WAITING")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
                .padding(4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(4)
        case .processing:
            ProgressView()
                .controlSize(.mini)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 14))
        case .error:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.system(size: 14))
        }
    }
    
    func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                folderPath = url.path
                scanFolder(url)
            }
        }
    }
    
    func scanFolder(_ url: URL) {
        let musicExtensions = ["mp3", "wav", "flac", "alac", "m4a", "aiff"]
        var matches: [FileItem] = []
        
        let fm = FileManager.default
        let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) { url, error in
            return true
        }
        
        while let fileUrl = enumerator?.nextObject() as? URL {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: fileUrl.path, isDirectory: &isDir), !isDir.boolValue {
                if musicExtensions.contains(fileUrl.pathExtension.lowercased()) {
                    matches.append(FileItem(url: fileUrl))
                }
            }
        }
        
        self.fileItems = matches
        
        if fileItems.isEmpty {
            activeNotification = NotificationMessage(text: lang.selectedLanguage == "ru" ? "Музыкальные файлы не найдены." : "No music files found.", isError: true)
        } else {
            activeNotification = NotificationMessage(text: lang.t("files_to_process", fileItems.count), isError: false)
        }
    }
    
    func fixFolderMetadata() {
        isProcessing = true
        activeNotification = NotificationMessage(text: lang.t("processing_files"), isError: false)
        
        // Reset statuses
        for i in fileItems.indices {
            fileItems[i].status = .pending
            fileItems[i].message = ""
        }
        
        DispatchQueue.global().async {
            for index in fileItems.indices {
                DispatchQueue.main.async {
                    fileItems[index].status = .processing
                }
                
                // Real fixing logic
                let result = FileMetadataService.shared.fixFile(url: fileItems[index].url, downloadCover: downloadCovers)
                
                DispatchQueue.main.async {
                    fileItems[index].status = result.success ? .done : .error
                    fileItems[index].message = result.message
                    if let newURL = result.newURL {
                        fileItems[index].url = newURL
                    }
                }
            }
            
            DispatchQueue.main.async {
                isProcessing = false
                activeNotification = NotificationMessage(text: lang.t("done"), isError: false)
            }
        }
    }
}
