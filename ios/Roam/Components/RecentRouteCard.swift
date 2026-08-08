import SwiftUI

/// A single row in the Home screen's recent-routes list: a compact repeat of
/// the trip-header dot/line used on Results, plus the score that route
/// earned, so a driver can spot a route worth avoiding without reopening it.
struct RecentRouteRow: View {
    @ObservedObject private var theme = ThemeManager.shared
    let entry: RecentRouteEntry
    let action: () -> Void

    private var labelColor: Color {
        entry.label.color
    }

    private var relativeTime: String {
        entry.analyzedAt.formatted(.relative(presentation: .named))
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: AppDesign.space12) {
                VStack(spacing: 3) {
                    Circle()
                        .fill(AppDesign.accent)
                        .frame(width: 6, height: 6)
                    Rectangle()
                        .fill(AppDesign.cardStrokeStrong)
                        .frame(width: 1.5)
                    Circle()
                        .fill(AppDesign.Ink.secondary)
                        .frame(width: 6, height: 6)
                }
                .padding(.top, 5)
                .frame(height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.origin)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppDesign.Ink.primary)
                        .lineLimit(1)
                    Text(entry.destination)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppDesign.Ink.primary)
                        .lineLimit(1)
                    Text("\(relativeTime) · \(entry.formattedDuration) · \(entry.formattedDistance)")
                        .font(.caption)
                        .foregroundStyle(AppDesign.Ink.secondary)
                        .lineLimit(1)
                }
                .layoutPriority(1)

                Spacer(minLength: AppDesign.space8)

                VStack(spacing: 2) {
                    Text(entry.formattedScore)
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(labelColor)
                    Text(entry.label.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppDesign.Ink.secondary)
                        .lineLimit(1)
                }
                .frame(width: 64)
                .padding(.vertical, 8)
                .background(labelColor.opacity(0.12), in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusTiny, style: .continuous))
            }
            .padding(.horizontal, AppDesign.space16)
            .padding(.vertical, AppDesign.space12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleStyle())
        .accessibilityLabel("\(entry.origin) to \(entry.destination), difficulty \(entry.formattedScore), \(entry.label.rawValue), analyzed \(relativeTime)")
        .accessibilityHint("Fills the route planner with this trip")
    }
}

#Preview {
    RecentRouteRow(
        entry: RecentRouteEntry(
            origin: "1200 Congress Ave, Austin, TX",
            destination: "Austin-Bergstrom International Airport",
            departureTime: Date(),
            analyzedAt: Date().addingTimeInterval(-3600),
            score: 6.4,
            label: .hard,
            distanceMeters: 14000,
            durationSeconds: 1400
        ),
        action: {}
    )
    .padding()
}
