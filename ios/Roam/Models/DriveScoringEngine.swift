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

    init(
        acceptedLocationSamples: Int,
        rejectedLocationSamples: Int,
        motionSamples: Int,
        confidence: DriveScoreConfidence,
        placementQuality: PhonePlacementAssessment? = nil
    ) {
        self.acceptedLocationSamples = acceptedLocationSamples
        self.rejectedLocationSamples = rejectedLocationSamples
        self.motionSamples = motionSamples
        self.confidence = confidence
        self.placementQuality = placementQuality
    }

    var summary: String {
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
    static let sharpCornerDegreesPerSecond = 28.0
    static let highMotionThresholdG = PhoneMovementDetector.peakAccelerationThresholdG

    static func accepts(_ sample: DriveLocationSample) -> Bool {
        sample.horizontalAccuracyMeters > 0 &&
            sample.horizontalAccuracyMeters <= maximumLocationAccuracyMeters &&
            sample.speedMetersPerSecond >= 0
    }

    static func isPlausibleTransition(
        previous: DriveLocationSample,
        current: DriveLocationSample,
        distanceMeters: Double
    ) -> Bool {
        guard accepts(previous), accepts(current), distanceMeters >= 0 else { return false }
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
        let motionCorroborates = (nearbyMotionG ?? 0) >= 0.18
        let source: DrivingEventSource = motionCorroborates ? .fused : .gpsSpeed
        var events: [DetectedDrivingEvent] = []

        // GPS-derived longitudinal acceleration is our primary maneuver signal.
        // Motion corroboration raises provenance, but GPS remains usable when a
        // phone is loosely mounted or motion sampling is unavailable.
        if previous.speedMetersPerSecond >= 4, acceleration <= hardBrakeThreshold {
            events.append(DetectedDrivingEvent(kind: .hardBrake, source: source))
        } else if current.speedMetersPerSecond >= 4, acceleration >= rapidAccelerationThreshold {
            events.append(DetectedDrivingEvent(kind: .rapidAcceleration, source: source))
        }

        if current.speedMetersPerSecond >= 6,
           let previousCourse = previous.courseDegrees,
           let currentCourse = current.courseDegrees,
           let previousCourseAccuracy = previous.courseAccuracyDegrees,
           let currentCourseAccuracy = current.courseAccuracyDegrees,
           previousCourseAccuracy <= maximumCourseAccuracyDegrees,
           currentCourseAccuracy <= maximumCourseAccuracyDegrees {
            let courseRate = abs(normalizedAngle(currentCourse - previousCourse)) / elapsed
            if courseRate >= sharpCornerDegreesPerSecond {
                events.append(DetectedDrivingEvent(kind: .sharpCorner, source: source))
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
            .filter { abs($0.timestamp.timeIntervalSince(timestamp)) <= window }
            .map(\.horizontalAccelerationG)
            .sorted()
        guard values.count >= 3 else { return nil }
        return values[values.count / 2]
    }

    static func shouldFlagPhoneMovement(_ horizontalAccelerationG: Double) -> Bool {
        horizontalAccelerationG >= highMotionThresholdG
    }

    static func score(
        duration: TimeInterval,
        distanceMeters: Double,
        events: [DrivingEvent],
        acceptedLocationSamples: Int,
        rejectedLocationSamples: Int,
        motionSamples: Int
    ) -> (score: Int, quality: DriveDataQuality) {
        let distanceMiles = distanceMeters / 1_609.344
        // Use a 3-mile floor so a single event in a brief trip does not turn
        // into a misleadingly severe grade. The confidence label handles the
        // remaining uncertainty explicitly.
        let normalizedMiles = max(3, distanceMiles)
        let perTenMiles = 10 / normalizedMiles

        let hardBrakes = Double(events.filter { $0.kind == .hardBrake }.count) * perTenMiles
        let rapidAcceleration = Double(events.filter { $0.kind == .rapidAcceleration }.count) * perTenMiles
        let sharpCorners = Double(events.filter { $0.kind == .sharpCorner }.count) * perTenMiles
        let phoneMovement = Double(events.filter { $0.kind == .phoneMovement }.count) * perTenMiles

        let penalty = min(
            55,
            hardBrakes * 3.5 +
                rapidAcceleration * 2.5 +
                sharpCorners * 2.25 +
                phoneMovement * 0.75
        )

        let confidence: DriveScoreConfidence
        if duration >= 300, distanceMiles >= 2, acceptedLocationSamples >= 24, motionSamples >= 1_200 {
            confidence = .high
        } else if duration >= 90, distanceMiles >= 0.5, acceptedLocationSamples >= 8, motionSamples >= 240 {
            confidence = .medium
        } else {
            confidence = .low
        }

        return (
            score: max(20, Int((100 - penalty).rounded())),
            quality: DriveDataQuality(
                acceptedLocationSamples: acceptedLocationSamples,
                rejectedLocationSamples: rejectedLocationSamples,
                motionSamples: motionSamples,
                confidence: confidence
            )
        )
    }

    private static func normalizedAngle(_ degrees: Double) -> Double {
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped > 180 ? wrapped - 360 : (wrapped < -180 ? wrapped + 360 : wrapped)
    }
}
