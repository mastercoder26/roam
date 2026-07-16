import CoreLocation
import Foundation

/// The three coaching states shown for a route. These are deliberately not a
/// driving permission or safety guarantee.
enum DriverReadinessVerdict: String, Hashable {
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
    /// The app has not captured enough tagged information to compare this yet.
    case unmeasured
    /// A low-demand or unavailable route signal that should not affect advice.
    case informational
}

struct DriverReadinessInsight: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let state: DriverReadinessInsightState
}

enum RouteFamiliarityLevel: String, Hashable {
    case unmeasured
    case unfamiliar
    case partlyFamiliar
    case familiar
}

/// Local GPS overlap only. No familiarity value or recorded trace is sent to
/// the route-analysis backend.
struct RouteFamiliarity: Hashable {
    let level: RouteFamiliarityLevel
    let matchedShare: Double
    let sampledPointCount: Int
    let matchingPointCount: Int
}

/// A private, aggregate view of usable drives on this phone. It intentionally
/// contains no route geometry, origin, destination, or cloud identifier.
struct DriverReadinessProfile: Hashable {
    let qualifyingDriveCount: Int
    let totalMiles: Double
    let nightMiles: Double
    let highSpeedMiles: Double
    let longestDriveDuration: TimeInterval
    let averageDrivingScore: Double?
    let recentAverageDrivingScore: Double?
    let taggedExposureCounts: [String: Int]

    /// A small baseline avoids presenting a recommendation after one short
    /// errand, even when that errand had a high-confidence sensor score.
    var hasEnoughRecordedExperience: Bool {
        qualifyingDriveCount >= 2 && totalMiles >= 5
    }

    func taggedExposureCount(for demand: RouteDemandKind) -> Int {
        taggedExposureCounts[demand.rawValue, default: 0]
    }
}

struct DriverReadinessAssessment: Hashable {
    let verdict: DriverReadinessVerdict
    let headline: String
    let summary: String
    let insights: [DriverReadinessInsight]
    let profile: DriverReadinessProfile
    let familiarity: RouteFamiliarity
}

/// Pure local reasoning for the “Can I drive this?” experience. Route demands
/// arrive from the backend, while every experience signal is calculated from
/// local `RecordedDrive` data only.
enum DriverReadinessEngine {
    struct Configuration: Hashable {
        let minimumQualifyingDuration: TimeInterval
        let minimumQualifyingMiles: Double
        let highSpeedThresholdMPH: Double
        let routeFamiliarityDistanceMeters: CLLocationDistance
        let routeFamiliaritySampleLimit: Int
        let nightStartHour: Int
        let nightEndHour: Int

        init(
            minimumQualifyingDuration: TimeInterval = 5 * 60,
            minimumQualifyingMiles: Double = 1,
            highSpeedThresholdMPH: Double = 45,
            routeFamiliarityDistanceMeters: CLLocationDistance = 125,
            routeFamiliaritySampleLimit: Int = 120,
            nightStartHour: Int = 20,
            nightEndHour: Int = 6
        ) {
            self.minimumQualifyingDuration = minimumQualifyingDuration
            self.minimumQualifyingMiles = minimumQualifyingMiles
            self.highSpeedThresholdMPH = highSpeedThresholdMPH
            self.routeFamiliarityDistanceMeters = routeFamiliarityDistanceMeters
            self.routeFamiliaritySampleLimit = max(2, routeFamiliaritySampleLimit)
            self.nightStartHour = nightStartHour
            self.nightEndHour = nightEndHour
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
            calendar: .current
        )
    }

    /// An injectable calendar and configuration keep the calculation fully
    /// deterministic in checks without adding mutable global state.
    static func assess(
        route: ScoredRoute,
        recordedDrives: [RecordedDrive],
        configuration: Configuration,
        calendar: Calendar
    ) -> DriverReadinessAssessment {
        let qualifyingDrives = qualifyingDrives(
            from: recordedDrives,
            configuration: configuration
        )
        let profile = makeProfile(
            qualifyingDrives: qualifyingDrives,
            configuration: configuration,
            calendar: calendar
        )
        let familiarity = makeFamiliarity(
            for: route,
            qualifyingDrives: qualifyingDrives,
            configuration: configuration
        )

        guard profile.hasEnoughRecordedExperience else {
            let historyDetail: String
            if profile.qualifyingDriveCount == 0 {
                historyDetail = "Save at least two qualifying drives before comparing this route with recorded experience."
            } else {
                historyDetail = "One qualifying drive is saved so far. A little more recorded driving will make this comparison more useful."
            }
            return DriverReadinessAssessment(
                verdict: .insufficientHistory,
                headline: DriverReadinessVerdict.insufficientHistory.title,
                summary: historyDetail,
                insights: [familiarityInsight(familiarity)],
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
                        state: .informational
                    ),
                    familiarityInsight(familiarity)
                ],
                profile: profile,
                familiarity: familiarity
            )
        }

        var insights = routeDemands.map {
            readinessInsight(
                for: $0,
                route: route,
                profile: profile
            )
        }
        insights.append(drivingQualityInsight(profile))
        insights.append(familiarityInsight(familiarity))

        let hasPracticeGap = insights.contains { insight in
            switch insight.state {
            case .practiceNeeded:
                return true
            case .unmeasured:
                // Unknown experience becomes coaching guidance only when the
                // verified route demand is meaningful, never for a low signal.
                return (routeDemands.first(where: { $0.id == insight.id })?.intensity ?? 0) >= 0.6
            case .matched, .informational:
                return false
            }
        }

        let verdict: DriverReadinessVerdict = hasPracticeGap ? .practiceWithAdult : .looksLikeMatch
        let summary: String
        switch verdict {
        case .looksLikeMatch:
            summary = "Based on qualifying drives saved on this phone, this route’s measured demands fit the experience we can compare."
        case .practiceWithAdult:
            summary = "This route includes a demand that is new, lightly practiced, or not yet measured in saved drives."
        case .insufficientHistory:
            summary = "Save more qualifying drives to build a useful comparison."
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
            calendar: .current
        )
    }

    static func profile(
        from recordedDrives: [RecordedDrive],
        configuration: Configuration,
        calendar: Calendar
    ) -> DriverReadinessProfile {
        makeProfile(
            qualifyingDrives: qualifyingDrives(from: recordedDrives, configuration: configuration),
            configuration: configuration,
            calendar: calendar
        )
    }

    static func qualifies(
        _ drive: RecordedDrive,
        configuration: Configuration = Configuration()
    ) -> Bool {
        guard drive.score.dataQuality.confidence == .medium || drive.score.dataQuality.confidence == .high else {
            return false
        }
        return drive.score.duration >= configuration.minimumQualifyingDuration ||
            drive.score.distanceMiles >= configuration.minimumQualifyingMiles
    }

    /// Verifies that a manually recorded drive substantially followed the route
    /// selected immediately before it. The route polyline stays in memory for
    /// this comparison; callers should persist only the returned Boolean.
    static func matchesPlannedPracticeRoute(
        plannedPolyline: String,
        recordedRoute: [DriveRoutePoint]
    ) -> Bool {
        let plannedCoordinates = RoutePolylineDecoder.decode(plannedPolyline)
            .filter(CLLocationCoordinate2DIsValid)
        let recordedCoordinates = recordedRoute.map(\.coordinate)
            .filter { CLLocationCoordinate2DIsValid($0.clLocationCoordinate) }

        // A handful of distinct fixes protects against a short stationary
        // sample accidentally satisfying a sparse polyline.
        guard plannedCoordinates.count >= 2, recordedCoordinates.count >= 5 else {
            return false
        }

        let distanceThreshold: CLLocationDistance = 150
        let requiredMatchingShare = 0.60
        let recordedSample = evenlySampled(recordedCoordinates, limit: 600)
        let plannedSample = evenlySampled(plannedCoordinates, limit: 180)
        let recordedPolyline = recordedCoordinates.map(\.clLocationCoordinate)

        let recordedShare = matchingShare(
            recordedSample,
            within: distanceThreshold,
            of: plannedCoordinates
        )
        guard recordedShare >= requiredMatchingShare else { return false }

        // Check the reverse direction too. A loop around one short section of
        // the planned drive should not be treated as having practiced the
        // whole route merely because every recorded point is nearby.
        let plannedShare = matchingShare(
            plannedSample.map(DriveCoordinate.init),
            within: distanceThreshold,
            of: recordedPolyline
        )
        return plannedShare >= requiredMatchingShare
    }

    private static func qualifyingDrives(
        from recordedDrives: [RecordedDrive],
        configuration: Configuration
    ) -> [RecordedDrive] {
        recordedDrives.filter { qualifies($0, configuration: configuration) }
    }

    private static func makeProfile(
        qualifyingDrives: [RecordedDrive],
        configuration: Configuration,
        calendar: Calendar
    ) -> DriverReadinessProfile {
        var nightMiles = 0.0
        var highSpeedMiles = 0.0
        var exposures: [String: Int] = [:]

        for drive in qualifyingDrives {
            let distance = routeDistanceBreakdown(
                for: drive,
                configuration: configuration,
                calendar: calendar
            )
            nightMiles += distance.nightMiles
            highSpeedMiles += distance.highSpeedMiles

            guard drive.plannedRouteContext?.recordedRouteMatched == true else { continue }
            for demand in drive.plannedRouteContext?.routeDemands ?? [] where demand.available && demand.intensity >= 0.34 {
                exposures[demand.id, default: 0] += 1
            }
        }

        let sortedByMostRecent = qualifyingDrives.sorted { $0.startedAt > $1.startedAt }
        let scores = qualifyingDrives.map { Double($0.score.score) }
        let recentScores = sortedByMostRecent.prefix(5).map { Double($0.score.score) }
        let averageScore = scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
        let recentAverage = recentScores.isEmpty ? nil : recentScores.reduce(0, +) / Double(recentScores.count)

        return DriverReadinessProfile(
            qualifyingDriveCount: qualifyingDrives.count,
            totalMiles: qualifyingDrives.reduce(0) { $0 + $1.score.distanceMiles },
            nightMiles: nightMiles,
            highSpeedMiles: highSpeedMiles,
            longestDriveDuration: qualifyingDrives.map(\.score.duration).max() ?? 0,
            averageDrivingScore: averageScore,
            recentAverageDrivingScore: recentAverage,
            taggedExposureCounts: exposures
        )
    }

    private static func routeDistanceBreakdown(
        for drive: RecordedDrive,
        configuration: Configuration,
        calendar: Calendar
    ) -> (nightMiles: Double, highSpeedMiles: Double) {
        guard drive.route.count > 1 else { return (0, 0) }

        var nightMiles = 0.0
        var highSpeedMiles = 0.0
        for (previous, current) in zip(drive.route, drive.route.dropFirst()) {
            let elapsed = current.timestamp.timeIntervalSince(previous.timestamp)
            // Do not turn a GPS gap into evidence for a route characteristic.
            guard elapsed > 0, elapsed <= 120 else { continue }
            let meters = coordinateDistanceMeters(previous.coordinate, current.coordinate)
            guard meters.isFinite, meters > 0, meters < 2_500 else { continue }
            let miles = meters / 1_609.344

            if isAfterDark(current.timestamp, calendar: calendar, configuration: configuration) {
                nightMiles += miles
            }
            let fastestMetersPerSecond = max(previous.speedMetersPerSecond, current.speedMetersPerSecond)
            if fastestMetersPerSecond * 2.236936 >= configuration.highSpeedThresholdMPH {
                highSpeedMiles += miles
            }
        }
        return (nightMiles, highSpeedMiles)
    }

    private static func isAfterDark(
        _ date: Date,
        calendar: Calendar,
        configuration: Configuration
    ) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= configuration.nightStartHour || hour < configuration.nightEndHour
    }

    private static func readinessInsight(
        for demand: RouteDemand,
        route: ScoredRoute,
        profile: DriverReadinessProfile
    ) -> DriverReadinessInsight {
        let routeEvidence = demand.evidence.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = routeEvidence.isEmpty ? "" : "\(routeEvidence) "

        guard demand.available else {
            return DriverReadinessInsight(
                id: demand.id,
                title: demand.title,
                detail: prefix + "This route characteristic was not available to compare.",
                state: .informational
            )
        }

        guard demand.level != .low && demand.intensity >= 0.34 else {
            return DriverReadinessInsight(
                id: demand.id,
                title: demand.title,
                detail: prefix + "This is a lower-demand part of this route.",
                state: .informational
            )
        }

        switch demand.kind {
        case .afterDark:
            let target = comparableMiles(for: route, intensity: demand.intensity)
            return mileageInsight(
                demand: demand,
                routeEvidencePrefix: prefix,
                recordedMiles: profile.nightMiles,
                targetMiles: target,
                experienceName: "after-dark driving"
            )
        case .fastRoads:
            let target = comparableMiles(for: route, intensity: demand.intensity)
            return mileageInsight(
                demand: demand,
                routeEvidencePrefix: prefix,
                recordedMiles: profile.highSpeedMiles,
                targetMiles: target,
                experienceName: "45+ mph driving"
            )
        case .sustainedDrive:
            let target = max(10 * 60, Double(route.durationSeconds) * 0.75)
            let longest = profile.longestDriveDuration
            if longest >= target {
                return DriverReadinessInsight(
                    id: demand.id,
                    title: demand.title,
                    detail: prefix + "Your longest qualifying drive is \(durationText(longest)), which is comparable with this trip.",
                    state: .matched
                )
            }
            return DriverReadinessInsight(
                id: demand.id,
                title: demand.title,
                detail: prefix + "Your longest qualifying drive is \(durationText(longest)); a longer supervised practice drive would make this comparison stronger.",
                state: .practiceNeeded
            )
        case .merges, .complexIntersections, .weatherVisibility, .traffic, .roadConditions:
            let count = demand.kind.map { profile.taggedExposureCount(for: $0) } ?? 0
            if count > 0 {
                let driveText = count == 1
                    ? "1 saved practice drive substantially overlapped a route planned with this demand."
                    : "\(count) saved practice drives substantially overlapped routes planned with this demand."
                return DriverReadinessInsight(
                    id: demand.id,
                    title: demand.title,
                    detail: prefix + driveText,
                    state: .matched
                )
            }
            return DriverReadinessInsight(
                id: demand.id,
                title: demand.title,
                detail: prefix + "Experience with this route demand is not yet measured on a saved practice drive.",
                state: .unmeasured
            )
        case .none:
            return DriverReadinessInsight(
                id: demand.id,
                title: demand.title,
                detail: prefix + "Experience with this route demand is not yet measured.",
                state: .unmeasured
            )
        }
    }

    private static func mileageInsight(
        demand: RouteDemand,
        routeEvidencePrefix: String,
        recordedMiles: Double,
        targetMiles: Double,
        experienceName: String
    ) -> DriverReadinessInsight {
        if recordedMiles >= targetMiles {
            return DriverReadinessInsight(
                id: demand.id,
                title: demand.title,
                detail: routeEvidencePrefix + "\(milesText(recordedMiles)) of \(experienceName) is saved on this phone.",
                state: .matched
            )
        }
        return DriverReadinessInsight(
            id: demand.id,
            title: demand.title,
            detail: routeEvidencePrefix + "\(milesText(recordedMiles)) of \(experienceName) is saved; supervised practice would make the comparison stronger.",
            state: .practiceNeeded
        )
    }

    private static func comparableMiles(for route: ScoredRoute, intensity: Double) -> Double {
        // A route does not require a teen to have already driven its entire
        // length; cap the evidence target while still scaling short routes.
        max(1, min(12, route.distanceMiles * max(0.35, intensity) * 0.65))
    }

    private static func familiarityInsight(_ familiarity: RouteFamiliarity) -> DriverReadinessInsight {
        switch familiarity.level {
        case .unmeasured:
            return DriverReadinessInsight(
                id: "familiarity",
                title: "Route familiarity",
                detail: "Route overlap has not yet been measured because saved qualifying drives need usable GPS traces.",
                state: .unmeasured
            )
        case .unfamiliar:
            return DriverReadinessInsight(
                id: "familiarity",
                title: "Route familiarity",
                detail: "Very little of this route overlaps with saved qualifying drives. Practice the route with an adult before relying on that familiarity.",
                state: .practiceNeeded
            )
        case .partlyFamiliar:
            return DriverReadinessInsight(
                id: "familiarity",
                title: "Route familiarity",
                detail: "Part of this route overlaps with saved qualifying drives.",
                state: .matched
            )
        case .familiar:
            return DriverReadinessInsight(
                id: "familiarity",
                title: "Route familiarity",
                detail: "Most of this route overlaps with saved qualifying drives.",
                state: .matched
            )
        }
    }

    private static func drivingQualityInsight(_ profile: DriverReadinessProfile) -> DriverReadinessInsight {
        let score = profile.recentAverageDrivingScore ?? profile.averageDrivingScore ?? 0
        if score < 70 {
            return DriverReadinessInsight(
                id: "drivingQuality",
                title: "Recent driving quality",
                detail: "Recent qualifying drives average \(Int(score.rounded()))/100. Continue practicing smooth braking, acceleration, and turns before taking on more demand.",
                state: .practiceNeeded
            )
        }
        return DriverReadinessInsight(
            id: "drivingQuality",
            title: "Recent driving quality",
            detail: "Recent qualifying drives average \(Int(score.rounded()))/100. Keep using the same calm driving habits on a new route.",
            state: .matched
        )
    }

    private static func makeFamiliarity(
        for route: ScoredRoute,
        qualifyingDrives: [RecordedDrive],
        configuration: Configuration
    ) -> RouteFamiliarity {
        let plannedCoordinates = RoutePolylineDecoder.decode(route.polyline)
        let historicalCoordinates = qualifyingDrives.flatMap { $0.route.map(\.coordinate) }
        guard plannedCoordinates.count > 1, !historicalCoordinates.isEmpty else {
            return RouteFamiliarity(level: .unmeasured, matchedShare: 0, sampledPointCount: 0, matchingPointCount: 0)
        }

        let sample = evenlySampled(
            plannedCoordinates,
            limit: configuration.routeFamiliaritySampleLimit
        )
        // Bound work done when a user has many long local drives. This still
        // samples substantially more densely than the 125 m match threshold.
        let historySample = evenlySampled(historicalCoordinates, limit: 2_400)
        let matching = sample.filter { planned in
            historySample.contains {
                coordinateDistanceMeters($0, DriveCoordinate(planned)) <= configuration.routeFamiliarityDistanceMeters
            }
        }
        let share = sample.isEmpty ? 0 : Double(matching.count) / Double(sample.count)
        let level: RouteFamiliarityLevel
        switch share {
        case ..<0.1: level = .unfamiliar
        case ..<0.65: level = .partlyFamiliar
        default: level = .familiar
        }
        return RouteFamiliarity(
            level: level,
            matchedShare: share,
            sampledPointCount: sample.count,
            matchingPointCount: matching.count
        )
    }

    private static func evenlySampled<Element>(
        _ values: [Element],
        limit: Int
    ) -> [Element] {
        guard values.count > limit else { return values }
        let step = Double(values.count - 1) / Double(limit - 1)
        return (0..<limit).map { index in
            values[Int((Double(index) * step).rounded())]
        }
    }

    private static func coordinateDistanceMeters(_ lhs: DriveCoordinate, _ rhs: DriveCoordinate) -> CLLocationDistance {
        let latitudeRadians = Double.pi / 180
        let lhsLatitude = lhs.latitude * latitudeRadians
        let rhsLatitude = rhs.latitude * latitudeRadians
        let latitudeDelta = (rhs.latitude - lhs.latitude) * latitudeRadians
        let longitudeDelta = (rhs.longitude - lhs.longitude) * latitudeRadians
        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2) +
            cos(lhsLatitude) * cos(rhsLatitude) * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return 6_371_000 * 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }

    private static func matchingShare(
        _ points: [DriveCoordinate],
        within threshold: CLLocationDistance,
        of polyline: [CLLocationCoordinate2D]
    ) -> Double {
        guard !points.isEmpty, polyline.count >= 2 else { return 0 }
        let matched = points.reduce(into: 0) { count, point in
            if distanceFromPolylineMeters(point, polyline: polyline) <= threshold {
                count += 1
            }
        }
        return Double(matched) / Double(points.count)
    }

    /// Local equirectangular projection is accurate enough for a 150 m nearby
    /// check and avoids importing MapKit for this pure model calculation.
    private static func distanceFromPolylineMeters(
        _ point: DriveCoordinate,
        polyline: [CLLocationCoordinate2D]
    ) -> CLLocationDistance {
        guard polyline.count >= 2 else { return .greatestFiniteMagnitude }
        return zip(polyline, polyline.dropFirst()).reduce(.greatestFiniteMagnitude) { closest, segment in
            min(closest, distanceFromSegmentMeters(point, start: segment.0, end: segment.1))
        }
    }

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

    private static func milesText(_ miles: Double) -> String {
        String(format: "%.1f mi", miles)
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let minutes = max(0, Int((duration / 60).rounded()))
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes) min"
    }
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
