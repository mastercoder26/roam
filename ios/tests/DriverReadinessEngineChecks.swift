import CoreLocation
import Foundation

@main
struct DriverReadinessEngineChecks {
    static func main() throws {
        let calendar = utcCalendar()
        let start = makeDate(year: 2026, month: 7, day: 1, hour: 21, minute: 0, calendar: calendar)
        let knownPolyline = "_p~iF~ps|U_ulLnnqC_mqNvxq`@"
        let matchedRoute = [
            coordinate(38.5, -120.2),
            // A nearby accepted GPS segment supplies measurable night/highway
            // mileage; the later points exercise route-overlap matching.
            coordinate(38.5145, -120.2),
            coordinate(40.7, -120.95),
            coordinate(43.252, -126.453)
        ]

        let mergeDemand = demand(.merges, intensity: 0.8, evidence: "Two ramp transitions appear on this route.")
        let nightDemand = demand(.afterDark, intensity: 0.8, evidence: "The full drive falls in the 8 PM–6 AM window.")
        let fastDemand = demand(.fastRoads, intensity: 0.75, evidence: "Most of the route is estimated at 45+ mph.")
        let intersectionDemand = demand(.complexIntersections, intensity: 0.8, evidence: "Several turn instructions are closely spaced.")

        let plannedPracticeCoordinates = RoutePolylineDecoder.decode(knownPolyline)
        let matchingPracticeTrace = interpolatedTrace(plannedPracticeCoordinates)
        expect(
            DriverReadinessEngine.matchesPlannedPracticeRoute(
                plannedPolyline: knownPolyline,
                recordedRoute: routePoints(matchingPracticeTrace, start: start, speedMetersPerSecond: 18)
            ),
            "a local GPS trace that follows most of the planned geometry should verify the practice route"
        )
        expect(
            !DriverReadinessEngine.matchesPlannedPracticeRoute(
                plannedPolyline: knownPolyline,
                recordedRoute: routePoints(offset(matchingPracticeTrace, latitudeBy: 0.02), start: start, speedMetersPerSecond: 18)
            ),
            "an off-route GPS trace must not verify a planned practice route"
        )
        expect(
            !DriverReadinessEngine.matchesPlannedPracticeRoute(
                plannedPolyline: knownPolyline,
                recordedRoute: routePoints(partialTrace(plannedPracticeCoordinates), start: start, speedMetersPerSecond: 18)
            ),
            "a short portion of the planned geometry must not verify the whole practice route"
        )

        let taggedNightDrive = drive(
            startedAt: start,
            miles: 3.2,
            duration: 12 * 60,
            route: routePoints(matchedRoute, start: start, speedMetersPerSecond: 26),
            context: PlannedRouteContext(
                createdAt: start,
                routeDemands: [mergeDemand],
                recordedRouteMatched: true
            )
        )
        let secondQualifyingDrive = drive(
            startedAt: start.addingTimeInterval(-86_400),
            miles: 3.1,
            duration: 11 * 60,
            route: routePoints(matchedRoute, start: start.addingTimeInterval(-86_400), speedMetersPerSecond: 26)
        )
        let lowConfidenceDrive = drive(
            startedAt: start,
            miles: 20,
            duration: 30 * 60,
            confidence: .low,
            route: routePoints(matchedRoute, start: start, speedMetersPerSecond: 26)
        )

        let profile = DriverReadinessEngine.profile(
            from: [taggedNightDrive, secondQualifyingDrive, lowConfidenceDrive],
            configuration: .init(),
            calendar: calendar
        )
        expect(profile.qualifyingDriveCount == 2, "only medium/high-confidence drives should qualify")
        expect(profile.totalMiles > 6 && profile.totalMiles < 7, "low-confidence distance must not contribute to readiness")
        expect(profile.nightMiles > 0, "after-dark route segments should count as night mileage")
        expect(profile.highSpeedMiles > 0, "45+ mph route segments should count as high-speed mileage")
        expect(profile.longestDriveDuration == 12 * 60, "profile should retain the longest qualifying drive")
        expect(profile.taggedExposureCount(for: .merges) == 1, "planned route tags should count after a qualifying drive")

        let route = scoredRoute(
            polyline: knownPolyline,
            demands: [nightDemand, fastDemand, mergeDemand, intersectionDemand],
            durationSeconds: 12 * 60,
            distanceMeters: Int(3.2 * 1_609.344)
        )
        let assessment = DriverReadinessEngine.assess(
            route: route,
            recordedDrives: [taggedNightDrive, secondQualifyingDrive],
            configuration: .init(),
            calendar: calendar
        )
        expect(assessment.verdict == .practiceWithAdult, "a high unmeasured route demand should recommend supervised practice")
        expect(assessment.familiarity.level == .familiar, "matching local GPS traces should make the route familiar")
        expect(insight("merges", in: assessment)?.state == .matched, "a tagged future practice drive should satisfy merge exposure")
        let intersection = insight("complexIntersections", in: assessment)
        expect(intersection?.state == .unmeasured, "untagged complex intersections must remain unmeasured")
        expect(intersection?.detail.lowercased().contains("not yet measured") == true, "unmeasured copy should be explicit")
        expect(intersection?.detail.lowercased().contains("first") == false, "the engine must not claim a first experience")

        let unverifiedTaggedDrive = drive(
            startedAt: start.addingTimeInterval(-172_800),
            miles: 3.3,
            duration: 12 * 60,
            route: routePoints(matchedRoute, start: start.addingTimeInterval(-172_800), speedMetersPerSecond: 26),
            context: PlannedRouteContext(createdAt: start, routeDemands: [mergeDemand])
        )
        let unverifiedProfile = DriverReadinessEngine.profile(
            from: [unverifiedTaggedDrive, secondQualifyingDrive],
            configuration: .init(),
            calendar: calendar
        )
        expect(unverifiedProfile.taggedExposureCount(for: .merges) == 0, "a legacy or unverified route context must not count as merge experience")
        let unverifiedAssessment = DriverReadinessEngine.assess(
            route: route,
            recordedDrives: [unverifiedTaggedDrive, secondQualifyingDrive],
            configuration: .init(),
            calendar: calendar
        )
        expect(insight("merges", in: unverifiedAssessment)?.state == .unmeasured, "unverified tagged drives must remain unmeasured")

        let thinHistory = DriverReadinessEngine.assess(
            route: route,
            recordedDrives: [taggedNightDrive],
            configuration: .init(),
            calendar: calendar
        )
        expect(thinHistory.verdict == .insufficientHistory, "one drive must not produce a readiness recommendation")
        expect(thinHistory.headline == "Need more recorded experience", "thin history should use the honest empty-state headline")

        let routeWithoutDemands = scoredRoute(
            polyline: knownPolyline,
            demands: [],
            durationSeconds: 12 * 60,
            distanceMeters: Int(3.2 * 1_609.344)
        )
        let unavailableDemandAssessment = DriverReadinessEngine.assess(
            route: routeWithoutDemands,
            recordedDrives: [taggedNightDrive, secondQualifyingDrive],
            configuration: .init(),
            calendar: calendar
        )
        expect(unavailableDemandAssessment.verdict == .practiceWithAdult, "missing route-demand data must not produce a generic match")
        expect(
            insight("routeDemandsUnavailable", in: unavailableDemandAssessment)?.state == .informational,
            "missing route-demand data should be described as unavailable rather than guessed"
        )

        let routeDemandJSON = """
        {"id":"fastRoads","title":"Fast roads","intensity":0.72,"level":"HIGH","evidence":"70% is fast.","available":true}
        """.data(using: .utf8)!
        let decodedDemand = try JSONDecoder().decode(RouteDemand.self, from: routeDemandJSON)
        expect(decodedDemand.level == .high, "route demand levels should decode case-insensitively")

        let scoredRouteJSON = """
        {
          "score": 6.2,
          "label": "Hard",
          "reasons": [],
          "breakdown": {"traffic": 0, "highway": 0, "maneuvers": 0, "navDensity": 0, "effort": 0},
          "distanceMeters": 5000,
          "durationSeconds": 600,
          "staticDurationSeconds": 600,
          "trafficDelaySeconds": 0,
          "polyline": "_p~iF~ps|U_ulLnnqC_mqNvxq`@",
          "bounds": {
            "southwest": {"lat": 38.5, "lng": -126.5},
            "northeast": {"lat": 43.3, "lng": -120.1}
          },
          "routeDemands": [
            {"id":"fastRoads","title":"Fast roads","intensity":0.72,"level":"high","evidence":"70% is fast.","available":true}
          ]
        }
        """.data(using: .utf8)!
        let decodedRoute = try JSONDecoder().decode(ScoredRoute.self, from: scoredRouteJSON)
        expect(decodedRoute.routeDemands?.first?.id == "fastRoads", "route demand payloads must decode with scored routes")
        var oldRoutePayload = try JSONSerialization.jsonObject(with: scoredRouteJSON) as! [String: Any]
        oldRoutePayload.removeValue(forKey: "routeDemands")
        let decodedOldRoute = try JSONDecoder().decode(
            ScoredRoute.self,
            from: JSONSerialization.data(withJSONObject: oldRoutePayload)
        )
        expect(decodedOldRoute.routeDemands == nil, "older route responses must remain decodable")

        let savedDrive = RecordedDrive(
            startedAt: start,
            score: taggedNightDrive.score,
            route: taggedNightDrive.route,
            plannedRouteContext: taggedNightDrive.plannedRouteContext
        )
        let savedData = try JSONEncoder().encode(savedDrive)
        let savedObject = try JSONSerialization.jsonObject(with: savedData) as! [String: Any]
        expect(savedObject["plannedRouteContext"] != nil, "new drives should persist their optional practice context")
        let context = savedObject["plannedRouteContext"] as! [String: Any]
        expect(
            Set(context.keys) == Set(["id", "createdAt", "routeDemands", "recordedRouteMatched"]),
            "practice context must contain only privacy-safe demand tags and a match verdict"
        )
        expect(context["recordedRouteMatched"] as? Bool == true, "a verified practice route should persist only its match verdict")

        var legacyContext = context
        legacyContext.removeValue(forKey: "recordedRouteMatched")
        var driveWithLegacyContext = savedObject
        driveWithLegacyContext["plannedRouteContext"] = legacyContext
        let decodedLegacyContextDrive = try JSONDecoder().decode(
            RecordedDrive.self,
            from: JSONSerialization.data(withJSONObject: driveWithLegacyContext)
        )
        expect(decodedLegacyContextDrive.plannedRouteContext?.recordedRouteMatched == nil, "older practice contexts must decode without a match verdict")

        var legacyObject = savedObject
        legacyObject.removeValue(forKey: "plannedRouteContext")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let decodedLegacyDrive = try JSONDecoder().decode(RecordedDrive.self, from: legacyData)
        expect(decodedLegacyDrive.plannedRouteContext == nil, "legacy saved drives must decode without a migration")

        print("DriverReadinessEngine checks passed")
    }

    private static func demand(
        _ kind: RouteDemandKind,
        intensity: Double,
        evidence: String
    ) -> RouteDemand {
        RouteDemand(
            id: kind.rawValue,
            intensity: intensity,
            level: intensity >= 0.67 ? .high : .moderate,
            evidence: evidence,
            available: true
        )
    }

    private static func drive(
        startedAt: Date,
        miles: Double,
        duration: TimeInterval,
        confidence: DriveScoreConfidence = .high,
        route: [DriveRoutePoint],
        context: PlannedRouteContext? = nil
    ) -> RecordedDrive {
        RecordedDrive(
            startedAt: startedAt,
            score: DrivingScore(
                score: 92,
                duration: duration,
                distanceMeters: miles * 1_609.344,
                topSpeedMetersPerSecond: 26,
                events: [],
                motionSamples: 1_500,
                dataQuality: DriveDataQuality(
                    acceptedLocationSamples: 30,
                    rejectedLocationSamples: 0,
                    motionSamples: 1_500,
                    confidence: confidence
                )
            ),
            route: route,
            plannedRouteContext: context
        )
    }

    private static func scoredRoute(
        polyline: String,
        demands: [RouteDemand],
        durationSeconds: Int,
        distanceMeters: Int
    ) -> ScoredRoute {
        ScoredRoute(
            score: 6.5,
            uncalibratedScore: nil,
            label: .hard,
            reasons: [],
            breakdown: DifficultyBreakdown(
                speed: nil,
                merges: nil,
                turns: nil,
                traffic: 0,
                length: nil,
                fatigue: nil,
                weather: nil,
                road: nil,
                highway: 0,
                maneuvers: 0,
                navDensity: 0,
                effort: 0
            ),
            contributions: nil,
            uncertainty: nil,
            hotspots: nil,
            conditions: nil,
            modelVersion: nil,
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
            staticDurationSeconds: durationSeconds,
            trafficDelaySeconds: 0,
            polyline: polyline,
            bounds: RouteBounds(
                southwest: Coordinate(latitude: 38.5, longitude: -126.5),
                northeast: Coordinate(latitude: 43.3, longitude: -120.1)
            ),
            scoreDelta: nil,
            routeDemands: demands
        )
    }

    private static func routePoints(
        _ coordinates: [CLLocationCoordinate2D],
        start: Date,
        speedMetersPerSecond: Double
    ) -> [DriveRoutePoint] {
        coordinates.enumerated().map { index, coordinate in
            DriveRoutePoint(
                timestamp: start.addingTimeInterval(Double(index) * 45),
                coordinate: DriveCoordinate(coordinate),
                speedMetersPerSecond: speedMetersPerSecond
            )
        }
    }

    private static func interpolatedTrace(_ polyline: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard polyline.count > 1 else { return polyline }
        return zip(polyline, polyline.dropFirst()).flatMap { start, end in
            (0...5).map { step in
                let progress = Double(step) / 5
                return coordinate(
                    start.latitude + (end.latitude - start.latitude) * progress,
                    start.longitude + (end.longitude - start.longitude) * progress
                )
            }
        }
    }

    private static func partialTrace(_ polyline: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard let start = polyline.first, polyline.count > 1 else { return polyline }
        let end = polyline[1]
        return (0...6).map { step in
            let progress = Double(step) / 6 * 0.35
            return coordinate(
                start.latitude + (end.latitude - start.latitude) * progress,
                start.longitude + (end.longitude - start.longitude) * progress
            )
        }
    }

    private static func offset(
        _ coordinates: [CLLocationCoordinate2D],
        latitudeBy offset: Double
    ) -> [CLLocationCoordinate2D] {
        coordinates.map { coordinate($0.latitude + offset, $0.longitude) }
    }

    private static func coordinate(_ latitude: Double, _ longitude: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private static func insight(_ id: String, in assessment: DriverReadinessAssessment) -> DriverReadinessInsight? {
        assessment.insights.first { $0.id == id }
    }

    private static func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError("DriverReadinessEngine check failed: \(message)")
        }
    }
}
