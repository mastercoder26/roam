import Foundation

/// A graded route a person has already analyzed, kept only for a fast shortcut
/// back into the same trip. This is quick-recall convenience, not driving
/// evidence — it plays no part in any score.
struct RecentRouteEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let origin: String
    let destination: String
    let departureTime: Date
    let analyzedAt: Date
    let score: Double
    let label: DifficultyLabel
    let distanceMeters: Int
    let durationSeconds: Int

    init(
        id: UUID = UUID(),
        origin: String,
        destination: String,
        departureTime: Date,
        analyzedAt: Date = Date(),
        score: Double,
        label: DifficultyLabel,
        distanceMeters: Int,
        durationSeconds: Int
    ) {
        self.id = id
        self.origin = origin
        self.destination = destination
        self.departureTime = departureTime
        self.analyzedAt = analyzedAt
        self.score = score
        self.label = label
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
    }

    var formattedScore: String {
        String(format: "%.1f", score)
    }

    var formattedDistance: String {
        String(format: "%.1f mi", Double(distanceMeters) / 1609.344)
    }

    var formattedDuration: String {
        ScoredRoute.formatDuration(seconds: durationSeconds)
    }
}

/// Local-only history of already-analyzed routes, most recent first. Kept
/// entirely on-device — the same trip run twice replaces its earlier entry
/// rather than duplicating it, so the list reads as "routes you've checked,"
/// not "every analysis you've ever run."
@MainActor
final class RecentRouteStore: ObservableObject {
    static let shared = RecentRouteStore()

    @Published private(set) var entries: [RecentRouteEntry] = []

    private let storageKey = "recentRoutes.v1"
    private let maxEntries = 8
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        load()
    }

    func record(origin: String, destination: String, departureTime: Date, route: ScoredRoute) {
        let trimmedOrigin = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDestination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        // A non-finite score cannot be JSON-encoded, so persisting it would
        // fail for the entire list and silently drop every later entry too.
        guard !trimmedOrigin.isEmpty, !trimmedDestination.isEmpty, route.score.isFinite else { return }

        var updated = entries.filter {
            !($0.origin == trimmedOrigin && $0.destination == trimmedDestination)
        }
        let entry = RecentRouteEntry(
            origin: trimmedOrigin,
            destination: trimmedDestination,
            departureTime: departureTime,
            score: route.score,
            label: route.label,
            distanceMeters: route.distanceMeters,
            durationSeconds: route.durationSeconds
        )
        updated.insert(entry, at: 0)
        entries = Array(updated.prefix(maxEntries))
        persist()
    }

    func remove(_ entry: RecentRouteEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func clear() {
        entries = []
        persist()
    }

    private func load() {
        guard let data = userDefaults.data(forKey: storageKey) else { return }
        // Decoded entry by entry: one row written by another build (an unknown
        // difficulty label, a missing field) must not blank the whole list,
        // which the next `record` would then overwrite for good.
        let decoded = (try? JSONDecoder().decode([LossyRecentRouteEntry].self, from: data)) ?? []
        entries = Array(decoded.compactMap(\.value).filter { $0.score.isFinite }.prefix(maxEntries))
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}

private struct LossyRecentRouteEntry: Decodable {
    let value: RecentRouteEntry?

    init(from decoder: Decoder) throws {
        value = try? RecentRouteEntry(from: decoder)
    }
}
