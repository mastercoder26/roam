import Foundation

/// The fixed product story shown from Settings. Keeping its order and copy
/// outside SwiftUI makes the walkthrough straightforward to verify and keeps
/// the visual layer focused on presentation.
enum FeatureWalkthroughStep: String, CaseIterable, Identifiable {
    case plan
    case understand
    case drive
    case grow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plan: "Plan your route"
        case .understand: "Know what to expect"
        case .drive: "Record the drive"
        case .grow: "Build experience"
        }
    }

    var detail: String {
        switch self {
        case .plan:
            "In Routes, enter your destination and compare options before you leave."
        case .understand:
            "Check turns, traffic, and weather along the way."
        case .drive:
            "Start recording in Drive before you set off. Review your trip when you arrive."
        case .grow:
            "Track your practice in Progress. Find settings and milestones in Profile."
        }
    }

    var symbol: String {
        switch self {
        case .plan: "point.topleft.down.curvedto.point.bottomright.up"
        case .understand: "road.lanes"
        case .drive: "steeringwheel"
        case .grow: "chart.line.uptrend.xyaxis"
        }
    }

    var actionTitle: String {
        self == .grow ? "Open Roam" : "Next"
    }

    var progressLabel: String {
        guard let index = Self.allCases.firstIndex(of: self) else { return "" }
        return "\(index + 1) of \(Self.allCases.count)"
    }

    var next: FeatureWalkthroughStep? {
        guard let index = Self.allCases.firstIndex(of: self), index < Self.allCases.count - 1 else {
            return nil
        }
        return Self.allCases[index + 1]
    }

    static func step(at index: Int) -> FeatureWalkthroughStep {
        let safeIndex = min(max(index, 0), allCases.count - 1)
        return allCases[safeIndex]
    }
}
