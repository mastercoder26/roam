import SwiftUI

// MARK: - Design tokens

enum AppDesign {
    static let cornerRadius: CGFloat = 16
    static let cornerRadiusSmall: CGFloat = 12
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 20
    static let contentPadding: CGFloat = 16

    enum Typography {
        static let heroTitle = Font.system(.largeTitle, design: .default, weight: .semibold)
        static let sectionTitle = Font.headline
        static let metricValue = Font.subheadline.weight(.semibold)
        static let metricLabel = Font.caption
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
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous))
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
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Press feedback (scale 0.97 on active)

struct PressableScaleStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
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
                    .fill(isEnabled ? Color.accentColor : Color(.systemGray3))
            )
        }
        .buttonStyle(PressableScaleStyle())
        .disabled(!isEnabled)
        .animation(AppAnimation.quick, value: isLoading)
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
