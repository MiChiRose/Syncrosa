import SwiftUI

struct SafetyPreviewDetail: Identifiable {
    let id = UUID()
    let title: String
    let value: String
}

struct SafetyPreviewRequest: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var details: [SafetyPreviewDetail] = []
    var confirmTitle: String
    var isDestructive: Bool = false
}

struct SafetyPreviewSheet: View {
    @ObservedObject var lang = LocalizationService.shared
    let request: SafetyPreviewRequest
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: request.isDestructive ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(request.isDestructive ? SyncrosaTheme.destructive : SyncrosaTheme.accent)

                VStack(alignment: .leading, spacing: 4) {
                    Text(request.title)
                        .font(.title3)
                        .fontWeight(.bold)
                    Text(lang.selectedLanguage == "ru" ? "Предпросмотр перед запуском" : "Preview before starting")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Text(request.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !request.details.isEmpty {
                VStack(spacing: 0) {
                    ForEach(request.details) { detail in
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 12) {
                                detailTitle(detail.title)
                                    .frame(width: 130, alignment: .leading)
                                detailValue(detail.value)
                                Spacer(minLength: 0)
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                detailTitle(detail.title)
                                detailValue(detail.value)
                            }
                        }
                        .padding(.vertical, 9)

                        if detail.id != request.details.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(SyncrosaTheme.subtleBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(SyncrosaTheme.panelBorder.opacity(0.7), lineWidth: 1)
                )
            }

            SyncrosaWarningPanel(
                title: lang.selectedLanguage == "ru" ? "Проверьте перед продолжением" : "Check before continuing",
                message: request.isDestructive
                    ? (lang.selectedLanguage == "ru" ? "Это действие может изменить или удалить данные. Убедитесь, что backup создан или вы работаете с копиями." : "This action can change or delete data. Make sure a backup exists or you are working on copies.")
                    : (lang.selectedLanguage == "ru" ? "Syncrosa покажет прогресс и запишет результат в историю операций." : "Syncrosa will show progress and record the result in Operation History."),
                systemImage: request.isDestructive ? "exclamationmark.triangle.fill" : "info.circle.fill"
            )

            HStack {
                Spacer()
                Button(lang.selectedLanguage == "ru" ? "Отмена" : "Cancel", action: cancel)
                    .buttonStyle(SyncrosaSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)

                if request.isDestructive {
                    Button(action: confirm) {
                        Text(request.confirmTitle)
                            .frame(minWidth: 96)
                    }
                    .buttonStyle(SyncrosaDestructiveButtonStyle())
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(action: confirm) {
                        Text(request.confirmTitle)
                            .frame(minWidth: 96)
                    }
                    .buttonStyle(SyncrosaPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 520, idealWidth: 620, maxWidth: 720, minHeight: 420)
    }

    private func detailTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func detailValue(_ value: String) -> some View {
        Text(value)
            .font(.caption.monospaced())
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}
