import CoreLocation
import Foundation

@main
struct RoutePracticeEnginesChecks {
    static func main() throws {
        let calendar = utcCalendar()
        let referenceDate = makeDate(2026, 7, 17, 18, 0, calendar: calendar)
        let configuration = DriverReadinessEngine.Configuration(
            minimumQualifyingDuration: 2,
            minimumQualifyingMiles: 0.01,
            minimumHistoryDriveCount: 3,
            minimumHistoryDayCount: 3,
            minimumHistoryMiles: 0.04,
            minimumHistoryTraceDuration: 5,
            minimumRecentQualityMiles: 0.01,
            minimumRecentHistoryMiles: 0.01,
            minimumRecentHistoryDriveCount: 1,
            recentWindowDays: 90,
            staleExperienceDays: 180,
            experienceHalfLifeDays: 120
        )

        let steadyHistory = (1...3).map {
            drive(
                startedAt: referenceDate.addingTimeInterval(TimeInterval(-$0 * 86_400)),
                score: 92
            )
        }
        let lowQualityHistory = (1...3).map {
            drive(
                startedAt: referenceDate.addingTimeInterval(TimeInterval(-$0 * 86_400)),
                score: 60
            )
        }

        let primary = route(
            polyline: "primary-route",
            score: 6.5,
            duration: 760,
            demands: [demand(.afterDark, intensity: 0.10, level: .low)]
        )
        let hardAlternate = route(
            polyline: "hard-alternate",
            score: 4.0,
            duration: 620,
            demands: [demand(.merges, intensity: 0.90, level: .high)]
        )
        let unavailableAlternate = route(
            polyline: "unavailable-alternate",
            score: 7.5,
            duration: 700,
            demands: [
                RouteDemand(
                    id: RouteDemandKind.merges.rawValue,
                    intensity: 0.95,
                    level: .high,
                    evidence: "Merge data was unavailable.",
                    available: false
                )
            ]
        )

        let ranked = RouteChoiceRankingEngine.rank(
            primaryRoute: primary,
            alternateRoutes: [hardAlternate, unavailableAlternate],
            recordedDrives: steadyHistory,
            configuration: configuration,
            calendar: calendar,
            referenceDate: referenceDate
        )
        expect(!ranked.comparisonLimitedByHistory, "enough qualifying history should enable readiness ranking")
        expect(ranked.initialSelectedRouteID == primary.id, "the primary route must remain selected by default")
        expect(ranked.choices.first?.route.id == primary.id, "a matched route should outrank an easier but unmeasured high-demand route")
        expect(ranked.bestFitRouteID == primary.id, "the first matched route should receive the best-fit designation")
        expect(ranked.lowestDifficultyRouteID == hardAlternate.id, "the lowest numeric route difficulty should remain visible separately")
        expect(
            ranked.choice(for: primary.id)?.badges == [.bestFit],
            "the matching route should receive the best-fit badge"
        )
        expect(
            ranked.choice(for: hardAlternate.id)?.badges == [.lowestDifficulty],
            "the easier alternate should keep its lowest-difficulty badge when it differs from best fit"
        )
        expect(
            ranked.choice(for: unavailableAlternate.id)?.meaningfulGapCount == 0,
            "unavailable route enrichment must not become a readiness gap"
        )
        expect(
            !ranked.choice(for: unavailableAlternate.id)!.badges.contains(.bestFit),
            "unavailable route enrichment must not receive a personalized best-fit claim"
        )
        expect(
            ranked.selectedRouteID(preserving: hardAlternate.id) == hardAlternate.id,
            "a user-selected alternate must survive a ranking refresh"
        )
        expect(
            ranked.selectedRouteID(preserving: "missing-route") == primary.id,
            "a no-longer-returned route should fall back to the primary selection"
        )

        let limited = RouteChoiceRankingEngine.rank(
            primaryRoute: primary,
            alternateRoutes: [hardAlternate],
            recordedDrives: [],
            configuration: configuration,
            calendar: calendar,
            referenceDate: referenceDate
        )
        expect(limited.comparisonLimitedByHistory, "empty history should surface an honest comparison limitation")
        expect(limited.bestFitRouteID == nil, "thin history must never nominate a best experience fit")
        expect(limited.choices.first?.route.id == hardAlternate.id, "thin history should order routes by difficulty")

        let tiedAlternate = route(
            polyline: "tied-alternate",
            score: primary.score,
            duration: primary.durationSeconds,
            demands: primary.routeDemands ?? []
        )
        let ties = RouteChoiceRankingEngine.rank(
            primaryRoute: primary,
            alternateRoutes: [tiedAlternate],
            recordedDrives: [],
            configuration: configuration,
            calendar: calendar,
            referenceDate: referenceDate
        )
        expect(ties.choices.map(\.route.id) == [primary.id, tiedAlternate.id], "full ordering ties must retain API order")

        let keyBefore = RouteChoiceRankingEngine.cacheKey(
            primaryRoute: primary,
            alternateRoutes: [hardAlternate],
            recordedDrives: steadyHistory
        )
        let keyAfter = RouteChoiceRankingEngine.cacheKey(
            primaryRoute: primary,
            alternateRoutes: [hardAlternate],
            recordedDrives: steadyHistory + [drive(startedAt: referenceDate, score: 92)]
        )
        expect(keyBefore != keyAfter, "a saved-drive change must invalidate a cached readiness ranking")

        let insufficientAssessment = DriverReadinessEngine.assess(
            route: primary,
            recordedDrives: [],
            configuration: configuration,
            calendar: calendar,
            referenceDate: referenceDate
        )
        let historyPlan = PracticePlanEngine.makePlan(
            assessment: insufficientAssessment,
            route: primary,
            createdAt: referenceDate
        )
        expect(historyPlan.goals.first?.kind == .buildRecordedHistory, "missing qualifying history should be the first practice goal")
        expect(historyPlan.goals.first?.requiresAdultSupervision == true, "history goals should use adult-supervision coaching")

        let demandingRoute = route(
            polyline: "demanding-route",
            score: 7.5,
            duration: 960,
            demands: [
                demand(.merges, intensity: 0.95, level: .high),
                demand(.complexIntersections, intensity: 0.85, level: .high),
                demand(.weatherVisibility, intensity: 0.75, level: .high),
                demand(.traffic, intensity: 0.70, level: .high)
            ]
        )
        let demandAssessment = DriverReadinessEngine.assess(
            route: demandingRoute,
            recordedDrives: steadyHistory,
            configuration: configuration,
            calendar: calendar,
            referenceDate: referenceDate
        )
        let demandPlan = PracticePlanEngine.makePlan(
            assessment: demandAssessment,
            route: demandingRoute,
            createdAt: referenceDate
        )
        expect(demandPlan.goals.count == 3, "practice plans must cap goals at three")
        expect(
            demandPlan.goals.allSatisfy { $0.kind == .routeDemand },
            "unmeasured high-intensity route demands should take priority over less specific coaching"
        )
        expect(
            demandPlan.goals.map(\.demandID) == ["merges", "complexIntersections", "weatherVisibility"],
            "higher-intensity demands should have a stable priority order"
        )

        let qualityAssessment = DriverReadinessEngine.assess(
            route: primary,
            recordedDrives: lowQualityHistory,
            configuration: configuration,
            calendar: calendar,
            referenceDate: referenceDate
        )
        let qualityPlan = PracticePlanEngine.makePlan(
            assessment: qualityAssessment,
            route: primary,
            createdAt: referenceDate
        )
        expect(qualityPlan.goals.map(\.kind) == [.drivingQuality], "quality coaching should appear only when measured history supports it")

        let beforeProfile = DriverReadinessEngine.profile(
            from: steadyHistory,
            configuration: configuration,
            calendar: calendar,
            referenceDate: referenceDate
        )
        let practiceDrive = drive(startedAt: referenceDate, score: 90)
        let afterProfile = DriverReadinessEngine.profile(
            from: steadyHistory + [practiceDrive],
            configuration: configuration,
            calendar: calendar,
            referenceDate: referenceDate
        )
        let debriefPlan = PracticePlan(
            id: UUID(uuidString: "9C6AD2C7-9E45-4B2A-A755-76A2A2C5C611")!,
            createdAt: referenceDate,
            goals: [PracticeGoal(id: "demand:merges", kind: .routeDemand, demandID: "merges")]
        )
        let verifiedCoverage = PracticeRouteCoverageSummary(
            recordedAt: referenceDate,
            overallCoverage: 0.92,
            longestContinuousCoverage: 0.88,
            originCoverage: 0.90,
            destinationCoverage: 0.91,
            demandCoverage: [
                PracticeDemandCoverage(
                    demandID: "merges",
                    demandIntensity: 0.95,
                    coveredShare: 0.90,
                    routeShare: 0.15
                )
            ]
        )
        let verifiedDebrief = PracticePlanEngine.makeDebrief(
            plan: debriefPlan,
            savedDrive: practiceDrive,
            coverage: verifiedCoverage,
            profileBefore: beforeProfile,
            profileAfter: afterProfile,
            configuration: configuration,
            calendar: calendar,
            createdAt: referenceDate
        )
        expect(verifiedDebrief.outcome == .verifiedRoutePractice, "full continuous planned-route coverage should verify practice")
        expect(verifiedDebrief.goalCompletions.first?.status == .measured, "covered demand goals should be marked measured")

        let partialCoverage = PracticeRouteCoverageSummary(
            recordedAt: referenceDate,
            overallCoverage: 0.45,
            longestContinuousCoverage: 0.32,
            originCoverage: 0.60,
            destinationCoverage: 0.10,
            demandCoverage: [
                PracticeDemandCoverage(
                    demandID: "merges",
                    demandIntensity: 0.95,
                    coveredShare: 0.45,
                    routeShare: 0.15
                )
            ]
        )
        let partialDebrief = PracticePlanEngine.makeDebrief(
            plan: debriefPlan,
            savedDrive: practiceDrive,
            coverage: partialCoverage,
            profileBefore: beforeProfile,
            profileAfter: afterProfile,
            configuration: configuration,
            calendar: calendar,
            createdAt: referenceDate
        )
        expect(partialDebrief.outcome == .partialRouteCoverage, "partial local coverage must not be called full-route practice")
        expect(partialDebrief.goalCompletions.first?.status == .needsMorePractice, "partial demand coverage should remain a practice target")
        expect(partialDebrief.goalCompletions.first?.wasMeasuredToday == true, "partial coverage should still be clearly shown as measured today")

        let missingGPSDebrief = PracticePlanEngine.makeDebrief(
            plan: debriefPlan,
            savedDrive: practiceDrive,
            coverage: nil,
            profileBefore: beforeProfile,
            profileAfter: afterProfile,
            configuration: configuration,
            calendar: calendar,
            createdAt: referenceDate
        )
        expect(missingGPSDebrief.outcome == .insufficientGPSCoverage, "missing route coverage must have an explicit debrief state")
        expect(missingGPSDebrief.goalCompletions.first?.status == .notMeasured, "no coverage should not mark a demand as measured")

        let preliminaryDrive = drive(startedAt: referenceDate, score: 90, confidence: .low)
        let preliminaryDebrief = PracticePlanEngine.makeDebrief(
            plan: debriefPlan,
            savedDrive: preliminaryDrive,
            coverage: verifiedCoverage,
            profileBefore: beforeProfile,
            profileAfter: afterProfile,
            configuration: configuration,
            calendar: calendar,
            createdAt: referenceDate
        )
        expect(preliminaryDebrief.outcome == .savedNotYetQualifying, "a preliminary saved drive must not change readiness evidence")

        let encodedPlan = try JSONEncoder().encode(demandPlan)
        let restoredPlan = try JSONDecoder().decode(PracticePlan.self, from: encodedPlan)
        expect(restoredPlan == demandPlan, "practice plans should round-trip through local persistence")
        let encodedText = String(decoding: encodedPlan, as: UTF8.self).lowercased()
        expect(!encodedText.contains("polyline"), "practice plans must not persist route polylines")
        expect(!encodedText.contains("latitude"), "practice plans must not persist route coordinates")
        expect(!encodedText.contains("longitude"), "practice plans must not persist route coordinates")
        expect(!encodedText.contains("address"), "practice plans must not persist route addresses")
        let encodedDebriefText = String(
            decoding: try JSONEncoder().encode(verifiedDebrief),
            as: UTF8.self
        ).lowercased()
        expect(!encodedDebriefText.contains("polyline"), "practice debriefs must not persist route polylines")
        expect(!encodedDebriefText.contains("latitude"), "practice debriefs must not persist route coordinates")
        expect(!encodedDebriefText.contains("longitude"), "practice debriefs must not persist route coordinates")
        expect(!encodedDebriefText.contains("motionsamples"), "practice debriefs must not persist raw motion measurements")

        let persistedContext = PlannedRouteContext(
            routeDemands: demandingRoute.routeDemands ?? [],
            recordedRouteMatched: true,
            verifiedDemandExposures: verifiedCoverage.verifiedDemandExposures(),
            practicePlan: demandPlan,
            coverageSummary: verifiedCoverage,
            debrief: verifiedDebrief
        )
        let encodedContext = try JSONEncoder().encode(persistedContext)
        let encodedContextText = String(decoding: encodedContext, as: UTF8.self).lowercased()
        expect(!encodedContextText.contains("polyline"), "saved practice contexts must not persist planned polylines")
        expect(!encodedContextText.contains("latitude"), "saved practice contexts must not persist planned coordinates")
        expect(!encodedContextText.contains("longitude"), "saved practice contexts must not persist planned coordinates")
        expect(!encodedContextText.contains("motionsamples"), "saved practice contexts must not persist raw motion samples")
        let contextObject = try JSONSerialization.jsonObject(with: encodedContext) as! [String: Any]
        let savedTags = contextObject["routeDemandTags"] as! [[String: Any]]
        expect(
            savedTags.allSatisfy { Set($0.keys) == Set(["id"]) },
            "saved practice demand tags must retain only stable demand IDs"
        )
        let decodedContext = try JSONDecoder().decode(PlannedRouteContext.self, from: encodedContext)
        expect(decodedContext.practicePlan == demandPlan, "saved practice plans should round-trip with a route context")
        expect(decodedContext.debrief == verifiedDebrief, "saved debriefs should round-trip with a route context")

        print("RoutePracticeEngines checks passed")
    }

    private static func route(
        polyline: String,
        score: Double,
        duration: Int,
        demands: [RouteDemand]
    ) -> ScoredRoute {
        ScoredRoute(
            score: score,
            uncalibratedScore: nil,
            label: .moderate,
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
            distanceMeters: 1_000,
            durationSeconds: duration,
            staticDurationSeconds: duration,
            trafficDelaySeconds: 0,
            polyline: polyline,
            bounds: RouteBounds(
                southwest: Coordinate(latitude: 30, longitude: -97),
                northeast: Coordinate(latitude: 31, longitude: -96)
            ),
            scoreDelta: nil,
            routeDemands: demands
        )
    }

    private static func demand(
        _ kind: RouteDemandKind,
        intensity: Double,
        level: RouteDemandLevel
    ) -> RouteDemand {
        RouteDemand(
            id: kind.rawValue,
            intensity: intensity,
            level: level,
            evidence: "Measured route demand.",
            available: true
        )
    }

    private static func drive(
        startedAt: Date,
        score: Int,
        confidence: DriveScoreConfidence = .high
    ) -> RecordedDrive {
        let route = (0...8).map { index in
            DriveRoutePoint(
                timestamp: startedAt.addingTimeInterval(TimeInterval(index)),
                coordinate: DriveCoordinate(
                    CLLocationCoordinate2D(latitude: 30, longitude: -97 + Double(index) * 0.0008)
                ),
                speedMetersPerSecond: 35
            )
        }
        return RecordedDrive(
            startedAt: startedAt,
            score: DrivingScore(
                score: score,
                duration: 8,
                distanceMeters: 700,
                topSpeedMetersPerSecond: 35,
                events: [],
                motionSamples: 12,
                dataQuality: DriveDataQuality(
                    acceptedLocationSamples: route.count,
                    rejectedLocationSamples: 0,
                    motionSamples: 12,
                    confidence: confidence
                )
            ),
            route: route,
            recordingTimeZoneIdentifier: "UTC"
        )
    }

    private static func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func makeDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError("RoutePracticeEngines check failed: \(message)")
        }
    }
}
