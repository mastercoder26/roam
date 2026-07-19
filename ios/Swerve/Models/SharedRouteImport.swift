import Foundation

/// The mapping provider that supplied a route. This is retained only for a
/// small import notice and is never sent to the route-scoring backend.
enum SharedRouteProvider: String, Codable, Equatable {
    case appleMaps
    case googleMaps

    var displayName: String {
        switch self {
        case .appleMaps:
            "Apple Maps"
        case .googleMaps:
            "Google Maps"
        }
    }
}

enum SharedRouteTravelMode: String, Codable, Equatable {
    case driving
    case walking
    case transit
    case bicycling
    case unknown
}

/// A parsed route before it enters the app-group inbox. It has no raw source
/// URL, so directly imported routes retain only the endpoints needed to fill
/// Swerve's route form.
struct SharedRouteCandidate: Equatable {
    let provider: SharedRouteProvider
    let origin: String?
    let destination: String
    let travelMode: SharedRouteTravelMode
    let waypointCount: Int
}

enum SharedRouteImportParseResult: Equatable {
    case ready(SharedRouteCandidate)
    case needsGoogleShortLinkResolution(URL)
    case unsupportedTravelMode(SharedRouteTravelMode)
    case unsupported(String)
}

/// The privacy-safe representation moved from the Share extension to Swerve.
/// A direct import stores endpoints only. A raw short URL exists only in the
/// short-lived inbox entry that still needs a redirect resolution.
struct SharedRouteDraft: Codable, Equatable, Identifiable {
    let id: UUID
    let provider: SharedRouteProvider
    let origin: String?
    let destination: String
    let importedAt: Date
    let waypointCount: Int
}

enum SharedRouteImportParser {
    static let maximumURLLength = 8_192
    static let maximumEndpointLength = 512

    static func parse(url: URL?, text: String?) -> SharedRouteImportParseResult {
        if let url {
            return parse(url: url)
        }

        let candidates = urls(in: text ?? "")
        guard !candidates.isEmpty else {
            return .unsupported("Swerve could not find a map link in this share.")
        }

        let results = candidates.map { parse(url: $0) }
        if let complete = results.first(where: { result in
            guard case let .ready(route) = result else { return false }
            return route.origin != nil
        }) {
            return complete
        }
        if let destinationOnly = results.first(where: { result in
            guard case .ready = result else { return false }
            return true
        }) {
            return destinationOnly
        }
        if let shortLink = results.first(where: { result in
            guard case .needsGoogleShortLinkResolution = result else { return false }
            return true
        }) {
            return shortLink
        }
        if let mode = results.first(where: { result in
            guard case .unsupportedTravelMode = result else { return false }
            return true
        }) {
            return mode
        }
        return results.first ?? .unsupported("Swerve could not read that map link.")
    }

    static func parse(url: URL) -> SharedRouteImportParseResult {
        guard isSafeLength(url), url.user == nil, url.password == nil else {
            return .unsupported("That map link is not valid.")
        }

        let scheme = url.scheme?.lowercased()
        let host = url.host?.lowercased()

        if scheme == "comgooglemaps" {
            return parseGoogle(url: url)
        }

        guard scheme == "https" || scheme == "http" else {
            return .unsupported("Swerve only accepts shared Apple Maps or Google Maps links.")
        }

        if host == "maps.apple.com" {
            return parseApple(url: url)
        }
        if isGoogleShortLinkHost(host) {
            guard scheme == "https" else {
                return .unsupported("Google Maps short links must use HTTPS.")
            }
            return .needsGoogleShortLinkResolution(url)
        }
        if isGoogleMapsHost(host) {
            return parseGoogle(url: url)
        }
        return .unsupported("This link is not from Apple Maps or Google Maps.")
    }

    private static func parseApple(url: URL) -> SharedRouteImportParseResult {
        guard case let .success(query) = queryValues(in: url) else {
            return .unsupported("The Apple Maps link has invalid query values.")
        }
        let origin = singleEndpoint(named: ["saddr", "source"], in: query)
        guard let destination = singleEndpoint(named: ["daddr", "destination", "address", "q", "query"], in: query)
            ?? coordinateEndpoint(from: query) else {
            return .unsupported("Swerve could not find a destination in this Apple Maps link.")
        }

        let mode = travelMode(from: singleValue(named: ["dirflg"], in: query))
        guard mode == .driving || mode == .unknown else {
            return .unsupportedTravelMode(mode)
        }

        return .ready(
            SharedRouteCandidate(
                provider: .appleMaps,
                origin: origin,
                destination: destination,
                travelMode: mode,
                waypointCount: 0
            )
        )
    }

    private static func parseGoogle(url: URL) -> SharedRouteImportParseResult {
        guard case let .success(query) = queryValues(in: url) else {
            return .unsupported("The Google Maps link has invalid query values.")
        }

        let mode = travelMode(from: singleValue(named: ["travelmode", "directionsmode", "dirflg"], in: query))
        guard mode == .driving || mode == .unknown else {
            return .unsupportedTravelMode(mode)
        }

        let queryOrigin = singleEndpoint(named: ["origin", "saddr"], in: query)
        let queryDestination = singleEndpoint(named: ["destination", "daddr", "query", "q"], in: query)
        let pathRoute = routeFromGooglePath(url)

        let origin = queryOrigin ?? pathRoute?.origin
        guard let destination = queryDestination ?? pathRoute?.destination else {
            return .unsupported("Swerve could not find a destination in this Google Maps link.")
        }

        let waypointCount = waypointCount(from: singleValue(named: ["waypoints"], in: query))
        return .ready(
            SharedRouteCandidate(
                provider: .googleMaps,
                origin: origin,
                destination: destination,
                travelMode: mode,
                waypointCount: waypointCount
            )
        )
    }

    /// A nil result means either no endpoint was supplied or conflicting
    /// duplicates were supplied. The latter is deliberately rejected by the
    /// caller when it leaves the route without a usable destination.
    private static func singleEndpoint(
        named names: [String],
        in query: [String: [String]]
    ) -> String? {
        guard let raw = singleValue(named: names, in: query) else { return nil }
        return cleanEndpoint(raw)
    }

    private static func singleValue(
        named names: [String],
        in query: [String: [String]]
    ) -> String? {
        let values = names.flatMap { query[$0] ?? [] }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard values.count <= 1 else { return nil }
        return values.first
    }

    private static func coordinateEndpoint(from query: [String: [String]]) -> String? {
        guard let raw = singleValue(named: ["ll"], in: query) else { return nil }
        let parts = raw.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let latitude = Double(parts[0]),
              let longitude = Double(parts[1]),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else {
            return nil
        }
        return "\(latitude),\(longitude)"
    }

    private static func routeFromGooglePath(_ url: URL) -> (origin: String?, destination: String?)? {
        let path = url.path.split(separator: "/", omittingEmptySubsequences: false)
        guard let directoryIndex = path.firstIndex(where: { $0.lowercased() == "dir" }) else {
            return nil
        }

        let endpointParts = path.dropFirst(directoryIndex + 1)
            .prefix { !$0.lowercased().hasPrefix("data=") }
            .map(String.init)
        guard !endpointParts.isEmpty else { return nil }

        let decoded = endpointParts.map { component -> String? in
            let formDecoded = component.replacingOccurrences(of: "+", with: " ")
            return formDecoded.removingPercentEncoding ?? formDecoded
        }
        guard let firstDecoded = decoded.first ?? nil,
              let first = cleanEndpoint(firstDecoded) else {
            return nil
        }

        if decoded.count >= 2,
           let secondDecoded = decoded[1],
           let second = cleanEndpoint(secondDecoded) {
            return (first, second)
        }
        return (nil, first)
    }

    private static func queryValues(in url: URL) -> Result<[String: [String]], Never> {
        guard let rawQuery = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery,
              !rawQuery.isEmpty else {
            return .success([:])
        }

        var values: [String: [String]] = [:]
        for pair in rawQuery.split(separator: "&", omittingEmptySubsequences: false) {
            let pieces = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawName = pieces.first,
                  let name = decodeFormComponent(String(rawName)),
                  !name.isEmpty else {
                return .success([:])
            }
            let rawValue = pieces.count == 2 ? String(pieces[1]) : ""
            guard let value = decodeFormComponent(rawValue) else {
                return .success([:])
            }
            values[name.lowercased(), default: []].append(value)
        }
        return .success(values)
    }

    private static func decodeFormComponent(_ string: String) -> String? {
        string
            .replacingOccurrences(of: "+", with: " ")
            .removingPercentEncoding
    }

    private static func cleanEndpoint(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.count <= maximumEndpointLength,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        let lowercased = value.lowercased()
        if lowercased == "current location" || lowercased == "currentlocation" || lowercased == "my location" {
            return nil
        }
        return value
    }

    private static func travelMode(from raw: String?) -> SharedRouteTravelMode {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "d", "drive", "driving":
            .driving
        case "w", "walk", "walking":
            .walking
        case "r", "transit", "public_transit":
            .transit
        case "b", "bike", "bicycling", "cycling":
            .bicycling
        default:
            .unknown
        }
    }

    private static func waypointCount(from raw: String?) -> Int {
        guard let raw else { return 0 }
        return min(20, raw.split(separator: "|").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count)
    }

    private static func urls(in text: String) -> [URL] {
        guard text.count <= maximumURLLength * 2 else { return [] }
        let pattern = #"(?i)(?:https?://|comgooglemaps://)[^\s<>()]+"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let matchedRange = Range(match.range, in: text) else { return nil }
            let candidate = String(text[matchedRange])
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
            guard candidate.count <= maximumURLLength else { return nil }
            return URL(string: candidate)
        }
    }

    private static func isSafeLength(_ url: URL) -> Bool {
        !url.absoluteString.isEmpty && url.absoluteString.count <= maximumURLLength
    }

    private static func isGoogleShortLinkHost(_ host: String?) -> Bool {
        host == "maps.app.goo.gl" || host == "goo.gl"
    }

    private static func isGoogleMapsHost(_ host: String?) -> Bool {
        guard let host else { return false }
        return host == "google.com" ||
            host == "www.google.com" ||
            host == "maps.google.com" ||
            host.hasPrefix("www.google.") ||
            host.hasPrefix("maps.google.")
    }
}

/// Small, bounded local handoff storage shared by the app and its Share
/// extension. Direct routes persist no raw provider URL.
struct SharedRouteInbox {
    static let appGroupIdentifier = "group.com.akhilkonduru.swerve"

    private static let storageKey = "shared-route-inbox-v1"
    private static let maximumEntries = 5
    private static let directRouteLifetime: TimeInterval = 60 * 60 * 24
    private static let unresolvedLinkLifetime: TimeInterval = 60 * 15

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: Self.appGroupIdentifier)) {
        self.defaults = defaults
    }

    @discardableResult
    func enqueue(route: SharedRouteDraft, now: Date = Date()) -> Bool {
        update(now: now) { entries in
            entries + [
                StoredEntry(
                    id: route.id,
                    receivedAt: route.importedAt,
                    expiresAt: max(route.importedAt, now).addingTimeInterval(Self.directRouteLifetime),
                    route: route,
                    unresolvedGoogleURL: nil
                )
            ]
        }
    }

    @discardableResult
    func enqueueGoogleShortLink(_ url: URL, id: UUID = UUID(), now: Date = Date()) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.absoluteString.count <= SharedRouteImportParser.maximumURLLength else {
            return false
        }
        return update(now: now) { entries in
            entries + [
                StoredEntry(
                    id: id,
                    receivedAt: now,
                    expiresAt: now.addingTimeInterval(Self.unresolvedLinkLifetime),
                    route: nil,
                    unresolvedGoogleURL: url.absoluteString
                )
            ]
        }
    }

    func peek(now: Date = Date()) -> SharedRouteInboxItem? {
        let entries = prunedEntries(now: now)
        persist(entries)
        return entries.first?.item
    }

    func acknowledge(id: UUID, now: Date = Date()) {
        _ = update(now: now) { entries in
            entries.filter { $0.id != id }
        }
    }

    @discardableResult
    func replaceGoogleShortLink(id: UUID, with route: SharedRouteDraft, now: Date = Date()) -> Bool {
        update(now: now) { entries in
            entries.map { entry in
                guard entry.id == id, entry.unresolvedGoogleURL != nil else { return entry }
                return StoredEntry(
                    id: id,
                    receivedAt: entry.receivedAt,
                    expiresAt: max(route.importedAt, now).addingTimeInterval(Self.directRouteLifetime),
                    route: route,
                    unresolvedGoogleURL: nil
                )
            }
        }
    }

    private func update(now: Date, transform: ([StoredEntry]) -> [StoredEntry]) -> Bool {
        guard defaults != nil else { return false }
        let entries = transform(prunedEntries(now: now))
            .sorted { $0.receivedAt < $1.receivedAt }
        persist(Array(entries.suffix(Self.maximumEntries)))
        return true
    }

    private func prunedEntries(now: Date) -> [StoredEntry] {
        decodedEntries().filter { $0.expiresAt > now && $0.item != nil }
    }

    private func decodedEntries() -> [StoredEntry] {
        guard let data = defaults?.data(forKey: Self.storageKey),
              let entries = try? JSONDecoder().decode([StoredEntry].self, from: data) else {
            return []
        }
        return entries
    }

    private func persist(_ entries: [StoredEntry]) {
        guard let defaults else { return }
        if entries.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
            return
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private struct StoredEntry: Codable, Equatable, Identifiable {
        let id: UUID
        let receivedAt: Date
        let expiresAt: Date
        let route: SharedRouteDraft?
        let unresolvedGoogleURL: String?

        var item: SharedRouteInboxItem? {
            if let route { return .route(route) }
            guard let unresolvedGoogleURL,
                  let url = URL(string: unresolvedGoogleURL) else {
                return nil
            }
            return .unresolvedGoogleShortLink(
                SharedRouteGoogleShortLink(
                    id: id,
                    url: url,
                    receivedAt: receivedAt
                )
            )
        }
    }
}

enum SharedRouteInboxItem: Equatable, Identifiable {
    case route(SharedRouteDraft)
    case unresolvedGoogleShortLink(SharedRouteGoogleShortLink)

    var id: UUID {
        switch self {
        case let .route(route):
            route.id
        case let .unresolvedGoogleShortLink(link):
            link.id
        }
    }
}

struct SharedRouteGoogleShortLink: Equatable, Identifiable {
    let id: UUID
    let url: URL
    let receivedAt: Date
}

protocol GoogleMapsShortLinkResolving {
    func resolve(_ url: URL) async throws -> URL
}

enum GoogleMapsShortLinkResolverError: LocalizedError {
    case invalidLink
    case unsupportedRedirect

    var errorDescription: String? {
        switch self {
        case .invalidLink:
            "That Google Maps link could not be resolved."
        case .unsupportedRedirect:
            "That Google Maps link did not lead to a supported directions route."
        }
    }
}

struct GoogleMapsShortLinkResolver: GoogleMapsShortLinkResolving {
    private let session: URLSession

    init(session: URLSession = GoogleMapsShortLinkResolver.makeSession()) {
        self.session = session
    }

    func resolve(_ url: URL) async throws -> URL {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "maps.app.goo.gl" || url.host?.lowercased() == "goo.gl",
              url.absoluteString.count <= SharedRouteImportParser.maximumURLLength else {
            throw GoogleMapsShortLinkResolverError.invalidLink
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("Swerve Route Import", forHTTPHeaderField: "User-Agent")

        let (_, response) = try await session.data(for: request)
        guard let finalURL = response.url,
              finalURL.scheme?.lowercased() == "https" else {
            throw GoogleMapsShortLinkResolverError.unsupportedRedirect
        }
        guard case .ready = SharedRouteImportParser.parse(url: finalURL, text: nil) else {
            throw GoogleMapsShortLinkResolverError.unsupportedRedirect
        }
        return finalURL
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }
}
