import CoreLocation
import Foundation

enum DrivingEventKind: String, CaseIterable, Identifiable, Codable {
    case hardBrake
    case rapidAcceleration
    case sharpCorner
    case phoneMovement

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hardBrake: "Hard braking"
        case .rapidAcceleration: "Rapid acceleration"
        case .sharpCorner: "Sharp corner"
        case .phoneMovement: "Phone movement"
        }
    }

    var symbol: String {
        switch self {
        case .hardBrake: "brakesignal"
        case .rapidAcceleration: "bolt.car.fill"
        case .sharpCorner: "arrow.triangle.turn.up.right.diamond.fill"
        case .phoneMovement: "iphone.gen3.radiowaves.left.and.right"
        }
    }
}

struct DriveCoordinate: Codable, Hashable {
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct DriveRoutePoint: Codable, Identifiable, Hashable {
    let timestamp: Date
    let coordinate: DriveCoordinate
    let speedMetersPerSecond: Double

    var id: Date { timestamp }
}

struct DrivingEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let kind: DrivingEventKind
    let timestamp: Date
    let source: DrivingEventSource
    /// Present for GPS/fused events and for motion events after a GPS fix.
    let coordinate: DriveCoordinate?

    init(id: UUID = UUID(), kind: DrivingEventKind, timestamp: Date, source: DrivingEventSource, coordinate: DriveCoordinate? = nil) {
        self.id = id
        self.kind = kind
        self.timestamp = timestamp
        self.source = source
        self.coordinate = coordinate
    }
}

struct DrivingScore: Codable {
    let score: Int
    let duration: TimeInterval
    let distanceMeters: CLLocationDistance
    let topSpeedMetersPerSecond: CLLocationSpeed
    let events: [DrivingEvent]
    let motionSamples: Int
    let dataQuality: DriveDataQuality

    var distanceMiles: Double { distanceMeters / 1_609.344 }
    var topSpeedMPH: Int { Int((topSpeedMetersPerSecond * 2.23694).rounded()) }
    var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3_600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "0m"
    }

    var grade: String {
        if dataQuality.confidence == .low { return "Preliminary" }
        switch score {
        case 90...:
            return "Excellent"
        case 78...:
            return "Steady"
        case 65...:
            return "Needs attention"
        default:
            return "Practice needed"
        }
    }

    var summary: String {
        guard dataQuality.confidence != .low else {
            return dataQuality.summary
        }
        guard !events.isEmpty else {
            return "Smooth trip. Keep leaving room to brake and taking turns calmly."
        }
        let mostCommon = Dictionary(grouping: events, by: \.kind)
            .max { $0.value.count < $1.value.count }?.key
        return mostCommon.map { "Focus on fewer \($0.title.lowercased()) events next drive." }
            ?? "Review this trip before the next drive."
    }

    func count(for kind: DrivingEventKind) -> Int {
        events.filter { $0.kind == kind }.count
    }
}

/// Route characteristics intentionally saved with a manually started practice
/// drive. It contains no origin, destination, raw polyline, or map coordinates;
/// the recorded GPS trace remains local to the device as part of the drive.
struct PlannedRouteContext: Identifiable, Codable, Hashable {
    let id: UUID
    let createdAt: Date
    let routeDemands: [RouteDemand]
    /// Set only after the locally recorded GPS trace overlaps the in-memory
    /// planned route. It stores a verdict, never route geometry or addresses.
    let recordedRouteMatched: Bool?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        routeDemands: [RouteDemand],
        recordedRouteMatched: Bool? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.routeDemands = routeDemands
        self.recordedRouteMatched = recordedRouteMatched
    }
}

struct RecordedDrive: Identifiable, Codable {
    let id: UUID
    let startedAt: Date
    let score: DrivingScore
    let route: [DriveRoutePoint]
    /// Absent on historical drives and on ordinary manual drives. Its optional
    /// type makes old `recorded-drives-v1` data decode without a migration.
    let plannedRouteContext: PlannedRouteContext?

    init(
        id: UUID = UUID(),
        startedAt: Date,
        score: DrivingScore,
        route: [DriveRoutePoint],
        plannedRouteContext: PlannedRouteContext? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.score = score
        self.route = route
        self.plannedRouteContext = plannedRouteContext
    }
}
