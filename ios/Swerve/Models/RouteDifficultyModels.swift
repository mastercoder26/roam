import Foundation
import CoreLocation

// MARK: - Request

struct RouteDifficultyRequest: Encodable {
    let origin: String
    let destination: String
    let departureTime: String
    /// The driver's selected local clock time, independent from server timezone.
    let departureLocalMinutes: Int
    let includeAlternates: Bool
    let continuousDriveMinutes: Double?
}

// MARK: - Response

struct RouteDifficultyResponse: Decodable {
    let primaryRoute: ScoredRoute
    let alternateRoutes: [ScoredRoute]
}

struct ScoredRoute: Decodable, Identifiable, Hashable {
    // Google route polylines commonly share their opening segment. The complete
    // encoded polyline is needed to keep SwiftUI identities distinct.
    var id: String { polyline }

    let score: Double
    let uncalibratedScore: Double?
    let label: DifficultyLabel
    let reasons: [String]
    let breakdown: DifficultyBreakdown
    let contributions: [FactorContribution]?
    let uncertainty: ScoreUncertainty?
    let hotspots: [SegmentHotspot]?
    let conditions: RouteConditions?
    let modelVersion: String?
    let distanceMeters: Int
    let durationSeconds: Int
    let staticDurationSeconds: Int
    let trafficDelaySeconds: Int
    let polyline: String
    let bounds: RouteBounds
    let scoreDelta: Double?
    /// A semantic, evidence-backed description of what this route asks of a
    /// driver. It is optional while older backend deployments are still in use.
    let routeDemands: [RouteDemand]?

    func hash(into hasher: inout Hasher) {
        hasher.combine(polyline)
    }

    static func == (lhs: ScoredRoute, rhs: ScoredRoute) -> Bool {
        lhs.polyline == rhs.polyline
    }
}

// MARK: - Route Readiness

/// Stable identifiers emitted by the route-analysis service. Keep these
/// identifiers separate from display copy: a planned practice drive stores only
/// the identifier and its factual route evidence, never an address or polyline.
enum RouteDemandKind: String, Codable, CaseIterable, Hashable {
    case afterDark
    case fastRoads
    case merges
    case complexIntersections
    case weatherVisibility
    case sustainedDrive
    case traffic
    case roadConditions

    var defaultTitle: String {
        switch self {
        case .afterDark: "After-dark driving"
        case .fastRoads: "Fast roads"
        case .merges: "Merges"
        case .complexIntersections: "Complex intersections"
        case .weatherVisibility: "Weather and visibility"
        case .sustainedDrive: "Sustained drive"
        case .traffic: "Traffic"
        case .roadConditions: "Road conditions"
        }
    }
}

enum RouteDemandLevel: String, Codable, Hashable {
    case low
    case moderate
    case high

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "low", "minimal": self = .low
        case "moderate", "medium", "elevated": self = .moderate
        case "high", "severe": self = .high
        default:
            // The numeric intensity remains available to the UI and readiness
            // engine even if a newer server introduces a display level.
            self = .moderate
        }
    }
}

/// A verified route characteristic returned by the backend. `evidence` is a
/// concise factual sentence, such as "42% of the route is on major roads.".
struct RouteDemand: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let intensity: Double
    let level: RouteDemandLevel
    let evidence: String
    let available: Bool

    init(
        id: String,
        title: String? = nil,
        intensity: Double,
        level: RouteDemandLevel,
        evidence: String,
        available: Bool
    ) {
        self.id = id
        self.title = title ?? RouteDemandKind(rawValue: id)?.defaultTitle ?? id
        self.intensity = min(max(intensity, 0), 1)
        self.level = level
        self.evidence = evidence
        self.available = available
    }

    var kind: RouteDemandKind? {
        RouteDemandKind(rawValue: id)
    }
}

struct FactorContribution: Decodable, Identifiable {
    var id: String { factor }
    let factor: String
    let label: String
    let value: Double
    let weight: Double
    let contribution: Double
    let share: Double
}

struct ScoreUncertainty: Decodable {
    let low: Double
    let high: Double
    let confidence: Double
    let spread: Double

    var formattedBand: String {
        String(format: "%.1f – %.1f", low, high)
    }
}

struct SegmentHotspot: Decodable, Identifiable {
    var id: Int { segmentIndex }
    let segmentIndex: Int
    let difficulty: Double
    let cumulativeSecondsFromStart: Double
    let label: String?
}

struct DifficultyBreakdown: Decodable {
    let speed: Double?
    let merges: Double?
    let turns: Double?
    let traffic: Double
    let length: Double?
    let fatigue: Double?
    let weather: Double?
    let road: Double?
    let highway: Double
    let maneuvers: Double
    let navDensity: Double
    let effort: Double

    var items: [(key: String, title: String, value: Double)] {
        if speed != nil {
            var rows: [(key: String, title: String, value: Double)] = [
                ("speed", "Speed", speed ?? highway),
                ("merges", "Merges", merges ?? 0),
                ("turns", "Turns", turns ?? maneuvers),
                ("traffic", "Traffic", traffic),
                ("length", "Length", length ?? effort),
                ("fatigue", "Drive Load", fatigue ?? 0)
            ]
            if let weather, weather > 0.02 {
                rows.append(("weather", "Weather", weather))
            }
            if let road, road > 0.02 {
                rows.append(("road", "Road Conditions", road))
            }
            return rows
        }
        return [
            ("highway", "Road Type", highway),
            ("maneuvers", "Turns", maneuvers),
            ("traffic", "Traffic", traffic),
            ("navDensity", "Navigation", navDensity),
            ("effort", "Drive Length", effort)
        ]
    }
}

// MARK: - Live Conditions

struct RouteConditions: Decodable {
    let weather: WeatherConditions
    let road: RoadConditions
    let turns: TurnExposure
    let sources: [String]
}

struct WeatherConditions: Decodable {
    let available: Bool
    let condition: String
    let severity: Double
    let precipIntensity: Double
    let snowRisk: Double
    let windSeverity: Double
    let lowVisibilityRisk: Double
    let icyRisk: Double
    let temperatureF: Double
    let windGustMph: Double
    let visibilityMiles: Double

    var systemImage: String {
        switch condition.lowercased() {
        case "clear": return "sun.max.fill"
        case "partly cloudy": return "cloud.sun.fill"
        case "overcast": return "cloud.fill"
        case "fog": return "cloud.fog.fill"
        case "drizzle": return "cloud.drizzle.fill"
        case "rain": return "cloud.rain.fill"
        case "freezing rain": return "cloud.sleet.fill"
        case "snow": return "cloud.snow.fill"
        case "thunderstorm": return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    var severityLabel: String {
        switch severity {
        case ..<0.15: return "Good"
        case ..<0.4: return "Fair"
        case ..<0.7: return "Poor"
        default: return "Severe"
        }
    }
}

struct RoadConditions: Decodable {
    let available: Bool
    let avgLanes: Double
    let narrowRoadShare: Double
    let majorRoadShare: Double
    let unpavedShare: Double
    let roadSizeScore: Double
    let constructionZones: Int
    let dominantRoadClass: String

    var dominantRoadLabel: String {
        switch dominantRoadClass {
        case "motorway", "motorway_link": return "Interstate / freeway"
        case "trunk", "trunk_link": return "Major highway"
        case "primary", "primary_link": return "Primary road"
        case "secondary", "secondary_link": return "Secondary road"
        case "tertiary", "tertiary_link": return "Local connector"
        case "residential": return "Residential streets"
        case "living_street", "service": return "Small access roads"
        case "track": return "Unpaved track"
        default: return "Mixed roads"
        }
    }
}

struct TurnExposure: Decodable {
    let available: Bool
    let unprotectedLeftTurns: Int
    let protectedLeftTurns: Int
    let unprotectedTurnShare: Double
}

struct RouteBounds: Decodable {
    let southwest: Coordinate
    let northeast: Coordinate

    var mapRect: (southwest: CLLocationCoordinate2D, northeast: CLLocationCoordinate2D) {
        (
            southwest: CLLocationCoordinate2D(latitude: southwest.latitude, longitude: southwest.longitude),
            northeast: CLLocationCoordinate2D(latitude: northeast.latitude, longitude: northeast.longitude)
        )
    }
}

struct Coordinate: Decodable {
    let latitude: Double
    let longitude: Double

    enum CodingKeys: String, CodingKey {
        case latitude = "lat"
        case longitude = "lng"
    }
}

enum DifficultyLabel: String, Decodable, CaseIterable {
    case veryEasy = "Very Easy"
    case easy = "Easy"
    case moderate = "Moderate"
    case hard = "Hard"
    case veryHard = "Very Hard"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let match = DifficultyLabel(rawValue: raw) {
            self = match
            return
        }
        switch raw.lowercased() {
        case "very easy": self = .veryEasy
        case "easy": self = .easy
        case "moderate": self = .moderate
        case "hard": self = .hard
        case "very hard": self = .veryHard
        default: self = .moderate
        }
    }
}

// MARK: - Formatting

extension ScoredRoute {
    var distanceMiles: Double {
        Double(distanceMeters) / 1609.344
    }

    var formattedDistance: String {
        String(format: "%.1f mi", distanceMiles)
    }

    var formattedDuration: String {
        Self.formatDuration(seconds: durationSeconds)
    }

    var formattedStaticDuration: String {
        Self.formatDuration(seconds: staticDurationSeconds)
    }

    var formattedDelay: String? {
        guard trafficDelaySeconds > 0 else { return nil }
        return "+\(Self.formatDuration(seconds: trafficDelaySeconds))"
    }

    var formattedScoreWithUncertainty: String {
        guard let uncertainty else {
            return String(format: "%.1f", score)
        }
        let half = uncertainty.spread / 2
        return String(format: "%.1f ± %.1f", score, half)
    }

    static func formatDuration(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes) min"
    }
}

extension DifficultyLabel {
    var colorName: String {
        switch self {
        case .veryEasy: return "DifficultyVeryEasy"
        case .easy: return "DifficultyEasy"
        case .moderate: return "DifficultyModerate"
        case .hard: return "DifficultyHard"
        case .veryHard: return "DifficultyVeryHard"
        }
    }

    var systemColor: (red: Double, green: Double, blue: Double) {
        switch self {
        case .veryEasy: return (0.20, 0.78, 0.35)
        case .easy: return (0.40, 0.85, 0.45)
        case .moderate: return (1.00, 0.80, 0.00)
        case .hard: return (1.00, 0.55, 0.20)
        case .veryHard: return (0.95, 0.25, 0.25)
        }
    }
}
