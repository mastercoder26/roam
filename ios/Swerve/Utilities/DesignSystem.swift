import SwiftUI

// MARK: - Design tokens

enum AppDesign {
    static let accent = Color(red: 0.02, green: 0.42, blue: 0.92)
    static let safety = Color.orange
    static let positive = Color.green

    /// Soft dark canvas (#121212) — avoids harsh true-black edges in low light.
    static let canvas = Color(red: 18 / 255, green: 18 / 255, blue: 18 / 255)
    /// Raised surface for primary cards (#1E1E1E).
    static let cardSurface = Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255)
    /// Slightly higher elevation for map / featured panels (#242424).
    static let cardSurfaceElevated = Color(red: 36 / 255, green: 36 / 255, blue: 36 / 255)
    static let cardStroke = Color.white.opacity(0.10)
    static let cardStrokeStrong = Color.white.opacity(0.16)

    static let space4: CGFloat = 4
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space24: CGFloat = 24
    /// Shared radius scale — keep cards, buttons, and pills on this ladder.
    static let cornerRadius: CGFloat = 16
    static let cornerRadiusSmall: CGFloat = 12
    static let cornerRadiusLarge: CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 20
    static let contentPadding: CGFloat = 16

    /// Material-style emphasis tiers for dark UI (high / medium / low).
    enum Ink {
        /// Off-white primary copy (#F1F1F1) — ~high emphasis without glare.
        static let primary = Color(red: 241 / 255, green: 241 / 255, blue: 241 / 255)
        /// Medium emphasis (~60% white).
        static let secondary = Color.white.opacity(0.60)
        /// Low emphasis / placeholders (~38% white).
        static let tertiary = Color.white.opacity(0.38)
        /// Section micro-labels (FROM / TO) — kept above 4.5:1 on card surfaces.
        static let label = Color.white.opacity(0.64)
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
            .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
    }
}

extension View {
    func premiumCard() -> some View {
        modifier(PremiumCardModifier())
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
    var body: some View {
        Text("Swerve")
            .font(.custom("Baskerville-SemiBoldItalic", size: 36))
            .tracking(-0.4)
            .foregroundStyle(AppDesign.Ink.primary.opacity(0.92))
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Swerve")
            .accessibilityAddTraits(.isHeader)
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
                        .tint(.white)
                        .transition(.opacity)
                }
                Text(isLoading ? "Analyzing…" : title)
                    .font(.body.weight(.semibold))
                    .contentTransition(.interpolate)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous)
                    .fill(isEnabled ? AppDesign.accent : Color(.systemGray3))
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
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
