import Charts
import SwiftUI

/// A private view of measured driving evidence and a route-adjusted coaching
/// score. It is never a safety guarantee, driving permission, or ranking.
struct DriverProgressView: View {
    @EnvironmentObject private var session: DriveSessionManager
    @EnvironmentObject private var scrollCollapse: ScrollCollapseTracker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var summary: DriverProgressSummary {
        DriverProgressEngine.makeSummary(from: session.recordedDrives)
    }

    private var performance: DriverPerformanceSummary {
        DriverPerformanceEngine.makeSummary(from: session.recordedDrives)
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
                VStack(alignment: .leading, spacing: AppDesign.sectionSpacing) {
                    header
                    overallScoreCard

                    if summary.hasRecordedEvidence {
                        evidenceSummary
                        if hasThinRecordedHistory {
                            thinEvidenceState
                        }
                        weeklyChart
                        coverageSection
                        measurementNote
                    } else {
                        emptyEvidenceState
                    }

                    if notYetQualifyingDriveCount > 0 {
                        notYetQualifyingNote
                    }
                }
                .padding(.horizontal, AppDesign.contentPadding)
                .padding(.vertical, 12)
            }
            .trackingScrollCollapse(scrollCollapse)
            .background(AppDesign.canvas)
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recorded progress")
                .font(AppDesign.Typography.heroTitle)
                .tracking(-0.5)
            Text("Private measurement coverage from drives recorded on this iPhone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var overallScoreCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "steeringwheel.and.heat.waves")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppDesign.accent)
                    .frame(width: 42, height: 42)
                    .background(AppDesign.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Overall driving score")
                        .font(.headline)
                    Text(performance.evidence.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppDesign.accent)
                }
                Spacer(minLength: 8)

                if let score = performance.score {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(score)")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .tracking(-1)
                            .monospacedDigit()
                        Text("/100")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Overall driving score \(score) out of 100")
                }
            }

            if let score = performance.score {
                ProgressView(value: Double(score), total: 100)
                    .tint(score >= 78 ? AppDesign.positive : AppDesign.safety)
                    .accessibilityHidden(true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        performanceSignals
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        performanceSignals
                    }
                }
            }

            Text(performance.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppDesign.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [AppDesign.accent.opacity(0.16), AppDesign.cardSurface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusLarge, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.cornerRadiusLarge, style: .continuous)
                .stroke(AppDesign.accent.opacity(0.24), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var performanceSignals: some View {
        ProgressScoreSignal(
            value: "\(performance.includedDriveCount)",
            label: performance.includedDriveCount == 1 ? "analyzed drive" : "analyzed drives"
        )
        ProgressScoreSignal(
            value: String(format: "%.1f mi", performance.measuredMiles),
            label: "measured evidence"
        )
        if let difficulty = performance.averageDifficulty {
            ProgressScoreSignal(
                value: String(format: "%.1f / 10", difficulty),
                label: "avg. route difficulty"
            )
        }
    }

    private var emptyEvidenceState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AppDesign.accent)
                .frame(width: 52, height: 52)
                .background(AppDesign.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("No recorded evidence yet")
                .font(.headline)
            Text("Complete a drive with usable GPS and motion. It stays in history while Roam automatically analyzes its start-to-destination route difficulty.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .premiumCard()
    }

    private var evidenceSummary: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Recorded evidence", subtitle: "Only qualifying local drives are included.")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    metrics
                }
                VStack(alignment: .leading, spacing: 14) {
                    metrics
                }
            }
        }
        .premiumCard()
    }

    @ViewBuilder
    private var metrics: some View {
        ProgressMetric(value: String(format: "%.1f", summary.validatedMiles), label: "validated mi", symbol: "location.fill")
        ProgressMetric(value: "\(summary.qualifyingDriveCount)", label: "qualifying drives", symbol: "steeringwheel")
        ProgressMetric(value: "\(summary.qualifyingDriveDayCount)", label: "recorded days", symbol: "calendar")
    }

    private var thinEvidenceState: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .foregroundStyle(AppDesign.accent)
            Text("Recorded evidence is still limited. These measurements describe what this iPhone has captured so far, not a recommendation about a future drive.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(AppDesign.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))
    }

    private var weeklyChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Measured miles", subtitle: "The last eight calendar weeks.")

            Chart(summary.weeklyMeasuredMiles) { week in
                BarMark(
                    x: .value("Week", week.startDate, unit: .weekOfYear),
                    y: .value("Measured miles", week.measuredMiles)
                )
                .foregroundStyle(AppDesign.accent.gradient)
                .cornerRadius(5)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.secondary.opacity(0.18))
                    AxisValueLabel {
                        if let miles = value.as(Double.self) {
                            Text(miles, format: .number.precision(.fractionLength(0)))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                }
            }
            .frame(height: 180)
            .animation(reduceMotion ? .easeOut(duration: 0.16) : AppAnimation.content, value: summary.weeklyMeasuredMiles)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(chartAccessibilitySummary)
        }
        .premiumCard()
    }

    private var coverageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Measurement coverage", subtitle: "What the qualifying GPS trace has actually captured.")

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
        .premiumCard()
    }

    private var measurementNote: some View {
        Label(
            "Roam keeps driving history, route overlap, and progress calculations on this device.",
            systemImage: "lock.shield.fill"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private var notYetQualifyingNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(AppDesign.safety)
            Text("\(notYetQualifyingDriveCount) \(notYetQualifyingDriveCount == 1 ? "saved drive is" : "saved drives are") not yet qualifying for progress totals. They remain in your private history and need enough usable GPS, motion, distance, and continuous trace data before they count here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct ProgressScoreSignal: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusTiny, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct ProgressCoverageRow: View {
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
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    DriverProgressView()
        .environmentObject(DriveSessionManager())
        .environmentObject(ScrollCollapseTracker())
}
