import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct IPodConverterView: View {
    @ObservedObject private var lang = LocalizationService.shared

    @State private var files: [URL] = []
    @State private var outputDirectory: URL?
    @State private var conversionMode: IPodConversionMode = .createCopy
    @State private var isConverting = false
    @State private var completedCount = 0
    @State private var currentFilename = ""
    @State private var resultText = ""

    private var isRussian: Bool { lang.selectedLanguage == "ru" }
    private var replacesMusicTrack: Bool { conversionMode == .replaceMusicTrack }
    private var allFilesAreM4A: Bool {
        !files.isEmpty && files.allSatisfy { $0.pathExtension.lowercased() == "m4a" }
    }

    var body: some View {
        SyncrosaPage {
            SyncrosaPageHeader(
                title: isRussian ? "Конвертер для iPod" : "iPod Converter",
                systemImage: "ipod",
                subtitle: isRussian
                    ? "Создаёт совместимые M4A для старых iPod. ALAC остаётся lossless ALAC."
                    : "Creates compatible M4A files for older iPods. ALAC stays lossless ALAC."
            )

            VStack(alignment: .leading, spacing: 14) {
                SyncrosaSectionLabel(
                    text: isRussian ? "ПРОФИЛЬ СОВМЕСТИМОСТИ" : "COMPATIBILITY PROFILE",
                    systemImage: "checkmark.shield"
                )

                Text(isRussian
                     ? "ALAC пересобирается в ALAC без потери качества, с исходной частотой и разрядностью. Остальные форматы преобразуются в Apple M4A / AAC-LC."
                     : "ALAC is rebuilt as ALAC without quality loss, preserving its sample rate and bit depth. Other formats are converted to Apple M4A / AAC-LC.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(isRussian
                     ? "Подходит для длинных MP3/M4A, которые старый iPod пропускает из-за заголовков VBR или особенностей кодирования."
                     : "Useful for long MP3/M4A files that an older iPod skips because of VBR headers or encoding details.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .syncrosaCard()

            VStack(alignment: .leading, spacing: 14) {
                SyncrosaSectionLabel(
                    text: isRussian ? "ФАЙЛЫ И ПАПКА НАЗНАЧЕНИЯ" : "FILES AND DESTINATION",
                    systemImage: "music.note"
                )

                Picker(isRussian ? "Режим" : "Mode", selection: $conversionMode) {
                    Text(isRussian ? "Создать копию" : "Create Copy")
                        .tag(IPodConversionMode.createCopy)
                    Text(isRussian ? "Заменить в Music" : "Replace in Music")
                        .tag(IPodConversionMode.replaceMusicTrack)
                }
                .pickerStyle(.segmented)
                .disabled(isConverting)

                SyncrosaAdaptiveRow(spacing: 12) {
                    Button(action: selectFiles) {
                        Label(isRussian ? "Выбрать аудиофайлы" : "Choose Audio Files", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(SyncrosaSecondaryButtonStyle())
                    .disabled(isConverting)

                    Button(action: selectOutputDirectory) {
                        Label(isRussian ? "Выбрать папку" : "Choose Output Folder", systemImage: "folder")
                    }
                    .buttonStyle(SyncrosaSecondaryButtonStyle())
                    .disabled(isConverting || replacesMusicTrack)
                }

                Text(files.isEmpty
                     ? (isRussian ? "Файлы не выбраны." : "No files selected.")
                     : (isRussian ? "Выбрано файлов: \(files.count)" : "\(files.count) file(s) selected"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(replacesMusicTrack
                     ? (isRussian
                        ? "Оригинал будет сохранён рядом как Syncrosa Backup."
                        : "The original will be saved beside the track as Syncrosa Backup.")
                     : (outputDirectory?.path ?? (isRussian ? "Папка назначения не выбрана." : "No output folder selected.")))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                if !files.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(files, id: \.path) { file in
                                Text(file.lastPathComponent)
                                    .font(.caption.monospaced())
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 130)
                }
            }
            .syncrosaCard()

            VStack(alignment: .leading, spacing: 12) {
                if isConverting {
                    ProgressView(value: Double(completedCount), total: Double(max(files.count, 1)))
                    Text(isRussian
                         ? "\(completedCount) из \(files.count): \(currentFilename)"
                         : "\(completedCount) of \(files.count): \(currentFilename)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Button(action: isConverting ? cancelConversion : startConversion) {
                    Label(
                        isConverting
                            ? (isRussian ? "Остановить" : "Stop")
                            : (replacesMusicTrack
                                ? (isRussian ? "Починить и заменить" : "Repair and Replace")
                                : (isRussian ? "Подготовить для iPod" : "Prepare for iPod")),
                        systemImage: isConverting ? "stop.fill" : "waveform.badge.plus"
                    )
                }
                .buttonStyle(SyncrosaPrimaryButtonStyle())
                .disabled(!isConverting && (
                    files.isEmpty ||
                    (replacesMusicTrack ? !allFilesAreM4A : outputDirectory == nil)
                ))

                if !resultText.isEmpty {
                    Text(resultText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .syncrosaCard()

            Spacer()
        }
    }

    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = IPodCompatibilityService.supportedExtensions
            .compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK {
            files = panel.urls
            resultText = ""
        }
    }

    private func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK {
            outputDirectory = panel.url
            resultText = ""
        }
    }

    private func startConversion() {
        guard !files.isEmpty else { return }
        if replacesMusicTrack {
            guard allFilesAreM4A else {
                let alert = NSAlert()
                alert.messageText = isRussian
                    ? "Замена поддерживается только для M4A"
                    : "Replacement supports M4A files only"
                alert.informativeText = isRussian
                    ? "Для MP3, WAV и других форматов используйте режим создания отдельной копии."
                    : "Use Create Copy for MP3, WAV, and other source formats."
                alert.runModal()
                return
            }

            if !MusicService.shared.isMusicRunning() {
                let alert = NSAlert()
                alert.messageText = isRussian ? "Для замены нужен Music" : "Music is required"
                alert.informativeText = isRussian
                    ? "Syncrosa найдёт существующую запись трека, чтобы сохранить метаданные и обложку."
                    : "Syncrosa uses the existing track entry to preserve its metadata and artwork."
                alert.addButton(withTitle: isRussian ? "Открыть Music и продолжить" : "Open Music and Continue")
                alert.addButton(withTitle: isRussian ? "Отмена" : "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn,
                      MusicService.shared.launchMusic() else {
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    startConversion()
                }
                return
            }

            let confirmation = NSAlert()
            confirmation.alertStyle = .warning
            confirmation.messageText = isRussian
                ? "Заменить выбранные треки?"
                : "Replace the selected tracks?"
            confirmation.informativeText = isRussian
                ? "Каждый исходный M4A будет сохранён рядом как «Syncrosa Backup». Путь в Music останется прежним; метаданные и обложка будут применены к новому файлу."
                : "Each original M4A will be saved beside it as “Syncrosa Backup”. Its Music path stays the same, and metadata and artwork are reapplied to the new file."
            confirmation.addButton(withTitle: isRussian ? "Заменить с резервной копией" : "Replace with Backup")
            confirmation.addButton(withTitle: isRussian ? "Отмена" : "Cancel")
            guard confirmation.runModal() == .alertFirstButtonReturn else { return }
        }

        guard let destinationDirectory = replacesMusicTrack
            ? files.first?.deletingLastPathComponent()
            : outputDirectory else {
            return
        }
        isConverting = true
        completedCount = 0
        currentFilename = ""
        resultText = ""

        IPodCompatibilityService.shared.convert(
            files: files,
            to: destinationDirectory,
            mode: conversionMode,
            progress: { completed, _, filename in
                completedCount = completed
                currentFilename = filename
            },
            completion: { result in
                isConverting = false
                completedCount = result.convertedFiles.count + result.failures.count

                if result.wasCancelled {
                    resultText = isRussian
                        ? "Остановлено. Готово файлов: \(result.convertedFiles.count)."
                        : "Stopped. Converted files: \(result.convertedFiles.count)."
                } else if result.failures.isEmpty {
                    resultText = isRussian
                        ? (replacesMusicTrack
                            ? "Готово. Заменено треков: \(result.convertedFiles.count). Оригиналы сохранены как Syncrosa Backup."
                            : "Готово. Создано совместимых файлов: \(result.convertedFiles.count).")
                        : (replacesMusicTrack
                            ? "Done. Replaced tracks: \(result.convertedFiles.count). Originals were saved as Syncrosa Backup."
                            : "Done. Compatible files created: \(result.convertedFiles.count).")
                } else {
                    resultText = isRussian
                        ? "Создано: \(result.convertedFiles.count). Не удалось: \(result.failures.count). \(result.failures.first?.message ?? "")"
                        : "Created: \(result.convertedFiles.count). Failed: \(result.failures.count). \(result.failures.first?.message ?? "")"
                }

                OperationHistoryService.shared.record(
                    tool: "iPod Converter",
                    title: "Compatibility conversion",
                    status: result.failures.isEmpty ? "OK" : "Warning",
                    message: resultText,
                    affectedCount: result.convertedFiles.count
                )
            }
        )
    }

    private func cancelConversion() {
        IPodCompatibilityService.shared.cancel()
    }
}
