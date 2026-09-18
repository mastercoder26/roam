import CoreLocation
import Foundation

@main
struct LiveDriveScoreEngineChecks {
    static func main() {
        checkProvisionalScoreGating()
        checkBands()
        checkTrend()
        checkSmoothness()
        checkCleanStreak()
        checkSmoothnessHysteresis()
        checkCelebrationIdentity()
        checkEvaluate()
        print("LiveDriveScoreEngine checks passed")
    }

    // MARK: - Provisional score

    private static func checkProvisionalScoreGating() {
        expect(
            LiveDriveScoreEngine.provisionalScore(duration: 20, distanceMeters: 800, events: []) == nil,
            "a drive shorter than the minimum duration must not produce a score"
        )
        expect(
            LiveDriveScoreEngine.provisionalScore(duration: 300, distanceMeters: 40, events: []) == nil,
            "a stationary drive must not produce a score however long it runs"
        )
        expect(
            LiveDriveScoreEngine.provisionalScore(duration: 300, distanceMeters: 4_000, events: []) == 100,
            "a clean qualifying drive must score 100"
        )

        let withEvents = LiveDriveScoreEngine.provisionalScore(
            duration: 600,
            distanceMeters: 8_000,
            events: [event(.hardBrake, at: 10), event(.hardBrake, at: 20)]
        )
        expect(withEvents != nil, "a qualifying drive with events must still produce a score")
        expect((withEvents ?? 100) < 100, "coaching events must lower the live score")

        // The live score must agree with the number the saved drive will carry.
        let saved = DriveScoringEngine.score(
            duration: 600,
            distanceMeters: 8_000,
            events: [event(.hardBrake, at: 10), event(.hardBrake, at: 20)],
            acceptedLocationSamples: 0,
            rejectedLocationSamples: 0,
            motionSamples: 0
        ).score
        expect(withEvents == saved, "live scoring must reuse the saved-drive penalty math")
    }

    // MARK: - Bands

    private static func checkBands() {
        expect(LiveDriveScoreEngine.band(for: nil) == .settling, "no score must read as settling")
        expect(LiveDriveScoreEngine.band(for: 96) == .excellent, "96 must read as excellent")
        expect(LiveDriveScoreEngine.band(for: 90) == .excellent, "the excellent threshold is inclusive")
        expect(LiveDriveScoreEngine.band(for: 80) == .steady, "80 must read as steady")
        expect(LiveDriveScoreEngine.band(for: 74) == .steady, "the steady threshold is inclusive")
        expect(LiveDriveScoreEngine.band(for: 60) == .watch, "60 must ask the driver to ease off")

        expect(LiveDriveScore.idle.ringProgress == 0, "a settling drive must show an empty ring, never a full one")
    }

    // MARK: - Trend

    private static func checkTrend() {
        expect(LiveDriveScoreEngine.trend(current: 90, previous: nil) == .steady, "a first reading has no trend")
        expect(LiveDriveScoreEngine.trend(current: nil, previous: 90) == .steady, "a lost reading has no trend")
        expect(LiveDriveScoreEngine.trend(current: 91, previous: 90) == .steady, "a one-point move must not flip the arrow")
        expect(LiveDriveScoreEngine.trend(current: 94, previous: 90) == .rising, "a four-point gain must read as rising")
        expect(LiveDriveScoreEngine.trend(current: 86, previous: 90) == .falling, "a four-point loss must read as falling")
    }

    // MARK: - Smoothness

    private static func checkSmoothness() {
        let now = Date(timeIntervalSinceReferenceDate: 100)
        expect(LiveDriveScoreEngine.smoothness(from: [], now: now) == 1, "no motion data must read as smooth, not as rough")

        let calm = (0..<10).map { motion(100 - Double($0) * 0.1, acceleration: 0.04) }
        expect(LiveDriveScoreEngine.smoothness(from: calm, now: now) == 1, "calm driving must read as fully smooth")

        let rough = (0..<10).map { motion(100 - Double($0) * 0.1, acceleration: 0.9) }
        expect(LiveDriveScoreEngine.smoothness(from: rough, now: now) == 0, "sustained hard motion must read as zero")

        // One spike among calm samples must not empty the meter.
        var spiked = (0..<10).map { motion(100 - Double($0) * 0.1, acceleration: 0.04) }
        spiked.append(motion(99.9, acceleration: 1.8))
        expect(
            LiveDriveScoreEngine.smoothness(from: spiked, now: now) > 0.9,
            "a single sensor spike must not collapse the smoothness meter"
        )

        // Samples older than the window must be ignored.
        let stale = [motion(10, acceleration: 0.9)]
        expect(
            LiveDriveScoreEngine.smoothness(from: stale, now: now) == 1,
            "samples outside the window must not affect the reading"
        )
    }

    /// The state must hold across a boundary until the signal is clearly past
    /// it, or a value hovering on a threshold flickers between two labels on
    /// a screen the driver is glancing at.
    private static func checkSmoothnessHysteresis() {
        expect(
            LiveDriveScoreEngine.smoothnessState(for: 0.9, current: nil) == .smooth,
            "a first reading snaps straight to its matching state"
        )
        expect(
            LiveDriveScoreEngine.smoothnessState(for: 0.5, current: nil) == .moderate,
            "a first mid reading is moderate"
        )
        expect(
            LiveDriveScoreEngine.smoothnessState(for: 0.1, current: nil) == .choppy,
            "a first low reading is choppy"
        )

        // Just below the smooth threshold, but inside the hysteresis band.
        expect(
            LiveDriveScoreEngine.smoothnessState(for: 0.64, current: .smooth) == .smooth,
            "a signal inside the band must not leave the current state"
        )
        expect(
            LiveDriveScoreEngine.smoothnessState(for: 0.5, current: .smooth) == .moderate,
            "a signal clear of the band must change state"
        )
        // And symmetrically on the way back up.
        expect(
            LiveDriveScoreEngine.smoothnessState(for: 0.68, current: .moderate) == .moderate,
            "coming back up must also clear the band before switching"
        )
        expect(
            LiveDriveScoreEngine.smoothnessState(for: 0.8, current: .moderate) == .smooth,
            "a clearly smooth signal must switch back"
        )

        // A value oscillating around a boundary must settle on one state.
        var state: SmoothnessState = .smooth
        var changes = 0
        for step in 0..<200 {
            let wobble = step % 2 == 0 ? 0.655 : 0.665
            let next = LiveDriveScoreEngine.smoothnessState(for: wobble, current: state)
            if next != state { changes += 1 }
            state = next
        }
        expect(changes == 0, "a signal wobbling on the threshold must never flicker the label")
    }

    // MARK: - Clean streak

    private static func checkCleanStreak() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        expect(
            LiveDriveScoreEngine.cleanStreakSeconds(now: now, lastEventAt: nil, driveStartedAt: nil) == 0,
            "with no drive there is no streak"
        )
        expect(
            LiveDriveScoreEngine.cleanStreakSeconds(
                now: now,
                lastEventAt: nil,
                driveStartedAt: Date(timeIntervalSinceReferenceDate: 700)
            ) == 300,
            "an event-free drive streaks from its start"
        )
        expect(
            LiveDriveScoreEngine.cleanStreakSeconds(
                now: now,
                lastEventAt: Date(timeIntervalSinceReferenceDate: 940),
                driveStartedAt: Date(timeIntervalSinceReferenceDate: 700)
            ) == 60,
            "an event restarts the streak"
        )

        expect(LiveDriveScoreEngine.milestone(forStreak: 119) == nil, "a streak below two minutes earns nothing")
        expect(LiveDriveScoreEngine.milestone(forStreak: 120) == .twoMinutes, "two minutes earns the first badge")
        expect(LiveDriveScoreEngine.milestone(forStreak: 900) == .tenMinutes, "the highest passed milestone wins")
        expect(LiveDriveScoreEngine.milestone(forStreak: 9_999) == .twentyMinutes, "the ladder tops out at twenty minutes")

        let sample = LiveDriveScore(
            score: 90,
            band: .excellent,
            trend: .steady,
            cleanStreakSeconds: 125,
            cleanStreakMilestone: .twoMinutes,
            smoothness: .smooth,
            eventCount: 0
        )
        // Minute granularity on purpose: a per-second counter on a driving
        // surface is motion the eye keeps returning to for no information.
        expect(sample.formattedStreak == "Clean 2 min", "a two-minute streak reads in whole minutes")
        expect(
            LiveDriveScore.idle.formattedStreak == "Clean",
            "a streak under a minute must not show a ticking seconds count"
        )
        let oneMinute = LiveDriveScore(
            score: 100,
            band: .excellent,
            trend: .steady,
            cleanStreakSeconds: 61,
            cleanStreakMilestone: nil,
            smoothness: .smooth,
            eventCount: 0
        )
        expect(oneMinute.formattedStreak == "Clean 1 min", "one minute must read in the singular")
    }

    /// A driver can earn the same milestone twice in one drive: streak, event,
    /// streak again. Two such badges must be distinguishable, or the view sees
    /// an unchanged value and the second one is earned in silence.
    private static func checkCelebrationIdentity() {
        let first = CleanStreakCelebration(milestone: .twoMinutes)
        let second = CleanStreakCelebration(milestone: .twoMinutes)
        expect(first != second, "two separate badges of the same milestone must not compare equal")
        expect(first.milestone == second.milestone, "both must still carry the milestone they represent")
        expect(first == first, "a badge must compare equal to itself")
    }

    // MARK: - Evaluate

    private static func checkEvaluate() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let now = Date(timeIntervalSinceReferenceDate: 600)

        let settling = LiveDriveScoreEngine.evaluate(
            now: Date(timeIntervalSinceReferenceDate: 10),
            driveStartedAt: start,
            duration: 10,
            distanceMeters: 30,
            events: [],
            motionSamples: [],
            previousScore: nil,
            currentSmoothness: nil
        )
        expect(settling.score == nil, "a just-started drive must not claim a score")
        expect(settling.band == .settling, "a just-started drive reads as settling")
        expect(settling.cleanStreakSeconds == 10, "the streak runs from the drive start")

        let live = LiveDriveScoreEngine.evaluate(
            now: now,
            driveStartedAt: start,
            duration: 600,
            distanceMeters: 8_000,
            events: [event(.hardBrake, at: 540)],
            motionSamples: [motion(599.5, acceleration: 0.05)],
            previousScore: 100,
            currentSmoothness: .smooth
        )
        expect(live.score != nil, "a qualifying drive must produce a score")
        expect(live.eventCount == 1, "the readout must carry the event count")
        expect(live.cleanStreakSeconds == 60, "the streak restarts at the most recent event")
        expect(live.trend == .falling, "a score drop must read as falling")
        expect(live.ringProgress > 0 && live.ringProgress <= 1, "the ring fill must stay in range")
    }

    // MARK: - Helpers

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError("LiveDriveScoreEngine check failed: \(message)")
        }
    }

    private static func event(_ kind: DrivingEventKind, at seconds: TimeInterval) -> DrivingEvent {
        DrivingEvent(
            kind: kind,
            timestamp: Date(timeIntervalSinceReferenceDate: seconds),
            source: .gpsSpeed
        )
    }

    private static func motion(_ seconds: TimeInterval, acceleration: Double) -> DriveMotionSample {
        DriveMotionSample(
            timestamp: Date(timeIntervalSinceReferenceDate: seconds),
            horizontalAccelerationG: acceleration,
            rotationRateRadiansPerSecond: 0
        )
    }
}
