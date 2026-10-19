import SwiftUI

struct AlternateRouteCard: View {
    @ObservedObject private var theme = ThemeManager.shared
    let route: ScoredRoute
    let isSelected: Bool
    var readinessHeadline: String? = nil
    var badges: [RouteChoiceBadge] = []
    var comparisonLimitedByHistory = false
    let onSelect: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accentColor: Color {
        route.label.color
    }

    private var readinessColor: Color {
        if readinessHeadline == DriverReadinessVerdict.looksLikeMatch.title {
            return AppDesign.positive
        }
        if readinessHeadline == DriverReadinessVerdict.practiceWithAdult.title {
            return AppDesign.safety
        }
        return AppDesign.accent
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(route.formattedDuration).font(.title3.weight(.semibold)).monospacedDigit()
                    Text(route.formattedDistance).font(.footnote).foregroundStyle(AppDesign.Ink.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(route.label.rawValue).font(.subheadline.weight(.medium)).foregroundStyle(accentColor)
                    Text("\(route.formattedScore) / 10").font(.caption).foregroundStyle(AppDesign.Ink.secondary)
                }
            }
            .foregroundStyle(AppDesign.Ink.primary)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(isSelected ? AppDesign.cardSurfaceElevated : .clear, in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(isSelected ? AppDesign.cardStrokeStrong : .clear, lineWidth: 0.75)
            }
        }
        .buttonStyle(PressableScaleStyle())
        .animation(reduceMotion ? nil : AppAnimation.selection, value: isSelected)
        .accessibilityLabel("\(route.formattedDuration), \(route.formattedDistance), \(route.label.rawValue), difficulty \(route.formattedScore) out of 10")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private func deltaText(_ delta: Double) -> String {
        let sign = delta >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", delta))"
    }
}

#Preview {
    AlternateRouteCard(
        route: ScoredRoute(
            score: 5.1,
            uncalibratedScore: 5.0,
            label: .moderate,
            reasons: ["Many turns"],
            breakdown: DifficultyBreakdown(
                speed: 0.3, merges: 0.2, turns: 0.6, traffic: 0.2,
                length: 0.3, fatigue: 0.1, weather: nil, road: nil,
                highway: 0.3, maneuvers: 0.6, navDensity: 0.4, effort: 0.3
            ),
            contributions: nil,
            uncertainty: ScoreUncertainty(low: 4.5, high: 5.7, confidence: 0.7, spread: 1.2, evidence: nil),
            hotspots: nil,
            conditions: nil,
            modelVersion: nil,
            distanceMeters: 12000,
            durationSeconds: 1800,
            staticDurationSeconds: 1500,
            trafficDelaySeconds: 300,
            polyline: "abc",
            bounds: RouteBounds(
                southwest: Coordinate(latitude: 30.0, longitude: -97.0),
                northeast: Coordinate(latitude: 30.5, longitude: -97.5)
            ),
            scoreDelta: 0.9,
            routeDemands: nil
        ),
        isSelected: false,
        readinessHeadline: "Practice this with an adult",
        onSelect: {}
    )
    .padding()
}
