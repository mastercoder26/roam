import Foundation
import CoreLocation

struct DifficultyRequest: Encodable {
    let origin: String
    let destination: String
    let departureTime: String?
    let includeAlternates: Bool
    let continuousDriveMinutes: Int?
}

struct DifficultyResponse: Decodable {
    let primaryRoute: ScoredRoute
    let alternateRoutes: [AlternateRoute]
}

struct ScoredRoute: Decodable, Identifiable {
    var id: String { polyline }
    let score: Double
    let uncalibratedScore: Double?
    let label: String
    let reasons: [String]
    let breakdown: ScoringBreakdown
    let contributions: [FactorContribution]
    let uncertainty: ScoreUncertainty
    let hotspots: [SegmentHotspot]
    let conditions: RouteConditions?
    let modelVersion: String?
    let distanceMeters: Double
    let durationSeconds: Double
    let staticDurationSeconds: Double
    let trafficDelaySeconds: Double
    let polyline: String
    let bounds: RouteBounds

    var distanceText: String {
        String(format: "%.1f mi", distanceMeters / 1_609.34)
    }

    var durationText: String {
        let minutes = Int((durationSeconds / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60) hr \(minutes % 60) min" : "\(minutes) min"
    }
}

struct AlternateRoute: Decodable, Identifiable {
    var id: String { polyline }
    let scoreDelta: Double
    let score: Double
    let label: String
    let reasons: [String]
    let distanceMeters: Double
    let durationSeconds: Double
    let staticDurationSeconds: Double
    let trafficDelaySeconds: Double
    let polyline: String
    let bounds: RouteBounds
}

struct ScoringBreakdown: Decodable {
    let speed: Double
    let merges: Double
    let turns: Double
    let traffic: Double
    let length: Double
    let fatigue: Double
    let weather: Double
    let road: Double
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
}

struct SegmentHotspot: Decodable, Identifiable {
    var id: Int { segmentIndex }
    let segmentIndex: Int
    let difficulty: Double
    let cumulativeSecondsFromStart: Double
    let label: String?
}

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
    let temperatureF: Double
    let windGustMph: Double
    let visibilityMiles: Double
}

struct RoadConditions: Decodable {
    let available: Bool
    let avgLanes: Double
    let narrowRoadShare: Double
    let majorRoadShare: Double
    let constructionZones: Int
    let dominantRoadClass: String
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
}

struct Coordinate: Decodable {
    let lat: CLLocationDegrees
    let lng: CLLocationDegrees
}
