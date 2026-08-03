import Combine
import Foundation

/// The driver's self-declared identity. Deliberately separate from anything
/// measured: nothing here feeds a route score, a drive score, or readiness.
/// It exists so the app can address the person by name and frame their own
/// progress against the stage they say they are at.
struct DriverProfile: Equatable, Codable {
    enum Stage: String, CaseIterable, Identifiable, Codable {
        case permit
        case provisional
        case licensed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .permit: "Learner's permit"
            case .provisional: "Provisional license"
            case .licensed: "Full license"
            }
        }

        var detail: String {
            switch self {
            case .permit: "Practicing with a supervising driver."
            case .provisional: "Driving alone with restrictions still in place."
            case .licensed: "Unrestricted, still building experience."
            }
        }
    }

    var displayName: String
    var stage: Stage

    static let empty = DriverProfile(displayName: "", stage: .permit)
}

/// Persists the profile locally. `UserDefaults` is correct here precisely
/// because none of this is sensitive or authoritative — it is a display
/// preference, not a credential and not a measurement.
@MainActor
final class DriverProfileStore: ObservableObject {
    private let storageKey = "roam.driver-profile-v1"
    private let defaults: UserDefaults

    @Published var displayName: String {
        didSet { persist() }
    }

    @Published var stage: DriverProfile.Stage {
        didSet { persist() }
    }

    /// Falls back to a neutral label rather than an empty headline, so the
    /// card never renders as a blank row before the driver enters a name.
    var resolvedDisplayName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Your profile" : trimmed
    }

    /// Initials for the avatar. Falls back to a glyph-free placeholder rather
    /// than an arbitrary letter when no name has been entered.
    var monogram: String {
        let words = displayName
            .split(separator: " ")
            .compactMap(\.first)
            .prefix(2)
        return words.isEmpty ? "—" : String(words).uppercased()
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = Self.load(from: defaults) ?? .empty
        displayName = stored.displayName
        stage = stored.stage
    }

    private static func load(from defaults: UserDefaults) -> DriverProfile? {
        guard let data = defaults.data(forKey: "roam.driver-profile-v1") else { return nil }
        return try? JSONDecoder().decode(DriverProfile.self, from: data)
    }

    private func persist() {
        let profile = DriverProfile(displayName: displayName, stage: stage)
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
