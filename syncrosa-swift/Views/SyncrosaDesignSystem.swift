import SwiftUI

extension SyncrosaTheme {
    static let contentMaxWidth: CGFloat = 1120
    static let pageHorizontalPadding: CGFloat = 32
    static let pageVerticalPadding: CGFloat = 28
    static let cardRadius: CGFloat = 14
    static let controlRadius: CGFloat = 10
    static let accent = Color(nsColor: .controlAccentColor)
    static let destructive = Color(nsColor: .systemRed)
    static let success = Color(nsColor: .systemGreen)
    static let caution = Color(nsColor: .systemOrange)
    static let elevatedFill = Color(nsColor: .controlBackgroundColor).opacity(0.78)
    static let consoleBackground = Color(nsColor: .textColor).opacity(0.94)
    static let consoleForeground = Color(nsColor: .systemGreen)
    static let glassHighlight = Color.white.opacity(0.36)
    static let glassHairline = Color.primary.opacity(0.12)
    static let glassFill = Color.white.opacity(0.055)
}

struct SyncrosaPage<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content
            }
            .padding(.horizontal, SyncrosaTheme.pageHorizontalPadding)
            .padding(.top, SyncrosaTheme.pageVerticalPadding)
            .padding(.bottom, SyncrosaTheme.pageVerticalPadding + 40)
            .frame(maxWidth: SyncrosaTheme.contentMaxWidth, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(SyncrosaTheme.pageBackground)
    }
}

struct SyncrosaPageHeader<Trailing: View>: View {
    let title: String
    let systemImage: String
    let subtitle: String?
    let helpAction: (() -> Void)?
    private let trailing: Trailing

    init(
        title: String,
        systemImage: String,
        subtitle: String? = nil,
        helpAction: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.helpAction = helpAction
        self.trailing = trailing()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                titleBlock
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 16)
                trailing
            }

            VStack(alignment: .leading, spacing: 12) {
                titleBlock
                trailing
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.bottom, 2)
    }

    private var titleBlock: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(SyncrosaTheme.accent)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 28, weight: .bold, design: .default))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)

                    if let helpAction {
                        SyncrosaIconButton(systemImage: "questionmark.circle", action: helpAction)
                    }
                }

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

extension SyncrosaPageHeader where Trailing == EmptyView {
    init(
        title: String,
        systemImage: String,
        subtitle: String? = nil,
        helpAction: (() -> Void)? = nil
    ) {
        self.init(title: title, systemImage: systemImage, subtitle: subtitle, helpAction: helpAction) {
            EmptyView()
        }
    }
}

struct SyncrosaIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(SyncrosaGlassIconButtonStyle(size: 30))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SyncrosaCardModifier: ViewModifier {
    var padding: CGFloat = 18
    var radius: CGFloat = SyncrosaTheme.cardRadius

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background(SyncrosaTheme.glassFill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(SyncrosaTheme.glassHighlight, lineWidth: 1)
                    .blendMode(.screen)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(SyncrosaTheme.glassHairline, lineWidth: 1)
                    .blendMode(.multiply)
            )
            .shadow(color: Color.white.opacity(0.22), radius: 1, x: 0, y: -1)
            .shadow(color: SyncrosaTheme.softShadow.opacity(0.58), radius: 18, x: 0, y: 8)
    }
}

extension View {
    func syncrosaCard(padding: CGFloat = 18, radius: CGFloat = SyncrosaTheme.cardRadius) -> some View {
        modifier(SyncrosaCardModifier(padding: padding, radius: radius))
    }

    func syncrosaControlShell(
        horizontal: CGFloat = 8,
        vertical: CGFloat = 4,
        radius: CGFloat = SyncrosaTheme.controlRadius
    ) -> some View {
        modifier(SyncrosaControlShellModifier(horizontal: horizontal, vertical: vertical, radius: radius))
    }
}

struct SyncrosaControlShellModifier: ViewModifier {
    var horizontal: CGFloat
    var vertical: CGFloat
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.primary.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: SyncrosaTheme.softShadow.opacity(0.35), radius: 6, x: 0, y: 2)
    }
}

struct SyncrosaMenuOption<Value: Hashable> {
    let title: String
    let value: Value
}

struct SyncrosaGlassMenu<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [SyncrosaMenuOption<Value>]
    var width: CGFloat? = nil
    var minWidth: CGFloat = 180
    var isDisabled: Bool = false

    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Text(selectedTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isDisabled ? .secondary : .primary)

                Spacer(minLength: 8)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 13)
            .frame(width: width, height: 34, alignment: .leading)
            .frame(minWidth: width == nil ? minWidth : nil)
            .modifier(SyncrosaGlassControlModifier(isActive: false))
            .opacity(isDisabled ? 0.55 : 1)
            .accessibilityElement(children: .combine)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private var selectedTitle: String {
        options.first(where: { $0.value == selection })?.title ?? "-"
    }
}

struct SyncrosaGlassSegmentedPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [SyncrosaMenuOption<Value>]
    var minSegmentWidth: CGFloat = 88
    var isDisabled: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.84)) {
                        selection = option.value
                    }
                } label: {
                    Text(option.title)
                        .font(.system(size: 13, weight: option.value == selection ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(option.value == selection ? Color.white : Color.primary.opacity(0.86))
                        .padding(.horizontal, 14)
                        .frame(minWidth: minSegmentWidth, minHeight: 32)
                        .background(
                            Group {
                                if option.value == selection {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(SyncrosaTheme.accent)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(Color.white.opacity(0.28), lineWidth: 1)
                                        )
                                        .shadow(color: SyncrosaTheme.accent.opacity(0.30), radius: 10, x: 0, y: 4)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
            }
        }
        .padding(4)
        .modifier(SyncrosaGlassControlModifier(isActive: true))
        .opacity(isDisabled ? 0.55 : 1)
    }
}

struct SyncrosaGlassControlModifier: ViewModifier {
    var isActive: Bool

    func body(content: Content) -> some View {
        content
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background(SyncrosaTheme.glassFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(SyncrosaTheme.glassHighlight, lineWidth: 1)
                    .blendMode(.screen)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(SyncrosaTheme.glassHairline.opacity(isActive ? 1.0 : 0.86), lineWidth: 1)
                    .blendMode(.multiply)
            )
            .shadow(color: Color.white.opacity(0.30), radius: 1, x: 0, y: -1)
            .shadow(color: SyncrosaTheme.softShadow.opacity(0.70), radius: 10, x: 0, y: 5)
    }
}

struct SyncrosaSectionLabel: View {
    let text: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 7) {
            if let systemImage {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
            }
            Text(text)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
    }
}

struct SyncrosaEmptyState: View {
    let systemImage: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(SyncrosaTheme.placeholderIcon)

            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }
}

struct SyncrosaWarningPanel: View {
    let title: String
    let message: String
    var systemImage: String = "exclamationmark.triangle.fill"

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(SyncrosaTheme.destructive)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                Text(message)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(SyncrosaTheme.warningForeground)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SyncrosaTheme.warningBackground, in: RoundedRectangle(cornerRadius: SyncrosaTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SyncrosaTheme.cardRadius, style: .continuous)
                .stroke(SyncrosaTheme.warningBorder, lineWidth: 1)
        )
    }
}

struct SyncrosaLogConsole: View {
    @ObservedObject private var lang = LocalizationService.shared

    let title: String
    let lines: [String]
    var emptyText: String? = nil
    var minHeight: CGFloat = 150
    var prefixLines: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SyncrosaSectionLabel(text: title, systemImage: "terminal")

            ScrollView {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 4) {
                        if lines.isEmpty {
                            Text(resolvedEmptyText)
                                .foregroundStyle(.white.opacity(0.45))
                                .id("empty")
                        } else {
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                Text(prefixLines ? "> \(line)" : line)
                                    .foregroundStyle(SyncrosaTheme.consoleForeground)
                                    .id(index)
                            }
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: lines.count) { _, newValue in
                        if newValue > 0 {
                            proxy.scrollTo(newValue - 1, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: minHeight, idealHeight: minHeight, maxHeight: minHeight)
            .background(SyncrosaTheme.consoleBackground, in: RoundedRectangle(cornerRadius: SyncrosaTheme.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SyncrosaTheme.controlRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resolvedEmptyText: String {
        emptyText ?? (lang.selectedLanguage == "ru" ? "Ожидание действий..." : "Waiting for activity...")
    }
}

struct SyncrosaStatusBadge: View {
    let text: String
    var color: Color = SyncrosaTheme.accent

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.24), lineWidth: 1))
    }
}

struct SyncrosaSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .center, spacing: 16) {
                configuration.label

                Spacer(minLength: 16)

                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(configuration.isOn ? SyncrosaTheme.accent.opacity(0.92) : Color.primary.opacity(0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(configuration.isOn ? SyncrosaTheme.accent.opacity(0.35) : Color.primary.opacity(0.28), lineWidth: 1)
                        )

                    Circle()
                        .fill(Color.white)
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.10), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(configuration.isOn ? 0.24 : 0.18), radius: 5, x: 0, y: 2)
                        .padding(3)
                }
                .frame(width: 54, height: 30)
                .animation(.spring(response: 0.22, dampingFraction: 0.82), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

struct SyncrosaSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(minHeight: 30)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(
                (configuration.isPressed ? Color.primary.opacity(0.10) : SyncrosaTheme.glassFill),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(SyncrosaTheme.glassHighlight.opacity(isEnabled ? 1 : 0.45), lineWidth: 1)
                    .blendMode(.screen)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(isEnabled ? 0.16 : 0.07), lineWidth: 1)
                    .blendMode(.multiply)
            )
            .shadow(color: Color.white.opacity(isEnabled ? 0.20 : 0), radius: 1, x: 0, y: -1)
            .shadow(color: SyncrosaTheme.softShadow.opacity(isEnabled ? 0.50 : 0), radius: 8, x: 0, y: 4)
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SyncrosaPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var tint: Color = SyncrosaTheme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 32)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .background(
                tint.opacity(configuration.isPressed ? 0.74 : 0.92),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.white.opacity(isEnabled ? 0.34 : 0.14), lineWidth: 1)
                    .blendMode(.screen)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(tint.opacity(isEnabled ? 0.50 : 0.12), lineWidth: 1)
                    .blendMode(.multiply)
            )
            .shadow(color: tint.opacity(isEnabled ? 0.34 : 0), radius: 12, x: 0, y: 6)
            .shadow(color: Color.white.opacity(isEnabled ? 0.26 : 0), radius: 1, x: 0, y: -1)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.982 : 1)
            .animation(.spring(response: 0.20, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

struct SyncrosaDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SyncrosaPrimaryButtonStyle(tint: SyncrosaTheme.destructive)
            .makeBody(configuration: configuration)
    }
}

struct SyncrosaGlassIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var size: CGFloat = 30
    var tint: Color = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? tint.opacity(0.82) : Color.secondary)
            .frame(width: size, height: size)
            .background(.thinMaterial, in: Circle())
            .background(SyncrosaTheme.glassFill, in: Circle())
            .overlay(Circle().stroke(SyncrosaTheme.glassHighlight.opacity(isEnabled ? 1 : 0.4), lineWidth: 1).blendMode(.screen))
            .overlay(Circle().stroke(Color.primary.opacity(isEnabled ? 0.12 : 0.06), lineWidth: 1).blendMode(.multiply))
            .shadow(color: Color.white.opacity(isEnabled ? 0.18 : 0), radius: 1, x: 0, y: -1)
            .shadow(color: SyncrosaTheme.softShadow.opacity(isEnabled ? 0.45 : 0), radius: 7, x: 0, y: 3)
            .opacity(isEnabled ? 1 : 0.50)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SyncrosaAdaptiveRow<Content: View>: View {
    var alignment: VerticalAlignment = .center
    var spacing: CGFloat = 12
    private let content: Content

    init(
        alignment: VerticalAlignment = .center,
        spacing: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: alignment, spacing: spacing) {
                content
            }

            VStack(alignment: .leading, spacing: spacing) {
                content
            }
        }
    }
}
