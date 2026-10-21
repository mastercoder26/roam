import SwiftUI

/// The same title, margins, and canvas for every pushed report and settings page.
struct AppDetailPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppDesign.sectionSpacing, content: content)
                .padding(.horizontal, AppDesign.contentPadding)
                .padding(.vertical, 16)
                .frame(maxWidth: AppDesign.maximumContentWidth)
                .frame(maxWidth: .infinity)
        }
        .background(AppDesign.canvas)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .toolbar(.visible, for: .navigationBar)
    }
}

/// Uses the same qualifying drives as Goals & progress so all three totals
/// describe the same locally recorded evidence, including a new driver's zeros.
struct ProfileDrivingSummary: View {
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var valueSize: CGFloat = 25
    let insights: DriverProfileInsights

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 15))

        layout {
            metric("Miles driven", value: insights.measuredMiles.formatted(.number.precision(.fractionLength(1))), id: "miles")
            metric("Drives", value: insights.qualifyingDriveCount.formatted(), id: "drives")
            metric("Days driven", value: insights.drivingDayCount.formatted(), id: "days")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.drivingSummary")
    }

    private func metric(_ title: String, value: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: valueSize, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(AppDesign.Ink.primary)
            Text(title)
                .font(.caption)
                .foregroundStyle(AppDesign.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityHint("From recorded drives that count toward driving progress")
        .accessibilityIdentifier("profile.summary.\(id)")
    }
}

/// Compact settings geometry shared by Profile and its nested menus.
struct ProfileSettingsRow: View {
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let symbol: String
    var value: String? = nil
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: AppDesign.Menu.iconSpacing) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .regular))
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                if dynamicTypeSize.isAccessibilitySize {
                    Text(title)
                    if let value { Text(value).foregroundStyle(AppDesign.Ink.secondary) }
                } else {
                    HStack(spacing: 8) {
                        Text(title)
                        Spacer(minLength: 4)
                        if let value {
                            Text(value)
                                .foregroundStyle(AppDesign.Ink.secondary)
                                .layoutPriority(-1)
                        }
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(AppDesign.Ink.secondary)
                }
            }
            .font(.body)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppDesign.Ink.tertiary)
                .accessibilityHidden(true)
        }
        .foregroundStyle(AppDesign.Ink.primary)
        .padding(.horizontal, AppDesign.contentPadding)
        .padding(.vertical, AppDesign.Menu.rowPadding)
        .frame(minHeight: AppDesign.Menu.minimumRowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct ProfileSettingsSurface: ViewModifier {
    @ObservedObject private var theme = ThemeManager.shared

    func body(content: Content) -> some View {
        content
            .menuSurface()
    }
}

private struct ProfileGlassSurface: ViewModifier {
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content.background(AppDesign.cardSurfaceElevated, in: shape)
                .overlay { shape.strokeBorder(AppDesign.cardStrokeStrong, lineWidth: 0.5) }
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
                .overlay { shape.strokeBorder(.white.opacity(0.22), lineWidth: 0.5) }
        }
    }
}

extension View {
    func profileSettingsSurface() -> some View { modifier(ProfileSettingsSurface()) }

    func profileGlassSurface(cornerRadius: CGFloat) -> some View {
        modifier(ProfileGlassSurface(cornerRadius: cornerRadius))
    }

    @ViewBuilder
    func profileGlassContainer() -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 16) { self }
        } else {
            self
        }
    }
}

/// Presentational subviews for `ProfileView`. Split out to keep the main file
/// focused on state and layout: every view here is a pure function of the
/// `DriverProfileInsights` (or, for the live banner, the session) it is
/// handed, so nothing here recomputes an engine or touches the network.

// MARK: - Shared copy

/// Copy repeated across more than one Profile subview. Declared once so the
/// wording cannot drift between the rows that share it.
enum ProfileCopy {
    /// Stands in for any measurement that has no qualifying evidence behind it
    /// yet. Deliberately states the absence rather than showing a zero, which
    /// would read as a measured result.
    static let notEnoughData = "Not enough data yet"
}

// MARK: - Folder navigation

/// A compact entry point that keeps the Profile home scannable. The full
/// report stays one tap away without competing with the driver's identity and
/// headline mileage.
struct ProfileFolderCard: View {
    @ObservedObject private var theme = ThemeManager.shared
    let folder: ProfileFolder
    let summary: String

    var body: some View {
        AppMenuRow(title: folder.title, subtitle: summary, symbol: folder.symbol)
        .accessibilityLabel("\(folder.title). \(summary)")
        .accessibilityHint("Opens \(folder.subtitle.lowercased())")
    }
}

// MARK: - Live drive banner

/// Reflects an in-progress drive without duplicating the Drive tab: a single
/// row with elapsed time, distance, and speed, all read straight off the
/// session's already-published values.
struct LiveDriveBanner: View {
    @ObservedObject private var theme = ThemeManager.shared
    let driveSession: DriveSessionManager

    var body: some View {
        HStack(spacing: AppDesign.space12) {
            Circle()
                .fill(AppDesign.danger)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Recording now")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppDesign.Ink.primary)
                Text("\(driveSession.formattedElapsed) \u{00B7} \(String(format: "%.1f", driveSession.currentDistanceMiles)) mi \u{00B7} \(driveSession.currentSpeedMilesPerHour) mph")
                    .font(.caption)
                    .foregroundStyle(AppDesign.Ink.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
        }
        .premiumCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Recording a drive now. Elapsed \(driveSession.formattedElapsed). "
                + "Distance \(String(format: "%.1f", driveSession.currentDistanceMiles)) miles. "
                + "Speed \(driveSession.currentSpeedMilesPerHour) miles per hour."
        )
    }
}

// MARK: - Milestones

struct MilestonesSection: View {
    @ObservedObject private var theme = ThemeManager.shared
    let milestones: [DriverProfileMilestone]

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.space12) {
            SectionHeader(title: "Goals")

            ForEach(milestones) { milestone in
                MilestoneRow(milestone: milestone)
            }
        }
        .premiumCard()
    }
}

private struct MilestoneRow: View {
    @ObservedObject private var theme = ThemeManager.shared
    let milestone: DriverProfileMilestone

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: AppDesign.space12) {
                IconTile(symbol: milestone.symbol, color: milestone.isComplete ? AppDesign.positive : nil)

                VStack(alignment: .leading, spacing: 2) {
                    Text(milestone.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppDesign.Ink.primary)
                    Text(milestone.detail)
                        .font(.caption)
                        .foregroundStyle(AppDesign.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if milestone.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppDesign.positive)
                }
            }

            ProgressView(value: milestone.progress)
                .tint(milestone.isComplete ? AppDesign.positive : AppDesign.accent)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            "\(Int((milestone.progress * 100).rounded())) percent complete"
                + (milestone.isComplete ? ", complete" : "")
        )
    }
}

// MARK: - Experience breakdown

struct ExperienceBreakdownSection: View {
    @ObservedObject private var theme = ThemeManager.shared
    let insights: DriverProfileInsights

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.space12) {
            SectionHeader(title: "Measured experience")

            if insights.hasEvidence {
                StatRow(title: "Measured miles", value: String(format: "%.1f mi", insights.measuredMiles), symbol: "road.lanes")
                StatRow(title: "Qualifying drives", value: "\(insights.qualifyingDriveCount)", symbol: "checkmark.seal")
                StatRow(title: "Days driven", value: "\(insights.drivingDayCount)", symbol: "calendar")
                StatRow(title: "After-dark miles", value: String(format: "%.1f mi", insights.afterDarkMiles), symbol: "moon.stars")
                StatRow(title: "45+ mph miles", value: String(format: "%.1f mi", insights.milesAt45Plus), symbol: "speedometer")
                StatRow(title: "Longest continuous trace", value: longestDriveText, symbol: "point.3.connected.trianglepath.dotted")
            } else {
                Text("No qualifying drives yet. Record one from the Drive tab.")
                    .font(.footnote)
                    .foregroundStyle(AppDesign.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .premiumCard()
    }

    private var longestDriveText: String {
        String(format: "%.1f mi, %.0f min", insights.longestContinuousMiles, insights.longestDriveMinutes)
    }
}

// MARK: - Behavior signals

struct BehaviorSignalsSection: View {
    @ObservedObject private var theme = ThemeManager.shared
    let insights: DriverProfileInsights

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.space12) {
            SectionHeader(title: "Driving behavior")

            StatRow(title: "Overall driving score", value: formattedWholeScore(insights.performanceScore), symbol: "gauge.with.dots.needle.50percent")
            StatRow(title: "Recent average score", value: formattedAverageScore(insights.recentAverageScore), symbol: "chart.line.uptrend.xyaxis")
            StatRow(title: "Hard brakes", value: formattedRate(insights.hardBrakesPerTenMiles), symbol: "exclamationmark.brakesignal")
            StatRow(title: "Sharp corners", value: formattedRate(insights.sharpCornersPerTenMiles), symbol: "arrow.triangle.turn.up.right.circle")
            StatRow(title: "Smooth drive streak", value: "\(insights.smoothDriveStreak)", symbol: "checkmark.seal")

            if insights.pendingAnalysisCount > 0 {
                Text("\(insights.pendingAnalysisCount) recent \(insights.pendingAnalysisCount == 1 ? "drive is" : "drives are") still analyzing route difficulty.")
                    .font(.caption)
                    .foregroundStyle(AppDesign.Ink.tertiary)
            }
        }
        .premiumCard()
    }

    private func formattedWholeScore(_ score: Int?) -> String {
        guard let score else { return ProfileCopy.notEnoughData }
        return "\(score)/100"
    }

    private func formattedAverageScore(_ value: Double?) -> String {
        guard let value, value.isFinite else { return ProfileCopy.notEnoughData }
        return String(format: "%.0f/100", value)
    }

    private func formattedRate(_ value: Double?) -> String {
        guard let value, value.isFinite else { return ProfileCopy.notEnoughData }
        return String(format: "%.1f per 10 mi", value)
    }
}

// MARK: - Weekly trend

struct WeeklyTrendSection: View {
    @ObservedObject private var theme = ThemeManager.shared
    let insights: DriverProfileInsights
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.space12) {
            SectionHeader(title: "Weekly trend")

            if insights.hasEvidence {
                weeklyChart
                weekComparison
            } else {
                Text("Appears after your first recorded drive.")
                    .font(.footnote)
                    .foregroundStyle(AppDesign.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .premiumCard()
    }

    /// Shorter than the shared default: this card also carries the week-over-week
    /// comparison row, so the chart yields height to keep the whole card in view.
    private static let chartHeight: CGFloat = 160

    private var weeklyChart: some View {
        WeeklyMilesChart(weeks: insights.weeklyMiles, height: Self.chartHeight)
            .animation(reduceMotion ? .easeOut(duration: 0.16) : AppAnimation.content, value: insights.weeklyMiles)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(chartAccessibilitySummary)
    }

    private var weekComparison: some View {
        HStack(spacing: AppDesign.space12) {
            WeekComparisonTile(label: "This week", miles: insights.currentWeekMiles)
            WeekComparisonTile(label: "Last week", miles: insights.previousWeekMiles)

            if let changeText = percentChangeText(current: insights.currentWeekMiles, previous: insights.previousWeekMiles) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(changeText)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(insights.currentWeekMiles >= insights.previousWeekMiles ? AppDesign.positive : AppDesign.safety)
                        .monospacedDigit()
                    Text("vs last week")
                        .font(.caption2)
                        .foregroundStyle(AppDesign.Ink.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(changeText) versus last week")
            }
        }
    }

    /// Guards the denominator explicitly: a zero or non-finite previous week
    /// has no meaningful percentage change, so the comparison is simply
    /// omitted rather than divided into a NaN or an infinite jump.
    private func percentChangeText(current: Double, previous: Double) -> String? {
        guard previous.isFinite, previous > 0, current.isFinite else { return nil }
        let change = ((current - previous) / previous) * 100
        guard change.isFinite else { return nil }
        return String(format: "%+.0f%%", change)
    }

    private var chartAccessibilitySummary: String {
        let values = insights.weeklyMiles.map {
            "\($0.startDate.formatted(.dateTime.month(.abbreviated).day())): \(String(format: "%.1f", $0.measuredMiles)) miles"
        }
        return "Measured miles over the last eight weeks. " + values.joined(separator: ". ")
    }
}

private struct WeekComparisonTile: View {
    @ObservedObject private var theme = ThemeManager.shared
    let label: String
    let miles: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "%.1f mi", max(0, miles)))
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppDesign.Ink.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
