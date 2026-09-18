import SwiftUI

// MARK: - Band styling

extension LiveScoreBand {
    var color: Color {
        switch self {
        case .settling: AppDesign.Ink.tertiary
        case .excellent: AppDesign.positive
        case .steady: AppDesign.accent
        case .watch: AppDesign.safety
        }
    }
}

extension LiveScoreTrend {
    /// `nil` while the score is holding, so the ring shows an arrow only when
    /// there is a direction worth reporting.
    var indicatorSymbol: String? {
        self == .steady ? nil : symbol
    }

    var color: Color {
        switch self {
        case .rising: AppDesign.positive
        case .steady: AppDesign.Ink.tertiary
        case .falling: AppDesign.safety
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .rising: "improving"
        case .steady: "holding steady"
        case .falling: "slipping"
        }
    }
}

// MARK: - Score ring

/// The live drive score, as a ring that fills with earned score.
///
/// Before a drive has produced enough evidence to score, the ring shows a
/// travelling arc instead of a number — an honest "still measuring" state
/// rather than a confident 100 that can only ever go down.
struct LiveDriveScoreRing: View {
    @ObservedObject private var theme = ThemeManager.shared
    let live: LiveDriveScore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let diameter: CGFloat = 196
    private let lineWidth: CGFloat = 13

    private var isSettling: Bool { live.score == nil }

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppDesign.trackSurface, lineWidth: lineWidth)

            if !isSettling {
                scoreArc
            }

            centerReadout
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live drive score")
        .accessibilityValue(accessibilityValue)
    }

    private var scoreArc: some View {
        Circle()
            .trim(from: 0, to: live.ringProgress)
            // A flat fill, not an angular gradient: at a full ring the
            // gradient's start and end meet and the seam is visible as a
            // notch at twelve o'clock.
            .stroke(
                live.band.color,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .shadow(color: live.band.color.opacity(0.22), radius: 5)
            // One spring carries both the fill and the recolor, so a score
            // change reads as a single movement rather than two.
            .animation(reduceMotion ? .easeOut(duration: 0.25) : AppAnimation.reveal, value: live.ringProgress)
            .animation(reduceMotion ? .easeOut(duration: 0.25) : AppAnimation.reveal, value: live.band)
    }

    private var centerReadout: some View {
        VStack(spacing: AppDesign.space4) {
            Text("LIVE SCORE")
                .font(AppDesign.Typography.microLabel)
                .tracking(1.1)
                .foregroundStyle(AppDesign.Ink.label)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(live.score.map(String.init) ?? "—")
                    .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 48 : 60, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    // A live safety value rolls between digits rather than
                    // cross-fading, so a changing score is never briefly
                    // unreadable.
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .foregroundStyle(AppDesign.Ink.primary)

                // Only when the score is actually moving. A permanent "="
                // beside the numeral is a mark the eye has to resolve every
                // glance, and it resolves to "nothing has changed".
                if let trendSymbol = live.trend.indicatorSymbol {
                    Image(systemName: trendSymbol)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(live.trend.color)
                        .transition(.opacity)
                }
            }

            Text(live.band.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(live.band.color)
                .contentTransition(.opacity)
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : AppAnimation.content, value: live.score)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : AppAnimation.content, value: live.trend)
    }

    private var accessibilityValue: String {
        guard let score = live.score else {
            return "Still measuring. A score appears once there is enough of this drive to judge."
        }
        return "\(score) out of 100, \(live.band.title), \(live.trend.accessibilityDescription)"
    }
}

// MARK: - Smoothness

extension SmoothnessState {
    var color: Color {
        switch self {
        case .smooth: AppDesign.positive
        case .moderate: AppDesign.accent
        case .choppy: AppDesign.safety
        }
    }
}

/// How smoothly the car is being driven right now, as a state that changes
/// rarely.
///
/// This was a bar tracking a continuously-updating value. On a screen the
/// driver glances at, a bar that is always moving is ambient motion that keeps
/// pulling the eye back for no new information — so the value is quantized and
/// hysteresis-gated upstream, and this just states the result.
struct LiveSmoothnessBadge: View {
    @ObservedObject private var theme = ThemeManager.shared
    let state: SmoothnessState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: state.symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(state.color)
                .contentTransition(.symbolEffect(.replace))

            Text(state.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppDesign.Ink.primary)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(state.color.opacity(0.1), in: Capsule())
        .overlay { Capsule().stroke(state.color.opacity(0.2), lineWidth: 1) }
        // A plain crossfade on a rare change. No spring: nothing here should
        // draw the eye by moving.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: state)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Driving smoothness")
        .accessibilityValue(state.title)
    }
}

// MARK: - Clean streak

/// How long the driver has gone without a coaching event, plus the badge for
/// the highest milestone this streak has passed.
struct LiveCleanStreakChip: View {
    @ObservedObject private var theme = ThemeManager.shared
    let live: LiveDriveScore
    /// Set for one beat when a new milestone is earned, which is what fires
    /// the flourish. The parent clears it.
    let celebration: CleanStreakCelebration?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasMilestone: Bool { live.cleanStreakMilestone != nil }
    private var tint: Color { hasMilestone ? AppDesign.positive : AppDesign.Ink.secondary }

    var body: some View {
        HStack(spacing: AppDesign.space8) {
            Image(systemName: hasMilestone ? "checkmark.seal.fill" : "shield.lefthalf.filled")
                .font(.footnote.weight(.bold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))

            Text(live.cleanStreakMilestone?.title ?? live.formattedStreak)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(AppDesign.Ink.primary)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(tint.opacity(hasMilestone ? 0.14 : 0.08), in: Capsule())
        .overlay {
            Capsule().stroke(tint.opacity(hasMilestone ? 0.3 : 0.14), lineWidth: 1)
        }
        // A single expanding ring on the beat a badge is earned. One-shot, so
        // the reward never becomes ambient motion the driver tunes out.
        .overlay {
            if celebration != nil, !reduceMotion {
                Capsule()
                    .stroke(AppDesign.positive, lineWidth: 2)
                    .scaleEffect(1.35)
                    .opacity(0)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 1).combined(with: .opacity),
                            removal: .identity
                        )
                    )
            }
        }
        .scaleEffect(celebration != nil && !reduceMotion ? 1.06 : 1)
        .animation(AppAnimation.selection, value: celebration)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : AppAnimation.content, value: live.cleanStreakMilestone)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Clean streak")
        .accessibilityValue(live.cleanStreakMilestone?.title ?? live.formattedStreak)
    }
}

// MARK: - Event feed

#Preview("Scoring") {
    VStack(spacing: 24) {
        LiveDriveScoreRing(
            live: LiveDriveScore(
                score: 92,
                band: .excellent,
                trend: .rising,
                cleanStreakSeconds: 310,
                cleanStreakMilestone: .fiveMinutes,
                smoothness: .smooth,
                eventCount: 1
            )
        )
        LiveSmoothnessBadge(state: .smooth)
        LiveCleanStreakChip(
            live: LiveDriveScore(
                score: 92,
                band: .excellent,
                trend: .rising,
                cleanStreakSeconds: 310,
                cleanStreakMilestone: .fiveMinutes,
                smoothness: .smooth,
                eventCount: 1
            ),
            celebration: nil
        )
    }
    .padding()
    .background(AppCanvasBackground())
}

#Preview("Settling") {
    LiveDriveScoreRing(live: .idle)
        .padding()
        .background(AppCanvasBackground())
}
