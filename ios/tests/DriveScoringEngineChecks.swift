import CoreLocation
import Foundation

@main
struct DriveScoringEngineChecks {
    static func main() {
        let poorGPS = sample(0, speed: 8, accuracy: 70)
        expect(!DriveScoringEngine.accepts(poorGPS), "poor GPS fixes must be rejected")
        expect(!DriveScoringEngine.accepts(sample(0, speed: -1)), "negative GPS speed must be rejected")
        expect(!DriveScoringEngine.accepts(sample(0, speed: .infinity)), "non-finite GPS speed must be rejected")
        for invalidDuration in [Double.infinity, Double.nan, -Double.infinity] {
            expect(
                DriveScoringEngine.score(duration: 600, distanceMeters: 6_437.376, events: [], acceptedLocationSamples: 40, rejectedLocationSamples: 0, motionSamples: 2_000, usableTraceDuration: invalidDuration).quality.confidence == .low,
                "invalid trace duration must remain preliminary before normalization"
            )
            expect(
                DriveScoringEngine.score(duration: invalidDuration, distanceMeters: 6_437.376, events: [], acceptedLocationSamples: 40, rejectedLocationSamples: 0, motionSamples: 2_000, usableTraceDuration: 600).quality.confidence == .low,
                "invalid drive duration must remain preliminary even with a finite trace"
            )
        }
        expect(
            DriveScoringEngine.acceptedLocationSampleShare(acceptedLocationSamples: Int.max, rejectedLocationSamples: Int.max) == 0.5,
            "sample-share calculation must not overflow for large counters"
        )
        for invalidCourse in [-1.0, 360.0, Double.infinity] {
            expect(
                DriveScoringEngine.detectEvents(previous: sample(0, speed: 12, course: invalidCourse), current: sample(2, speed: 12, course: 80), nearbyMotionG: nil).isEmpty,
                "invalid course readings must not produce corner events"
            )
        }
        expect(
            DriveScoringEngine.detectEvents(previous: sample(0, speed: 12, course: 5, courseAccuracy: -1), current: sample(2, speed: 12, course: 80), nearbyMotionG: nil).isEmpty,
            "Core Location's unavailable course accuracy must not produce corner events"
        )
        expect(
            DriveScoringEngine.score(duration: 600, distanceMeters: .infinity, events: [], acceptedLocationSamples: 40, rejectedLocationSamples: 0, motionSamples: 2_000).quality.confidence == .low,
            "invalid distance must not earn strong confidence"
        )

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
        expect(!DriveScoringEngine.shouldFlagPhoneMovement(0.64), "motion below the abrupt-movement peak must not flag phone movement")
        expect(DriveScoringEngine.shouldFlagPhoneMovement(0.65), "only a clearly abrupt single-sample peak should pass the legacy threshold helper")

        var phoneDetector = PhoneMovementDetector()
        expect(
            !phoneDetector.ingest(
                motion(0, acceleration: 1.1, rotation: 0.1),
                vehicleSpeedMetersPerSecond: 14,
                hasRecentAcceptedGPS: true
            ),
            "a rough-road acceleration spike without phone rotation must not flag handling"
        )
        expect(
            !phoneDetector.ingest(
                motion(0.1, acceleration: 0.7, rotation: 1.4),
                vehicleSpeedMetersPerSecond: 0,
                hasRecentAcceptedGPS: true
            ),
            "phone setup or movement while stopped must not create a driving event"
        )
        expect(
            !phoneDetector.ingest(
                motion(0.2, acceleration: 0.7, rotation: 1.4),
                vehicleSpeedMetersPerSecond: 14,
                hasRecentAcceptedGPS: false
            ),
            "motion before a fresh accepted GPS fix must not create a driving event"
        )

        var smallMovementDetector = PhoneMovementDetector()
        for seconds in stride(from: 0.0, through: 0.3, by: 0.05) {
            expect(
                !smallMovementDetector.ingest(
                    motion(seconds, acceleration: 0.20, rotation: 0.45),
                    vehicleSpeedMetersPerSecond: 14,
                    hasRecentAcceptedGPS: true
                ),
                "repeated small phone movement must remain below the coaching-event threshold"
            )
        }

        expect(
            !phoneDetector.ingest(
                motion(1.00, acceleration: 0.42, rotation: 0.85),
                vehicleSpeedMetersPerSecond: 14,
                hasRecentAcceptedGPS: true
            ),
            "one sustained-pattern sample is not enough evidence"
        )
        expect(
            !phoneDetector.ingest(
                motion(1.05, acceleration: 0.43, rotation: 0.90),
                vehicleSpeedMetersPerSecond: 14,
                hasRecentAcceptedGPS: true
            ),
            "two sustained-pattern samples are not enough evidence"
        )
        expect(
            phoneDetector.ingest(
                motion(1.12, acceleration: 0.72, rotation: 1.30),
                vehicleSpeedMetersPerSecond: 14,
                hasRecentAcceptedGPS: true
            ),
            "a sustained acceleration-and-rotation burst while moving should flag one coaching event"
        )
        expect(
            !phoneDetector.ingest(
                motion(1.18, acceleration: 0.75, rotation: 1.35),
                vehicleSpeedMetersPerSecond: 14,
                hasRecentAcceptedGPS: true
            ),
            "a continuous movement burst must remain latched instead of creating repeated events"
        )
        expect(
            !phoneDetector.ingest(
                motion(1.25, acceleration: 0.08, rotation: 0.10),
                vehicleSpeedMetersPerSecond: 14,
                hasRecentAcceptedGPS: true
            ),
            "a quiet sample should only re-arm the detector, not create an event"
        )

        let motionTimestamp = Date(timeIntervalSinceReferenceDate: 10)
        let isolatedMotion = DriveScoringEngine.corroboratingMotionG(
            from: [motion(10, acceleration: 0.8, rotation: 1.2)],
            near: motionTimestamp
        )
        expect(isolatedMotion == nil, "one motion spike must not upgrade a GPS event to fused provenance")
        let sustainedMotion = DriveScoringEngine.corroboratingMotionG(
            from: [
                motion(9.9, acceleration: 0.15, rotation: 0.1),
                motion(10.0, acceleration: 0.22, rotation: 0.1),
                motion(10.1, acceleration: 0.24, rotation: 0.1)
            ],
            near: motionTimestamp
        )
        expect(sustainedMotion == 0.22, "motion corroboration should use the robust median, not a peak spike")

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

        let scoringBase = Date(timeIntervalSince1970: 1_800_000_000)
        func scoredEvent(
            _ kind: DrivingEventKind,
            at offset: TimeInterval,
            source: DrivingEventSource = .fused,
            intensity: Double? = nil,
            speed: Double? = nil
        ) -> DrivingEvent {
            DrivingEvent(
                kind: kind, timestamp: scoringBase.addingTimeInterval(offset), source: source,
                intensity: intensity, speedMetersPerSecond: speed
            )
        }
        func tripScore(_ events: [DrivingEvent], miles: Double = 5, movingDuration: TimeInterval? = nil) -> Int {
            DriveScoringEngine.score(
                duration: 900, distanceMeters: miles * 1_609.344, events: events,
                acceptedLocationSamples: 100, rejectedLocationSamples: 0, motionSamples: 2_000,
                movingDuration: movingDuration
            ).score
        }

        let manyEvents = (0..<100).map { scoredEvent(.hardBrake, at: Double($0) * 30, source: .gpsSpeed) }
        let boundedScore = tripScore(manyEvents, miles: 1)
        expect(
            boundedScore >= Int(DriveScoringEngine.scoreFloor) && boundedScore < 40,
            "an extreme drive must stay at or above the floor without being rounded up to a usable score"
        )
        let fewerEvents = Array(manyEvents.prefix(12))
        expect(
            tripScore(fewerEvents, miles: 1) > boundedScore,
            "the score must keep separating bad drives from worse ones instead of flattening at a cap"
        )
        expect(tripScore([]) == 100, "a drive with no detected events scores 100")

        expect(
            tripScore([scoredEvent(.hardBrake, at: 0, intensity: 1.05)]) >
                tripScore([scoredEvent(.hardBrake, at: 0, intensity: 1.8)]),
            "a barely-over-threshold brake must cost less than a severe one"
        )
        expect(
            tripScore([scoredEvent(.hardBrake, at: 0, speed: 6)]) >
                tripScore([scoredEvent(.hardBrake, at: 0, speed: 30)]),
            "the same maneuver must cost more at highway speed than in a parking lot"
        )
        expect(
            DriveScoringEngine.penaltyPoints(for: scoredEvent(.hardBrake, at: 0, source: .gpsSpeed)) <
                DriveScoringEngine.penaltyPoints(for: scoredEvent(.hardBrake, at: 0, source: .fused)),
            "an event device motion did not confirm must count less than a corroborated one"
        )
        expect(
            DriveScoringEngine.penaltyPoints(for: scoredEvent(.hardBrake, at: 0, intensity: .infinity, speed: .nan)) ==
                DriveScoringEngine.penaltyPoints(for: scoredEvent(.hardBrake, at: 0)),
            "corrupt severity or speed must fall back to a typical event"
        )
        expect(
            DriveScoringEngine.penaltyPoints(for: scoredEvent(.phoneMovement, at: 0, intensity: 2, speed: 30)) ==
                DriveScoringEngine.penaltyPoints(for: scoredEvent(.phoneMovement, at: 0)),
            "phone movement is not a driving maneuver and must not scale with speed or severity"
        )

        let oneManeuver = [scoredEvent(.hardBrake, at: 0), scoredEvent(.sharpCorner, at: 2), scoredEvent(.hardBrake, at: 5)]
        let separateManeuvers = [scoredEvent(.hardBrake, at: 0), scoredEvent(.sharpCorner, at: 120), scoredEvent(.hardBrake, at: 240)]
        expect(DriveScoringEngine.maneuvers(from: oneManeuver).count == 1, "events seconds apart are one maneuver")
        expect(DriveScoringEngine.maneuvers(from: separateManeuvers).count == 3, "events minutes apart are separate maneuvers")
        expect(
            tripScore(oneManeuver) > tripScore(separateManeuvers),
            "one maneuver that trips several detectors must not be charged as several maneuvers"
        )
        expect(
            tripScore(oneManeuver) <= tripScore([scoredEvent(.hardBrake, at: 0)]),
            "extra events in a maneuver must never make it cheaper"
        )
        expect(
            tripScore(oneManeuver.reversed()) == tripScore(oneManeuver),
            "the score must not depend on the order events are stored in"
        )
        let chained = (0..<20).map { scoredEvent(.hardBrake, at: Double($0) * 5) }
        expect(
            DriveScoringEngine.maneuvers(from: chained).count > 1,
            "a long run of events must not chain into a single cheap maneuver"
        )
        expect(
            DriveScoringEngine.maneuvers(from: [scoredEvent(.phoneMovement, at: 0), scoredEvent(.phoneMovement, at: 1)]).count == 2,
            "phone movement is never folded into a driving maneuver"
        )

        let cityEvents = [scoredEvent(.hardBrake, at: 0), scoredEvent(.hardBrake, at: 200), scoredEvent(.hardBrake, at: 400)]
        expect(
            tripScore(cityEvents, miles: 2, movingDuration: 30 * 60) > tripScore(cityEvents, miles: 2),
            "slow city driving is exposure too: time moving must count, not only miles"
        )
        expect(
            tripScore(cityEvents, miles: 2, movingDuration: .nan) == tripScore(cityEvents, miles: 2) &&
                tripScore(cityEvents, miles: 2, movingDuration: -50) == tripScore(cityEvents, miles: 2),
            "an invalid moving duration must be ignored"
        )
        expect(
            DriveScoringEngine.scoreValue(forPenaltyPoints: .infinity) == Int(DriveScoringEngine.scoreFloor) &&
                DriveScoringEngine.scoreValue(forPenaltyPoints: .nan) == Int(DriveScoringEngine.scoreFloor) &&
                DriveScoringEngine.scoreValue(forPenaltyPoints: -5) == 100,
            "non-finite penalties must never produce a perfect or out-of-range score"
        )

        let legacyEventJSON = Data("""
        {"id":"7C0B7C8E-4B8E-4C56-9B7B-0C1D2E3F4A5B","kind":"hardBrake","timestamp":700000000,"source":"GPS speed"}
        """.utf8)
        let legacyEvent = try? JSONDecoder().decode(DrivingEvent.self, from: legacyEventJSON)
        expect(
            legacyEvent != nil && legacyEvent?.intensity == nil && legacyEvent?.speedMetersPerSecond == nil,
            "events saved before severity was recorded must still decode"
        )
        let detailedEvent = scoredEvent(.sharpCorner, at: 0, intensity: 1.4, speed: 18)
        let detailedRoundTrip = try? JSONDecoder().decode(DrivingEvent.self, from: JSONEncoder().encode(detailedEvent))
        expect(detailedRoundTrip == detailedEvent, "severity and speed must round-trip")
        expect(
            detailedEvent.replacingCoordinate(with: nil).intensity == 1.4,
            "redacting an event's location must keep its severity"
        )

        let slowTightTurn = DriveScoringEngine.detectEvents(
            previous: DriveLocationSample(timestamp: scoringBase, speedMetersPerSecond: 6.5, courseDegrees: 0, courseAccuracyDegrees: 5, horizontalAccuracyMeters: 5),
            current: DriveLocationSample(timestamp: scoringBase.addingTimeInterval(1), speedMetersPerSecond: 6.5, courseDegrees: 30, courseAccuracyDegrees: 5, horizontalAccuracyMeters: 5),
            nearbyMotionG: nil
        )
        expect(
            !slowTightTurn.contains { $0.kind == .sharpCorner },
            "an ordinary slow intersection turn is not a sharp corner"
        )
        let fastSweep = DriveScoringEngine.detectEvents(
            previous: DriveLocationSample(timestamp: scoringBase, speedMetersPerSecond: 25, courseDegrees: 0, courseAccuracyDegrees: 5, horizontalAccuracyMeters: 5),
            current: DriveLocationSample(timestamp: scoringBase.addingTimeInterval(1), speedMetersPerSecond: 25, courseDegrees: 15, courseAccuracyDegrees: 5, horizontalAccuracyMeters: 5),
            nearbyMotionG: nil
        )
        expect(
            fastSweep.contains { $0.kind == .sharpCorner && ($0.intensity ?? 0) > 1 },
            "a fast curve with high lateral force is a sharp corner even at a modest turn rate"
        )

        // A 45-minute drive whose GPS was almost entirely unusable must not be
        // presented as a strong sample just because the clock kept running.
        let starvedTrip = DriveScoringEngine.score(
            duration: 2_700,
            distanceMeters: 3_479,
            events: [],
            acceptedLocationSamples: 27,
            rejectedLocationSamples: 4_000,
            motionSamples: 54_000
        )
        expect(
            starvedTrip.quality.confidence == .low,
            "a drive where nearly every GPS fix was rejected must stay preliminary"
        )
        let starvedScore = DrivingScore(
            score: starvedTrip.score, duration: 2_700, distanceMeters: 3_479,
            topSpeedMetersPerSecond: 12, events: [], motionSamples: 54_000,
            dataQuality: starvedTrip.quality
        )
        expect(starvedScore.grade == "Preliminary", "a starved GPS trace must be graded Preliminary, not Excellent")
        expect(
            !starvedScore.summary.contains("sustained GPS"),
            "a starved GPS trace must not claim it is based on sustained GPS data"
        )
        expect(
            !DriverReadinessEngine.qualifies(
                RecordedDrive(startedAt: Date(), score: starvedScore, route: [])
            ),
            "a starved GPS trace must not count as readiness evidence"
        )

        // Same samples, but the usable trace is short: wall-clock duration must
        // not be what earns high confidence.
        let suspendedTrip = DriveScoringEngine.score(
            duration: 2_700,
            distanceMeters: 6_437.376,
            events: [],
            acceptedLocationSamples: 40,
            rejectedLocationSamples: 0,
            motionSamples: 54_000,
            usableTraceDuration: 130
        )
        expect(
            suspendedTrip.quality.confidence == .medium,
            "confidence must key off measured trace time, not the drive's wall-clock length"
        )
        expect(
            DriveScoringEngine.score(
                duration: 2_700, distanceMeters: 6_437.376, events: [],
                acceptedLocationSamples: 40, rejectedLocationSamples: 0,
                motionSamples: 54_000, usableTraceDuration: 20
            ).quality.confidence == .low,
            "a drive with almost no usable trace must be preliminary"
        )
        expect(
            DriveScoringEngine.acceptedLocationSampleShare(
                acceptedLocationSamples: 0, rejectedLocationSamples: 0
            ) == nil,
            "a motion-only drive has no delivered fixes to judge as sparse"
        )
        expect(
            DriveScoringEngine.score(
                duration: 600, distanceMeters: 6_437.376, events: [],
                acceptedLocationSamples: 0, rejectedLocationSamples: 0, motionSamples: 54_000
            ).quality.confidence == .low,
            "a drive with no GPS fixes at all cannot be a strong sample"
        )

        // Background suspension must report its own cause, not revoked access.
        let suspendedQuality = DriveDataQuality(
            acceptedLocationSamples: 27, rejectedLocationSamples: 0, motionSamples: 54_000,
            confidence: .low, recordingSuspendedInBackground: true
        )
        let revokedQuality = DriveDataQuality(
            acceptedLocationSamples: 27, rejectedLocationSamples: 0, motionSamples: 54_000,
            confidence: .low, locationInterruptedMidDrive: true
        )
        expect(
            suspendedQuality.summary != revokedQuality.summary,
            "a background suspension must not be described as revoked location access"
        )
        expect(
            suspendedQuality.summary.contains("suspended"),
            "a background suspension must say the app was suspended"
        )
        expect(
            DriveDataQuality(
                acceptedLocationSamples: 27, rejectedLocationSamples: 0, motionSamples: 54_000,
                confidence: .low
            ).recordingSuspendedInBackground == nil,
            "an ordinary drive must not claim it was suspended"
        )
        let legacyQualityJSON = Data(
            #"{"acceptedLocationSamples":30,"rejectedLocationSamples":2,"motionSamples":1400,"confidence":"high"}"#.utf8
        )
        let legacyQuality = try! JSONDecoder().decode(DriveDataQuality.self, from: legacyQualityJSON)
        expect(
            legacyQuality.recordingSuspendedInBackground == nil && legacyQuality.confidence == .high,
            "drives saved before the suspension signal existed must still decode"
        )

        // The decode path is the untrusted path: it must clamp exactly as the
        // designated initializer does.
        let hostileExposureJSON = Data(
            #"{"demandID":"fastRoads","demandIntensity":5,"coveredShare":9,"routeShare":-4,"recordedAt":0}"#.utf8
        )
        let decodedExposure = try! JSONDecoder().decode(VerifiedDemandExposure.self, from: hostileExposureJSON)
        expect(decodedExposure.demandIntensity == 1, "decoded demand intensity must be clamped to 1")
        expect(decodedExposure.coveredShare == 1, "decoded covered share must be clamped to 1")
        expect(decodedExposure.routeShare == 0, "decoded route share must be clamped to 0")
        let roundTrippedExposure = try! JSONDecoder().decode(
            VerifiedDemandExposure.self,
            from: try! JSONEncoder().encode(
                VerifiedDemandExposure(
                    demandID: "fastRoads", demandIntensity: 0.5, coveredShare: 0.25,
                    routeShare: 0.75, recordedAt: Date(timeIntervalSinceReferenceDate: 0)
                )
            )
        )
        expect(
            roundTrippedExposure.demandID == "fastRoads" && roundTrippedExposure.coveredShare == 0.25,
            "saved exposures must keep round-tripping through their existing key names"
        )

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

    private static func motion(
        _ seconds: TimeInterval,
        acceleration: Double,
        rotation: Double
    ) -> DriveMotionSample {
        DriveMotionSample(
            timestamp: Date(timeIntervalSinceReferenceDate: seconds),
            horizontalAccelerationG: acceleration,
            rotationRateRadiansPerSecond: rotation
        )
    }
}
