import CoreLocation
import Foundation

@main
struct DriveScoringEngineChecks {
    static func main() {
        let poorGPS = sample(0, speed: 8, accuracy: 70)
        expect(!DriveScoringEngine.accepts(poorGPS), "poor GPS fixes must be rejected")
        expect(!DriveScoringEngine.accepts(sample(0, speed: -1)), "negative GPS speed must be rejected")

        let stationaryBrake = DriveScoringEngine.detectEvents(
            previous: sample(0, speed: 3.9), current: sample(2, speed: 0), nearbyMotionG: 0.6
        )
        expect(!stationaryBrake.contains { $0.kind == .hardBrake }, "low-speed stopping must not be called hard braking")

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

        let wraparoundCorner = DriveScoringEngine.detectEvents(
            previous: sample(0, speed: 12, course: 350), current: sample(2, speed: 12, course: 70), nearbyMotionG: nil
        )
        expect(wraparoundCorner.contains { $0.kind == .sharpCorner }, "course wraparound must preserve a real sharp corner")

        let unreliableCourseEvents = DriveScoringEngine.detectEvents(
            previous: sample(0, speed: 12, course: 5, courseAccuracy: 80),
            current: sample(2, speed: 12, course: 80, courseAccuracy: 80),
            nearbyMotionG: nil
        )
        expect(!unreliableCourseEvents.contains { $0.kind == .sharpCorner }, "poor compass accuracy must not create sharp-corner events")

        expect(
            !DriveScoringEngine.isPlausibleTransition(
                previous: sample(0, speed: 10),
                current: sample(2, speed: 10),
                distanceMeters: 2_000
            ),
            "impossible GPS distance jumps must be rejected"
        )
        expect(
            !DriveScoringEngine.isPlausibleTransition(
                previous: sample(0, speed: 10), current: sample(0.2, speed: 10), distanceMeters: 2
            ),
            "sub-second location duplicates must not create maneuvers or distance"
        )
        expect(
            !DriveScoringEngine.isPlausibleTransition(
                previous: sample(0, speed: 10), current: sample(8, speed: 10), distanceMeters: 80
            ),
            "long location gaps must not be joined into a route segment"
        )
        expect(
            DriveScoringEngine.isPlausibleTransition(
                previous: sample(0, speed: 20), current: sample(2, speed: 20), distanceMeters: 60
            ),
            "normal automotive movement should remain accepted"
        )
        expect(!DriveScoringEngine.shouldFlagPhoneMovement(0.47), "motion below threshold must not flag phone movement")
        expect(DriveScoringEngine.shouldFlagPhoneMovement(0.48), "motion at threshold should flag phone movement")

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

        let manyEvents = Array(repeating: DrivingEvent(kind: .hardBrake, timestamp: Date(), source: .gpsSpeed), count: 100)
        let boundedScore = DriveScoringEngine.score(
            duration: 900, distanceMeters: 1_609.344, events: manyEvents,
            acceptedLocationSamples: 100, rejectedLocationSamples: 0, motionSamples: 2_000
        )
        expect(boundedScore.score == 45, "penalties must remain capped instead of producing unusable scores")

        let encoded = try! JSONEncoder().encode(RecordedDrive(startedAt: Date(), score: DrivingScore(
            score: 90, duration: 120, distanceMeters: 1_000, topSpeedMetersPerSecond: 12,
            events: events, motionSamples: 300, dataQuality: sustainedTrip.quality
        ), route: [DriveRoutePoint(timestamp: Date(), coordinate: DriveCoordinate(CLLocationCoordinate2D(latitude: 1, longitude: 2)), speedMetersPerSecond: 8)]))
        expect((try? JSONDecoder().decode(RecordedDrive.self, from: encoded)) != nil, "saved drives must round-trip through local persistence")

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
        courseAccuracy: Double? = 10,
        accuracy: Double = 8
    ) -> DriveLocationSample {
        DriveLocationSample(
            timestamp: Date(timeIntervalSinceReferenceDate: seconds),
            speedMetersPerSecond: speed,
            courseDegrees: course,
            courseAccuracyDegrees: courseAccuracy,
            horizontalAccuracyMeters: accuracy
        )
    }
}
