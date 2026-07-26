import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct IPodConverterView: View {
    @ObservedObject private var lang = LocalizationService.shared

    @State private var files: [URL] = []
    @State private var outputDirectory: URL?
    @State private var isConverting = false
    @State private var completedCount = 0
    @State private var currentFilename = ""
    @State private var resultText = ""

    private var isRussian: Bool { lang.selectedLanguage == "ru" }

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
                    .disabled(isConverting)
                }

                Text(files.isEmpty
                     ? (isRussian ? "Файлы не выбраны." : "No files selected.")
                     : (isRussian ? "Выбрано файлов: \(files.count)" : "\(files.count) file(s) selected"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(outputDirectory?.path ?? (isRussian ? "Папка назначения не выбрана." : "No output folder selected."))
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
                        isConverting ? (isRussian ? "Остановить" : "Stop") : (isRussian ? "Подготовить для iPod" : "Prepare for iPod"),
                        systemImage: isConverting ? "stop.fill" : "waveform.badge.plus"
                    )
                }
                .buttonStyle(SyncrosaPrimaryButtonStyle())
                .disabled(!isConverting && (files.isEmpty || outputDirectory == nil))

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
        guard let outputDirectory else { return }
        isConverting = true
        completedCount = 0
        currentFilename = ""
        resultText = ""

        IPodCompatibilityService.shared.convert(
            files: files,
            to: outputDirectory,
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
                        ? "Готово. Создано совместимых файлов: \(result.convertedFiles.count)."
                        : "Done. Compatible files created: \(result.convertedFiles.count)."
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
