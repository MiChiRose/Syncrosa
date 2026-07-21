import AppKit
import SwiftUI

enum SyncrosaAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    func displayName(language: String) -> String {
        switch (self, language) {
        case (.system, "ru"): return "Как в системе"
        case (.light, "ru"): return "Светлая"
        case (.dark, "ru"): return "Тёмная"
        case (.system, _): return "System"
        case (.light, _): return "Light"
        case (.dark, _): return "Dark"
        }
    }
}

enum SyncrosaThemeChoice: String, CaseIterable, Identifiable {
    case system
    case graphite
    case aqua
    case sage
    case plum
    case ruby
    case ocean

    var id: String { rawValue }

    func displayName(language: String) -> String {
        let russian = language == "ru"
        switch self {
        case .system: return russian ? "Система" : "System"
        case .graphite: return russian ? "Графит" : "Graphite"
        case .aqua: return russian ? "Аква" : "Aqua"
        case .sage: return russian ? "Шалфей" : "Sage"
        case .plum: return russian ? "Слива" : "Plum"
        case .ruby: return russian ? "Рубин" : "Ruby"
        case .ocean: return russian ? "Океан" : "Ocean"
        }
    }

    var accent: Color {
        switch self {
        case .system: return Color(nsColor: .controlAccentColor)
        case .graphite: return adaptiveColor(light: 0x4F6F8F, dark: 0x84A7C7)
        case .aqua: return adaptiveColor(light: 0x087BC1, dark: 0x55B8F0)
        case .sage: return adaptiveColor(light: 0x43865A, dark: 0x72C58A)
        case .plum: return adaptiveColor(light: 0x85509B, dark: 0xC58DDA)
        case .ruby: return adaptiveColor(light: 0xAD4058, dark: 0xEC7890)
        case .ocean: return adaptiveColor(light: 0x237F7B, dark: 0x5AC4BD)
        }
    }

    var secondaryAccent: Color {
        switch self {
        case .system: return adaptiveColor(light: 0x55A9E6, dark: 0x77C5F4)
        case .graphite: return adaptiveColor(light: 0x8A98A5, dark: 0xAEBCC8)
        case .aqua: return adaptiveColor(light: 0x58B5E8, dark: 0x8DD4F7)
        case .sage: return adaptiveColor(light: 0x8DB69A, dark: 0x9DD2AA)
        case .plum: return adaptiveColor(light: 0xB48BC2, dark: 0xD8AFE4)
        case .ruby: return adaptiveColor(light: 0xCF8393, dark: 0xF0A4B3)
        case .ocean: return adaptiveColor(light: 0x79B6B2, dark: 0x8BD5D0)
        }
    }

    var pageBackground: Color {
        switch self {
        case .system: return Color(nsColor: .windowBackgroundColor)
        case .graphite: return adaptiveColor(light: 0xF2F4F5, dark: 0x171A1D)
        case .aqua: return adaptiveColor(light: 0xF1F8FC, dark: 0x101C24)
        case .sage: return adaptiveColor(light: 0xF3F8F4, dark: 0x131D16)
        case .plum: return adaptiveColor(light: 0xF8F3F9, dark: 0x1D151F)
        case .ruby: return adaptiveColor(light: 0xFAF4F5, dark: 0x211517)
        case .ocean: return adaptiveColor(light: 0xF1F8F7, dark: 0x111E1D)
        }
    }

    var sidebarBackground: Color {
        switch self {
        case .system: return Color(nsColor: .underPageBackgroundColor).opacity(0.62)
        case .graphite: return adaptiveColor(light: 0xE7EBEE, dark: 0x1D2226)
        case .aqua: return adaptiveColor(light: 0xE1F1FA, dark: 0x142630)
        case .sage: return adaptiveColor(light: 0xE5F0E8, dark: 0x18271C)
        case .plum: return adaptiveColor(light: 0xF0E5F2, dark: 0x291B2C)
        case .ruby: return adaptiveColor(light: 0xF2E6E9, dark: 0x2D1A1F)
        case .ocean: return adaptiveColor(light: 0xE0EFED, dark: 0x172927)
        }
    }

    var panelBackground: Color {
        switch self {
        case .system: return Color(nsColor: .controlBackgroundColor)
        case .graphite: return adaptiveColor(light: 0xFAFBFC, dark: 0x22272B)
        case .aqua: return adaptiveColor(light: 0xF8FCFF, dark: 0x192A34)
        case .sage: return adaptiveColor(light: 0xFAFCFA, dark: 0x1D2A20)
        case .plum: return adaptiveColor(light: 0xFDF9FD, dark: 0x2B202E)
        case .ruby: return adaptiveColor(light: 0xFEFAFB, dark: 0x302126)
        case .ocean: return adaptiveColor(light: 0xF9FCFC, dark: 0x1C2D2B)
        }
    }

    var border: Color {
        switch self {
        case .system: return Color(nsColor: .separatorColor)
        default: return accent.opacity(0.24)
        }
    }
}

final class SyncrosaAppearanceService: ObservableObject {
    static let shared = SyncrosaAppearanceService()

    static let appearanceDefaultsKey = "swiftui_appearance_mode"
    static let themeDefaultsKey = "swiftui_theme_identifier"

    @Published var appearanceMode: SyncrosaAppearanceMode {
        didSet { UserDefaults.standard.set(appearanceMode.rawValue, forKey: Self.appearanceDefaultsKey) }
    }

    @Published var selectedTheme: SyncrosaThemeChoice {
        didSet { UserDefaults.standard.set(selectedTheme.rawValue, forKey: Self.themeDefaultsKey) }
    }

    private init() {
        let savedAppearance = UserDefaults.standard.string(forKey: Self.appearanceDefaultsKey)
        let savedTheme = UserDefaults.standard.string(forKey: Self.themeDefaultsKey)
        appearanceMode = SyncrosaAppearanceMode(rawValue: savedAppearance ?? "") ?? .system
        selectedTheme = SyncrosaThemeChoice(rawValue: savedTheme ?? "") ?? .system
    }
}

private func adaptiveColor(light: UInt32, dark: UInt32) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return rgbColor(isDark ? dark : light)
    })
}

private func rgbColor(_ value: UInt32) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1
    )
}
