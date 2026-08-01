import SwiftUI

struct ScoreGaugeView: View {
    let score: Double
    let label: DifficultyLabel

    @State private var animatedProgress: Double = 0
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: Double {
        min(max(score / 10.0, 0), 1)
    }

    private var accentColor: Color {
        label.color
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppDesign.cardStrokeStrong, lineWidth: 12)

            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    accentColor,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text(String(format: "%.1f", score))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .tracking(-1)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(AppAnimation.spring, value: score)

                Text("/ 10")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            .scaleEffect(hasAppeared ? 1 : 0.95)
            .opacity(hasAppeared ? 1 : 0)
        }
        .frame(width: 180, height: 180)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.25) : AppAnimation.reveal) {
                animatedProgress = progress
                hasAppeared = true
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(AppAnimation.spring) {
                animatedProgress = newValue
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Difficulty score \(String(format: "%.1f", score)) out of 10, \(label.rawValue)")
    }
}

#Preview {
    ScoreGaugeView(score: 4.2, label: .easy)
        .padding()
}
