import Foundation

@main
struct DriveScoringEngineChecks {
    static func main() {
        let poorGPS = sample(0, speed: 8, accuracy: 70)
        expect(!DriveScoringEngine.accepts(poorGPS), "poor GPS fixes must be rejected")

        let brakeEvents = DriveScoringEngine.detectEvents(
            previous: sample(0, speed: 18),
            current: sample(2, speed: 10),
            nearbyMotionG: 0.22
        )
        expect(brakeEvents.contains { $0.kind == .hardBrake }, "strong deceleration should flag hard braking")
        expect(brakeEvents.contains { $0.source == .fused }, "motion should corroborate GPS when nearby")

        let cornerEvents = DriveScoringEngine.detectEvents(
            previous: sample(0, speed: 12, course: 5),
            current: sample(2, speed: 12, course: 80),
            nearbyMotionG: nil
        )
        expect(cornerEvents.contains { $0.kind == .sharpCorner }, "rapid course changes at driving speed should flag a sharp corner")

        let events = [
            DrivingEvent(kind: .hardBrake, timestamp: Date(), source: .gpsSpeed),
            DrivingEvent(kind: .rapidAcceleration, timestamp: Date(), source: .gpsSpeed),
        ]
        let shortTrip = DriveScoringEngine.score(
            duration: 45,
            distanceMeters: 400,
            events: events,
            acceptedLocationSamples: 3,
            rejectedLocationSamples: 1,
            motionSamples: 100
        )
        expect(shortTrip.quality.confidence == .low, "short trips must be marked preliminary")

        let sustainedTrip = DriveScoringEngine.score(
            duration: 360,
            distanceMeters: 6_437.376,
            events: events,
            acceptedLocationSamples: 30,
            rejectedLocationSamples: 2,
            motionSamples: 1_400
        )
        expect(sustainedTrip.quality.confidence == .high, "sustained high-quality trips should earn high confidence")
        expect(sustainedTrip.score > shortTrip.score, "short-trip distance floor should avoid over-penalizing sparse data")

        print("DriveScoringEngine checks passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError("DriveScoringEngine check failed: \(message)")
        }
    }

    private static func sample(
        _ seconds: TimeInterval,
        speed: Double,
        course: Double? = 0,
        accuracy: Double = 8
    ) -> DriveLocationSample {
        DriveLocationSample(
            timestamp: Date(timeIntervalSinceReferenceDate: seconds),
            speedMetersPerSecond: speed,
            courseDegrees: course,
            horizontalAccuracyMeters: accuracy
        )
    }
}
