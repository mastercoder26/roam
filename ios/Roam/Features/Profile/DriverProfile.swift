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

        /// A short, factual note the UI can surface alongside the stage.
        /// Deliberately general, not tied to any specific jurisdiction's
        /// rules, and not a claim of legal compliance: it is a nudge, not a
        /// guarantee. Kept separate from `detail`, which describes the
        /// stage itself rather than suggesting anything to do about it.
        var supervisionNote: String {
            switch self {
            case .permit: "Many places require a supervising driver in the car at all times."
            case .provisional: "Curfews and passenger limits are common at this stage, check local rules."
            case .licensed: "Most restrictions typically lift here, but confirm what applies locally."
            }
        }
    }

    var displayName: String
    var stage: Stage

    static let empty = DriverProfile(displayName: "", stage: .permit)
}

/// Persists the profile locally. `UserDefaults` is correct here precisely
/// because none of this is sensitive or authoritative, it is a display
/// preference, not a credential and not a measurement.
@MainActor
final class DriverProfileStore: ObservableObject {
    /// Declared once. `load` and `persist` both read this instead of
    /// carrying their own copies of the literal, so the key cannot drift
    /// between the two call sites.
    static let storageKey = "roam.driver-profile-v1"

    /// Names longer than this are truncated, not rejected, so a driver who
    /// pastes something long still ends up with a usable, storable value.
    private static let maxNameLength = 80

    private let defaults: UserDefaults

    @Published var displayName: String {
        didSet {
            let sanitized = Self.sanitizeName(displayName)
            guard sanitized == displayName else {
                // Re-entrant assignment: this fires didSet again with the
                // sanitized value, which then falls through to persist().
                displayName = sanitized
                return
            }
            persist()
        }
    }

    @Published var stage: DriverProfile.Stage {
        didSet { persist() }
    }

    /// Set whenever the most recent write to `UserDefaults` failed. This is
    /// a local display preference, not critical data, so a failed write
    /// must never crash the app or trigger a network report. It is instead
    /// surfaced here so the UI can choose to show a small, honest
    /// "couldn't save" indicator rather than the failure being swallowed
    /// silently.
    @Published private(set) var lastPersistenceError: String?

    /// Falls back to a neutral label rather than an empty headline, so the
    /// card never renders as a blank row before the driver enters a name.
    var resolvedDisplayName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Your profile" : trimmed
    }

    /// Initials for the avatar. Returns an empty string when no name has
    /// been entered, deliberately, rather than a placeholder glyph like an
    /// em dash: em dashes are banned project-wide, and baking in any other
    /// arbitrary character here would just move the same problem one layer
    /// down. An empty monogram lets the UI decide how to render an empty
    /// avatar, for example with a system icon, without this layer guessing.
    var monogram: String {
        let initials = displayName
            .split(whereSeparator: \.isWhitespace)
            .compactMap(\.first)
            .prefix(2)
        guard !initials.isEmpty else { return "" }
        return String(initials).uppercased()
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = Self.load(from: defaults) ?? .empty
        displayName = stored.displayName
        stage = stored.stage
    }

    private static func load(from defaults: UserDefaults) -> DriverProfile? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(DriverProfile.self, from: data)
    }

    private func persist() {
        let profile = DriverProfile(displayName: displayName, stage: stage)
        do {
            let data = try JSONEncoder().encode(profile)
            defaults.set(data, forKey: Self.storageKey)
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error.localizedDescription
        }
    }

    /// Strips newlines and other control characters, collapses runs of
    /// whitespace to a single space, trims the ends, and caps the length.
    /// Deliberately scalar-based rather than regex-based so combining
    /// marks in non-Latin scripts (accents, diacritics) survive intact,
    /// and deliberately permissive of apostrophes and hyphens since those
    /// are legitimate parts of real names.
    private static func sanitizeName(_ raw: String) -> String {
        var normalized: [Unicode.Scalar] = []
        normalized.reserveCapacity(raw.unicodeScalars.count)

        for scalar in raw.unicodeScalars {
            if CharacterSet.newlines.contains(scalar) || scalar == "\t" {
                normalized.append(" ")
            } else if CharacterSet.controlCharacters.contains(scalar) {
                continue
            } else {
                normalized.append(scalar)
            }
        }

        let collapsed = String(String.UnicodeScalarView(normalized))
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")

        return String(collapsed.prefix(maxNameLength))
    }
}
