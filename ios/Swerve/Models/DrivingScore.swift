import CoreLocation
import Foundation

enum DrivingEventKind: String, CaseIterable, Identifiable {
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

struct DrivingEvent: Identifiable {
    let id = UUID()
    let kind: DrivingEventKind
    let timestamp: Date
}

struct DrivingScore {
    let score: Int
    let duration: TimeInterval
    let distanceMeters: CLLocationDistance
    let topSpeedMetersPerSecond: CLLocationSpeed
    let events: [DrivingEvent]
    let motionSamples: Int

    var distanceMiles: Double { distanceMeters / 1_609.344 }
    var topSpeedMPH: Int { Int((topSpeedMetersPerSecond * 2.23694).rounded()) }
    var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3_600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "0m"
    }

    var grade: String {
        switch score {
        case 90...: "Excellent"
        case 78...: "Steady"
        case 65...: "Needs attention"
        default: "Practice needed"
        }
    }

    var summary: String {
        guard duration >= 60 else {
            return "Keep recording for a few minutes to make this score more useful."
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
