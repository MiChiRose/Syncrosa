import SwiftUI

struct OverviewView: View {
    @ObservedObject var lang = LocalizationService.shared
    @State private var showWizard = false
    @State private var showHistory = false
    @AppStorage("has_seen_setup_wizard") private var hasSeenSetupWizard = false
    @AppStorage("only_local_mode") private var onlyLocalMode = false

    let libraryStatus: MusicLibraryStatus
    let isRefreshingLibraryStatus: Bool
    let refreshLibraryStatus: () -> Void
    let openLibraryDoctor: () -> Void

    var body: some View {
        SyncrosaPage {
            SyncrosaPageHeader(
                title: "Overview",
                systemImage: "gauge.with.dots.needle.33percent",
                subtitle: lang.selectedLanguage == "ru" ? "Состояние медиатеки, режимы безопасности и быстрые действия." : "Library status, safety modes, and quick actions."
            ) {
                SyncrosaAdaptiveRow(spacing: 10) {
                    Button(action: { showWizard = true }) {
                        Label(lang.selectedLanguage == "ru" ? "Мастер первого запуска" : "First Launch Setup", systemImage: "sparkles")
                    }
                    .buttonStyle(SyncrosaSecondaryButtonStyle())

                    Button(action: { showHistory = true }) {
                        Label(lang.selectedLanguage == "ru" ? "История" : "History", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(SyncrosaSecondaryButtonStyle())
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                overviewCard(
                    title: lang.selectedLanguage == "ru" ? "Медиатека" : "Library",
                    value: libraryStatusText,
                    icon: "music.note.list",
                    tint: libraryStatus.isAvailable ? SyncrosaTheme.success : SyncrosaTheme.caution
                )
                overviewCard(
                    title: lang.selectedLanguage == "ru" ? "Режим без сети" : "Only Local Mode",
                    value: onlyLocalMode ? (lang.selectedLanguage == "ru" ? "Включён" : "Enabled") : (lang.selectedLanguage == "ru" ? "Выключен" : "Disabled"),
                    icon: "wifi.slash",
                    tint: onlyLocalMode ? SyncrosaTheme.accent : .secondary
                )
                overviewCard(
                    title: lang.selectedLanguage == "ru" ? "Резервные копии" : "Backups",
                    value: SyncrosaStorage.backupsDirectory.path,
                    icon: "externaldrive.badge.plus",
                    tint: .purple
                )
            }

            VStack(alignment: .leading, spacing: 14) {
                SyncrosaSectionLabel(text: lang.selectedLanguage == "ru" ? "Быстрые действия" : "Quick Actions", systemImage: "bolt")
                SyncrosaAdaptiveRow(spacing: 12) {
                    Button(action: refreshLibraryStatus) {
                        if isRefreshingLibraryStatus {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(lang.selectedLanguage == "ru" ? "Проверить Music" : "Check Music", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(SyncrosaPrimaryButtonStyle())
                    .disabled(isRefreshingLibraryStatus)

                    Button(action: openLibraryDoctor) {
                        Label(lang.selectedLanguage == "ru" ? "Открыть Library Doctor" : "Open Library Doctor", systemImage: "stethoscope")
                    }
                    .buttonStyle(SyncrosaSecondaryButtonStyle())
                    .disabled(libraryStatus.shouldBlockLibraryTools)

                    Toggle(lang.selectedLanguage == "ru" ? "Only Local" : "Only Local", isOn: $onlyLocalMode)
                        .toggleStyle(SyncrosaSwitchToggleStyle())
                }
            }
            .syncrosaCard()

            VStack(alignment: .leading, spacing: 10) {
                SyncrosaSectionLabel(text: lang.selectedLanguage == "ru" ? "Что сейчас защищено" : "Current Safeguards", systemImage: "checkmark.shield")
                safetyRow("Music/iTunes tabs are blocked when the library is confirmed empty.")
                safetyRow("Long scans run in chunks and show visible progress.")
                safetyRow("Info Eraser keeps restore metadata in a sidecar backup and records the operation.")
                safetyRow("Only Local Mode skips online metadata lookups when you want disk-local work only.")
            }
            .syncrosaCard()
        }
        .onAppear {
            if !hasSeenSetupWizard {
                showWizard = true
                hasSeenSetupWizard = true
                OperationHistoryService.shared.record(
                    tool: "Overview",
                    title: "First Launch Setup",
                    status: "OK",
                    message: "First launch checklist was shown.",
                    affectedCount: 0
                )
            }
        }
        .sheet(isPresented: $showWizard) {
            FirstLaunchSetupWizard()
        }
        .sheet(isPresented: $showHistory) {
            OperationHistoryView()
        }
    }

    private var libraryStatusText: String {
        switch libraryStatus {
        case .checking:
            return lang.selectedLanguage == "ru" ? "Проверяется" : "Checking"
        case .available(let count):
            return "\(count) tracks"
        case .empty:
            return lang.selectedLanguage == "ru" ? "Пустая" : "Empty"
        case .unavailable:
            return lang.selectedLanguage == "ru" ? "Не прочитана" : "Unavailable"
        }
    }

    private func overviewCard(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(tint)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
        .syncrosaCard(padding: 0)
    }

    private func safetyRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text(text)
                .foregroundColor(.secondary)
        }
        .font(.subheadline)
    }
}

struct FirstLaunchSetupWizard: View {
    @ObservedObject var lang = LocalizationService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(lang.selectedLanguage == "ru" ? "Первичная настройка Syncrosa" : "Syncrosa First Launch Setup", systemImage: "sparkles")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(lang.selectedLanguage == "ru" ? "Закрыть" : "Close") {
                    dismiss()
                }
                .buttonStyle(SyncrosaSecondaryButtonStyle())
            }

            Divider()

            wizardRow("1", lang.selectedLanguage == "ru" ? "Разрешите доступ к Music, когда macOS спросит." : "Allow Music access when macOS asks.")
            wizardRow("2", lang.selectedLanguage == "ru" ? "Проверьте Overview: Syncrosa покажет, видит ли медиатеку." : "Check Overview: Syncrosa shows whether it can see the library.")
            wizardRow("3", lang.selectedLanguage == "ru" ? "Перед массовыми изменениями делайте backup или работайте с копией папки." : "Before bulk changes, create a backup or work on a copied folder.")
            wizardRow("4", lang.selectedLanguage == "ru" ? "Для работы без сети включите Only Local Mode в Overview или Settings." : "For disk-local work, enable Only Local Mode in Overview or Settings.")

            Spacer()
        }
        .padding(24)
        .frame(width: 560, height: 360)
    }

    private func wizardRow(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(Color.blue.opacity(0.12))
                .clipShape(Circle())
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
