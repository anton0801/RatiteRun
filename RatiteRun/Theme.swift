//
//  Theme.swift
//  RatiteRun
//
//  Design system: palette, hex color helper, theme manager.
//

import SwiftUI
import Combine

// MARK: - Hex Color

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: s).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch s.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

// MARK: - Dynamic (light/dark) helper

private func dyn(_ light: String, _ dark: String) -> Color {
    Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(Color(hex: dark))
            : UIColor(Color(hex: light))
    })
}

// MARK: - Palette

enum Palette {
    // Neutrals (adapt to dark mode so the whole app repaints)
    static let bg        = dyn("#FBF4E6", "#151109")
    static let bgSoft    = dyn("#F3E8D2", "#201A0E")
    static let bgDepth   = dyn("#EBDCC0", "#2A2213")
    static let card      = dyn("#FFFFFF", "#241D11")
    static let cardHover = dyn("#FBF4E6", "#2E2515")
    static let border    = dyn("#E8D9BD", "#3A2F1B")
    static let divider   = dyn("#EFE2C7", "#33291790")

    // Brand — constant across modes
    static let primary       = Color(hex: "#E0982A")
    static let primaryActive = Color(hex: "#C27D18")
    static let primaryHi      = Color(hex: "#F4BE5A")
    static let savanna        = Color(hex: "#8A9A5B")
    static let savannaHi      = Color(hex: "#ABB985")
    static let action         = Color(hex: "#EE8A3A")
    static let actionHi       = Color(hex: "#F8AE66")

    // Status
    static let norm      = Color(hex: "#5FA84A")
    static let working   = Color(hex: "#E0982A")
    static let attention = Color(hex: "#F5B400")
    static let danger    = Color(hex: "#E5484D")

    // Text
    static let textPrimary   = dyn("#3A2C12", "#F2E7D0")
    static let textSecondary = dyn("#6E5A2C", "#C4B487")
    static let textDisabled  = dyn("#A89464", "#7C6E4C")

    // Button label colors
    static let onPrimary = Color(hex: "#3A2806")
    static let onSavanna = Color(hex: "#1E230F")
    static let onDanger  = Color(hex: "#FFFFFF")

    // Effects
    static let amberGlow = Color(hex: "#E0982A").opacity(0.22)
    static let oliveGlow = Color(hex: "#8A9A5B").opacity(0.20)
    static let shadow    = Color(hex: "#785A1E").opacity(0.10)
}

// MARK: - Theme Manager

enum AppThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

final class ThemeManager: ObservableObject {
    @Published var mode: AppThemeMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "ratiterun.theme") }
    }
    init() {
        let raw = UserDefaults.standard.string(forKey: "ratiterun.theme") ?? AppThemeMode.system.rawValue
        mode = AppThemeMode(rawValue: raw) ?? .system
    }
    var colorScheme: ColorScheme? { mode.scheme }
}

// MARK: - Fonts

enum AppFont {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static let title    = rounded(26, .bold)
    static let heading  = rounded(20, .semibold)
    static let body     = rounded(16, .regular)
    static let caption  = rounded(13, .medium)
    static let mono     = Font.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit()
}
