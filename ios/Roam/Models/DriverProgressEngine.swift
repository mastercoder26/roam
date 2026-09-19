import Foundation

/// One chronological column in the private eight-week measurement chart.
/// `endDate` is exclusive so adjacent buckets cannot double-count a drive.
struct DriverProgressWeek: Identifiable, Hashable {
    let startDate: Date
    let endDate: Date
    let measuredMiles: Double

    var id: Date { startDate }
}

/// Aggregate evidence from qualifying local drives. These quantities describe
/// what the phone actually measured, not a safety grade or a driving rank.
struct DriverProgressSummary: Hashable {
    let validatedMiles: Double
    let qualifyingDriveCount: Int
    let qualifyingDriveDayCount: Int
    let afterDarkMiles: Double
    let milesAt45Plus: Double
    let longestContinuousDuration: TimeInterval
    let longestContinuousDistanceMiles: Double
    let weeklyMeasuredMiles: [DriverProgressWeek]

    var hasRecordedEvidence: Bool { qualifyingDriveCount > 0 }
}

enum DriverProgressTrend: Hashable {
    case buildingBaseline
    case improving
    case steady
    case rebuilding

    var title: String {
        switch self {
        case .buildingBaseline: "Building your baseline"
        case .improving: "Trending up"
        case .steady: "Holding steady"
        case .rebuilding: "A chance to reset"
        }
    }

    var symbol: String {
        switch self {
        case .buildingBaseline: "chart.line.uptrend.xyaxis"
        case .improving: "arrow.up.right"
        case .steady: "arrow.right"
        case .rebuilding: "arrow.counterclockwise"
        }
    }
}

enum DriverProgressFocus: Hashable {
    case smoothBraking
    case gentleAcceleration
    case steadyCornering
    case phoneSetup
    case consistency

    var title: String {
        switch self {
        case .smoothBraking: "Smoother braking"
        case .gentleAcceleration: "Gentler acceleration"
        case .steadyCornering: "Steadier cornering"
        case .phoneSetup: "Set the phone before moving"
        case .consistency: "Keep the calm rhythm"
        }
    }

    var detail: String {
        switch self {
        case .smoothBraking:
            "Look farther ahead and ease off earlier when conditions allow."
        case .gentleAcceleration:
            "Build speed progressively and leave a little more space ahead."
        case .steadyCornering:
            "Set a comfortable speed before the turn, then steer smoothly through it."
        case .phoneSetup:
            "Mount or settle your phone before the drive and leave it in place."
        case .consistency:
            "Repeat the measured habits from your recent drives on a familiar route."
        }
    }

    var symbol: String {
        switch self {
        case .smoothBraking: "brakesignal"
        case .gentleAcceleration: "gauge.with.dots.needle.33percent"
        case .steadyCornering: "arrow.triangle.turn.up.right.diamond.fill"
        case .phoneSetup: "iphone.gen3"
        case .consistency: "metronome.fill"
        }
    }
}

/// A small, deterministic coaching layer derived only from qualifying local
/// history. It names a useful next focus without presenting a safety verdict.
struct DriverProgressCoachSummary: Hashable {
    let trend: DriverProgressTrend
    let recentScoreChange: Int?
    let focus: DriverProgressFocus
    let completedThisWeek: Int
    let weeklyTargetDriveCount: Int

    var weeklyGoalProgress: Double {
        guard weeklyTargetDriveCount > 0 else { return 0 }
        return min(1, Double(completedThisWeek) / Double(weeklyTargetDriveCount))
    }

    var trendDetail: String {
        guard let recentScoreChange else {
            return "Complete four qualifying drives to reveal a recent score trend."
        }
        switch trend {
        case .improving:
            return "Your latest drives average (recentScoreChange) points higher than the two before them."
        case .steady:
            return "Your latest drives are within (abs(recentScoreChange)) points of the two before them."
        case .rebuilding:
            return "Your latest drives average (abs(recentScoreChange)) points lower; use one focus at a time."
        case .buildingBaseline:
            return "Complete four qualifying drives to reveal a recent score trend."
        }
    }
}

enum DriverProgressCoachEngine {
    private static let trendThreshold = 3.0

    static func makeSummary(
        from recordedDrives: [RecordedDrive],
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        readinessConfiguration: DriverReadinessEngine.Configuration = .init()
    ) -> DriverProgressCoachSummary {
        let qualifying = recordedDrives
            .filter {
                $0.startedAt <= referenceDate &&
                    DriverReadinessEngine.qualifies(
                        $0,
                        configuration: readinessConfiguration,
                        calendar: calendar
                    )
            }
            .sorted { $0.startedAt < $1.startedAt }

        let trendResult = trend(for: qualifying)
        return DriverProgressCoachSummary(
            trend: trendResult.trend,
            recentScoreChange: trendResult.change,
            focus: focus(for: Array(qualifying.suffix(5)), calendar: calendar),
            completedThisWeek: completedThisWeek(
                qualifying,
                referenceDate: referenceDate,
                calendar: calendar
            ),
            weeklyTargetDriveCount: weeklyTarget(
                qualifying,
                referenceDate: referenceDate,
                calendar: calendar
            )
        )
    }

    private static func trend(for drives: [RecordedDrive]) -> (trend: DriverProgressTrend, change: Int?) {
        guard drives.count >= 4 else { return (.buildingBaseline, nil) }
        let latest = drives.suffix(2).map { Double($0.score.score) }
        let previous = drives.dropLast(2).suffix(2).map { Double($0.score.score) }
        let change = latest.reduce(0, +) / 2 - previous.reduce(0, +) / 2
        let roundedChange = Int(change.rounded())
        if change >= trendThreshold { return (.improving, roundedChange) }
        if change <= -trendThreshold { return (.rebuilding, roundedChange) }
        return (.steady, roundedChange)
    }

    private static func focus(for drives: [RecordedDrive], calendar: Calendar) -> DriverProgressFocus {
        let exposures = drives.map { DriveExperienceEngine.summary(for: $0, calendar: calendar).eventExposure }
        let totals = exposures.reduce(into: (braking: 0.0, acceleration: 0.0, cornering: 0.0, phone: 0.0)) { result, exposure in
            result.braking += Double(exposure.hardBrakeCount)
            result.acceleration += Double(exposure.rapidAccelerationCount) * 0.8
            result.cornering += Double(exposure.sharpCornerCount) * 0.7
            result.phone += Double(exposure.phoneMovementCount) * 0.25
        }
        let candidates: [(DriverProgressFocus, Double)] = [
            (.smoothBraking, totals.braking),
            (.gentleAcceleration, totals.acceleration),
            (.steadyCornering, totals.cornering),
            (.phoneSetup, totals.phone),
        ]
        guard let strongest = candidates.max(by: { $0.1 < $1.1 }), strongest.1 > 0 else {
            return .consistency
        }
        return strongest.0
    }

    private static func completedThisWeek(
        _ drives: [RecordedDrive],
        referenceDate: Date,
        calendar: Calendar
    ) -> Int {
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else { return 0 }
        return drives.filter { currentWeek.contains($0.startedAt) }.count
    }

    private static func weeklyTarget(
        _ drives: [RecordedDrive],
        referenceDate: Date,
        calendar: Calendar
    ) -> Int {
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else { return 2 }
        let completedWeekCounts = (1...4).compactMap { weeksAgo -> Int? in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: currentWeek.start),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else {
                return nil
            }
            return drives.filter { $0.startedAt >= start && $0.startedAt < end }.count
        }
        guard completedWeekCounts.contains(where: { $0 > 0 }) else { return 2 }
        let average = Double(completedWeekCounts.reduce(0, +)) / Double(completedWeekCounts.count)
        return min(4, max(2, Int(average.rounded())))
    }
}

/// Pure local aggregation for the Progress tab. It deliberately reuses the
/// readiness qualification rule so short or low-confidence recordings remain
/// in history without inflating measured experience.
enum DriverProgressEngine {
    static let weeklyBucketCount = 8

    static func makeSummary(
        from recordedDrives: [RecordedDrive],
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        readinessConfiguration: DriverReadinessEngine.Configuration = .init()
    ) -> DriverProgressSummary {
        let qualifying = recordedDrives.compactMap { drive -> (drive: RecordedDrive, summary: DriveExperienceSummary)? in
            guard drive.startedAt <= referenceDate,
                  DriverReadinessEngine.qualifies(
                    drive,
                    configuration: readinessConfiguration,
                    calendar: calendar
                  ) else {
                return nil
            }
            return (drive, DriveExperienceEngine.summary(for: drive, calendar: calendar))
        }

        let dayKeys = Set(qualifying.map { localDayKey(for: $0.drive, calendar: calendar) })
        let validatedMiles = qualifying.reduce(0) { $0 + $1.summary.measuredMiles }
        let afterDarkMiles = qualifying.reduce(0) { $0 + $1.summary.lightingExposure.afterDarkMiles }
        let milesAt45Plus = qualifying.reduce(0) { $0 + $1.summary.speedExposure.milesAt45Plus }
        let longestDuration = qualifying.map { $0.summary.traceQuality.longestContinuousDuration }.max() ?? 0
        let longestDistance = qualifying.map {
            $0.summary.traceQuality.longestContinuousDistanceMeters / 1_609.344
        }.max() ?? 0

        return DriverProgressSummary(
            validatedMiles: validatedMiles,
            qualifyingDriveCount: qualifying.count,
            qualifyingDriveDayCount: dayKeys.count,
            afterDarkMiles: afterDarkMiles,
            milesAt45Plus: milesAt45Plus,
            longestContinuousDuration: longestDuration,
            longestContinuousDistanceMiles: longestDistance,
            weeklyMeasuredMiles: weeklyBuckets(
                for: qualifying,
                referenceDate: referenceDate,
                calendar: calendar
            )
        )
    }

    private static func weeklyBuckets(
        for qualifying: [(drive: RecordedDrive, summary: DriveExperienceSummary)],
        referenceDate: Date,
        calendar: Calendar
    ) -> [DriverProgressWeek] {
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: referenceDate)
            ?? DateInterval(start: calendar.startOfDay(for: referenceDate), duration: 7 * 86_400)
        let oldestStart = calendar.date(
            byAdding: .weekOfYear,
            value: -(weeklyBucketCount - 1),
            to: currentWeek.start
        ) ?? currentWeek.start

        return (0..<weeklyBucketCount).compactMap { index in
            guard let start = calendar.date(byAdding: .weekOfYear, value: index, to: oldestStart),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else {
                return nil
            }
            let miles = qualifying.reduce(0) { partial, item in
                guard item.drive.startedAt >= start, item.drive.startedAt < end else {
                    return partial
                }
                return partial + item.summary.measuredMiles
            }
            return DriverProgressWeek(startDate: start, endDate: end, measuredMiles: miles)
        }
    }

    /// The local day at recording time keeps a later time-zone change from
    /// collapsing separate days of evidence into one UI count.
    private static func localDayKey(for drive: RecordedDrive, calendar: Calendar) -> String {
        let driveCalendar = DriveExperienceEngine.calendar(for: drive, base: calendar)
        let components = driveCalendar.dateComponents([.year, .month, .day], from: drive.startedAt)
        return [
            driveCalendar.timeZone.identifier,
            String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0),
        ].joined(separator: "|")
    }
}
