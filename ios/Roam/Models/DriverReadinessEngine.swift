import CoreLocation
import Foundation

/// The three coaching states shown for a route. These are deliberately not a
/// driving permission or safety guarantee.
enum DriverReadinessVerdict: String {
    case insufficientHistory
    case looksLikeMatch
    case practiceWithAdult

    var title: String {
        switch self {
        case .insufficientHistory: "Need more recorded experience"
        case .looksLikeMatch: "Looks like a match for recorded experience"
        case .practiceWithAdult: "Practice this with an adult"
        }
    }
}

enum DriverReadinessInsightState: String, Hashable {
    /// The local record contains relevant, qualifying experience.
    case matched
    /// The local record shows a measurable gap for this route.
    case practiceNeeded
    /// The app has not captured enough specific information to compare this.
    case unmeasured
    /// A low-demand or unavailable route signal that should not affect advice.
    case informational
}

enum DriverReadinessEvidenceSource: String, Hashable {
    case gpsMotion
    case routeOverlap
    case taggedPractice
    case unavailable
}

/// Structured facts behind an insight. Results can present the actual local
/// evidence without reverse-parsing coaching copy.
struct DriverReadinessEvidence: Hashable {
    let source: DriverReadinessEvidenceSource
    let recordedValue: String
    let comparisonTarget: String?
    let routeEvidence: String
    let collectionNote: String?
}

struct DriverReadinessInsight: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let state: DriverReadinessInsightState
    let evidence: DriverReadinessEvidence?

    init(
        id: String,
        title: String,
        detail: String,
        state: DriverReadinessInsightState,
        evidence: DriverReadinessEvidence? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.state = state
        self.evidence = evidence
    }
}

enum RouteFamiliarityLevel: String {
    case unmeasured
    case unfamiliar
    case partlyFamiliar
    case familiar
}

/// Local GPS overlap only. No familiarity value or recorded trace is sent to
/// the route-analysis backend.
struct RouteFamiliarity {
    let level: RouteFamiliarityLevel
    /// Coverage across the union of saved, continuous, directionally aligned
    /// traces. It is useful context, but never a driving permission.
    let matchedShare: Double
    let sampledPointCount: Int
    let matchingPointCount: Int
    /// The best single saved drive, which avoids calling a route familiar just
    /// because fragments from unrelated trips happen to cover it.
    let bestSingleDriveShare: Double
    let longestContinuousShare: Double
    let matchingDriveCount: Int
    let mostRecentMatchingDrive: Date?
}

/// Exposure from continuous, qualifying drives. A session only counts when
/// its local trace actually measured the characteristic.
struct DriverExperienceExposure {
    /// All validated history. This is shown transparently, but it is never by
    /// itself enough to call a route a match after a long break from driving.
    let miles: Double
    /// Recency-decayed miles. Each observation loses half its weight over the
    /// configured half-life so older experience remains context, not proof.
    let effectiveMiles: Double
    let duration: TimeInterval
    let sessionCount: Int
    let distinctDayCount: Int
    let recentMiles: Double
    let recentSessionCount: Int
    let recentDistinctDayCount: Int
    let lastRecordedAt: Date?
    let longestEpisodeDuration: TimeInterval
    let longestEpisodeMiles: Double
    let episodes: [DriverExperienceEpisode]
}

/// A single measured, continuous episode inside a saved drive. It remains
/// aggregate history only; no coordinate is retained here.
struct DriverExperienceEpisode: Hashable {
    let duration: TimeInterval
    let miles: Double
    let recordedAt: Date
    let localDayKey: String
}

struct DrivingBehaviorProfile {
    let measuredMiles: Double
    let recentMeasuredMiles: Double
    let weightedEventRatePerTenMiles: Double?
    let recentWeightedEventRatePerTenMiles: Double?
    let highSpeedEventRatePerTenMiles: Double?
    let afterDarkEventRatePerTenMiles: Double?
    let weightedAverageScore: Double?
    let recentWeightedAverageScore: Double?
    let hardBrakesPerTenMiles: Double?
    let sharpCornersPerTenMiles: Double?
}

/// A demand-specific, route-covered practice record. Unlike the original
/// whole-route Boolean, it cannot credit a merge or intersection unless the
/// recorded trace covered the mapped part of the route.
struct TaggedPracticeEvidence {
    let driveID: UUID
    let demandIntensity: Double
    let coveredShare: Double
    let routeShare: Double
    let recordedAt: Date
}

/// A private aggregate view of usable drives on this phone. It intentionally
/// contains no origin, destination, cloud identifier, or outbound history.
struct DriverReadinessProfile {
    let qualifyingDriveCount: Int
    let qualifyingDriveDayCount: Int
    let totalMiles: Double
    let reliableTraceMiles: Double
    let recentQualifyingDriveCount: Int
    let recentReliableTraceMiles: Double
    let effectiveReliableTraceMiles: Double
    let totalContinuousDuration: TimeInterval
    let nightMiles: Double
    let highSpeedMiles: Double
    let highestSpeedMiles: Double
    let longestDriveDuration: TimeInterval
    let averageDrivingScore: Double?
    let recentAverageDrivingScore: Double?
    let taggedExposureCounts: [String: Int]
    let nightExposure: DriverExperienceExposure
    let fastRoad45Exposure: DriverExperienceExposure
    let fastRoad55Exposure: DriverExperienceExposure
    let fastRoad60Exposure: DriverExperienceExposure
    let fastRoad65Exposure: DriverExperienceExposure
    let sustainedExposure: DriverExperienceExposure
    let behavior: DrivingBehaviorProfile
    let taggedPracticeEvidence: [String: [TaggedPracticeEvidence]]

    /// A cautious baseline prevents a recommendation after one or two short
    /// errands. It requires repeated, trace-backed practice on separate days.
    var hasEnoughRecordedExperience: Bool {
        hasEnoughRecordedExperience(using: DriverReadinessEngine.Configuration())
    }

    func hasEnoughRecordedExperience(using configuration: DriverReadinessEngine.Configuration) -> Bool {
        let recentHistoryFloor = min(
            configuration.minimumHistoryMiles,
            max(configuration.minimumRecentHistoryMiles, configuration.minimumHistoryMiles * 0.25)
        )
        return qualifyingDriveCount >= configuration.minimumHistoryDriveCount &&
            qualifyingDriveDayCount >= configuration.minimumHistoryDayCount &&
            reliableTraceMiles >= configuration.minimumHistoryMiles &&
            totalContinuousDuration >= configuration.minimumHistoryTraceDuration &&
            recentQualifyingDriveCount >= configuration.minimumRecentHistoryDriveCount &&
            recentReliableTraceMiles >= recentHistoryFloor
    }

    func taggedExposureCount(for demand: RouteDemandKind) -> Int {
        taggedExposureCounts[demand.rawValue, default: 0]
    }

    func taggedPractice(for demandID: String) -> [TaggedPracticeEvidence] {
        taggedPracticeEvidence[demandID, default: []]
    }
}

struct DriverReadinessAssessment {
    let verdict: DriverReadinessVerdict
    let headline: String
    let summary: String
    let insights: [DriverReadinessInsight]
    let profile: DriverReadinessProfile
    let familiarity: RouteFamiliarity
}

/// Pure local reasoning for “Can I drive this?” Route demands arrive from the
/// backend, but all history and route-overlap analysis stays on the device.
enum DriverReadinessEngine {
    struct Configuration {
        let minimumQualifyingDuration: TimeInterval
        let minimumQualifyingMiles: Double
        let minimumHistoryDriveCount: Int
        let minimumHistoryDayCount: Int
        let minimumHistoryMiles: Double
        let minimumHistoryTraceDuration: TimeInterval
        let minimumRecentQualityMiles: Double
        let minimumRecentHistoryMiles: Double
        let minimumRecentHistoryDriveCount: Int
        let recentWindowDays: Double
        let staleExperienceDays: Double
        let experienceHalfLifeDays: Double
        let practiceCoverageThreshold: Double
        let routeFamiliarityDistanceMeters: CLLocationDistance
        let routeFamiliaritySampleLimit: Int
        let minimumPracticeContiguousShare: Double
        let practiceRouteMatchDistanceMeters: CLLocationDistance
        let minimumPracticeRouteDistanceMeters: CLLocationDistance

        init(
            minimumQualifyingDuration: TimeInterval = 5 * 60,
            minimumQualifyingMiles: Double = 1,
            minimumHistoryDriveCount: Int = 3,
            minimumHistoryDayCount: Int = 3,
            minimumHistoryMiles: Double = 15,
            minimumHistoryTraceDuration: TimeInterval = 45 * 60,
            minimumRecentQualityMiles: Double = 5,
            minimumRecentHistoryMiles: Double = 3,
            minimumRecentHistoryDriveCount: Int = 1,
            recentWindowDays: Double = 90,
            staleExperienceDays: Double = 180,
            experienceHalfLifeDays: Double = 120,
            practiceCoverageThreshold: Double = 0.70,
            routeFamiliarityDistanceMeters: CLLocationDistance = 35,
            routeFamiliaritySampleLimit: Int = 500,
            minimumPracticeContiguousShare: Double = 0.45,
            practiceRouteMatchDistanceMeters: CLLocationDistance = 25,
            minimumPracticeRouteDistanceMeters: CLLocationDistance = 300
        ) {
            self.minimumQualifyingDuration = minimumQualifyingDuration
            self.minimumQualifyingMiles = minimumQualifyingMiles
            self.minimumHistoryDriveCount = max(1, minimumHistoryDriveCount)
            self.minimumHistoryDayCount = max(1, minimumHistoryDayCount)
            self.minimumHistoryMiles = max(0, minimumHistoryMiles)
            self.minimumHistoryTraceDuration = max(0, minimumHistoryTraceDuration)
            self.minimumRecentQualityMiles = max(0, minimumRecentQualityMiles)
            self.minimumRecentHistoryMiles = max(0, minimumRecentHistoryMiles)
            self.minimumRecentHistoryDriveCount = max(1, minimumRecentHistoryDriveCount)
            self.recentWindowDays = max(1, recentWindowDays)
            self.staleExperienceDays = max(recentWindowDays, staleExperienceDays)
            self.experienceHalfLifeDays = max(1, experienceHalfLifeDays)
            self.practiceCoverageThreshold = min(max(practiceCoverageThreshold, 0.5), 0.95)
            self.routeFamiliarityDistanceMeters = min(max(20, routeFamiliarityDistanceMeters), 45)
            self.routeFamiliaritySampleLimit = max(40, routeFamiliaritySampleLimit)
            self.minimumPracticeContiguousShare = min(max(minimumPracticeContiguousShare, 0.2), 0.9)
            self.practiceRouteMatchDistanceMeters = min(max(12, practiceRouteMatchDistanceMeters), 35)
            self.minimumPracticeRouteDistanceMeters = max(150, minimumPracticeRouteDistanceMeters)
        }
    }

    static func assess(
        route: ScoredRoute,
        recordedDrives: [RecordedDrive]
    ) -> DriverReadinessAssessment {
        assess(
            route: route,
            recordedDrives: recordedDrives,
            configuration: Configuration(),
            calendar: .current,
            referenceDate: Date()
        )
    }

    /// Injectable time/configuration makes the local calculation deterministic
    /// in checks without adding mutable global state.
    static func assess(
        route: ScoredRoute,
        recordedDrives: [RecordedDrive],
        configuration: Configuration,
        calendar: Calendar,
        referenceDate: Date = Date()
    ) -> DriverReadinessAssessment {
        let qualifying = qualifyingDrives(
            from: recordedDrives,
            configuration: configuration,
            calendar: calendar
        )
        let profile = makeProfile(
            qualifyingDrives: qualifying,
            configuration: configuration,
            calendar: calendar,
            referenceDate: referenceDate
        )
        let familiarity = makeFamiliarity(
            for: route,
            qualifyingDrives: qualifying,
            configuration: configuration
        )

        guard profile.hasEnoughRecordedExperience(using: configuration) else {
            let summary = historyRequirementSummary(profile: profile, configuration: configuration)
            return DriverReadinessAssessment(
                verdict: .insufficientHistory,
                headline: DriverReadinessVerdict.insufficientHistory.title,
                summary: summary,
                insights: [
                    historyInsight(profile: profile, configuration: configuration),
                    familiarityInsight(
                        familiarity,
                        routeMaxIntensity: (route.routeDemands ?? []).map(\.intensity).max() ?? 0
                    )
                ],
                profile: profile,
                familiarity: familiarity
            )
        }

        let routeDemands = route.routeDemands ?? []
        guard !routeDemands.isEmpty else {
            return DriverReadinessAssessment(
                verdict: .practiceWithAdult,
                headline: DriverReadinessVerdict.practiceWithAdult.title,
                summary: "Route demand details are not available yet, so this route cannot be compared with recorded experience.",
                insights: [
                    DriverReadinessInsight(
                        id: "routeDemandsUnavailable",
                        title: "Route readiness details",
                        detail: "This route’s specific demands were not available to verify.",
                        state: .informational,
                        evidence: DriverReadinessEvidence(
                            source: .unavailable,
                            recordedValue: historyBaseText(profile),
                            comparisonTarget: nil,
                            routeEvidence: "Route demand data was unavailable.",
                            collectionNote: nil
                        )
                    ),
                    drivingQualityInsight(profile, configuration: configuration),
                    familiarityInsight(familiarity, routeMaxIntensity: 0)
                ],
                profile: profile,
                familiarity: familiarity
            )
        }

        var insights = routeDemands.map {
            readinessInsight(
                for: $0,
                route: route,
                profile: profile,
                configuration: configuration,
                referenceDate: referenceDate
            )
        }
        let quality = drivingQualityInsight(profile, configuration: configuration)
        let familiarityInsightValue = familiarityInsight(
            familiarity,
            routeMaxIntensity: routeDemands.map(\.intensity).max() ?? 0
        )
        insights.append(quality)
        insights.append(familiarityInsightValue)

        let demandByID = Dictionary(uniqueKeysWithValues: routeDemands.map { ($0.id, $0) })
        let demandGap = insights.contains { insight in
            guard let demand = demandByID[insight.id] else { return false }
            switch insight.state {
            case .practiceNeeded:
                return true
            case .unmeasured:
                return demand.available && demand.intensity >= 0.60
            case .matched, .informational:
                return false
            }
        }
        let behaviorGap = quality.state == .practiceNeeded
        let familiarityGap = familiarityInsightValue.state == .practiceNeeded
        let verdict: DriverReadinessVerdict = demandGap || behaviorGap || familiarityGap
            ? .practiceWithAdult
            : .looksLikeMatch

        let summary: String
        switch verdict {
        case .looksLikeMatch:
            summary = "\(historyBaseText(profile)). The measured route demands fit the experience this phone can compare."
        case .practiceWithAdult:
            summary = "\(historyBaseText(profile)). At least one meaningful route demand is new, lightly practiced, or not yet measured."
        case .insufficientHistory:
            summary = historyRequirementSummary(profile: profile, configuration: configuration)
        }

        return DriverReadinessAssessment(
            verdict: verdict,
            headline: verdict.title,
            summary: summary,
            insights: insights,
            profile: profile,
            familiarity: familiarity
        )
    }

    static func profile(from recordedDrives: [RecordedDrive]) -> DriverReadinessProfile {
        profile(
            from: recordedDrives,
            configuration: Configuration(),
            calendar: .current,
            referenceDate: Date()
        )
    }

    static func profile(
        from recordedDrives: [RecordedDrive],
        configuration: Configuration,
        calendar: Calendar,
        referenceDate: Date = Date()
    ) -> DriverReadinessProfile {
        makeProfile(
            qualifyingDrives: qualifyingDrives(
                from: recordedDrives,
                configuration: configuration,
                calendar: calendar
            ),
            configuration: configuration,
            calendar: calendar,
            referenceDate: referenceDate
        )
    }

    static func qualifies(
        _ drive: RecordedDrive,
        configuration: Configuration = Configuration(),
        calendar: Calendar = .current
    ) -> Bool {
        guard drive.score.dataQuality.confidence == .medium || drive.score.dataQuality.confidence == .high else {
            return false
        }
        let summary = DriveExperienceEngine.summary(for: drive, calendar: calendar)
        return summary.measuredMinutes >= configuration.minimumQualifyingDuration / 60 ||
            summary.measuredMiles >= configuration.minimumQualifyingMiles
    }

    /// Verifies a manually recorded drive substantially followed the route
    /// selected immediately before it. Long tracking gaps, reversed travel,
    /// and fragments from scattered road sections cannot verify the route.
    static func matchesPlannedPracticeRoute(
        plannedPolyline: String,
        recordedRoute: [DriveRoutePoint]
    ) -> Bool {
        let coverage = practiceRouteCoverage(
            plannedPolyline: plannedPolyline,
            recordedRoute: recordedRoute,
            demands: [],
            configuration: Configuration()
        )
        return coverage.overallCoverage >= 0.60 &&
            coverage.longestContinuousCoverage >= Configuration().minimumPracticeContiguousShare &&
            coverage.originCoverage >= 0.60 &&
            coverage.destinationCoverage >= 0.60
    }

    /// Calculates route and demand-specific coverage while the queued route
    /// polyline remains in memory. Callers persist only returned numeric
    /// demand evidence, never the plan's geometry.
    static func practiceRouteCoverage(
        plannedPolyline: String,
        recordedRoute: [DriveRoutePoint],
        demands: [RouteDemand],
        configuration: Configuration = Configuration()
    ) -> PracticeRouteCoverage {
        let planned = sampledRoute(polyline: plannedPolyline, limit: configuration.routeFamiliaritySampleLimit)
        let recorded = DriveExperienceEngine.validTraceSegments(for: recordedRoute)
        guard planned.count >= 3,
              recorded.count >= 4,
              routeDistanceMeters(for: plannedPolyline) >= configuration.minimumPracticeRouteDistanceMeters else {
            return PracticeRouteCoverage(
                overallCoverage: 0,
                longestContinuousCoverage: 0,
                originCoverage: 0,
                destinationCoverage: 0,
                demandExposures: []
            )
        }
        let matches = orderedPracticeMatches(
            planned: planned,
            trace: recorded,
            threshold: configuration.practiceRouteMatchDistanceMeters
        )
        let overall = share(of: matches.flags)
        let contiguous = longestOrderedContinuousShare(matches)
        let endpointWindow = min(12, max(3, Int((Double(planned.count) * 0.08).rounded(.up))))
        let originCoverage = share(of: Array(matches.flags.prefix(endpointWindow)))
        let destinationCoverage = share(of: Array(matches.flags.suffix(endpointWindow)))
        let demandExposures = demandCoverage(
            demands: demands,
            samples: planned,
            matches: matches,
            threshold: configuration.practiceCoverageThreshold,
            fullRouteCoverage: overall,
            fullRouteContinuousCoverage: contiguous,
            minimumContinuousCoverage: configuration.minimumPracticeContiguousShare
        )
        return PracticeRouteCoverage(
            overallCoverage: overall,
            longestContinuousCoverage: contiguous,
            originCoverage: originCoverage,
            destinationCoverage: destinationCoverage,
            demandExposures: demandExposures
        )
    }

    private static func qualifyingDrives(
        from recordedDrives: [RecordedDrive],
        configuration: Configuration,
        calendar: Calendar
    ) -> [HistoryDrive] {
        recordedDrives.compactMap { drive in
            guard qualifies(drive, configuration: configuration, calendar: calendar) else { return nil }
            return HistoryDrive(
                drive: drive,
                summary: DriveExperienceEngine.summary(for: drive, calendar: calendar)
            )
        }
    }

    private static func makeProfile(
        qualifyingDrives: [HistoryDrive],
        configuration: Configuration,
        calendar: Calendar,
        referenceDate: Date
    ) -> DriverReadinessProfile {
        var total = ExposureAccumulator()
        var night = ExposureAccumulator()
        var fast45 = ExposureAccumulator()
        var fast55 = ExposureAccumulator()
        var fast60 = ExposureAccumulator()
        var fast65 = ExposureAccumulator()
        var sustained = ExposureAccumulator()
        var scoreAccumulator = WeightedScoreAccumulator()
        var behaviorAccumulator = BehaviorAccumulator()
        var tagged: [String: [TaggedPracticeEvidence]] = [:]

        for history in qualifyingDrives {
            let drive = history.drive
            let summary = history.summary
            let date = drive.startedAt
            let localDayKey = dayKey(for: drive, calendar: calendar)
            let miles = summary.measuredMiles
            let duration = summary.traceQuality.usableDuration

            total.add(
                miles: miles,
                duration: duration,
                date: date,
                localDayKey: localDayKey,
                episodeDuration: summary.traceQuality.longestContinuousDuration,
                episodeMiles: summary.traceQuality.longestContinuousDistanceMeters / 1_609.344
            )
            if summary.lightingExposure.afterDarkMiles > 0 {
                night.add(
                    miles: summary.lightingExposure.afterDarkMiles,
                    duration: summary.lightingExposure.afterDarkDuration,
                    date: date,
                    localDayKey: localDayKey
                )
            }
            if summary.speedExposure.milesAt45Plus > 0 {
                fast45.add(
                    miles: summary.speedExposure.milesAt45Plus,
                    duration: summary.speedExposure.longest45PlusDuration,
                    date: date,
                    localDayKey: localDayKey,
                    episodeDuration: summary.speedExposure.longest45PlusDuration,
                    episodeMiles: summary.speedExposure.longest45PlusDistanceMiles
                )
            }
            if summary.speedExposure.milesAt55Plus > 0 {
                fast55.add(
                    miles: summary.speedExposure.milesAt55Plus,
                    duration: summary.speedExposure.longest55PlusDuration,
                    date: date,
                    localDayKey: localDayKey,
                    episodeDuration: summary.speedExposure.longest55PlusDuration,
                    episodeMiles: summary.speedExposure.longest55PlusDistanceMiles
                )
            }
            if summary.speedExposure.milesAt60Plus > 0 {
                fast60.add(
                    miles: summary.speedExposure.milesAt60Plus,
                    duration: summary.speedExposure.longest60PlusDuration,
                    date: date,
                    localDayKey: localDayKey,
                    episodeDuration: summary.speedExposure.longest60PlusDuration,
                    episodeMiles: summary.speedExposure.longest60PlusDistanceMiles
                )
            }
            if summary.speedExposure.milesAt65Plus > 0 {
                fast65.add(
                    miles: summary.speedExposure.milesAt65Plus,
                    duration: 0,
                    date: date,
                    localDayKey: localDayKey
                )
            }
            sustained.add(
                miles: miles,
                duration: summary.traceQuality.longestContinuousDuration,
                date: date,
                localDayKey: localDayKey,
                episodeDuration: summary.traceQuality.longestContinuousDuration,
                episodeMiles: summary.traceQuality.longestContinuousDistanceMeters / 1_609.344
            )
            scoreAccumulator.add(
                score: Double(drive.score.score),
                miles: miles,
                date: date,
                referenceDate: referenceDate,
                recentWindowDays: configuration.recentWindowDays
            )
            behaviorAccumulator.add(
                summary: summary,
                score: Double(drive.score.score),
                miles: miles,
                date: date,
                referenceDate: referenceDate,
                recentWindowDays: configuration.recentWindowDays
            )

            guard drive.plannedRouteContext?.recordedRouteMatched == true else { continue }
            // Legacy Boolean-only tags are intentionally not treated as proof
            // of a demand. New records need mapped demand coverage.
            for exposure in drive.plannedRouteContext?.verifiedDemandExposures ?? [] {
                guard exposure.coveredShare >= configuration.practiceCoverageThreshold else { continue }
                tagged[exposure.demandID, default: []].append(
                    TaggedPracticeEvidence(
                        driveID: drive.id,
                        demandIntensity: exposure.demandIntensity,
                        coveredShare: exposure.coveredShare,
                        routeShare: exposure.routeShare,
                        recordedAt: exposure.recordedAt
                    )
                )
            }
        }

        let totalExposure = total.makeExposure(referenceDate: referenceDate, configuration: configuration)
        let nightExposure = night.makeExposure(referenceDate: referenceDate, configuration: configuration)
        let fast45Exposure = fast45.makeExposure(referenceDate: referenceDate, configuration: configuration)
        let fast55Exposure = fast55.makeExposure(referenceDate: referenceDate, configuration: configuration)
        let fast60Exposure = fast60.makeExposure(referenceDate: referenceDate, configuration: configuration)
        let fast65Exposure = fast65.makeExposure(referenceDate: referenceDate, configuration: configuration)
        let sustainedExposure = sustained.makeExposure(referenceDate: referenceDate, configuration: configuration)
        let taggedCounts = tagged.mapValues { entries in
            Set(entries.map(\.driveID)).count
        }

        return DriverReadinessProfile(
            qualifyingDriveCount: qualifyingDrives.count,
            qualifyingDriveDayCount: totalExposure.distinctDayCount,
            totalMiles: totalExposure.miles,
            reliableTraceMiles: totalExposure.miles,
            recentQualifyingDriveCount: totalExposure.recentSessionCount,
            recentReliableTraceMiles: totalExposure.recentMiles,
            effectiveReliableTraceMiles: totalExposure.effectiveMiles,
            totalContinuousDuration: totalExposure.duration,
            nightMiles: nightExposure.miles,
            highSpeedMiles: fast45Exposure.miles,
            highestSpeedMiles: fast55Exposure.miles,
            longestDriveDuration: sustainedExposure.longestEpisodeDuration,
            averageDrivingScore: scoreAccumulator.average,
            recentAverageDrivingScore: scoreAccumulator.recentAverage,
            taggedExposureCounts: taggedCounts,
            nightExposure: nightExposure,
            fastRoad45Exposure: fast45Exposure,
            fastRoad55Exposure: fast55Exposure,
            fastRoad60Exposure: fast60Exposure,
            fastRoad65Exposure: fast65Exposure,
            sustainedExposure: sustainedExposure,
            behavior: behaviorAccumulator.makeProfile(),
            taggedPracticeEvidence: tagged
        )
    }

    private static func readinessInsight(
        for demand: RouteDemand,
        route: ScoredRoute,
        profile: DriverReadinessProfile,
        configuration: Configuration,
        referenceDate: Date
    ) -> DriverReadinessInsight {
        let routeEvidence = demand.evidence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard demand.available else {
            return DriverReadinessInsight(
                id: demand.id,
                title: demand.title,
                detail: "\(routeEvidence) This route characteristic was not available to compare.",
                state: .informational,
                evidence: DriverReadinessEvidence(
                    source: .unavailable,
                    recordedValue: historyBaseText(profile),
                    comparisonTarget: nil,
                    routeEvidence: routeEvidence,
                    collectionNote: "Roam leaves unavailable route data out rather than estimating it."
                )
            )
        }
        guard demand.level != .low && demand.intensity >= 0.34 else {
            return DriverReadinessInsight(
                id: demand.id,
                title: demand.title,
                detail: "\(routeEvidence) This is a lower-demand part of this route.",
                state: .informational,
                evidence: DriverReadinessEvidence(
                    source: .gpsMotion,
                    recordedValue: historyBaseText(profile),
                    comparisonTarget: nil,
                    routeEvidence: routeEvidence,
                    collectionNote: nil
                )
            )
        }

        switch demand.kind {
        case .afterDark:
            let target = max(
                2,
                min(20, demand.metrics?["nightMiles"] ?? route.distanceMiles * demand.intensity)
            )
            return exposureInsight(
                demand: demand,
                exposure: profile.nightExposure,
                targetMiles: target,
                requiredSessions: demand.intensity >= 0.67 ? 2 : 1,
                experienceName: "after-dark driving",
                routeEvidence: routeEvidence,
                configuration: configuration,
                referenceDate: referenceDate
            )
        case .fastRoads:
            let estimated65Miles = demand.metrics?["estimatedMilesAt65"] ?? 0
            let estimated60Miles = demand.metrics?["estimatedMilesAt60"] ?? 0
            let expected45Miles = demand.metrics?["estimatedMilesAt45"] ?? route.distanceMiles * demand.intensity
            let meaningfulRouteShare = max(1, route.distanceMiles * 0.12)
            let requiredBand: Int
            let routeBandMiles: Double
            let exposure: DriverExperienceExposure
            if estimated65Miles >= meaningfulRouteShare {
                requiredBand = 65
                routeBandMiles = estimated65Miles
                exposure = profile.fastRoad65Exposure
            } else if estimated60Miles >= meaningfulRouteShare {
                requiredBand = 60
                routeBandMiles = estimated60Miles
                exposure = profile.fastRoad60Exposure
            } else {
                requiredBand = 45
                routeBandMiles = expected45Miles
                exposure = profile.fastRoad45Exposure
            }
            let target = max(
                requiredBand >= 60 ? 2.5 : 2,
                min(25, routeBandMiles * 0.75)
            )
            return exposureInsight(
                demand: demand,
                exposure: exposure,
                targetMiles: target,
                requiredSessions: demand.intensity >= 0.67 ? 2 : 1,
                experienceName: "\(requiredBand)+ mph driving",
                routeEvidence: routeEvidence,
                configuration: configuration,
                referenceDate: referenceDate
            )
        case .sustainedDrive:
            let expectedMinutes = demand.metrics?["expectedDurationMinutes"] ?? Double(route.durationSeconds) / 60
            let target = max(15 * 60, expectedMinutes * 60 * 0.80)
            let secondSessionTarget = target * 0.50
            let requiredSessions = demand.intensity >= 0.67 ? 2 : 1
            let episodes = profile.sustainedExposure.episodes
            let comparableEpisodes = episodes.filter { $0.duration >= target }
            let supportingEpisodes = episodes.filter { $0.duration >= secondSessionTarget }
            let recentSupportingEpisodes = supportingEpisodes.filter {
                isWithinRecentWindow($0.recordedAt, referenceDate: referenceDate, configuration: configuration)
            }
            let mostRecentComparable = comparableEpisodes.map(\.recordedAt).max()
            let hasFreshComparableLongest = comparableEpisodes.contains {
                !isStale($0.recordedAt, referenceDate: referenceDate, configuration: configuration)
            }
            let hasRepeatedPractice = recentSupportingEpisodes.count >= requiredSessions
            let state: DriverReadinessInsightState = hasFreshComparableLongest && hasRepeatedPractice
                ? .matched
                : .practiceNeeded
            let targetText = "\(durationText(target)) continuous trace"
            let recordText = "longest continuous trace: \(durationText(profile.sustainedExposure.longestEpisodeDuration)) · \(recentSupportingEpisodes.count) recent \(durationText(secondSessionTarget))+ session\(recentSupportingEpisodes.count == 1 ? "" : "s")"
            let detail: String
            if state == .matched {
                detail = "\(routeEvidence) Your \(recordText) is comparable with this trip."
            } else if isStale(mostRecentComparable, referenceDate: referenceDate, configuration: configuration) {
                detail = "\(routeEvidence) Your \(recordText) includes a longer drive, but it is not recent enough to use as a current comparison."
            } else if profile.sustainedExposure.longestEpisodeDuration >= secondSessionTarget {
                detail = "\(routeEvidence) Your \(recordText) is a start; a longer supervised practice drive would make this comparison stronger."
            } else {
                detail = "\(routeEvidence) Your \(recordText) is shorter than this route’s measured drive time."
            }
            return DriverReadinessInsight(
                id: demand.id,
                title: demand.title,
                detail: detail,
                state: state,
                evidence: DriverReadinessEvidence(
                    source: .gpsMotion,
                    recordedValue: recordText,
                    comparisonTarget: requiredSessions > 1
                        ? "\(targetText), plus \(requiredSessions) recent sessions of at least \(durationText(secondSessionTarget))"
                        : targetText,
                    routeEvidence: routeEvidence,
                    collectionNote: "Only continuous GPS trace time is used; background gaps are not joined, and a long drive is not carried forward indefinitely."
                )
            )
        case .merges, .complexIntersections:
            return taggedDemandInsight(
                demand: demand,
                profile: profile,
                configuration: configuration,
                referenceDate: referenceDate,
                routeEvidence: routeEvidence,
                conditionSnapshot: false
            )
        case .weatherVisibility, .traffic, .roadConditions:
            return taggedDemandInsight(
                demand: demand,
                profile: profile,
                configuration: configuration,
                referenceDate: referenceDate,
                routeEvidence: routeEvidence,
                conditionSnapshot: true
            )
        case .none:
            return DriverReadinessInsight(
                id: demand.id,
                title: demand.title,
                detail: "\(routeEvidence) Experience with this route demand is not yet measured.",
                state: .unmeasured,
                evidence: DriverReadinessEvidence(
                    source: .unavailable,
                    recordedValue: "No comparable on-device record",
                    comparisonTarget: nil,
                    routeEvidence: routeEvidence,
                    collectionNote: nil
                )
            )
        }
    }

    private static func exposureInsight(
        demand: RouteDemand,
        exposure: DriverExperienceExposure,
        targetMiles: Double,
        requiredSessions: Int,
        experienceName: String,
        routeEvidence: String,
        configuration: Configuration,
        referenceDate: Date
    ) -> DriverReadinessInsight {
        let stale = isStale(exposure.lastRecordedAt, referenceDate: referenceDate, configuration: configuration)
        let requiredRecentMiles = min(targetMiles, max(1.5, targetMiles * 0.25))
        let requiredRecentSessions = min(requiredSessions, 2)
        let sufficient = exposure.effectiveMiles >= targetMiles &&
            exposure.sessionCount >= requiredSessions &&
            exposure.recentMiles >= requiredRecentMiles &&
            exposure.recentSessionCount >= requiredRecentSessions &&
            !stale
        let state: DriverReadinessInsightState = sufficient ? .matched : .practiceNeeded
        let recordText = "\(milesText(exposure.miles)) saved · \(milesText(exposure.recentMiles)) in the last \(Int(configuration.recentWindowDays)) days · \(exposure.sessionCount) qualifying \(driveWord(exposure.sessionCount))"
        let targetText = "about \(milesText(targetMiles)) of recency-weighted practice, including \(milesText(requiredRecentMiles)) recently across \(requiredSessions) \(driveWord(requiredSessions))"
        let recency = recencyText(exposure.lastRecordedAt, referenceDate: referenceDate)
        let detail: String
        if sufficient {
            detail = "\(routeEvidence) \(recordText) of \(experienceName) is saved on this phone\(recency)."
        } else if stale {
            detail = "\(routeEvidence) \(recordText) is saved, but the last comparable drive was\(recency). A recent supervised refresh would make this comparison stronger."
        } else if exposure.recentMiles < requiredRecentMiles || exposure.recentSessionCount < requiredRecentSessions {
            detail = "\(routeEvidence) \(recordText) of \(experienceName) is saved, but more recent measured practice is needed before this route can be compared."
        } else {
            detail = "\(routeEvidence) \(recordText) of \(experienceName) is saved; this route calls for \(targetText)."
        }
        return DriverReadinessInsight(
            id: demand.id,
            title: demand.title,
            detail: detail,
            state: state,
            evidence: DriverReadinessEvidence(
                source: .gpsMotion,
                recordedValue: recordText,
                comparisonTarget: targetText,
                routeEvidence: routeEvidence,
                collectionNote: "Speed exposure requires continuous GPS samples at or above the band; one GPS spike is not credited."
            )
        )
    }

    private static func taggedDemandInsight(
        demand: RouteDemand,
        profile: DriverReadinessProfile,
        configuration: Configuration,
        referenceDate: Date,
        routeEvidence: String,
        conditionSnapshot: Bool
    ) -> DriverReadinessInsight {
        let comparable = profile.taggedPractice(for: demand.id).filter {
            $0.coveredShare >= configuration.practiceCoverageThreshold &&
                $0.demandIntensity >= max(0.34, demand.intensity * 0.75)
        }
        let driveIDs = Set(comparable.map(\.driveID))
        let requiredSessions = demand.intensity >= 0.67 ? 2 : 1
        let recentDriveIDs = Set(comparable.filter {
            isWithinRecentWindow($0.recordedAt, referenceDate: referenceDate, configuration: configuration)
        }.map(\.driveID))
        let last = comparable.map(\.recordedAt).max()
        let stale = isStale(last, referenceDate: referenceDate, configuration: configuration)
        let hasEnough = driveIDs.count >= requiredSessions &&
            recentDriveIDs.count >= requiredSessions &&
            !stale
        let recordText: String
        if driveIDs.isEmpty {
            recordText = "No demand-specific, route-covered practice drive is saved"
        } else {
            let averageCoverage = comparable.map(\.coveredShare).reduce(0, +) / Double(comparable.count)
            recordText = "\(driveIDs.count) route-covered practice \(driveWord(driveIDs.count)) · \(recentDriveIDs.count) recent · average mapped coverage \(percentText(averageCoverage))"
        }
        let note = conditionSnapshot
            ? "This records coverage of a route planned with that live-condition demand; it does not guarantee today’s weather, traffic, or road conditions."
            : "Only GPS coverage of the demand’s mapped route section is counted."

        if hasEnough {
            return DriverReadinessInsight(
                id: demand.id,
                title: demand.title,
                detail: "\(routeEvidence) \(recordText) is saved on this phone\(recencyText(last, referenceDate: referenceDate)).",
                state: .matched,
                evidence: DriverReadinessEvidence(
                    source: .taggedPractice,
                    recordedValue: recordText,
                    comparisonTarget: "\(requiredSessions) route-covered practice \(driveWord(requiredSessions))",
                    routeEvidence: routeEvidence,
                    collectionNote: note
                )
            )
        }

        let state: DriverReadinessInsightState = driveIDs.isEmpty ? .unmeasured : .practiceNeeded
        let ending: String
        if driveIDs.isEmpty {
            ending = "This demand is not yet measured. A manual practice drive needs to cover the mapped part of a planned route before it can be compared."
        } else if stale {
            ending = "The last comparable practice drive was\(recencyText(last, referenceDate: referenceDate)); a recent supervised refresh would make this comparison stronger."
        } else if recentDriveIDs.count < requiredSessions {
            ending = "This route needs \(requiredSessions) recent comparable route-covered practice \(driveWord(requiredSessions))."
        } else {
            ending = "This route needs \(requiredSessions) comparable route-covered practice \(driveWord(requiredSessions))."
        }
        return DriverReadinessInsight(
            id: demand.id,
            title: demand.title,
            detail: "\(routeEvidence) \(recordText). \(ending)",
            state: state,
            evidence: DriverReadinessEvidence(
                source: .taggedPractice,
                recordedValue: recordText,
                comparisonTarget: "\(requiredSessions) route-covered practice \(driveWord(requiredSessions))",
                routeEvidence: routeEvidence,
                collectionNote: note
            )
        )
    }

    private static func drivingQualityInsight(
        _ profile: DriverReadinessProfile,
        configuration: Configuration
    ) -> DriverReadinessInsight {
        let behavior = profile.behavior
        guard behavior.recentMeasuredMiles >= configuration.minimumRecentQualityMiles,
              let recentRate = behavior.recentWeightedEventRatePerTenMiles,
              let recentScore = behavior.recentWeightedAverageScore else {
            return DriverReadinessInsight(
                id: "drivingQuality",
                title: "Recent driving quality",
                detail: "Recent coaching-event data is still thin, so it is not being used to judge this route.",
                state: .unmeasured,
                evidence: DriverReadinessEvidence(
                    source: .gpsMotion,
                    recordedValue: "\(milesText(behavior.recentMeasuredMiles)) of recent trace-backed driving",
                    comparisonTarget: "\(milesText(configuration.minimumRecentQualityMiles)) of recent driving",
                    routeEvidence: "Driving quality is reviewed separately from route exposure.",
                    collectionNote: "Rates use Roam’s existing braking, acceleration, cornering, and phone-motion coaching events."
                )
            )
        }

        let needsPractice = recentRate > 3.5 || recentScore < 75
        let recordText = "last \(milesText(behavior.recentMeasuredMiles)) · \(String(format: "%.1f", recentRate)) weighted coaching events per 10 mi · \(Int(recentScore.rounded()))/100"
        let detail: String
        if needsPractice {
            detail = "Recent trace-backed drives show \(recordText). Continue practicing smooth braking, acceleration, and turns before adding more demand."
        } else {
            detail = "Recent trace-backed drives show \(recordText). Keep using those calm driving habits on a new route."
        }
        return DriverReadinessInsight(
            id: "drivingQuality",
            title: "Recent driving quality",
            detail: detail,
            state: needsPractice ? .practiceNeeded : .matched,
            evidence: DriverReadinessEvidence(
                source: .gpsMotion,
                recordedValue: recordText,
                comparisonTarget: "Recent, trace-backed coaching data",
                routeEvidence: "Quality is coaching context, not a safety guarantee.",
                collectionNote: "Short or low-confidence drives do not contribute."
            )
        )
    }

    private static func historyInsight(
        profile: DriverReadinessProfile,
        configuration: Configuration
    ) -> DriverReadinessInsight {
        let recordText = historyBaseText(profile)
        let target = "\(configuration.minimumHistoryDriveCount) qualifying drives on \(configuration.minimumHistoryDayCount) days · \(milesText(configuration.minimumHistoryMiles)) · \(durationText(configuration.minimumHistoryTraceDuration))"
        return DriverReadinessInsight(
            id: "history",
            title: "Recorded history",
            detail: "\(recordText). Roam needs more repeated, trace-backed driving before comparing this route with confidence.",
            state: .informational,
            evidence: DriverReadinessEvidence(
                source: .gpsMotion,
                recordedValue: recordText,
                comparisonTarget: target,
                routeEvidence: "A route comparison needs repeated measured practice, not a single trip.",
                collectionNote: "Only medium- or high-confidence GPS and motion records count."
            )
        )
    }

    private static func historyRequirementSummary(
        profile: DriverReadinessProfile,
        configuration: Configuration
    ) -> String {
        if profile.qualifyingDriveCount == 0 {
            return "No qualifying GPS and motion drives are saved yet. Record a few manual drives before using this comparison."
        }
        return "\(historyBaseText(profile)). Save a few more qualifying drives on different days before relying on a route comparison."
    }

    private static func familiarityInsight(
        _ familiarity: RouteFamiliarity,
        routeMaxIntensity: Double
    ) -> DriverReadinessInsight {
        let percentage = percentText(familiarity.matchedShare)
        let recordText = familiarity.sampledPointCount == 0
            ? "No usable local GPS overlap"
            : "\(percentage) of sampled route distance overlaps saved, directionally aligned GPS traces"
        switch familiarity.level {
        case .unmeasured:
            return DriverReadinessInsight(
                id: "familiarity",
                title: "Route familiarity",
                detail: "Route overlap has not yet been measured because saved qualifying drives need usable continuous GPS traces.",
                state: .unmeasured,
                evidence: DriverReadinessEvidence(
                    source: .routeOverlap,
                    recordedValue: recordText,
                    comparisonTarget: nil,
                    routeEvidence: "Familiarity is calculated on-device from local GPS traces.",
                    collectionNote: nil
                )
            )
        case .unfamiliar:
            let needsPractice = routeMaxIntensity >= 0.60
            return DriverReadinessInsight(
                id: "familiarity",
                title: "Route familiarity",
                detail: "\(recordText). \(needsPractice ? "Practice the route with an adult before relying on familiarity." : "This route is not familiar yet, but the route-demand comparison above remains separate.")",
                state: needsPractice ? .practiceNeeded : .informational,
                evidence: DriverReadinessEvidence(
                    source: .routeOverlap,
                    recordedValue: recordText,
                    comparisonTarget: nil,
                    routeEvidence: "Only continuous traces traveling in the planned direction are matched.",
                    collectionNote: "Parallel roads and long GPS gaps are excluded."
                )
            )
        case .partlyFamiliar:
            return DriverReadinessInsight(
                id: "familiarity",
                title: "Route familiarity",
                detail: "\(recordText) across \(familiarity.matchingDriveCount) saved \(driveWord(familiarity.matchingDriveCount)).",
                state: .matched,
                evidence: DriverReadinessEvidence(
                    source: .routeOverlap,
                    recordedValue: recordText,
                    comparisonTarget: nil,
                    routeEvidence: "Part of the route has been driven before.",
                    collectionNote: nil
                )
            )
        case .familiar:
            return DriverReadinessInsight(
                id: "familiarity",
                title: "Route familiarity",
                detail: "\(recordText); the best single saved drive covered \(percentText(familiarity.bestSingleDriveShare)) of the route.",
                state: .matched,
                evidence: DriverReadinessEvidence(
                    source: .routeOverlap,
                    recordedValue: recordText,
                    comparisonTarget: nil,
                    routeEvidence: "Most of this route overlaps a continuous saved drive.",
                    collectionNote: nil
                )
            )
        }
    }

    private static func makeFamiliarity(
        for route: ScoredRoute,
        qualifyingDrives: [HistoryDrive],
        configuration: Configuration
    ) -> RouteFamiliarity {
        let planned = sampledRoute(polyline: route.polyline, limit: configuration.routeFamiliaritySampleLimit)
        guard planned.count >= 3 else {
            return RouteFamiliarity(
                level: .unmeasured,
                matchedShare: 0,
                sampledPointCount: 0,
                matchingPointCount: 0,
                bestSingleDriveShare: 0,
                longestContinuousShare: 0,
                matchingDriveCount: 0,
                mostRecentMatchingDrive: nil
            )
        }

        var combined = Array(repeating: false, count: planned.count)
        var bestShare = 0.0
        var bestContinuous = 0.0
        var matchingDrives = 0
        var mostRecent: Date?
        var sawUsableTrace = false

        for history in qualifyingDrives {
            let trace = DriveExperienceEngine.validTraceSegments(for: history.drive.route)
            guard trace.count >= 4 else { continue }
            sawUsableTrace = true
            let matches = matchingFlags(
                planned: planned,
                trace: evenlySampled(trace, limit: 1_200),
                threshold: configuration.routeFamiliarityDistanceMeters
            )
            let coverage = share(of: matches)
            let continuous = longestRunShare(of: matches)
            bestShare = max(bestShare, coverage)
            bestContinuous = max(bestContinuous, continuous)
            if coverage >= 0.10 {
                matchingDrives += 1
                if mostRecent == nil || history.drive.startedAt > mostRecent! {
                    mostRecent = history.drive.startedAt
                }
            }
            for index in combined.indices where matches[index] {
                combined[index] = true
            }
        }

        guard sawUsableTrace else {
            return RouteFamiliarity(
                level: .unmeasured,
                matchedShare: 0,
                sampledPointCount: planned.count,
                matchingPointCount: 0,
                bestSingleDriveShare: 0,
                longestContinuousShare: 0,
                matchingDriveCount: 0,
                mostRecentMatchingDrive: nil
            )
        }

        let combinedShare = share(of: combined)
        let level: RouteFamiliarityLevel
        if bestShare >= 0.65 && bestContinuous >= 0.45 {
            level = .familiar
        } else if combinedShare >= 0.15 {
            level = .partlyFamiliar
        } else {
            level = .unfamiliar
        }
        return RouteFamiliarity(
            level: level,
            matchedShare: combinedShare,
            sampledPointCount: planned.count,
            matchingPointCount: combined.filter { $0 }.count,
            bestSingleDriveShare: bestShare,
            longestContinuousShare: bestContinuous,
            matchingDriveCount: matchingDrives,
            mostRecentMatchingDrive: mostRecent
        )
    }

    private static func demandCoverage(
        demands: [RouteDemand],
        samples: [RouteProgressSample],
        matches: OrderedRouteMatches,
        threshold: Double,
        fullRouteCoverage: Double,
        fullRouteContinuousCoverage: Double,
        minimumContinuousCoverage: Double
    ) -> [VerifiedDemandExposure] {
        guard samples.count == matches.flags.count else { return [] }
        return demands.compactMap { demand in
            guard demand.available, demand.intensity >= 0.34 else {
                return nil
            }
            let routeWideCondition = demand.kind == .weatherVisibility ||
                demand.kind == .traffic ||
                demand.kind == .roadConditions
            guard let ranges = demand.coverageRanges, !ranges.isEmpty else {
                // Weather, traffic, and road data are route-wide snapshots in
                // this release. They have no honest map section, but a manual
                // drive that substantially followed the full plan can retain
                // that it was recorded against the planned snapshot. The
                // readiness copy makes clear this never proves today's live
                // conditions.
                guard routeWideCondition,
                      fullRouteCoverage >= threshold,
                      fullRouteContinuousCoverage >= minimumContinuousCoverage else {
                    return nil
                }
                return VerifiedDemandExposure(
                    demandID: demand.id,
                    demandIntensity: demand.intensity,
                    coveredShare: fullRouteCoverage,
                    routeShare: 1,
                    recordedAt: Date()
                )
            }
            let normalizedRanges = ranges.map(\.normalized)
            let indices = samples.indices.filter { index in
                normalizedRanges.contains { range in
                    samples[index].fraction >= range.startFraction && samples[index].fraction <= range.endFraction
                }
            }
            guard !indices.isEmpty else { return nil }
            let covered = Double(indices.filter { matches.flags[$0] }.count) / Double(indices.count)
            let continuous = longestOrderedContinuousShare(matches, limitedTo: indices)
            let routeShare = Double(indices.count) / Double(samples.count)
            guard covered >= threshold, continuous >= threshold else { return nil }
            return VerifiedDemandExposure(
                demandID: demand.id,
                demandIntensity: demand.intensity,
                coveredShare: covered,
                routeShare: routeShare,
                recordedAt: Date()
            )
        }
    }

    private static func sampledRoute(polyline: String, limit: Int) -> [RouteProgressSample] {
        let coordinates = RoutePolylineDecoder.decode(polyline).filter(CLLocationCoordinate2DIsValid)
        guard coordinates.count >= 2 else { return [] }
        let distances = zip(coordinates, coordinates.dropFirst()).map {
            coordinateDistanceMeters(DriveCoordinate($0.0), DriveCoordinate($0.1))
        }
        let total = distances.reduce(0, +)
        guard total > 0 else { return [] }
        let count = min(limit, max(40, Int((total / 35).rounded()) + 1))
        let spacing = total / Double(max(1, count - 1))
        var samples: [RouteProgressSample] = []
        var segmentIndex = 0
        var beforeSegment = 0.0

        for sampleIndex in 0..<count {
            let target = min(total, Double(sampleIndex) * spacing)
            while segmentIndex < distances.count - 1,
                  target > beforeSegment + distances[segmentIndex] {
                beforeSegment += distances[segmentIndex]
                segmentIndex += 1
            }
            let segmentDistance = max(0.001, distances[segmentIndex])
            let withinSegment = min(1, max(0, (target - beforeSegment) / segmentDistance))
            let start = coordinates[segmentIndex]
            let end = coordinates[segmentIndex + 1]
            samples.append(
                RouteProgressSample(
                    coordinate: interpolatedCoordinate(from: start, to: end, fraction: withinSegment),
                    fraction: target / total,
                    bearing: bearing(from: start, to: end)
                )
            )
        }
        return samples
    }

    private static func matchingFlags(
        planned: [RouteProgressSample],
        trace: [DriveTraceSegment],
        threshold: CLLocationDistance
    ) -> [Bool] {
        planned.map { sample in
            trace.contains { segment in
                guard directionDifferenceDegrees(sample.bearing, bearing(
                    from: segment.start.coordinate.clLocationCoordinate,
                    to: segment.end.coordinate.clLocationCoordinate
                )) <= 75 else {
                    return false
                }
                return distanceFromSegmentMeters(
                    sample.coordinate,
                    start: segment.start.coordinate.clLocationCoordinate,
                    end: segment.end.coordinate.clLocationCoordinate
                ) <= threshold
            }
        }
    }

    /// A stricter matcher used only to verify a manually queued practice
    /// route. Each planned sample consumes a later segment of the recorded
    /// trace, so proximity alone cannot turn a reversed or scattered trip into
    /// a route match. Familiarity deliberately remains a looser local cue.
    private static func orderedPracticeMatches(
        planned: [RouteProgressSample],
        trace: [DriveTraceSegment],
        threshold: CLLocationDistance
    ) -> OrderedRouteMatches {
        guard !planned.isEmpty, !trace.isEmpty else {
            return OrderedRouteMatches(flags: [], traceIndices: [], continuityGroups: [])
        }

        var group = 0
        var groups: [Int] = []
        for index in trace.indices {
            if index > 0, !traceSegmentsAreContinuous(trace[index - 1], trace[index]) {
                group += 1
            }
            groups.append(group)
        }

        var flags: [Bool] = []
        var traceIndices: [Int?] = []
        var continuityGroups: [Int?] = []
        var lastTraceIndex = -1

        for sample in planned {
            var matchedIndex: Int?
            if lastTraceIndex + 1 < trace.count {
                for index in (lastTraceIndex + 1)..<trace.count {
                    if traceSegment(trace[index], matches: sample, threshold: threshold) {
                        matchedIndex = index
                        break
                    }
                }
            }
            guard let index = matchedIndex else {
                flags.append(false)
                traceIndices.append(nil)
                continuityGroups.append(nil)
                continue
            }
            flags.append(true)
            traceIndices.append(index)
            continuityGroups.append(groups[index])
            lastTraceIndex = index
        }

        return OrderedRouteMatches(
            flags: flags,
            traceIndices: traceIndices,
            continuityGroups: continuityGroups
        )
    }

    private static func traceSegment(
        _ segment: DriveTraceSegment,
        matches sample: RouteProgressSample,
        threshold: CLLocationDistance
    ) -> Bool {
        guard directionDifferenceDegrees(
            sample.bearing,
            bearing(
                from: segment.start.coordinate.clLocationCoordinate,
                to: segment.end.coordinate.clLocationCoordinate
            )
        ) <= 60 else {
            return false
        }
        return distanceFromSegmentMeters(
            sample.coordinate,
            start: segment.start.coordinate.clLocationCoordinate,
            end: segment.end.coordinate.clLocationCoordinate
        ) <= threshold
    }

    private static func traceSegmentsAreContinuous(
        _ lhs: DriveTraceSegment,
        _ rhs: DriveTraceSegment
    ) -> Bool {
        lhs.endIndex == rhs.startIndex &&
            abs(rhs.start.timestamp.timeIntervalSince(lhs.end.timestamp)) < 0.01
    }

    private static func longestOrderedContinuousShare(
        _ matches: OrderedRouteMatches,
        limitedTo indices: [Int]? = nil
    ) -> Double {
        let selected = indices ?? Array(matches.flags.indices)
        guard !selected.isEmpty else { return 0 }
        var longest = 0
        var current = 0
        var previousSampleIndex: Int?
        var previousGroup: Int?

        for index in selected {
            let isMatched = matches.flags[index]
            let group = matches.continuityGroups[index]
            let continues = isMatched &&
                previousSampleIndex.map { $0 + 1 == index } == true &&
                previousGroup == group
            if continues {
                current += 1
            } else if isMatched {
                current = 1
            } else {
                current = 0
            }
            longest = max(longest, current)
            previousSampleIndex = index
            previousGroup = isMatched ? group : nil
        }
        return Double(longest) / Double(selected.count)
    }

    private static func routeDistanceMeters(for polyline: String) -> CLLocationDistance {
        let coordinates = RoutePolylineDecoder.decode(polyline).filter(CLLocationCoordinate2DIsValid)
        return zip(coordinates, coordinates.dropFirst()).reduce(0) {
            $0 + coordinateDistanceMeters(DriveCoordinate($1.0), DriveCoordinate($1.1))
        }
    }

    private static func share(of flags: [Bool]) -> Double {
        guard !flags.isEmpty else { return 0 }
        return Double(flags.filter { $0 }.count) / Double(flags.count)
    }

    private static func longestRunShare(of flags: [Bool]) -> Double {
        guard !flags.isEmpty else { return 0 }
        var longest = 0
        var current = 0
        for value in flags {
            if value {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return Double(longest) / Double(flags.count)
    }

    private static func evenlySampled<Element>(_ values: [Element], limit: Int) -> [Element] {
        guard values.count > limit else { return values }
        let step = Double(values.count - 1) / Double(limit - 1)
        return (0..<limit).map { values[Int((Double($0) * step).rounded())] }
    }

    private static func coordinateDistanceMeters(
        _ lhs: DriveCoordinate,
        _ rhs: DriveCoordinate
    ) -> CLLocationDistance {
        DriveExperienceEngine.coordinateDistanceMeters(lhs, rhs)
    }

    private static func interpolatedCoordinate(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        fraction: Double
    ) -> DriveCoordinate {
        let longitudeDelta = normalizedLongitudeDelta(end.longitude - start.longitude)
        return DriveCoordinate(
            CLLocationCoordinate2D(
                latitude: start.latitude + (end.latitude - start.latitude) * fraction,
                longitude: start.longitude + longitudeDelta * fraction
            )
        )
    }

    private static func bearing(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> Double {
        let radians = Double.pi / 180
        let latitude1 = start.latitude * radians
        let latitude2 = end.latitude * radians
        let longitudeDelta = normalizedLongitudeDelta(end.longitude - start.longitude) * radians
        let y = sin(longitudeDelta) * cos(latitude2)
        let x = cos(latitude1) * sin(latitude2) - sin(latitude1) * cos(latitude2) * cos(longitudeDelta)
        let value = atan2(y, x) * 180 / Double.pi
        return (value + 360).truncatingRemainder(dividingBy: 360)
    }

    private static func directionDifferenceDegrees(_ lhs: Double, _ rhs: Double) -> Double {
        let difference = abs((lhs - rhs).truncatingRemainder(dividingBy: 360))
        return difference > 180 ? 360 - difference : difference
    }

    /// Local equirectangular projection is accurate enough for a nearby
    /// 60-meter comparison and avoids needing MapKit in this pure model.
    private static func distanceFromSegmentMeters(
        _ point: DriveCoordinate,
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        let earthRadius = 6_371_000.0
        let radians = Double.pi / 180
        let referenceLatitude = point.latitude * radians

        func projection(_ coordinate: CLLocationCoordinate2D) -> (x: Double, y: Double) {
            let longitudeDelta = normalizedLongitudeDelta(coordinate.longitude - point.longitude) * radians
            return (
                x: longitudeDelta * earthRadius * cos(referenceLatitude),
                y: (coordinate.latitude - point.latitude) * radians * earthRadius
            )
        }

        let a = projection(start)
        let b = projection(end)
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(a.x, a.y) }
        let progress = min(1, max(0, -(a.x * dx + a.y * dy) / lengthSquared))
        return hypot(a.x + progress * dx, a.y + progress * dy)
    }

    private static func normalizedLongitudeDelta(_ degrees: Double) -> Double {
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        if wrapped > 180 { return wrapped - 360 }
        if wrapped < -180 { return wrapped + 360 }
        return wrapped
    }

    private static func isStale(
        _ date: Date?,
        referenceDate: Date,
        configuration: Configuration
    ) -> Bool {
        guard let date else { return true }
        return referenceDate.timeIntervalSince(date) > configuration.staleExperienceDays * 86_400
    }

    private static func isWithinRecentWindow(
        _ date: Date,
        referenceDate: Date,
        configuration: Configuration
    ) -> Bool {
        let age = referenceDate.timeIntervalSince(date)
        return age >= 0 && age <= configuration.recentWindowDays * 86_400
    }

    private static func historyBaseText(_ profile: DriverReadinessProfile) -> String {
        "\(profile.qualifyingDriveCount) qualifying \(driveWord(profile.qualifyingDriveCount)) · \(milesText(profile.reliableTraceMiles)) of validated GPS trace · \(profile.qualifyingDriveDayCount) \(profile.qualifyingDriveDayCount == 1 ? "day" : "days")"
    }

    /// Group each drive by the local calendar day in effect when that drive was
    /// recorded. A later trip across time zones cannot silently rewrite the
    /// three-day history baseline.
    private static func dayKey(for drive: RecordedDrive, calendar: Calendar) -> String {
        let driveCalendar = DriveExperienceEngine.calendar(for: drive, base: calendar)
        let components = driveCalendar.dateComponents([.year, .month, .day], from: drive.startedAt)
        return [
            driveCalendar.timeZone.identifier,
            String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        ].joined(separator: "|")
    }

    private static func milesText(_ miles: Double) -> String {
        String(format: "%.1f mi", max(0, miles))
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let minutes = max(0, Int((duration / 60).rounded()))
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes) min"
    }

    private static func driveWord(_ count: Int) -> String {
        count == 1 ? "drive" : "drives"
    }

    private static func percentText(_ value: Double) -> String {
        "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
    }

    private static func recencyText(_ date: Date?, referenceDate: Date) -> String {
        guard let date else { return "" }
        let days = max(0, Int((referenceDate.timeIntervalSince(date) / 86_400).rounded(.down)))
        if days == 0 { return " today" }
        if days == 1 { return " 1 day ago" }
        return " \(days) days ago"
    }
}

/// Result of the in-memory route-practice matcher. It is deliberately not
/// Codable: only its privacy-safe `VerifiedDemandExposure` values are stored.
struct PracticeRouteCoverage {
    let overallCoverage: Double
    let longestContinuousCoverage: Double
    /// The leading and trailing route windows must both be observed before a
    /// saved drive is allowed to verify the complete planned route. This keeps
    /// a long but unrelated middle fragment from becoming a practice pass.
    let originCoverage: Double
    let destinationCoverage: Double
    let demandExposures: [VerifiedDemandExposure]
}

private struct HistoryDrive {
    let drive: RecordedDrive
    let summary: DriveExperienceSummary
}

private struct ExposureObservation {
    let miles: Double
    let duration: TimeInterval
    let date: Date
    let localDayKey: String
    let episodeDuration: TimeInterval
    let episodeMiles: Double
}

private struct ExposureAccumulator {
    var observations: [ExposureObservation] = []

    mutating func add(
        miles: Double,
        duration: TimeInterval,
        date: Date,
        localDayKey: String,
        episodeDuration: TimeInterval = 0,
        episodeMiles: Double = 0
    ) {
        guard miles > 0 || duration > 0 else { return }
        observations.append(
            ExposureObservation(
                miles: max(0, miles),
                duration: max(0, duration),
                date: date,
                localDayKey: localDayKey,
                episodeDuration: max(0, episodeDuration),
                episodeMiles: max(0, episodeMiles)
            )
        )
    }

    func makeExposure(
        referenceDate: Date,
        configuration: DriverReadinessEngine.Configuration
    ) -> DriverExperienceExposure {
        let recentThreshold = configuration.recentWindowDays * 86_400
        let recent = observations.filter {
            let age = referenceDate.timeIntervalSince($0.date)
            return age >= 0 && age <= recentThreshold
        }
        let recentMiles = recent
            .reduce(0) { $0 + $1.miles }
        let days = Set(observations.map(\.localDayKey))
        let recentDays = Set(recent.map(\.localDayKey))
        let halfLifeSeconds = configuration.experienceHalfLifeDays * 86_400
        let effectiveMiles = observations.reduce(0) { partial, observation in
            let age = max(0, referenceDate.timeIntervalSince(observation.date))
            let weight = pow(0.5, age / halfLifeSeconds)
            return partial + observation.miles * weight
        }
        let episodes = observations.compactMap { observation -> DriverExperienceEpisode? in
            guard observation.episodeDuration > 0 else { return nil }
            return DriverExperienceEpisode(
                duration: observation.episodeDuration,
                miles: observation.episodeMiles,
                recordedAt: observation.date,
                localDayKey: observation.localDayKey
            )
        }
        return DriverExperienceExposure(
            miles: observations.reduce(0) { $0 + $1.miles },
            effectiveMiles: effectiveMiles,
            duration: observations.reduce(0) { $0 + $1.duration },
            sessionCount: observations.count,
            distinctDayCount: days.count,
            recentMiles: recentMiles,
            recentSessionCount: recent.count,
            recentDistinctDayCount: recentDays.count,
            lastRecordedAt: observations.map(\.date).max(),
            longestEpisodeDuration: observations.map(\.episodeDuration).max() ?? 0,
            longestEpisodeMiles: observations.map(\.episodeMiles).max() ?? 0,
            episodes: episodes
        )
    }
}

private struct WeightedScoreAccumulator {
    private var totalWeight = 0.0
    private var totalScore = 0.0
    private var recentWeight = 0.0
    private var recentScore = 0.0

    mutating func add(
        score: Double,
        miles: Double,
        date: Date,
        referenceDate: Date,
        recentWindowDays: Double
    ) {
        let weight = min(12, max(1, miles))
        totalWeight += weight
        totalScore += score * weight
        if referenceDate.timeIntervalSince(date) <= recentWindowDays * 86_400 {
            recentWeight += weight
            recentScore += score * weight
        }
    }

    var average: Double? { totalWeight > 0 ? totalScore / totalWeight : nil }
    var recentAverage: Double? { recentWeight > 0 ? recentScore / recentWeight : nil }
}

private struct BehaviorAccumulator {
    private var measuredMiles = 0.0
    private var recentMeasuredMiles = 0.0
    private var weightedEvents = 0.0
    private var recentWeightedEvents = 0.0
    private var highSpeedMiles = 0.0
    private var highSpeedEvents = 0
    private var nightMiles = 0.0
    private var nightEvents = 0
    private var hardBrakes = 0
    private var sharpCorners = 0
    private var scoreAccumulator = WeightedScoreAccumulator()

    mutating func add(
        summary: DriveExperienceSummary,
        score: Double,
        miles: Double,
        date: Date,
        referenceDate: Date,
        recentWindowDays: Double
    ) {
        let events = summary.eventExposure
        let eventWeight = events.weightedCoachingEvents
        measuredMiles += miles
        weightedEvents += eventWeight
        highSpeedMiles += summary.speedExposure.milesAt45Plus
        highSpeedEvents += events.highSpeedEventCount
        nightMiles += summary.lightingExposure.afterDarkMiles
        nightEvents += events.afterDarkEventCount
        hardBrakes += events.hardBrakeCount
        sharpCorners += events.sharpCornerCount
        scoreAccumulator.add(
            score: score,
            miles: miles,
            date: date,
            referenceDate: referenceDate,
            recentWindowDays: recentWindowDays
        )
        if referenceDate.timeIntervalSince(date) <= recentWindowDays * 86_400 {
            recentMeasuredMiles += miles
            recentWeightedEvents += eventWeight
        }
    }

    func makeProfile() -> DrivingBehaviorProfile {
        func rate(_ amount: Double, miles: Double) -> Double? {
            guard miles >= 0.5 else { return nil }
            return amount / miles * 10
        }
        return DrivingBehaviorProfile(
            measuredMiles: measuredMiles,
            recentMeasuredMiles: recentMeasuredMiles,
            weightedEventRatePerTenMiles: rate(weightedEvents, miles: measuredMiles),
            recentWeightedEventRatePerTenMiles: rate(recentWeightedEvents, miles: recentMeasuredMiles),
            highSpeedEventRatePerTenMiles: rate(Double(highSpeedEvents), miles: highSpeedMiles),
            afterDarkEventRatePerTenMiles: rate(Double(nightEvents), miles: nightMiles),
            weightedAverageScore: scoreAccumulator.average,
            recentWeightedAverageScore: scoreAccumulator.recentAverage,
            hardBrakesPerTenMiles: rate(Double(hardBrakes), miles: measuredMiles),
            sharpCornersPerTenMiles: rate(Double(sharpCorners), miles: measuredMiles)
        )
    }
}

private struct RouteProgressSample {
    let coordinate: DriveCoordinate
    let fraction: Double
    let bearing: Double
}

private struct OrderedRouteMatches {
    let flags: [Bool]
    /// Index into the ordered, valid trace. `nil` means no order-preserving
    /// segment could be assigned to that planned sample.
    let traceIndices: [Int?]
    /// A run identifier separated at every dropped GPS segment or timestamp
    /// break. It prevents a background gap from becoming one continuous
    /// practice pass.
    let continuityGroups: [Int?]
}

/// A Foundation/CoreLocation-only Google encoded-polyline decoder. Keeping it
/// here lets readiness checks run without importing the SwiftUI map component.
enum RoutePolylineDecoder {
    static func decode(_ encoded: String) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        var index = encoded.startIndex
        var latitude: Int32 = 0
        var longitude: Int32 = 0

        while index < encoded.endIndex {
            guard let latitudeDelta = decodeComponent(from: encoded, index: &index) else { break }
            latitude += latitudeDelta
            guard let longitudeDelta = decodeComponent(from: encoded, index: &index) else { break }
            longitude += longitudeDelta
            coordinates.append(
                CLLocationCoordinate2D(
                    latitude: Double(latitude) / 1e5,
                    longitude: Double(longitude) / 1e5
                )
            )
        }
        return coordinates
    }

    private static func decodeComponent(from encoded: String, index: inout String.Index) -> Int32? {
        var result: Int32 = 0
        var shift: Int32 = 0
        var byte: Int32
        repeat {
            guard index < encoded.endIndex else { return nil }
            let scalar = encoded[index].asciiValue.map(Int32.init) ?? 0
            index = encoded.index(after: index)
            byte = scalar - 63
            result |= (byte & 0x1F) << shift
            shift += 5
        } while byte >= 0x20
        return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
    }
}
