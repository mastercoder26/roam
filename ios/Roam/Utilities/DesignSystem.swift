import SwiftUI

// MARK: - Design tokens

enum AppDesign {
    private static var palette: ThemePalette {
        ThemeManager.cachedPalette
    }

    static var accent: Color { palette.accent.color }
    /// Adaptive black/white foreground for accent-filled controls.
    static var accentForeground: Color { palette.accentForeground.color }
    static var safety: Color { palette.safety.color }
    static var positive: Color { palette.positive.color }

    /// Soft canvas — theme-aware background for primary surfaces.
    static var canvas: Color { palette.canvas.color }
    /// Raised surface for primary cards.
    static var cardSurface: Color { palette.cardSurface.color }
    /// Slightly higher elevation for map / featured panels.
    static var cardSurfaceElevated: Color { palette.cardSurfaceElevated.color }
    static var cardStroke: Color { palette.cardStroke.color }
    static var cardStrokeStrong: Color { palette.cardStrokeStrong.color }
    static var cardShadow: Color { palette.cardShadow.color }
    /// Fill for present-but-unavailable controls. Theme-aware, unlike the
    /// `Color(.systemGray3)` it replaces.
    static var disabledSurface: Color { palette.disabledSurface.color }
    static var glassHighlight: Color { palette.glassHighlight.color }
    /// Adaptive black/white foreground for controls filled with primary ink.
    static var primarySurfaceForeground: Color { palette.primarySurfaceForeground.color }

    static let space4: CGFloat = 4
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space24: CGFloat = 24
    /// Shared radius scale — keep cards, buttons, and pills on this ladder.
    static let cornerRadius: CGFloat = 16
    static let cornerRadiusSmall: CGFloat = 12
    static let cornerRadiusLarge: CGFloat = 20
    /// Icon tiles and other sub-32pt chips, which read as over-rounded on the
    /// 12pt step. A real rung on the ladder, not an ad-hoc literal.
    static let cornerRadiusTiny: CGFloat = 10

    /// Elevation tiers. Every shadow derives from the theme's own shadow color,
    /// so a dark scheme is never given a light scheme's near-invisible shadow.
    enum Elevation {
        /// Inline chips and rows sitting directly on a card.
        static let low = (radius: CGFloat(12), y: CGFloat(6), opacity: 0.7)
        /// Primary cards lifted off the canvas.
        static let medium = (radius: CGFloat(14), y: CGFloat(8), opacity: 1.0)
        /// Floating chrome — the tab bar and map panels.
        static let high = (radius: CGFloat(18), y: CGFloat(9), opacity: 1.0)
    }
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 20
    static let contentPadding: CGFloat = 16

    /// Material-style emphasis tiers (high / medium / low).
    enum Ink {
        static var primary: Color { AppDesign.palette.inkPrimary.color }
        static var secondary: Color { AppDesign.palette.inkSecondary.color }
        static var tertiary: Color { AppDesign.palette.inkTertiary.color }
        /// Section micro-labels (FROM / TO).
        static var label: Color { AppDesign.palette.inkLabel.color }
    }

    enum Typography {
        static let heroTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
        static let sectionTitle = Font.headline
        static let metricValue = Font.subheadline.weight(.semibold)
        static let metricLabel = Font.caption
        /// Functional UI — addresses, buttons, field values.
        static let body = Font.system(.body, design: .default, weight: .regular)
        static let bodyEmphasized = Font.system(.body, design: .default, weight: .medium)
    }
}

// MARK: - Difficulty color helper

extension DifficultyLabel {
    var color: Color {
        let rgb = systemColor
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

// MARK: - Card surface

struct PremiumCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppDesign.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppDesign.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous)
                    .stroke(AppDesign.cardStroke, lineWidth: 1)
            }
            .elevation(AppDesign.Elevation.medium)
    }
}

extension View {
    func premiumCard() -> some View {
        modifier(PremiumCardModifier())
    }

    /// Applies a themed elevation tier. Use instead of a literal
    /// `.shadow(color: .black.opacity(…))`, which cannot adapt to the
    /// active theme and disappears entirely on dark schemes.
    func elevation(_ tier: (radius: CGFloat, y: CGFloat, opacity: Double)) -> some View {
        shadow(
            color: AppDesign.cardShadow.opacity(tier.opacity),
            radius: tier.radius,
            y: tier.y
        )
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppDesign.Typography.sectionTitle)
                .foregroundStyle(AppDesign.Ink.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(AppDesign.Ink.secondary)
            }
        }
    }
}

struct BrandWordmark: View {
    // Observe the shared manager directly. safeAreaInset content does not always
    // inherit EnvironmentObject from the modified ancestor, which crashed launch.
    @ObservedObject private var themeManager = ThemeManager.shared
    var compact = false

    var body: some View {
        Text("Roam")
            .font(wordmarkFont)
            // The compact wordmark lives inside a fully-labelled color-scheme
            // control. Keep decorative chrome at a stable optical size so an
            // accessibility text setting reserves its space for route inputs.
            .dynamicTypeSize(compact ? .large : .accessibility5)
            .tracking(compact ? -0.25 : -0.4)
            .foregroundStyle(wordmarkColor)
            .contentShape(Rectangle())
            .accessibilityLabel("Roam")
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint("Opens color scheme options")
    }

    /// High-contrast brand ink for the current canvas (never uses a stale palette).
    private var wordmarkColor: Color {
        themeManager.palette.inkPrimary.color.opacity(0.92)
    }

    private var wordmarkFont: Font {
        // A wordmark is decorative inside the labelled color-scheme button.
        // Keep its compact form fixed so accessibility text enlarges the task
        // controls, not a persistent brand bar that would push them away.
        if compact {
            return .custom("Baskerville-SemiBoldItalic", size: 23)
        }
        return .custom("Baskerville-SemiBoldItalic", size: 36, relativeTo: .largeTitle)
    }
}

// MARK: - Press feedback (scale 0.97 on active)

struct PressableScaleStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(AppAnimation.press, value: configuration.isPressed)
    }
}

// MARK: - Primary CTA

struct PrimaryActionButton: View {
    let title: String
    let isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .tint(isEnabled ? AppDesign.accentForeground : AppDesign.Ink.tertiary)
                        .transition(.opacity)
                }
                Text(isLoading ? "Analyzing…" : title)
                    .font(.body.weight(.semibold))
                    .contentTransition(.interpolate)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(isEnabled ? AppDesign.accentForeground : AppDesign.Ink.tertiary)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous)
                    .fill(isEnabled ? AppDesign.accent : AppDesign.disabledSurface)
            )
        }
        .buttonStyle(PressableScaleStyle())
        .disabled(!isEnabled)
        .animation(AppAnimation.quick, value: isLoading)
    }
}

struct IconTile: View {
    let symbol: String
    var color: Color = AppDesign.accent

    var body: some View {
        Image(systemName: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .frame(width: 34, height: 34)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusTiny, style: .continuous))
    }
}

struct StatRow: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: AppDesign.space12) {
            IconTile(symbol: symbol)
            Text(title).font(.subheadline).foregroundStyle(AppDesign.Ink.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppDesign.Ink.primary)
                .monospacedDigit()
        }
    }
}

// MARK: - Motion-aware appear

extension View {
    /// Hero-only entrance: opacity + subtle lift. Skips offset when reduced motion is on.
    func heroAppear(visible: Bool, delay: Double = 0) -> some View {
        modifier(HeroAppearModifier(visible: visible, delay: delay))
    }
}

private struct HeroAppearModifier: ViewModifier {
    let visible: Bool
    let delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 12)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.2).delay(delay)
                    : AppAnimation.hero.delay(delay),
                value: visible
            )
    }
}
