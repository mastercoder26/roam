import Foundation

/// Which way the live score has moved over the recent window. Used only to
/// decorate the ring — never to change the score itself.
enum LiveScoreTrend: String, Equatable {
    case rising
    case steady
    case falling

    var symbol: String {
        switch self {
        case .rising: "arrow.up.right"
        case .steady: "equal"
        case .falling: "arrow.down.right"
        }
    }
}

/// The qualitative band a live score sits in. Deliberately separate from
/// `DrivingScore.grade`, which is a *final* judgement on a completed drive.
/// A live band is a coaching hint on partial data and says so.
enum LiveScoreBand: String, Equatable {
    case settling
    case excellent
    case steady
    case watch

    var title: String {
        switch self {
        case .settling: "Settling"
        case .excellent: "Excellent"
        case .steady: "Steady"
        case .watch: "Ease off"
        }
    }
}

/// A single milestone the driver crossed by staying clean. These are the beats
/// worth a haptic and a one-shot flourish; anything more frequent becomes
/// noise the driver learns to ignore.
enum CleanStreakMilestone: Int, CaseIterable, Equatable {
    case twoMinutes = 120
    case fiveMinutes = 300
    case tenMinutes = 600
    case twentyMinutes = 1_200

    var title: String {
        switch self {
        case .twoMinutes: "2 min clean"
        case .fiveMinutes: "5 min clean"
        case .tenMinutes: "10 min clean"
        case .twentyMinutes: "20 min clean"
        }
    }
}

/// How smoothly the car is being driven, as a state rather than a number.
///
/// Quantized on purpose. The underlying signal updates several times a second,
/// and a bar tracking it continuously is ambient motion in the driver's
/// peripheral vision — exactly what a driving surface must not have. Three
/// states, changed rarely, say the same thing without asking to be watched.
enum SmoothnessState: String, Equatable {
    case smooth
    case moderate
    case choppy

    var title: String {
        switch self {
        case .smooth: "Smooth"
        case .moderate: "Moderate"
        case .choppy: "Choppy"
        }
    }

    var symbol: String {
        switch self {
        case .smooth: "wave.3.right"
        case .moderate: "wave.3.right"
        case .choppy: "exclamationmark.triangle.fill"
        }
    }
}

/// One earned clean-streak badge, carrying its own identity.
///
/// The identity matters: a driver can earn the same milestone twice in a drive
/// (streak, event, streak again). Publishing the bare `milestone` would make
/// the second one an unchanged value, so the view would never see it and the
/// second badge would be earned silently.
struct CleanStreakCelebration: Equatable, Identifiable {
    let id: UUID
    let milestone: CleanStreakMilestone

    init(id: UUID = UUID(), milestone: CleanStreakMilestone) {
        self.id = id
        self.milestone = milestone
    }
}

/// Everything the live drive surface renders, computed in one place from the
/// session's raw state. Value-typed and `Equatable` so SwiftUI can diff it and
/// so the whole live readout can be checked without a simulator.
struct LiveDriveScore: Equatable {
    /// `nil` until there is enough of a drive to say anything at all. The view
    /// shows a settling state rather than a confident 100.
    let score: Int?
    let band: LiveScoreBand
    let trend: LiveScoreTrend
    /// Seconds since the last coaching event, or since the drive began.
    let cleanStreakSeconds: TimeInterval
    /// Highest milestone reached by the current streak, if any.
    let cleanStreakMilestone: CleanStreakMilestone?
    /// Short-window driving smoothness, already quantized. The raw 0...1
    /// signal deliberately does not reach the view: see `SmoothnessState`.
    let smoothness: SmoothnessState
    let eventCount: Int

    static let idle = LiveDriveScore(
        score: nil,
        band: .settling,
        trend: .steady,
        cleanStreakSeconds: 0,
        cleanStreakMilestone: nil,
        smoothness: .smooth,
        eventCount: 0
    )

    /// Ring fill in 0...1. A settling drive shows an empty ring rather than a
    /// full one, so the arc only ever fills with earned score.
    var ringProgress: Double {
        guard let score else { return 0 }
        return max(0, min(1, Double(score) / 100))
    }

    /// Whole minutes, and nothing at all below the first one.
    ///
    /// A seconds counter on this surface ticks once a second forever, which is
    /// motion the driver's eye keeps returning to for no new information. At
    /// minute granularity the chip changes rarely enough to be read rather
    /// than watched.
    var formattedStreak: String {
        let minutes = max(0, Int(cleanStreakSeconds)) / 60
        guard minutes > 0 else { return "Clean" }
        return minutes == 1 ? "Clean 1 min" : "Clean \(minutes) min"
    }
}

/// Computes the live drive readout.
///
/// Live scoring reuses `DriveScoringEngine.score` rather than inventing a
/// second set of penalties, so the number on screen mid-drive and the number
/// saved at the end come from the same math. What this engine adds is *when*
/// that number is honest enough to show, plus the streak and smoothness
/// signals that only make sense while a drive is in progress.
enum LiveDriveScoreEngine {
    /// Below this, a drive has not produced enough evidence for a score to
    /// mean anything — one early stop sign would read as a failing grade.
    static let minimumScoringDuration: TimeInterval = 45
    static let minimumScoringDistanceMeters: Double = 120

    /// Bands are set a notch more forgiving than the final grade ladder,
    /// because a live score on partial data swings harder than a final one.
    static let excellentThreshold = 90
    static let steadyThreshold = 74

    /// How much the score must move across the trend window before the arrow
    /// changes. Without this the indicator flickers on rounding alone.
    static let trendDelta = 2

    /// Smoothness maps horizontal g onto 0...1. `calmAccelerationG` and below
    /// is glass; `roughAccelerationG` and above is 0.
    static let calmAccelerationG = 0.08
    static let roughAccelerationG = 0.55

    /// Hysteresis band for `smoothnessState`. A state only changes once the
    /// signal has crossed *past* the boundary by this margin, so a value
    /// sitting on a threshold cannot flicker between two labels.
    static let smoothnessHysteresis = 0.06
    static let smoothThreshold = 0.66
    static let moderateThreshold = 0.33

    static func band(for score: Int?) -> LiveScoreBand {
        guard let score else { return .settling }
        if score >= excellentThreshold { return .excellent }
        if score >= steadyThreshold { return .steady }
        return .watch
    }

    static func trend(current: Int?, previous: Int?) -> LiveScoreTrend {
        guard let current, let previous else { return .steady }
        let delta = current - previous
        if delta >= trendDelta { return .rising }
        if delta <= -trendDelta { return .falling }
        return .steady
    }

    /// A short-window smoothness reading. Uses the *median* horizontal g so a
    /// single sensor spike or one pothole does not drop the meter to zero —
    /// the same reasoning as `DriveScoringEngine.corroboratingMotionG`.
    static func smoothness(from samples: [DriveMotionSample], window: TimeInterval = 2.5, now: Date) -> Double {
        let values = samples
            .filter { now.timeIntervalSince($0.timestamp) <= window }
            .map(\.horizontalAccelerationG)
            .sorted()
        guard !values.isEmpty else { return 1 }
        let median = values[values.count / 2]
        let span = roughAccelerationG - calmAccelerationG
        guard span > 0 else { return 1 }
        return max(0, min(1, 1 - (median - calmAccelerationG) / span))
    }

    /// Quantizes the raw smoothness signal, holding `current` unless the
    /// signal has moved clear of the boundary. Passing `nil` for `current` —
    /// the first reading of a drive — snaps straight to the matching state
    /// rather than easing in from an arbitrary default.
    static func smoothnessState(for value: Double, current: SmoothnessState?) -> SmoothnessState {
        guard let current else {
            if value >= smoothThreshold { return .smooth }
            return value >= moderateThreshold ? .moderate : .choppy
        }

        switch current {
        case .smooth:
            // Only leave `smooth` once the signal is clearly below the band.
            if value < smoothThreshold - smoothnessHysteresis {
                return value < moderateThreshold - smoothnessHysteresis ? .choppy : .moderate
            }
            return .smooth
        case .moderate:
            if value >= smoothThreshold + smoothnessHysteresis { return .smooth }
            if value < moderateThreshold - smoothnessHysteresis { return .choppy }
            return .moderate
        case .choppy:
            if value >= smoothThreshold + smoothnessHysteresis { return .smooth }
            if value >= moderateThreshold + smoothnessHysteresis { return .moderate }
            return .choppy
        }
    }

    static func cleanStreakSeconds(now: Date, lastEventAt: Date?, driveStartedAt: Date?) -> TimeInterval {
        guard let reference = lastEventAt ?? driveStartedAt else { return 0 }
        return max(0, now.timeIntervalSince(reference))
    }

    /// The highest milestone the streak has passed. Returning the highest —
    /// rather than the next — means a streak that resumes mid-drive never
    /// re-announces a badge the driver already earned in this streak.
    static func milestone(forStreak seconds: TimeInterval) -> CleanStreakMilestone? {
        CleanStreakMilestone.allCases
            .filter { seconds >= TimeInterval($0.rawValue) }
            .max { $0.rawValue < $1.rawValue }
    }

    /// `nil` when the drive is still too short or too stationary to score.
    static func provisionalScore(
        duration: TimeInterval,
        distanceMeters: Double,
        events: [DrivingEvent]
    ) -> Int? {
        guard duration >= minimumScoringDuration,
              distanceMeters >= minimumScoringDistanceMeters else {
            return nil
        }
        // Sample counts do not matter here: this call wants the penalty math,
        // and the confidence label it would also produce is a property of the
        // *saved* drive, not of a mid-drive readout.
        return DriveScoringEngine.score(
            duration: duration,
            distanceMeters: distanceMeters,
            events: events,
            acceptedLocationSamples: 0,
            rejectedLocationSamples: 0,
            motionSamples: 0
        ).score
    }

    static func evaluate(
        now: Date,
        driveStartedAt: Date?,
        duration: TimeInterval,
        distanceMeters: Double,
        events: [DrivingEvent],
        motionSamples: [DriveMotionSample],
        previousScore: Int?,
        currentSmoothness: SmoothnessState?
    ) -> LiveDriveScore {
        let score = provisionalScore(
            duration: duration,
            distanceMeters: distanceMeters,
            events: events
        )
        let streak = cleanStreakSeconds(
            now: now,
            lastEventAt: events.last?.timestamp,
            driveStartedAt: driveStartedAt
        )

        return LiveDriveScore(
            score: score,
            band: band(for: score),
            trend: trend(current: score, previous: previousScore),
            cleanStreakSeconds: streak,
            cleanStreakMilestone: milestone(forStreak: streak),
            smoothness: smoothnessState(
                for: smoothness(from: motionSamples, now: now),
                current: currentSmoothness
            ),
            eventCount: events.count
        )
    }
}
