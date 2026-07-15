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
}

enum DrivingEventSource: String {
    case gpsSpeed = "GPS speed"
    case fused = "GPS + motion"
    case deviceMotion = "Device motion"
}

struct DetectedDrivingEvent {
    let kind: DrivingEventKind
    let source: DrivingEventSource
}

enum DriveScoreConfidence: String {
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

struct DriveDataQuality {
    let acceptedLocationSamples: Int
    let rejectedLocationSamples: Int
    let motionSamples: Int
    let confidence: DriveScoreConfidence

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
    static let highMotionThresholdG = 0.48

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
