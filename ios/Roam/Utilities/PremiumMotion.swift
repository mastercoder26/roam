import SwiftUI

/// Roam's display mark: a heavy, direct wordmark split into quiet horizontal
/// bands. The offsets are deliberately small when settled, so the mark reads
/// as a brand detail instead of a perpetual glitch effect.
struct RoamWordmark: View {
    let fontSize: CGFloat
    let foreground: Color
    var sliceProgress: Double = 1
    var reduceMotion = false

    var body: some View {
        ZStack {
            ForEach(Array(PremiumMotionSpec.wordmarkSlices.enumerated()), id: \.offset) { _, slice in
                wordmarkText
                    .mask {
                        GeometryReader { proxy in
                            Rectangle()
                                // A half-point overlap avoids hairline seams
                                // between antialiased masks at odd pixel scales.
                                .frame(
                                    width: proxy.size.width,
                                    height: proxy.size.height * CGFloat(slice.upperBound - slice.lowerBound) + 0.5
                                )
                                .offset(y: proxy.size.height * CGFloat(slice.lowerBound) - 0.25)
                        }
                    }
                    .offset(
                        x: fontSize * CGFloat(
                            PremiumMotionSpec.wordmarkOffsetFactor(
                                for: slice,
                                progress: sliceProgress,
                                reduceMotion: reduceMotion
                            )
                        )
                    )
            }
        }
        .fixedSize()
        .drawingGroup()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Roam")
        .accessibilityAddTraits(.isHeader)
    }

    private var wordmarkText: some View {
        Text("Roam")
            .font(.system(size: fontSize, weight: .black, design: .default))
            .tracking(fontSize * -0.045)
            .foregroundStyle(foreground)
            .fixedSize()
    }
}

/// A result-only metric treatment inspired by split-flap and odometer motion:
/// the value rolls, briefly sharpens out of a tiny blur, and carries a faint
/// compressed echo. It is intentionally not used for live driving values.
struct KineticMetricText: View {
    let value: String
    let fontSize: CGFloat
    let foreground: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blurRadius: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            metricText
                .blur(radius: blurRadius)

            metricText
                .scaleEffect(x: 1, y: -0.42, anchor: .center)
                .offset(y: fontSize * 0.72)
                .mask {
                    LinearGradient(
                        colors: [.white.opacity(0.48), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .opacity(reduceMotion ? 0 : PremiumMotionSpec.heroMetric.reflectionOpacity)
                .accessibilityHidden(true)
        }
        .padding(.bottom, fontSize * 0.10)
        .animation(reduceMotion ? nil : AppAnimation.kineticMetric, value: value)
        .onChange(of: value) { _, _ in
            resolveMetricBlur()
        }
    }

    private var metricText: some View {
        Text(value)
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .tracking(fontSize * -0.023)
            .monospacedDigit()
            .foregroundStyle(foreground)
            .contentTransition(reduceMotion ? .identity : .numericText())
    }

    private func resolveMetricBlur() {
        guard !reduceMotion else {
            blurRadius = 0
            return
        }

        var resetTransaction = Transaction(animation: nil)
        resetTransaction.disablesAnimations = true
        withTransaction(resetTransaction) {
            blurRadius = PremiumMotionSpec.heroMetric.maximumBlur
        }
        withAnimation(AppAnimation.kineticMetric) {
            blurRadius = 0
        }
    }
}

private struct PremiumFocusModifier: ViewModifier {
    let spec: FocusTransitionSpec

    func body(content: Content) -> some View {
        content
            .opacity(spec.opacity)
            .scaleEffect(spec.scale)
            .offset(y: spec.verticalOffset)
            .blur(radius: spec.blurRadius)
    }
}

extension AnyTransition {
    /// A short focus pull for consequential state changes. It is symmetric and
    /// interruptible, so a quick reversal does not snap or finish stale motion.
    static func premiumFocus(reduceMotion: Bool) -> AnyTransition {
        let active = reduceMotion
            ? PremiumMotionSpec.reducedFocusTransition
            : PremiumMotionSpec.focusTransition

        return .modifier(
            active: PremiumFocusModifier(spec: active),
            identity: PremiumFocusModifier(
                spec: FocusTransitionSpec(
                    opacity: 1,
                    scale: 1,
                    verticalOffset: 0,
                    blurRadius: 0,
                    duration: active.duration
                )
            )
        )
    }
}
