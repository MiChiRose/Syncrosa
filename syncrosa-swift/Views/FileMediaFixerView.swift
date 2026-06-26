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
    let url: URL
    var status: FileStatus = .pending
}

struct FileMediaFixerView: View {
    @ObservedObject var lang = LocalizationService.shared
    @State private var folderPath: String = ""
    @State private var fileItems: [FileItem] = []
    @State private var isProcessing: Bool = false
    @State private var activeNotification: NotificationMessage? = nil
    @State private var downloadCovers: Bool = true
    @State private var showHelp: Bool = false
    
    // Checkbox checklist states
    @State private var fixAlbum: Bool = true
    @State private var fixTitle: Bool = true
    @State private var fixArtist: Bool = true
    @State private var fixGenre: Bool = true
    @State private var fixTrackNumber: Bool = true
    @State private var fixLyrics: Bool = true
    
    // Select All Binding
    var selectAllBinding: Binding<Bool> {
        Binding<Bool>(
            get: { fixAlbum && fixTitle && fixArtist && fixGenre && fixTrackNumber && fixLyrics },
            set: { newValue in
                fixAlbum = newValue
                fixTitle = newValue
                fixArtist = newValue
                fixGenre = newValue
                fixTrackNumber = newValue
                fixLyrics = newValue
            }
        )
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                // Title with Help Button
                HStack(alignment: .center, spacing: 10) {
                    Label(lang.t("file_fixing"), systemImage: "folder.badge.gearshape")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Button(action: { showHelp = true }) {
                        Image(systemName: "questionmark.circle")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                // Checklist Card
                VStack(alignment: .leading, spacing: 15) {
                    Text(lang.selectedLanguage == "ru" ? "ПРИМЕНЯТЬ ТОЛЬКО ОТМЕЧЕННЫЕ ТЕГИ" : "APPLY ONLY CHECKED TAGS")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Toggle(isOn: selectAllBinding) {
                        Text(lang.selectedLanguage == "ru" ? "Выбрать все" : "Select All")
                            .fontWeight(.bold)
                    }
                    .toggleStyle(.checkbox)
                    
                    Divider()
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], alignment: .leading, spacing: 12) {
                        Toggle(lang.selectedLanguage == "ru" ? "Альбом" : "Album", isOn: $fixAlbum)
                            .toggleStyle(.checkbox)
                        Toggle(lang.selectedLanguage == "ru" ? "Название" : "Title", isOn: $fixTitle)
                            .toggleStyle(.checkbox)
                        Toggle(lang.selectedLanguage == "ru" ? "Исполнитель" : "Artist", isOn: $fixArtist)
                            .toggleStyle(.checkbox)
                        Toggle(lang.selectedLanguage == "ru" ? "Жанр" : "Genre", isOn: $fixGenre)
                            .toggleStyle(.checkbox)
                        Toggle(lang.selectedLanguage == "ru" ? "Номер трека" : "Track Number", isOn: $fixTrackNumber)
                            .toggleStyle(.checkbox)
                        Toggle(lang.selectedLanguage == "ru" ? "Текст песен" : "Lyrics", isOn: $fixLyrics)
                            .toggleStyle(.checkbox)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
                
                // Card 1: Folder Selection & Controls
                VStack(alignment: .leading, spacing: 15) {
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
                        
                        Button(action: fixFolderMetadata) {
                            Label(lang.t("fix_all"), systemImage: "wrench.and.screwdriver")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(fileItems.isEmpty || isProcessing || (!fixAlbum && !fixTitle && !fixArtist && !fixGenre && !fixTrackNumber && !fixLyrics))
                    }
                    
                    Toggle(isOn: $downloadCovers) {
                        Text(lang.selectedLanguage == "ru" ? "Скачивать обложки альбомов в папку" : "Download album covers into the folder")
                            .font(.caption)
                    }
                    .toggleStyle(.checkbox)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
                
                // Card 2: File List
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
                                Text(item.url.lastPathComponent)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                
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
        .sheet(isPresented: $showHelp) {
            helpSheetView
        }
    }
    
    var helpSheetView: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(lang.selectedLanguage == "ru" ? "Инструкция: Работа с файлами" : "Help: Folder Fixer")
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
                         "Этот инструмент предназначен для прямого переименования и упорядочивания музыкальных файлов (MP3, FLAC, M4A и др.) в выбранной папке на диске.\n\n" +
                         "Инструкция по использованию:\n" +
                         "1. Выберите в панели тегов те свойства, которые вы хотите применить к переименованию файлов.\n" +
                         "2. Укажите, нужно ли автоматически скачивать обложку альбома в ту же папку.\n" +
                         "3. Нажмите «Выбрать папку» и укажите директорию с вашей музыкой.\n" +
                         "4. Программа отсканирует все поддерживаемые файлы и выведет их список.\n" +
                         "5. Нажмите «Исправить все файлы». Программа запросит корректные данные из iTunes Search API и переименует файлы по шаблону «Исполнитель - Название.расширение», применяя только выбранные теги." :
                         
                         "This tool is designed to directly rename and organize music files (MP3, FLAC, M4A, etc.) in a folder on your disk.\n\n" +
                         "How to use:\n" +
                         "1. Select the specific tags in the tags panel that you wish to apply to the file processing/renaming.\n" +
                         "2. Select whether to download album covers to the folder.\n" +
                         "3. Click 'Select Folder' and choose the directory containing your music files.\n" +
                         "4. The program will scan the directory and list all supported files.\n" +
                         "5. Click 'Fix All Files' to process the files. The app will search iTunes Search API and rename files to '[Artist] - [Title].[ext]' based only on the checked tags."
                    )
                    .font(.body)
                }
            }
            .frame(minWidth: 450, minHeight: 300)
        }
        .padding()
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
        
        for i in fileItems.indices {
            fileItems[i].status = .pending
        }
        
        let tagsMap: [String: Bool] = [
            "album": fixAlbum,
            "title": fixTitle,
            "artist": fixArtist,
            "genre": fixGenre,
            "trackNumber": fixTrackNumber,
            "lyrics": fixLyrics
        ]
        
        DispatchQueue.global().async {
            for index in fileItems.indices {
                DispatchQueue.main.async {
                    fileItems[index].status = .processing
                }
                
                let success = FileMetadataService.shared.fixFile(
                    url: fileItems[index].url,
                    downloadCover: downloadCovers,
                    checkedTags: tagsMap
                )
                
                DispatchQueue.main.async {
                    fileItems[index].status = success ? .done : .error
                }
            }
            
            DispatchQueue.main.async {
                isProcessing = false
                activeNotification = NotificationMessage(text: lang.t("done"), isError: false)
            }
        }
    }
}
