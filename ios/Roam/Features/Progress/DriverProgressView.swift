import Charts
import SwiftUI
import UIKit

/// A private view of measured driving evidence and a route-adjusted coaching
/// score. It is never a safety guarantee, driving permission, or ranking.
struct DriverProgressView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var session: DriveSessionManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.showDriveTab) private var showDriveTab
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 64

    private var summary: DriverProgressSummary {
        DriverProgressEngine.makeSummary(from: session.recordedDrives)
    }

    private var performance: DriverPerformanceSummary {
        DriverPerformanceEngine.makeSummary(from: session.recordedDrives)
    }

    private var coaching: DriverProgressCoachSummary {
        DriverProgressCoachEngine.makeSummary(from: session.recordedDrives)
    }

    /// Saved drives can be high-quality yet still fall short of the minimum
    /// distance or continuous-trace threshold for progress aggregation.
    private var notYetQualifyingDriveCount: Int {
        max(0, session.recordedDrives.count - summary.qualifyingDriveCount)
    }

    private var hasThinRecordedHistory: Bool {
        summary.qualifyingDriveCount < 3 || summary.qualifyingDriveDayCount < 3
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    CompactScreenHeader(title: "Progress")
                    overallScoreCard

                    weeklyActivity
                    if session.recordedDrives.isEmpty {
                        emptyEvidenceState
                    } else {
                        nextDriveCard
                        if performance.score != nil { recentTrendCard }
                    }

                    if notYetQualifyingDriveCount > 0 {
                        notYetQualifyingNote
                    }
                }
                .padding(.horizontal, AppDesign.contentPadding)
                .padding(.bottom, AppDesign.space24)
                .frame(maxWidth: AppDesign.maximumContentWidth)
                .frame(maxWidth: .infinity)
            }
            .contentMargins(.bottom, AppDesign.tabBarClearance, for: .scrollContent)
            .background(AppCanvasBackground())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var overallScoreCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let score = performance.score {
                Text("Overall driving score").font(.subheadline.weight(.medium)).foregroundStyle(AppDesign.Ink.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(score)")
                        .font(.system(size: min(scoreSize, 112), weight: .semibold))
                        .tracking(-2).monospacedDigit().minimumScaleFactor(0.7)
                    Text("/ 100").font(.title3).foregroundStyle(AppDesign.Ink.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Overall driving score \(score) out of 100")
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 16) { performanceSignals }
                } else {
                    HStack(alignment: .top, spacing: 12) { performanceSignals }
                }
            } else if !session.recordedDrives.isEmpty {
                Text("Recorded driving").font(.title2.weight(.semibold))
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 16) { recordedDrivingSignals }
                } else {
                    HStack(alignment: .top, spacing: 16) { recordedDrivingSignals }
                }
                Divider()
                Text(performance.pendingAnalysisCount > 0 ? "Route analysis pending" : "No score yet").font(.headline)
                Text(performance.detail).font(.footnote).foregroundStyle(AppDesign.Ink.secondary)
            } else {
                Text("Overall driving score").font(.subheadline.weight(.medium)).foregroundStyle(AppDesign.Ink.secondary)
                Text("No score yet").font(.headline)
                Text("A score appears after a drive has usable sensor data and route difficulty analysis.")
                    .font(.footnote).foregroundStyle(AppDesign.Ink.secondary)
            }
        }
        .foregroundStyle(AppDesign.Ink.primary)
        .heroCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progress.overallScore")
    }

    @ViewBuilder
    private var recordedDrivingSignals: some View {
        ProgressScoreSignal(value: String(format: "%.1f", session.recordedDrives.reduce(0) { $0 + $1.score.distanceMiles }), label: "Miles driven")
        ProgressScoreSignal(value: String(Int(session.recordedDrives.reduce(0) { $0 + $1.score.duration } / 60)), label: "Minutes")
        ProgressScoreSignal(value: String(Set(session.recordedDrives.map { Calendar.current.startOfDay(for: $0.startedAt) }).count), label: "Driving days")
    }

    private var weeklyActivity: some View {
        let days = CadenceDay.recentWeek(completedDates: session.recordedDrives.map(\.startedAt))
        let count = days.filter(\.isComplete).count
        return VStack(alignment: .leading, spacing: 10) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text("This week").font(.title3.weight(.semibold))
                    Text(count == 1 ? "1 driving day" : "\(count) driving days").font(.footnote).foregroundStyle(AppDesign.Ink.secondary)
                }
            } else {
                HStack {
                    Text("This week").font(.title3.weight(.semibold))
                    Spacer()
                    Text(count == 1 ? "1 driving day" : "\(count) driving days").font(.footnote).foregroundStyle(AppDesign.Ink.secondary)
                }
            }
            WeekCadenceStrip(title: "", days: days, showsHeader: false)
        }
    }

    private var nextDriveCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if summary.hasRecordedEvidence {
                Text(coaching.focus.title).font(.body)
                Text(coaching.focus.detail).font(.subheadline).foregroundStyle(AppDesign.Ink.secondary)
            } else { Text("Next drive").font(.title3.weight(.semibold)) }
            Button { showDriveTab() } label: {
                Text(summary.hasRecordedEvidence ? "Start a focus drive" : "Start a drive")
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.large)
            .tint(AppDesign.Ink.primary)
            .accessibilityIdentifier("progress.startFocusDrive")
        }.premiumCard()
    }

    private var scoredHistory: [RecordedDrive] {
        session.recordedDrives.filter { DriverPerformanceEngine.makeSummary(from: [$0]).score != nil }
            .sorted { $0.startedAt < $1.startedAt }
    }

    private func trendChart(height: CGFloat) -> some View {
        Chart(scoredHistory) { drive in
            let score = DriverPerformanceEngine.makeSummary(from: [drive]).score ?? 0
            AreaMark(x: .value("Date", drive.startedAt), yStart: .value("Base", 0), yEnd: .value("Score", score))
                .foregroundStyle(AppDesign.accent.opacity(0.08))
            LineMark(x: .value("Date", drive.startedAt), y: .value("Score", score))
                .foregroundStyle(AppDesign.accent).lineStyle(StrokeStyle(lineWidth: 2.5))
            if drive.id == scoredHistory.last?.id {
                PointMark(x: .value("Date", drive.startedAt), y: .value("Score", score))
                    .foregroundStyle(AppDesign.positive).symbolSize(22)
            }
        }
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden).chartYAxis(.hidden)
        .frame(height: height)
        .accessibilityLabel("Route-adjusted scores from \(scoredHistory.count) analyzed drives")
    }

    private var recentTrendCard: some View {
        NavigationLink {
            drivingInsights
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recent trend").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(AppDesign.Ink.tertiary)
                }
                trendChart(height: 56)
            }.premiumCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("progress.drivingInsights")
    }

    private var drivingInsights: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("From \(performance.includedDriveCount) analyzed drives").font(.subheadline).foregroundStyle(AppDesign.Ink.secondary)
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(performance.score.map(String.init) ?? "—").font(.system(size: 58, weight: .light))
                        VStack(alignment: .leading) {
                            Text("Overall driving score").font(.subheadline)
                            Text("Route adjusted").font(.caption).foregroundStyle(AppDesign.Ink.secondary)
                        }
                    }
                    trendChart(height: 120)
                }.premiumCard()
                Text("Experience recorded").font(.title3.weight(.semibold))
                VStack(spacing: 22) {
                    experienceBar("Total miles", miles: summary.validatedMiles, tint: AppDesign.accent)
                    experienceBar("After-dark miles", miles: summary.afterDarkMiles, tint: .cyan)
                    experienceBar("Faster-road miles", miles: summary.milesAt45Plus, tint: .cyan)
                }.premiumCard()
                Text("Based on recorded drives with usable GPS and motion.").font(.footnote).foregroundStyle(AppDesign.Ink.secondary)
                measurementDetailsDisclosure
            }.padding(20)
        }
        .background(AppCanvasBackground())
        .navigationTitle("Driving insights")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func experienceBar(_ title: String, miles: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%.1f", miles)).font(.title3.weight(.medium)).monospacedDigit()
                Text(title).font(.footnote).foregroundStyle(AppDesign.Ink.secondary)
            }
            ProgressView(value: summary.validatedMiles > 0 ? min(1, max(0, miles / summary.validatedMiles)) : 0).tint(tint)
        }
    }

    @ViewBuilder
    private var performanceSignals: some View {
        ProgressScoreSignal(
            value: "\(performance.includedDriveCount)",
            label: performance.includedDriveCount == 1 ? "analyzed drive" : "analyzed drives"
        )
        ProgressScoreSignal(
            value: String(format: "%.1f", performance.measuredMiles),
            label: "analyzed miles"
        )
        if let difficulty = performance.averageDifficulty {
            ProgressScoreSignal(
                value: String(format: "%.1f / 10", difficulty),
                label: "avg. route difficulty"
            )
        }
    }

    private var emptyEvidenceState: some View {
        VStack(alignment: .leading, spacing: AppDesign.space12) {
            Text("No recorded drives")
                .font(.headline)
            Text("Record a drive to add it to your history.")
                .font(.footnote)
                .foregroundStyle(AppDesign.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                showDriveTab()
            } label: {
                Label("Record your first drive", systemImage: "steeringwheel")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(AppDesign.primarySurfaceForeground)
                    .background(AppDesign.Ink.primary, in: Capsule())
            }
            .buttonStyle(PressableScaleStyle())
            .accessibilityHint("Opens the Drive tab")
        }
        .premiumCard()
    }

    private var personalizedCoachCard: some View {
        VStack(alignment: .leading, spacing: AppDesign.space16) {
            SectionHeader(title: "Your next drive")

            HStack(alignment: .top, spacing: AppDesign.space12) {
                Image(systemName: coaching.focus.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppDesign.accent)
                    .frame(width: 42, height: 42)
                    .background(AppDesign.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))

                VStack(alignment: .leading, spacing: AppDesign.space4) {
                    Text(coaching.focus.title)
                        .font(.headline)
                        .foregroundStyle(AppDesign.Ink.primary)
                    Text(coaching.focus.detail)
                        .font(.footnote)
                        .foregroundStyle(AppDesign.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                showDriveTab()
            } label: {
                Label("Start a focus drive", systemImage: "steeringwheel")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(AppDesign.Ink.primary)
                    .background(AppDesign.trackSurface, in: Capsule())
            }
            .buttonStyle(PressableScaleStyle())
            .accessibilityHint("Opens the Drive tab with this coaching focus in mind")

            Divider()

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: AppDesign.space12) {
                    trendTile
                    weeklyGoalTile
                }
                VStack(spacing: AppDesign.space12) {
                    trendTile
                    weeklyGoalTile
                }
            }
        }
        .premiumCard()
    }

    private var trendTile: some View {
        ProgressCoachTile(
            eyebrow: "RECENT TREND",
            title: coaching.trend.title,
            detail: coaching.trendDetail,
            symbol: coaching.trend.symbol
        )
    }

    private var weeklyGoalTile: some View {
        ProgressCoachTile(
            eyebrow: "WEEKLY RHYTHM",
            title: coaching.completedThisWeek >= coaching.weeklyTargetDriveCount
                ? "Goal complete"
                : String(coaching.completedThisWeek) + " of " + String(coaching.weeklyTargetDriveCount) + " drives",
            detail: coaching.completedThisWeek >= coaching.weeklyTargetDriveCount
                ? "Weekly practice target reached."
                : "Target follows your recent practice pace.",
            symbol: coaching.completedThisWeek >= coaching.weeklyTargetDriveCount
                ? "checkmark.circle.fill"
                : "calendar.badge.clock",
            progress: coaching.weeklyGoalProgress
        )
    }

    private var progressOverview: some View {
        VStack(alignment: .leading, spacing: AppDesign.space12) {
            SectionHeader(title: "Measured miles")

            DashboardMetricStrip(metrics: [
                DashboardMetric(value: String(format: "%.1f", summary.validatedMiles), label: "validated miles"),
                DashboardMetric(value: "\(summary.qualifyingDriveCount)", label: "qualifying drives"),
                DashboardMetric(value: "\(summary.qualifyingDriveDayCount)", label: "recorded days")
            ])

            Divider()

            WeeklyMilesChart(weeks: summary.weeklyMeasuredMiles)
                .animation(reduceMotion ? .easeOut(duration: 0.16) : AppAnimation.content, value: summary.weeklyMeasuredMiles)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(chartAccessibilitySummary)
        }
        .premiumCard()
    }

    private var thinEvidenceState: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .foregroundStyle(AppDesign.accent)
            Text("Based only on drives recorded so far.")
                .font(.footnote)
                .foregroundStyle(AppDesign.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(AppDesign.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))
    }

    private var coverageSection: some View {
        VStack(alignment: .leading, spacing: AppDesign.space12) {
            SectionHeader(title: "Measurement coverage")

            ProgressCoverageRow(
                title: "After-dark miles",
                value: String(format: "%.1f mi", summary.afterDarkMiles),
                detail: "Recorded between 8 PM and 6 AM in the drive’s local time zone.",
                symbol: "moon.stars.fill"
            )
            Divider().padding(.leading, 46)
            ProgressCoverageRow(
                title: "45+ mph miles",
                value: String(format: "%.1f mi", summary.milesAt45Plus),
                detail: "Counted only across continuous GPS segments with measured speed.",
                symbol: "speedometer"
            )
            Divider().padding(.leading, 46)
            ProgressCoverageRow(
                title: "Longest continuous trace",
                value: durationText(summary.longestContinuousDuration),
                detail: String(format: "%.1f mi without a GPS gap", summary.longestContinuousDistanceMiles),
                symbol: "point.3.connected.trianglepath.dotted"
            )
        }
    }

    private var measurementDetailsDisclosure: some View {
        NavigationLink {
            AppDetailPage(title: "Measurement details") {
                coverageSection
                measurementNote
            }
        } label: {
            ProfileSettingsRow(title: "Measurement details", symbol: "scope")
        }
        .buttonStyle(.plain)
        .profileSettingsSurface()
    }

    private var measurementNote: some View {
        Label(
            "Roam keeps driving history, route overlap, and progress calculations on this device.",
            systemImage: "lock.shield.fill"
        )
        .font(.footnote)
        .foregroundStyle(AppDesign.Ink.secondary)
        .padding(.horizontal, 4)
    }

    private var notYetQualifyingNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(AppDesign.safety)
            Text("\(notYetQualifyingDriveCount) \(notYetQualifyingDriveCount == 1 ? "saved drive is" : "saved drives are") not yet qualifying for progress totals: not enough GPS and motion data.")
                .font(.footnote)
                .foregroundStyle(AppDesign.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(AppDesign.safety.opacity(0.10), in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))
    }

    private var chartAccessibilitySummary: String {
        let values = summary.weeklyMeasuredMiles.map {
            "\($0.startDate.formatted(.dateTime.month(.abbreviated).day())): \(String(format: "%.1f", $0.measuredMiles)) miles"
        }
        return "Measured miles over the last eight weeks. " + values.joined(separator: ". ")
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let totalMinutes = max(0, Int((duration / 60).rounded()))
        if totalMinutes >= 60 {
            return "\(totalMinutes / 60)h \(totalMinutes % 60)m"
        }
        return "\(totalMinutes) min"
    }
}

private struct ProgressMetric: View {
    @ObservedObject private var theme = ThemeManager.shared
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppDesign.accent)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppDesign.Ink.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct ProgressScoreSignal: View {
    @ObservedObject private var theme = ThemeManager.shared
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.body.weight(.medium).monospacedDigit())
                .foregroundStyle(AppDesign.Ink.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppDesign.Ink.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        .accessibilityElement(children: .combine)
    }
}

private struct ProgressCoverageRow: View {
    @ObservedObject private var theme = ThemeManager.shared
    let title: String
    let value: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppDesign.positive)
                .frame(width: 34, height: 34)
                .background(AppDesign.positive.opacity(0.12), in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusTiny, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(AppDesign.Ink.secondary)
            }
            Spacer(minLength: 4)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ProgressCoachTile: View {
    @ObservedObject private var theme = ThemeManager.shared
    let eyebrow: String
    let title: String
    let detail: String
    let symbol: String
    var progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.space8) {
            HStack(spacing: AppDesign.space8) {
                Image(systemName: symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppDesign.accent)
                Text(eyebrow)
                    .font(AppDesign.Typography.microLabel)
                    .tracking(1.1)
                    .foregroundStyle(AppDesign.Ink.tertiary)
            }

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppDesign.Ink.primary)

            if let progress {
                ProgressView(value: progress)
                    .tint(AppDesign.accent)
                    .accessibilityHidden(true)
            }

            Text(detail)
                .font(.caption)
                .foregroundStyle(AppDesign.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppDesign.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppDesign.trackSurface.opacity(0.72), in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    DriverProgressView()
        .environmentObject(DriveSessionManager())
}
