import AppKit
import SwiftUI

struct OverviewView: View {
    @ObservedObject var lang = LocalizationService.shared
    @ObservedObject private var recovery = OperationRecoveryService.shared
    @State private var showWizard = false
    @State private var showHistory = false
    @AppStorage("only_local_mode") private var onlyLocalMode = false

    let libraryStatus: MusicLibraryStatus
    let isRefreshingLibraryStatus: Bool
    let refreshLibraryStatus: () -> Void
    let openLibraryDoctor: () -> Void
    let openRecoveryCenter: () -> Void

    var body: some View {
        SyncrosaPage {
            SyncrosaPageHeader(
                title: lang.t("overview"),
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
                overviewCard(
                    title: lang.selectedLanguage == "ru" ? "Восстановление" : "Recovery",
                    value: recovery.activeOperation == nil ? (lang.selectedLanguage == "ru" ? "Чисто" : "Clean") : (lang.selectedLanguage == "ru" ? "Нужна проверка" : "Needs Review"),
                    icon: recovery.activeOperation == nil ? "checkmark.shield" : "exclamationmark.triangle",
                    tint: recovery.activeOperation == nil ? SyncrosaTheme.success : SyncrosaTheme.caution
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

                    Button(action: openRecoveryCenter) {
                        Label(lang.t("recovery_center"), systemImage: "cross.case")
                    }
                    .buttonStyle(SyncrosaSecondaryButtonStyle())

                    Toggle(lang.selectedLanguage == "ru" ? "Only Local" : "Only Local", isOn: $onlyLocalMode)
                        .toggleStyle(SyncrosaSwitchToggleStyle())
                }
            }
            .syncrosaCard()

            VStack(alignment: .leading, spacing: 10) {
                SyncrosaSectionLabel(text: lang.selectedLanguage == "ru" ? "Что сейчас защищено" : "Current Safeguards", systemImage: "checkmark.shield")
                safetyRow(lang.selectedLanguage == "ru" ? "Вкладки Music блокируются, когда медиатека пуста или недоступна." : "Music tabs are blocked when the library is empty or unavailable.")
                safetyRow(lang.selectedLanguage == "ru" ? "Долгие операции выполняются частями и показывают прогресс." : "Long operations run in chunks and show visible progress.")
                safetyRow(lang.selectedLanguage == "ru" ? "Info Eraser сохраняет данные восстановления и записывает операцию в историю." : "Info Eraser keeps restore data and records the operation.")
                safetyRow(lang.selectedLanguage == "ru" ? "Локальный режим отключает сетевой поиск метаданных." : "Only Local Mode skips online metadata lookups.")
                safetyRow(lang.selectedLanguage == "ru" ? "Прерванные операции оставляют маркер в Центре восстановления." : "Interrupted operations leave a marker in Recovery Center.")
            }
            .syncrosaCard()
        }
        .sheet(isPresented: $showWizard) {
            FirstLaunchSetupWizard(
                libraryStatus: libraryStatus,
                checkMusic: refreshLibraryStatus,
                completion: {
                    showWizard = false
                    OperationHistoryService.shared.record(
                        tool: "Overview",
                        title: "First Launch Setup",
                        status: "OK",
                        message: "First launch setup was completed or skipped.",
                        affectedCount: 0
                    )
                }
            )
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
            return lang.selectedLanguage == "ru" ? "\(count) треков" : "\(count) tracks"
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("only_local_mode") private var onlyLocalMode = false
    @State private var currentStep = 0
    @State private var forward = true

    let libraryStatus: MusicLibraryStatus
    let checkMusic: () -> Void
    let completion: () -> Void

    private struct Step {
        let title: String
        let message: String
        let detail: String
        let highlights: [String]
        let symbol: String
        let badgeSymbol: String
        let tint: Color
    }

    private var steps: [Step] {
        if lang.selectedLanguage == "ru" {
            return [
                Step(
                    title: "Всё для музыкальной коллекции",
                    message: "Syncrosa объединяет работу с медиатекой Music, локальными файлами, папками и внешними накопителями.",
                    detail: "Этот обзор ничего не изменяет. Он коротко покажет, где находится каждая группа инструментов.",
                    highlights: [
                        "Исправляйте данные и создавайте плейлисты в Music.",
                        "Обрабатывайте файлы, папки и музыку для старых Apple-устройств."
                    ],
                    symbol: "music.note.house.fill",
                    badgeSymbol: "wand.and.stars",
                    tint: SyncrosaTheme.accent
                ),
                Step(
                    title: "Подключите Music",
                    message: "Разрешите доступ к Music, когда macOS покажет системный запрос, затем проверьте медиатеку.",
                    detail: "Syncrosa читает названия и идентификаторы треков через системную автоматизацию macOS.",
                    highlights: [
                        "Статус и количество треков всегда видны в «Обзоре».",
                        "Аудиофайлы не копируются и не изменяются без отдельной команды."
                    ],
                    symbol: "music.note.list",
                    badgeSymbol: "checkmark.shield.fill",
                    tint: .blue
                ),
                Step(
                    title: "Плейлисты с AI и без сети",
                    message: "«AI Плейлист» собирает подборки через выбранного AI-провайдера, а «Офлайн-плейлист» работает по локальным правилам и эпохам.",
                    detail: "В Media Fixer можно экспортировать каталог JSON для любого внешнего AI и импортировать его выбор обратно как плейлист.",
                    highlights: [
                        "AI-подборки по запросу, жанру или настроению.",
                        "Локальная генерация без отправки медиатеки в сеть."
                    ],
                    symbol: "sparkles",
                    badgeSymbol: "music.note",
                    tint: .purple
                ),
                Step(
                    title: "Исправляйте данные треков",
                    message: "«Медиа Фиксер iTunes» восстанавливает выбранные поля: название, исполнителя, альбом, жанр, номер трека и текст песни.",
                    detail: "Он также находит разделённые альбомы. Вы сами отмечаете поля, которые разрешено менять, до запуска процесса.",
                    highlights: [
                        "Добавление текстов песен и корректных метаданных.",
                        "Поиск обложек и объединение ошибочно разделённых альбомов."
                    ],
                    symbol: "wrench.and.screwdriver.fill",
                    badgeSymbol: "text.quote",
                    tint: .orange
                ),
                Step(
                    title: "Работайте прямо с файлами",
                    message: "«Фиксер папок» изменяет теги и имена локальных музыкальных файлов, включая вложенные папки, не добавляя их в Music.",
                    detail: "«Info Eraser» отдельно удаляет встроенные теги и обложки с обязательным подтверждением и возможностью восстановления из backup.",
                    highlights: [
                        "Исправление MP3, M4A, FLAC и других поддерживаемых форматов.",
                        "Предпросмотр имён и безопасная обработка копии папки."
                    ],
                    symbol: "folder.badge.gearshape",
                    badgeSymbol: "doc.text.magnifyingglass",
                    tint: .teal
                ),
                Step(
                    title: "Проверяйте здоровье медиатеки",
                    message: "Library Doctor проверяет обложки, повреждённые ссылки и совместимость, а «Поиск дубликатов» помогает разобрать повторяющиеся треки пакетно.",
                    detail: "Library Toolkit добавляет аудит тегов, предпросмотр переименований, источники данных, undo-пакеты и отчёты JSON/CSV.",
                    highlights: [
                        "Сначала аудит и предпросмотр, затем применение.",
                        "Отчёты и история помогают понять результат операции."
                    ],
                    symbol: "stethoscope",
                    badgeSymbol: "checkmark.circle.fill",
                    tint: .green
                ),
                Step(
                    title: "Готовьте музыку для старых устройств",
                    message: "«Оптимизатор обложек» уменьшает artwork под iPod и старые устройства, экономя место без изменения аудиодорожки.",
                    detail: "«USB Экспорт» копирует выбранный плейлист на флешку в отдельную папку и при необходимости создаёт M3U/M3U8.",
                    highlights: [
                        "Размеры обложек под Classic, Nano и другие профили.",
                        "Безопасные имена файлов и готовая структура на флешке."
                    ],
                    symbol: "externaldrive.fill",
                    badgeSymbol: "photo.fill",
                    tint: .blue
                ),
                Step(
                    title: "Безопасность и контроль",
                    message: "Перед массовыми изменениями создавайте backup. Recovery Center и история операций показывают, что можно проверить или восстановить.",
                    detail: "В «Настройках» находятся оформление, язык, AI-провайдер, обновления и локальный режим. Их можно изменить в любой момент.",
                    highlights: [
                        "Прерванные операции оставляют маркер восстановления.",
                        "Локальный режим отключает сетевой поиск метаданных."
                    ],
                    symbol: "cross.case.fill",
                    badgeSymbol: onlyLocalMode ? "lock.fill" : "globe",
                    tint: onlyLocalMode ? .green : .indigo
                )
            ]
        }

        return [
            Step(
                title: "Everything for your music collection",
                message: "Syncrosa brings together your Music library, local files, folders, and external drives.",
                detail: "This tour changes nothing. It quickly shows where every group of tools lives.",
                highlights: [
                    "Repair details and create playlists in Music.",
                    "Process files, folders, and music for older Apple devices."
                ],
                symbol: "music.note.house.fill",
                badgeSymbol: "wand.and.stars",
                tint: SyncrosaTheme.accent
            ),
            Step(
                title: "Connect Music",
                message: "Allow Music access when macOS asks, then verify that Syncrosa can read your library.",
                detail: "Syncrosa reads track names and identifiers through macOS system automation.",
                highlights: [
                    "Overview always shows library status and track count.",
                    "Audio is never copied or changed without a separate command."
                ],
                symbol: "music.note.list",
                badgeSymbol: "checkmark.shield.fill",
                tint: .blue
            ),
            Step(
                title: "Playlists with AI or offline",
                message: "AI Playlist creates selections through your provider, while Offline Playlist works with local rules and eras.",
                detail: "Media Fixer can export a catalog JSON for any external AI and import its selection back as a playlist.",
                highlights: [
                    "AI selections by request, genre, or mood.",
                    "Local generation without sending your library online."
                ],
                symbol: "sparkles",
                badgeSymbol: "music.note",
                tint: .purple
            ),
            Step(
                title: "Repair track information",
                message: "iTunes Media Fixer restores selected fields: title, artist, album, genre, track number, and lyrics.",
                detail: "It also finds split albums. You choose exactly which fields may change before the process starts.",
                highlights: [
                    "Add lyrics and correct metadata.",
                    "Find artwork and merge accidentally split albums."
                ],
                symbol: "wrench.and.screwdriver.fill",
                badgeSymbol: "text.quote",
                tint: .orange
            ),
            Step(
                title: "Work directly with files",
                message: "Folder Fixer edits tags and filenames in local music files, including nested folders, without adding them to Music.",
                detail: "Info Eraser separately removes embedded tags and artwork with confirmation and backup-based restore.",
                highlights: [
                    "Repair MP3, M4A, FLAC, and other supported formats.",
                    "Preview names and process a copied folder safely."
                ],
                symbol: "folder.badge.gearshape",
                badgeSymbol: "doc.text.magnifyingglass",
                tint: .teal
            ),
            Step(
                title: "Check library health",
                message: "Library Doctor checks artwork, broken links, and compatibility, while Duplicate Finder batches repeated tracks for review.",
                detail: "Library Toolkit adds tag audits, rename previews, data sources, undo packages, and JSON/CSV reports.",
                highlights: [
                    "Audit and preview first, apply second.",
                    "Reports and history explain the result of each operation."
                ],
                symbol: "stethoscope",
                badgeSymbol: "checkmark.circle.fill",
                tint: .green
            ),
            Step(
                title: "Prepare music for older devices",
                message: "Covers Optimizer reduces artwork for iPods and older devices to save storage without changing the audio stream.",
                detail: "USB Export copies a selected playlist into its own folder on a drive and can create M3U or M3U8 files.",
                highlights: [
                    "Artwork sizes for Classic, Nano, and other profiles.",
                    "Device-safe filenames and a ready-to-use folder structure."
                ],
                symbol: "externaldrive.fill",
                badgeSymbol: "photo.fill",
                tint: .blue
            ),
            Step(
                title: "Safety and control",
                message: "Create a backup before bulk changes. Recovery Center and operation history show what can be reviewed or restored.",
                detail: "Settings contains appearance, language, AI provider, updates, and Only Local Mode. You can change them at any time.",
                highlights: [
                    "Interrupted operations leave a recovery marker.",
                    "Only Local Mode disables online metadata lookups."
                ],
                symbol: "cross.case.fill",
                badgeSymbol: onlyLocalMode ? "lock.fill" : "globe",
                tint: onlyLocalMode ? .green : .indigo
            )
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Syncrosa")
                        .font(.title3.weight(.bold))
                    Text(lang.selectedLanguage == "ru" ? "Обзор возможностей · 8 коротких шагов" : "Feature tour · 8 short steps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(lang.selectedLanguage == "ru" ? "Пропустить" : "Skip", action: completion)
                    .buttonStyle(SyncrosaSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 14)

            Divider()

            ScrollView(.vertical) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) {
                        illustration
                            .frame(width: 240)
                        stepContent
                    }

                    VStack(spacing: 14) {
                        illustration
                            .frame(height: 160)
                        stepContent
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 300, alignment: .top)
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 14) {
                HStack(spacing: 7) {
                    ForEach(steps.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == currentStep ? SyncrosaTheme.accent : Color.secondary.opacity(0.22))
                            .frame(width: index == currentStep ? 24 : 8, height: 8)
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.20), value: currentStep)

                Text("\(currentStep + 1) / \(steps.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                Button(lang.selectedLanguage == "ru" ? "Назад" : "Back") {
                    move(to: currentStep - 1)
                }
                .buttonStyle(SyncrosaSecondaryButtonStyle())
                .disabled(currentStep == 0)

                Button {
                    if currentStep == steps.count - 1 {
                        completion()
                    } else {
                        move(to: currentStep + 1)
                    }
                } label: {
                    Label(
                        currentStep == steps.count - 1
                            ? (lang.selectedLanguage == "ru" ? "Начать работу" : "Start Using Syncrosa")
                            : (lang.selectedLanguage == "ru" ? "Далее" : "Continue"),
                        systemImage: currentStep == steps.count - 1 ? "checkmark" : "arrow.right"
                    )
                }
                .buttonStyle(SyncrosaPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 14)
        }
        .frame(minWidth: 600, idealWidth: 740, maxWidth: 840, minHeight: 430, idealHeight: 480, maxHeight: 540)
    }

    private var illustration: some View {
        let step = steps[currentStep]
        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(step.tint.opacity(0.25), lineWidth: 1)

            VStack(spacing: 18) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: step.symbol)
                        .font(.system(size: 64, weight: .medium))
                        .foregroundStyle(step.tint)
                        .frame(width: 130, height: 96)
                        .rotationEffect(.degrees(currentStep == 3 ? -90 : 0))

                    Image(systemName: step.badgeSymbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(step.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.42), lineWidth: 1))
                }

                Text(illustrationCaption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(18)
            .id(currentStep)
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                removal: .opacity
            ))
        }
        .clipped()
    }

    private var stepContent: some View {
        let step = steps[currentStep]
        return VStack(alignment: .leading, spacing: 12) {
            Text(lang.selectedLanguage == "ru" ? "ШАГ \(currentStep + 1)" : "STEP \(currentStep + 1)")
                .font(.caption.weight(.bold))
                .foregroundStyle(step.tint)

            Text(step.title)
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)

            Text(step.message)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(step.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(step.highlights, id: \.self) { highlight in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(step.tint)
                            .padding(.top, 1)
                        Text(highlight)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if currentStep == 1 {
                HStack(spacing: 10) {
                    Label(libraryStatusLabel, systemImage: libraryStatusIcon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(libraryStatusColor)

                    Button(action: checkMusic) {
                        Label(lang.selectedLanguage == "ru" ? "Проверить Music" : "Check Music", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SyncrosaSecondaryButtonStyle())
                    .disabled(libraryStatus == .checking)
                }
            }

            if currentStep == steps.count - 1 {
                Toggle(isOn: $onlyLocalMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lang.t("only_local_mode"))
                            .fontWeight(.semibold)
                        Text(onlyLocalMode
                             ? (lang.selectedLanguage == "ru" ? "Сетевой поиск выключен" : "Online lookup is off")
                             : (lang.selectedLanguage == "ru" ? "Сетевой поиск разрешён" : "Online lookup is available"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(SyncrosaSwitchToggleStyle())
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(currentStep)
        .transition(reduceMotion ? .opacity : .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .opacity
        ))
    }

    private var illustrationCaption: String {
        let captionsRU = [
            "Музыка под вашим контролем",
            "Безопасный системный доступ",
            "Плейлист под любую задачу",
            "Метаданные, тексты и обложки",
            "Папки без обязательного импорта",
            "Сначала проверить, потом менять",
            "Больше музыки на старом устройстве",
            "Вы сами выбираете границы"
        ]
        let captionsEN = [
            "Your music, under control",
            "Safe system access",
            "A playlist for every purpose",
            "Metadata, lyrics, and artwork",
            "Folders without forced import",
            "Inspect first, change second",
            "More music on older devices",
            "You choose the boundaries"
        ]
        return (lang.selectedLanguage == "ru" ? captionsRU : captionsEN)[currentStep]
    }

    private var libraryStatusLabel: String {
        switch libraryStatus {
        case .checking:
            return lang.selectedLanguage == "ru" ? "Проверяю Music" : "Checking Music"
        case .available(let count):
            return lang.selectedLanguage == "ru" ? "Найдено треков: \(count)" : "Tracks found: \(count)"
        case .empty:
            return lang.selectedLanguage == "ru" ? "Медиатека пуста" : "Library is empty"
        case .unavailable:
            return lang.selectedLanguage == "ru" ? "Music пока недоступна" : "Music is unavailable"
        }
    }

    private var libraryStatusIcon: String {
        switch libraryStatus {
        case .checking: return "clock"
        case .available: return "checkmark.circle.fill"
        case .empty: return "tray"
        case .unavailable: return "exclamationmark.triangle.fill"
        }
    }

    private var libraryStatusColor: Color {
        switch libraryStatus {
        case .available: return SyncrosaTheme.success
        case .checking: return SyncrosaTheme.accent
        case .empty, .unavailable: return SyncrosaTheme.caution
        }
    }

    private func move(to step: Int) {
        guard steps.indices.contains(step) else { return }
        forward = step > currentStep
        if reduceMotion {
            currentStep = step
        } else {
            withAnimation(.easeOut(duration: 0.24)) {
                currentStep = step
            }
        }
    }
}
