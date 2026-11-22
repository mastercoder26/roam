import Foundation

struct DriveLocationSample {
    let timestamp: Date
    let speedMetersPerSecond: Double
    let courseDegrees: Double?
    let courseAccuracyDegrees: Double?
    let horizontalAccuracyMeters: Double
}

struct DriveMotionSample {
    let timestamp: Date
    /// Gravity-free horizontal acceleration in g, transformed into a vertical-Z reference frame.
    let horizontalAccelerationG: Double
    /// Rotation rate in radians per second. Vehicle acceleration alone is not
    /// enough to call something phone handling, so this is kept alongside the
    /// acceleration signal for the short evidence window below.
    let rotationRateRadiansPerSecond: Double

    init(
        timestamp: Date,
        horizontalAccelerationG: Double,
        rotationRateRadiansPerSecond: Double = 0
    ) {
        self.timestamp = timestamp
        self.horizontalAccelerationG = horizontalAccelerationG
        self.rotationRateRadiansPerSecond = rotationRateRadiansPerSecond
    }
}

/// Filters Core Motion into a deliberately cautious phone-handling signal.
/// Road texture, braking, and one-off sensor spikes can all create horizontal
/// acceleration, so this requires a short sustained pattern with meaningful
/// device rotation while the vehicle is moving. It is not a distraction
/// detector; it only produces a coaching event for a clearly abrupt movement.
struct PhoneMovementDetector {
    static let minimumDrivingSpeedMetersPerSecond = 4.0
    static let evidenceWindow: TimeInterval = 0.40
    static let sustainedAccelerationThresholdG = 0.32
    static let sustainedRotationThresholdRadiansPerSecond = 0.75
    static let peakAccelerationThresholdG = 0.65
    static let peakRotationThresholdRadiansPerSecond = 1.20
    static let minimumEvidenceSampleCount = 3
    static let resetAccelerationThresholdG = 0.18
    static let resetRotationThresholdRadiansPerSecond = 0.40

    private var evidence: [DriveMotionSample] = []
    private var isLatched = false

    mutating func ingest(
        _ sample: DriveMotionSample,
        vehicleSpeedMetersPerSecond: Double,
        hasRecentAcceptedGPS: Bool
    ) -> Bool {
        guard hasRecentAcceptedGPS,
              vehicleSpeedMetersPerSecond >= Self.minimumDrivingSpeedMetersPerSecond else {
            reset()
            return false
        }

        if isLatched {
            if sample.horizontalAccelerationG < Self.resetAccelerationThresholdG,
               sample.rotationRateRadiansPerSecond < Self.resetRotationThresholdRadiansPerSecond {
                reset()
            }
            return false
        }

        evidence.append(sample)
        evidence.removeAll {
            sample.timestamp.timeIntervalSince($0.timestamp) > Self.evidenceWindow
        }

        let sustainedSamples = evidence.filter {
            $0.horizontalAccelerationG >= Self.sustainedAccelerationThresholdG &&
                $0.rotationRateRadiansPerSecond >= Self.sustainedRotationThresholdRadiansPerSecond
        }
        guard sustainedSamples.count >= Self.minimumEvidenceSampleCount else {
            return false
        }

        let evidenceDuration = (sustainedSamples.last?.timestamp ?? sample.timestamp)
            .timeIntervalSince(sustainedSamples.first?.timestamp ?? sample.timestamp)
        guard evidenceDuration >= 0.08 else { return false }

        let hasAbruptPeak = sustainedSamples.contains {
            $0.horizontalAccelerationG >= Self.peakAccelerationThresholdG &&
                $0.rotationRateRadiansPerSecond >= Self.peakRotationThresholdRadiansPerSecond
        }
        guard hasAbruptPeak else { return false }

        // Do not let the same continuous shake become a stream of events. The
        // detector must see a quiet sample before it can arm again.
        isLatched = true
        return true
    }

    mutating func reset() {
        evidence.removeAll(keepingCapacity: true)
        isLatched = false
    }
}

enum DrivingEventSource: String, Codable {
    case gpsSpeed = "GPS speed"
    case fused = "GPS + motion"
    case deviceMotion = "Device motion"
}

struct DetectedDrivingEvent {
    let kind: DrivingEventKind
    let source: DrivingEventSource
    /// How far past its detection threshold the maneuver measured, as a ratio
    /// (1.0 is exactly at the threshold). `nil` when it was not measured.
    let intensity: Double?
    /// Vehicle speed the maneuver happened at.
    let speedMetersPerSecond: Double?

    init(
        kind: DrivingEventKind,
        source: DrivingEventSource,
        intensity: Double? = nil,
        speedMetersPerSecond: Double? = nil
    ) {
        self.kind = kind
        self.source = source
        self.intensity = intensity
        self.speedMetersPerSecond = speedMetersPerSecond
    }
}

/// Events that belong to one piece of driving. A brake into a tight turn, or a
/// long stop that is sampled twice, is one maneuver rather than several
/// independent mistakes.
struct DriveManeuver {
    let events: [DrivingEvent]
    /// Score points this maneuver costs before exposure normalization.
    let penaltyPoints: Double
}

enum DriveScoreConfidence: String, Codable {
    case low
    case medium
    case high

    var title: String {
        switch self {
        case .low: "Preliminary"
        case .medium: "Useful sample"
        case .high: "Strong sample"
        }
    }
}

struct DriveDataQuality: Codable {
    let acceptedLocationSamples: Int
    let rejectedLocationSamples: Int
    let motionSamples: Int
    let confidence: DriveScoreConfidence
    /// Final advisory-only result from the first minute of a manual drive.
    /// No raw motion samples or episode timings are retained in saved history.
    let placementQuality: PhonePlacementAssessment?
    /// True when location authorization was withdrawn while the drive was
    /// recording, so GPS stopped partway through.
    ///
    /// Distance after that point is not measured, which makes the saved
    /// distance an undercount rather than a reading. Optional so drives written
    /// before this field existed still decode, matching `placementQuality`.
    let locationInterruptedMidDrive: Bool?
    /// True when the app was suspended in the background during the drive, so
    /// no location updates arrived for a long stretch while authorization was
    /// still granted.
    ///
    /// Deliberately distinct from `locationInterruptedMidDrive`: authorization
    /// was never withdrawn here, and reporting a suspension as revoked access
    /// would name the wrong cause. Optional so drives written before this field
    /// existed still decode.
    let recordingSuspendedInBackground: Bool?

    init(
        acceptedLocationSamples: Int,
        rejectedLocationSamples: Int,
        motionSamples: Int,
        confidence: DriveScoreConfidence,
        placementQuality: PhonePlacementAssessment? = nil,
        locationInterruptedMidDrive: Bool? = nil,
        recordingSuspendedInBackground: Bool? = nil
    ) {
        self.acceptedLocationSamples = acceptedLocationSamples
        self.rejectedLocationSamples = rejectedLocationSamples
        self.motionSamples = motionSamples
        self.confidence = confidence
        self.placementQuality = placementQuality
        self.locationInterruptedMidDrive = locationInterruptedMidDrive
        self.recordingSuspendedInBackground = recordingSuspendedInBackground
    }

    var summary: String {
        // Say this before anything about confidence: when GPS stopped partway
        // through, the recorded distance is an undercount, so describing the
        // data as "sufficient" or "sustained" would misrepresent it.
        if locationInterruptedMidDrive == true {
            return "Location access was turned off during this drive, so the distance recorded after that point is missing."
        }
        // Same reasoning, different cause: access was never withdrawn, the app
        // simply stopped receiving updates while it was in the background.
        if recordingSuspendedInBackground == true {
            return "Roam was suspended in the background for part of this drive, so the distance covered while the phone was locked is missing. Allow location access \"Always\" to record a locked-phone drive."
        }
        switch confidence {
        case .low:
            return "More time and movement data will make the next score more reliable."
        case .medium:
            return "GPS and motion data were sufficient for a useful coaching score."
        case .high:
            return "This score is based on sustained GPS and motion data."
        }
    }
}

enum DriveScoringEngine {
    static let maximumLocationAccuracyMeters = 35.0
    static let maximumCourseAccuracyDegrees = 25.0
    static let minimumSampleGap = 0.5
    static let maximumSampleGap = 5.0
    static let hardBrakeThreshold = -3.2
    static let rapidAccelerationThreshold = 2.8
    /// Lateral acceleration (speed × turn rate) that marks a sharp corner,
    /// about 0.4 g. A fixed turn rate alone flagged ordinary slow right turns
    /// and missed fast sweeping ones.
    static let sharpCornerLateralAcceleration = 4.0
    /// Course changes slower than this are within GPS heading noise.
    static let minimumCornerDegreesPerSecond = 8.0
    static let minimumCornerSpeedMetersPerSecond = 6.0

    // Scoring.
    /// Events closer together than this are part of the same maneuver.
    static let maneuverWindow: TimeInterval = 6
    /// A chain of events longer than this is split into separate maneuvers.
    static let maximumManeuverSpan: TimeInterval = 15
    /// Share of their own weight that the additional events in a maneuver add.
    static let secondaryManeuverEventShare = 0.3
    /// A maneuver never costs more than this multiple of its worst event.
    static let maximumManeuverMultiplier = 1.6
    /// Shortest exposure a drive is normalized against, in miles, so a single
    /// event in a brief trip does not read as a severe grade.
    static let minimumExposureMiles = 3.0
    /// Slow city driving is credited one exposure mile per this many moving
    /// minutes, so stop-and-go traffic is not judged against its short mileage.
    static let movingMinutesPerExposureMile = 3.0
    static let movingSpeedThresholdMetersPerSecond = 2.5
    /// The score approaches this value as events pile up; it is never reached.
    static let scoreFloor = 25.0
    static let highMotionThresholdG = PhoneMovementDetector.peakAccelerationThresholdG

    // Confidence gates. These are stated against *usable trace* time, not
    // wall-clock time: a suspended app, a tunnel, or an urban canyon all keep
    // accruing wall-clock seconds while measuring nothing.
    static let highConfidenceUsableTraceDuration: TimeInterval = 300
    static let highConfidenceDistanceMiles = 2.0
    static let highConfidenceAcceptedSamples = 24
    static let highConfidenceMotionSamples = 1_200
    static let mediumConfidenceUsableTraceDuration: TimeInterval = 90
    static let mediumConfidenceDistanceMiles = 0.5
    static let mediumConfidenceAcceptedSamples = 8
    static let mediumConfidenceMotionSamples = 240
    /// When most delivered fixes had to be thrown away, the trace is too sparse
    /// to describe as anything but preliminary, however long the drive ran.
    static let minimumAcceptedLocationSampleShare = 0.5

    static func accepts(_ sample: DriveLocationSample) -> Bool {
        sample.timestamp.timeIntervalSinceReferenceDate.isFinite &&
            sample.speedMetersPerSecond.isFinite &&
            sample.horizontalAccuracyMeters > 0 &&
            sample.horizontalAccuracyMeters <= maximumLocationAccuracyMeters &&
            sample.speedMetersPerSecond >= 0
    }

    static func isPlausibleTransition(
        previous: DriveLocationSample,
        current: DriveLocationSample,
        distanceMeters: Double
    ) -> Bool {
        guard accepts(previous), accepts(current), distanceMeters.isFinite, distanceMeters >= 0 else { return false }
        let elapsed = current.timestamp.timeIntervalSince(previous.timestamp)
        guard elapsed >= minimumSampleGap, elapsed <= maximumSampleGap else { return false }

        // GPS can occasionally jump hundreds of meters despite a nominally good
        // horizontal accuracy. Allow a generous 2.4× speed envelope plus a
        // margin, while rejecting impossible distance leaps.
        let maximumExpectedDistance = max(previous.speedMetersPerSecond, current.speedMetersPerSecond) * elapsed * 2.4 + 80
        return distanceMeters <= maximumExpectedDistance
    }

    static func detectEvents(
        previous: DriveLocationSample,
        current: DriveLocationSample,
        nearbyMotionG: Double?
    ) -> [DetectedDrivingEvent] {
        guard accepts(previous), accepts(current) else { return [] }

        let elapsed = current.timestamp.timeIntervalSince(previous.timestamp)
        guard elapsed >= minimumSampleGap, elapsed <= maximumSampleGap else { return [] }

        let acceleration = (current.speedMetersPerSecond - previous.speedMetersPerSecond) / elapsed
        let motionCorroborates = nearbyMotionG.map { $0.isFinite && $0 >= 0.18 } ?? false
        let source: DrivingEventSource = motionCorroborates ? .fused : .gpsSpeed
        var events: [DetectedDrivingEvent] = []

        // GPS-derived longitudinal acceleration is our primary maneuver signal.
        // Motion corroboration raises provenance, but GPS remains usable when a
        // phone is loosely mounted or motion sampling is unavailable.
        if previous.speedMetersPerSecond >= 4, acceleration <= hardBrakeThreshold {
            events.append(DetectedDrivingEvent(
                kind: .hardBrake,
                source: source,
                intensity: acceleration / hardBrakeThreshold,
                speedMetersPerSecond: previous.speedMetersPerSecond
            ))
        } else if current.speedMetersPerSecond >= 4, acceleration >= rapidAccelerationThreshold {
            events.append(DetectedDrivingEvent(
                kind: .rapidAcceleration,
                source: source,
                intensity: acceleration / rapidAccelerationThreshold,
                speedMetersPerSecond: current.speedMetersPerSecond
            ))
        }

        if previous.speedMetersPerSecond >= minimumCornerSpeedMetersPerSecond,
           current.speedMetersPerSecond >= minimumCornerSpeedMetersPerSecond,
           let previousCourse = previous.courseDegrees,
           let currentCourse = current.courseDegrees,
           let previousCourseAccuracy = previous.courseAccuracyDegrees,
           let currentCourseAccuracy = current.courseAccuracyDegrees,
           previousCourse.isFinite, currentCourse.isFinite,
           (0..<360).contains(previousCourse), (0..<360).contains(currentCourse),
           previousCourseAccuracy >= 0, currentCourseAccuracy >= 0,
           previousCourseAccuracy <= maximumCourseAccuracyDegrees,
           currentCourseAccuracy <= maximumCourseAccuracyDegrees {
            let courseChange = abs(normalizedAngle(currentCourse - previousCourse))
            let courseRate = courseChange / elapsed
            // Speed × turn rate is the sideways force the driver actually
            // feels. The turn must also be larger than the reported heading
            // uncertainty, or highway-speed GPS jitter would read as a corner.
            let cornerSpeed = min(previous.speedMetersPerSecond, current.speedMetersPerSecond)
            let lateralAcceleration = cornerSpeed * courseRate * .pi / 180
            if courseRate >= minimumCornerDegreesPerSecond,
               courseChange > max(previousCourseAccuracy, currentCourseAccuracy),
               lateralAcceleration >= sharpCornerLateralAcceleration {
                events.append(DetectedDrivingEvent(
                    kind: .sharpCorner,
                    source: source,
                    intensity: lateralAcceleration / sharpCornerLateralAcceleration,
                    speedMetersPerSecond: cornerSpeed
                ))
            }
        }

        return events
    }

    /// Returns a robust short-window motion value for GPS-event provenance.
    /// A median prevents one sensor spike from making a GPS-derived braking or
    /// acceleration event look motion-confirmed.
    static func corroboratingMotionG(
        from samples: [DriveMotionSample],
        near timestamp: Date,
        window: TimeInterval = 0.35
    ) -> Double? {
        let values = samples
            .filter { $0.horizontalAccelerationG.isFinite && $0.horizontalAccelerationG >= 0 && abs($0.timestamp.timeIntervalSince(timestamp)) <= window }
            .map(\.horizontalAccelerationG)
            .sorted()
        guard values.count >= 3 else { return nil }
        return values[values.count / 2]
    }

    static func shouldFlagPhoneMovement(_ horizontalAccelerationG: Double) -> Bool {
        horizontalAccelerationG >= highMotionThresholdG
    }

    /// Share of delivered location fixes that survived the accuracy and
    /// plausibility filters. `nil` when no fix was ever delivered — that is a
    /// motion-only drive, not a starved one, and the sample-share gate below
    /// must not judge it.
    static func acceptedLocationSampleShare(
        acceptedLocationSamples: Int,
        rejectedLocationSamples: Int
    ) -> Double? {
        let accepted = Double(max(0, acceptedLocationSamples))
        let delivered = accepted + Double(max(0, rejectedLocationSamples))
        guard delivered > 0 else { return nil }
        return accepted / delivered
    }

    /// The honest confidence label. `usableTraceDuration` is the measured time
    /// covered by continuous, plausible GPS (`DriveTraceQuality.usableDuration`),
    /// never the drive's wall-clock length.
    static func confidence(
        usableTraceDuration: TimeInterval,
        distanceMiles: Double,
        acceptedLocationSamples: Int,
        rejectedLocationSamples: Int,
        motionSamples: Int
    ) -> DriveScoreConfidence {
        guard usableTraceDuration.isFinite, distanceMiles.isFinite else { return .low }
        if let share = acceptedLocationSampleShare(
            acceptedLocationSamples: acceptedLocationSamples,
            rejectedLocationSamples: rejectedLocationSamples
        ), share < minimumAcceptedLocationSampleShare {
            return .low
        }

        if usableTraceDuration >= highConfidenceUsableTraceDuration,
           distanceMiles >= highConfidenceDistanceMiles,
           acceptedLocationSamples >= highConfidenceAcceptedSamples,
           motionSamples >= highConfidenceMotionSamples {
            return .high
        }
        if usableTraceDuration >= mediumConfidenceUsableTraceDuration,
           distanceMiles >= mediumConfidenceDistanceMiles,
           acceptedLocationSamples >= mediumConfidenceAcceptedSamples,
           motionSamples >= mediumConfidenceMotionSamples {
            return .medium
        }
        return .low
    }

    /// - Parameter usableTraceDuration: Measured continuous-trace time from
    ///   `DriveExperienceEngine`. Omitted only by callers that have no trace to
    ///   measure, where wall-clock duration is the sole available proxy.
    /// - Parameter movingDuration: Time the trace shows the car moving, from
    ///   `movingDuration(for:)`. Omitted when there is no trace, in which case
    ///   only distance counts as exposure.
    static func score(
        duration: TimeInterval,
        distanceMeters: Double,
        events: [DrivingEvent],
        acceptedLocationSamples: Int,
        rejectedLocationSamples: Int,
        motionSamples: Int,
        usableTraceDuration: TimeInterval? = nil,
        movingDuration: TimeInterval? = nil
    ) -> (score: Int, quality: DriveDataQuality) {
        let distanceMiles = distanceMeters.isFinite ? max(0, distanceMeters) / 1_609.344 : 0
        let points = penaltyPoints(
            events: events,
            distanceMiles: distanceMiles,
            movingDuration: movingDuration
        )

        // A trace can never be longer than the drive that produced it, and a
        // caller without a measured trace falls back to wall-clock time.
        let measuredTraceDuration = usableTraceDuration
            .map { max(0, min($0, max(0, duration))) } ?? duration
        let hasValidDurations = duration.isFinite && (usableTraceDuration?.isFinite ?? true)

        return (
            score: scoreValue(forPenaltyPoints: points),
            quality: DriveDataQuality(
                acceptedLocationSamples: acceptedLocationSamples,
                rejectedLocationSamples: rejectedLocationSamples,
                motionSamples: motionSamples,
                confidence: hasValidDurations ? confidence(
                    usableTraceDuration: measuredTraceDuration,
                    distanceMiles: distanceMiles,
                    acceptedLocationSamples: acceptedLocationSamples,
                    rejectedLocationSamples: rejectedLocationSamples,
                    motionSamples: motionSamples
                ) : .low
            )
        )
    }

    // MARK: - Scoring model
    //
    // What is measured: braking and acceleration from GPS speed, cornering from
    // GPS speed and heading, and abrupt phone movement from device motion. The
    // score is a coaching summary of those signals, not a safety rating.

    /// Points an event of this kind costs when it is exactly at its threshold,
    /// at town speed, on a drive with one event per ten exposure miles.
    static func basePenaltyPoints(for kind: DrivingEventKind) -> Double {
        switch kind {
        case .hardBrake: 3.5
        case .rapidAcceleration: 2.5
        case .sharpCorner: 2.5
        case .phoneMovement: 0.75
        }
    }

    /// 0.75 for an event that barely crossed its threshold, 1.0 at 1.2× the
    /// threshold, up to 2.0 for one at twice the threshold or beyond. Events
    /// saved before intensity was recorded count as 1.0.
    static func severityMultiplier(intensity: Double?) -> Double {
        guard let intensity, intensity.isFinite else { return 1 }
        return min(2, max(0.75, 0.75 + (intensity - 1) * 1.25))
    }

    /// The same maneuver matters more the faster the car is going: 0.85 at or
    /// below 20 mph, 1.0 around 35 mph, up to 1.3 at 65 mph and above.
    static func speedMultiplier(kind: DrivingEventKind, speedMetersPerSecond: Double?) -> Double {
        guard kind != .phoneMovement,
              let speed = speedMetersPerSecond, speed.isFinite, speed >= 0 else { return 1 }
        let slow = 9.0, town = 15.5, fast = 29.0
        if speed <= slow { return 0.85 }
        if speed <= town { return 0.85 + (speed - slow) / (town - slow) * 0.15 }
        return min(1.3, 1 + (speed - town) / (fast - town) * 0.3)
    }

    /// A GPS-only speed change that device motion did not confirm is more
    /// likely to be signal noise, so it counts slightly less.
    static func sourceMultiplier(for source: DrivingEventSource) -> Double {
        source == .gpsSpeed ? 0.85 : 1
    }

    static func penaltyPoints(for event: DrivingEvent) -> Double {
        basePenaltyPoints(for: event.kind) *
            severityMultiplier(intensity: event.kind == .phoneMovement ? nil : event.intensity) *
            speedMultiplier(kind: event.kind, speedMetersPerSecond: event.speedMetersPerSecond) *
            sourceMultiplier(for: event.source)
    }

    /// Groups events into maneuvers. Driving events that follow one another
    /// within `maneuverWindow` are one maneuver, charged for the worst event
    /// plus a fraction of the rest. Phone movement is not a driving maneuver
    /// and always stands alone.
    static func maneuvers(from events: [DrivingEvent]) -> [DriveManeuver] {
        let ordered = events.enumerated()
            .filter { $0.element.timestamp.timeIntervalSinceReferenceDate.isFinite }
            .sorted {
                $0.element.timestamp == $1.element.timestamp
                    ? $0.offset < $1.offset
                    : $0.element.timestamp < $1.element.timestamp
            }
            .map(\.element)

        var groups: [[DrivingEvent]] = []
        var current: [DrivingEvent] = []
        for event in ordered {
            guard event.kind != .phoneMovement else {
                groups.append([event])
                continue
            }
            if let first = current.first, let last = current.last,
               event.timestamp.timeIntervalSince(last.timestamp) <= maneuverWindow,
               event.timestamp.timeIntervalSince(first.timestamp) <= maximumManeuverSpan {
                current.append(event)
            } else {
                if !current.isEmpty { groups.append(current) }
                current = [event]
            }
        }
        if !current.isEmpty { groups.append(current) }

        return groups.map { group in
            let weights = group.map(penaltyPoints(for:))
            let worst = weights.max() ?? 0
            let total = weights.reduce(0, +)
            let points = min(
                worst * maximumManeuverMultiplier,
                worst + (total - worst) * secondaryManeuverEventShare
            )
            return DriveManeuver(events: group, penaltyPoints: points)
        }
    }

    /// Miles the event rate is normalized against. Distance, or the time spent
    /// moving when traffic kept the distance short, with a floor for brief trips.
    static func exposureMiles(distanceMiles: Double, movingDuration: TimeInterval?) -> Double {
        let distance = distanceMiles.isFinite ? max(0, distanceMiles) : 0
        let timeMiles = movingDuration
            .flatMap { $0.isFinite ? max(0, $0) / 60 / movingMinutesPerExposureMile : nil } ?? 0
        return max(minimumExposureMiles, distance, timeMiles)
    }

    /// Penalty points per ten exposure miles.
    static func penaltyPoints(
        events: [DrivingEvent],
        distanceMiles: Double,
        movingDuration: TimeInterval? = nil
    ) -> Double {
        let total = maneuvers(from: events).reduce(0) { $0 + $1.penaltyPoints }
        return total * 10 / exposureMiles(distanceMiles: distanceMiles, movingDuration: movingDuration)
    }

    /// Maps penalty points onto 100...`scoreFloor`. Close to one point per
    /// penalty point for a mostly clean drive, flattening as events pile up so
    /// a rough drive and a very rough drive still score differently instead of
    /// both hitting a hard cap.
    static func scoreValue(forPenaltyPoints points: Double) -> Int {
        guard !points.isNaN, points != .infinity else { return Int(scoreFloor) }
        guard points > 0 else { return 100 }
        let range = 100 - scoreFloor
        return Int((100 - range * (1 - exp(-points / range))).rounded())
    }

    /// Penalty points attributed to each kind of event, after maneuver
    /// grouping, for explaining where a score went.
    static func penaltyShare(from events: [DrivingEvent]) -> [DrivingEventKind: Double] {
        var shares: [DrivingEventKind: Double] = [:]
        for maneuver in maneuvers(from: events) {
            let weights = maneuver.events.map(penaltyPoints(for:))
            let total = weights.reduce(0, +)
            guard total > 0 else { continue }
            for (event, weight) in zip(maneuver.events, weights) {
                shares[event.kind, default: 0] += maneuver.penaltyPoints * weight / total
            }
        }
        return shares
    }

    /// Time the saved trace shows the car moving. Uses the same continuous,
    /// plausible segments as the usable-trace measure.
    static func movingDuration(for route: [DriveRoutePoint]) -> TimeInterval {
        DriveExperienceEngine.validTraceSegments(for: route).reduce(0) { total, segment in
            let meanSpeed = (segment.start.speedMetersPerSecond + segment.end.speedMetersPerSecond) / 2
            return meanSpeed >= movingSpeedThresholdMetersPerSecond ? total + segment.duration : total
        }
    }

    private static func normalizedAngle(_ degrees: Double) -> Double {
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped > 180 ? wrapped - 360 : (wrapped < -180 ? wrapped + 360 : wrapped)
    }
}
