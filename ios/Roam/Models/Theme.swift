import Foundation

/// Stable identifiers for on-device appearance presets.
enum ThemeID: String, CaseIterable, Codable, Identifiable, Equatable {
    case dark
    case light
    case goldfish
    case midnight
    case ember
    case sequoia

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .goldfish: "Goldfish"
        case .midnight: "Midnight"
        case .ember: "Ember"
        case .sequoia: "Sequoia"
        }
    }

    var subtitle: String {
        switch self {
        case .dark: "Original Roam blue on soft black"
        case .light: "Bright canvas with dark ink"
        case .goldfish: "Warm coral on a soft cream pond"
        case .midnight: "Cyan signals on deep navy"
        case .ember: "Amber glow on charcoal"
        case .sequoia: "Mint accents in a forest dusk"
        }
    }
}

enum ThemeAppearance: String, Codable, Equatable {
    case light
    case dark
}

/// Device-independent color channel values for theme palettes.
struct RGBA: Equatable, Codable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    static func rgb(_ red: Double, _ green: Double, _ blue: Double, alpha: Double = 1) -> RGBA {
        RGBA(red: red, green: green, blue: blue, alpha: alpha)
    }

    static func white(opacity: Double) -> RGBA {
        RGBA(red: 1, green: 1, blue: 1, alpha: opacity)
    }

    static func black(opacity: Double) -> RGBA {
        RGBA(red: 0, green: 0, blue: 0, alpha: opacity)
    }
}

struct ThemePalette: Equatable {
    let accent: RGBA
    let safety: RGBA
    let positive: RGBA
    let canvas: RGBA
    let cardSurface: RGBA
    let cardSurfaceElevated: RGBA
    let cardStroke: RGBA
    let cardStrokeStrong: RGBA
    let inkPrimary: RGBA
    let inkSecondary: RGBA
    let inkTertiary: RGBA
    let inkLabel: RGBA
    let cardShadow: RGBA
    let appearance: ThemeAppearance
}

enum ThemeCatalog {
    static let `default`: ThemeID = .dark

    static func palette(for id: ThemeID) -> ThemePalette {
        switch id {
        case .dark: dark
        case .light: light
        case .goldfish: goldfish
        case .midnight: midnight
        case .ember: ember
        case .sequoia: sequoia
        }
    }

    /// Restores a saved raw value, falling back to the default when unknown.
    static func resolve(rawValue: String?) -> ThemeID {
        guard let rawValue, let id = ThemeID(rawValue: rawValue) else {
            return `default`
        }
        return id
    }

    private static let dark = ThemePalette(
        accent: .rgb(0.02, 0.42, 0.92),
        safety: .rgb(1.0, 0.58, 0.0),
        positive: .rgb(0.20, 0.78, 0.35),
        canvas: .rgb(18 / 255, 18 / 255, 18 / 255),
        cardSurface: .rgb(30 / 255, 30 / 255, 30 / 255),
        cardSurfaceElevated: .rgb(36 / 255, 36 / 255, 36 / 255),
        cardStroke: .white(opacity: 0.10),
        cardStrokeStrong: .white(opacity: 0.16),
        inkPrimary: .rgb(241 / 255, 241 / 255, 241 / 255),
        inkSecondary: .white(opacity: 0.60),
        inkTertiary: .white(opacity: 0.38),
        inkLabel: .white(opacity: 0.64),
        cardShadow: .black(opacity: 0.28),
        appearance: .dark
    )

    private static let light = ThemePalette(
        accent: .rgb(0.02, 0.42, 0.92),
        safety: .rgb(0.90, 0.45, 0.05),
        positive: .rgb(0.12, 0.62, 0.30),
        canvas: .rgb(0.96, 0.96, 0.97),
        cardSurface: .rgb(1.0, 1.0, 1.0),
        cardSurfaceElevated: .rgb(0.98, 0.98, 0.99),
        cardStroke: .black(opacity: 0.08),
        cardStrokeStrong: .black(opacity: 0.14),
        inkPrimary: .rgb(0.10, 0.10, 0.12),
        inkSecondary: .black(opacity: 0.58),
        inkTertiary: .black(opacity: 0.55),
        inkLabel: .black(opacity: 0.56),
        cardShadow: .black(opacity: 0.10),
        appearance: .light
    )

    private static let goldfish = ThemePalette(
        accent: .rgb(1.0, 0.45, 0.18),
        safety: .rgb(0.92, 0.28, 0.18),
        positive: .rgb(0.18, 0.62, 0.42),
        canvas: .rgb(1.0, 0.96, 0.90),
        cardSurface: .rgb(1.0, 0.99, 0.96),
        cardSurfaceElevated: .rgb(1.0, 0.97, 0.92),
        cardStroke: .rgb(0.85, 0.55, 0.28, alpha: 0.28),
        cardStrokeStrong: .rgb(0.85, 0.45, 0.18, alpha: 0.40),
        inkPrimary: .rgb(0.28, 0.14, 0.06),
        inkSecondary: .rgb(0.42, 0.24, 0.10, alpha: 0.82),
        inkTertiary: .rgb(0.42, 0.24, 0.10, alpha: 0.70),
        inkLabel: .rgb(0.42, 0.24, 0.10, alpha: 0.74),
        cardShadow: .rgb(0.70, 0.35, 0.10, alpha: 0.14),
        appearance: .light
    )

    private static let midnight = ThemePalette(
        accent: .rgb(0.20, 0.82, 0.92),
        safety: .rgb(1.0, 0.62, 0.28),
        positive: .rgb(0.35, 0.86, 0.62),
        canvas: .rgb(0.05, 0.08, 0.16),
        cardSurface: .rgb(0.09, 0.13, 0.24),
        cardSurfaceElevated: .rgb(0.12, 0.17, 0.30),
        cardStroke: .white(opacity: 0.10),
        cardStrokeStrong: .white(opacity: 0.18),
        inkPrimary: .rgb(0.90, 0.95, 1.0),
        inkSecondary: .white(opacity: 0.62),
        inkTertiary: .white(opacity: 0.40),
        inkLabel: .white(opacity: 0.66),
        cardShadow: .black(opacity: 0.34),
        appearance: .dark
    )

    private static let ember = ThemePalette(
        accent: .rgb(0.98, 0.62, 0.18),
        safety: .rgb(1.0, 0.42, 0.18),
        positive: .rgb(0.45, 0.82, 0.38),
        canvas: .rgb(0.10, 0.08, 0.07),
        cardSurface: .rgb(0.16, 0.12, 0.10),
        cardSurfaceElevated: .rgb(0.20, 0.15, 0.12),
        cardStroke: .white(opacity: 0.10),
        cardStrokeStrong: .white(opacity: 0.16),
        inkPrimary: .rgb(0.98, 0.94, 0.88),
        inkSecondary: .white(opacity: 0.60),
        inkTertiary: .white(opacity: 0.38),
        inkLabel: .white(opacity: 0.64),
        cardShadow: .black(opacity: 0.32),
        appearance: .dark
    )

    private static let sequoia = ThemePalette(
        accent: .rgb(0.35, 0.78, 0.58),
        safety: .rgb(0.95, 0.55, 0.20),
        positive: .rgb(0.45, 0.86, 0.55),
        canvas: .rgb(0.07, 0.11, 0.09),
        cardSurface: .rgb(0.11, 0.16, 0.13),
        cardSurfaceElevated: .rgb(0.14, 0.20, 0.16),
        cardStroke: .white(opacity: 0.10),
        cardStrokeStrong: .white(opacity: 0.16),
        inkPrimary: .rgb(0.90, 0.96, 0.92),
        inkSecondary: .white(opacity: 0.60),
        inkTertiary: .white(opacity: 0.38),
        inkLabel: .white(opacity: 0.64),
        cardShadow: .black(opacity: 0.30),
        appearance: .dark
    )
}
