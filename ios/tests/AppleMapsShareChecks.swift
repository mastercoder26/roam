import Foundation

@main
struct AppleMapsShareChecks {
    @MainActor
    static func main() async {
        modernPlaceLinksKeepTheirCoordinates()
        modernDirectionsKeepEndpointsModeAndStops()
        shortLinksRequireResolution()
        textCanRecoverAnUnsupportedURLAttachment()
        redirectsStayOnAppleMaps()
        await shortLinksSurviveTheExtensionToAppHandoff()
        await networkFailuresKeepTheSavedLinkForRetry()
        await permanentFailuresConsumeOnlyTheFailedShare()
        expiredShortLinksArePurged()
        legacyGoogleEntriesStillDecode()
        print("Apple Maps share checks passed")
    }

    private static func modernPlaceLinksKeepTheirCoordinates() {
        for value in [
            "https://maps.apple.com/place?coordinate=37.3349,-122.0090&name=Apple%20Park",
            "https://maps.apple.com/?ll=37.3349,-122.0090&q=Dropped+Pin"
        ] {
            let route = candidate(value)
            expect(route.provider == .appleMaps, "the provider must remain Apple Maps")
            expect(route.origin == nil, "a place must not invent a starting point")
            expect(route.destination == "37.3349,-122.009", "use the pin, not its ambiguous label")
        }
        let address = candidate("https://maps.apple.com/place?address=1+Infinite+Loop%2C+Cupertino&coordinate=37.3318,-122.0312")
        expect(address.destination == "1 Infinite Loop, Cupertino", "full addresses should remain readable")
        for coordinate in ["91,0", "0,181", "nan,0", "0", "0,0,0"] {
            guard case .unsupported = SharedRouteImportParser.parse(url: URL(string: "https://maps.apple.com/place?coordinate=\(coordinate)")!) else {
                fatalError("invalid coordinates must not become destinations")
            }
        }
    }

    private static func modernDirectionsKeepEndpointsModeAndStops() {
        let route = candidate("https://maps.apple.com/directions?source=Austin%2C+TX&destination=Dallas%2C+TX&mode=driving&waypoint=Waco&waypoint=Temple")
        expect(route.origin == "Austin, TX" && route.destination == "Dallas, TX", "unified directions must preserve both endpoints")
        expect(route.travelMode == .driving && route.waypointCount == 2, "mode and additional stops must be disclosed")
        for mode in ["walking", "transit", "cycling"] {
            guard case .unsupportedTravelMode = SharedRouteImportParser.parse(url: URL(string: "https://maps.apple.com/directions?destination=Dallas&mode=\(mode)")!) else {
                fatalError("a non-driving unified link must not silently become driving")
            }
        }
    }

    private static func shortLinksRequireResolution() {
        let url = URL(string: "https://maps.apple/p/example")!
        guard case let .needsAppleShortLinkResolution(link) = SharedRouteImportParser.parse(url: url) else {
            fatalError("an Apple short link must be saved for expansion, not rejected as no route")
        }
        expect(link == url, "keep the short link intact until resolution")
        guard case .needsAppleShortLinkResolution = SharedRouteImportParser.parse(url: nil, text: "Apple Park https://maps.apple/p/example") else {
            fatalError("plain-text short links must also be accepted")
        }
    }

    private static func textCanRecoverAnUnsupportedURLAttachment() {
        let result = SharedRouteImportParser.parse(
            url: URL(string: "https://example.com/place")!,
            text: "Directions: https://maps.apple.com/directions?source=Austin&destination=Dallas&mode=driving"
        )
        guard case let .ready(route) = result else {
            fatalError("an unrelated attachment must not hide a usable link in the text")
        }
        expect(route.origin == "Austin" && route.destination == "Dallas", "the text fallback must keep the route")
    }

    private static func redirectsStayOnAppleMaps() {
        for value in [
            "https://maps.apple/p/example", "https://maps.apple.com/place?coordinate=37,-122"
        ] {
            expect(SharedRouteImportParser.isTrustedAppleRedirectURL(URL(string: value)!), "Apple Maps HTTPS redirects should be allowed")
        }
        for value in [
            "https://maps.apple.evil.example/p/example", "https://evil.example/maps.apple",
            "https://maps.apple.com.evil.example/place", "https://apple.com/place",
            "http://maps.apple/p/example", "https://user@maps.apple/p/example",
            "https://maps.apple:8443/p/example", "https://maps.app.goo.gl/example"
        ] {
            expect(!SharedRouteImportParser.isTrustedAppleRedirectURL(URL(string: value)!), "redirects must stay on the original Maps provider")
        }
    }

    @MainActor
    private static func shortLinksSurviveTheExtensionToAppHandoff() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = SharedRouteInbox(storageDirectory: directory)
        let reader = SharedRouteInbox(storageDirectory: directory)
        let id = UUID()
        let url = URL(string: "https://maps.apple/p/example")!
        expect(writer.enqueueAppleShortLink(url, id: id), "the extension must save an Apple short link")
        guard case let .unresolvedAppleShortLink(link) = reader.peek() else {
            fatalError("a separate app inbox must read the saved Apple link")
        }
        expect(link.id == id && link.url == url, "the app must receive the same link and ID")
        let resolver = StubMapsResolver(result: .success(URL(string: "https://maps.apple.com/place?coordinate=37.3349,-122.0090")!))
        let coordinator = SharedRouteImportCoordinator(inbox: reader, appleShortLinkResolver: resolver)
        await coordinator.refresh()
        guard case let .ready(route) = coordinator.state else {
            fatalError("the expanded place link must become a route draft")
        }
        expect(route.id == id && route.provider == .appleMaps, "resolution must preserve the share's identity and provider")
        expect(route.origin == nil && route.destination == "37.3349,-122.009", "resolution must preserve the shared pin")
        let saved = String(data: try! Data(contentsOf: directory.appendingPathComponent("shared-route-inbox-v1.json")), encoding: .utf8)!
        expect(!saved.contains("maps.apple"), "raw links must be removed once endpoints are saved")
        coordinator.acknowledgeReadyRoute(id: id)
        expect(reader.peek() == nil, "accepting the imported form must consume the share")
    }

    @MainActor
    private static func networkFailuresKeepTheSavedLinkForRetry() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = SharedRouteInbox(storageDirectory: directory)
        let id = UUID()
        expect(inbox.enqueueAppleShortLink(URL(string: "https://maps.apple/p/example")!, id: id), "save the link before resolving")
        let coordinator = SharedRouteImportCoordinator(
            inbox: inbox,
            appleShortLinkResolver: StubMapsResolver(result: .failure(URLError(.notConnectedToInternet)))
        )
        await coordinator.refresh()
        guard case let .failed(message) = coordinator.state else { fatalError("resolution failure must be visible") }
        expect(message == SharedRouteImportCoordinator.retryableFailureMessage, "explain that the route remains saved")
        expect(inbox.peek()?.id == id, "network failures must keep the Apple link for retry")
        let retry = SharedRouteImportCoordinator(
            inbox: inbox,
            appleShortLinkResolver: StubMapsResolver(result: .success(URL(string: "https://maps.apple.com/directions?source=Austin&destination=Dallas&mode=driving")!))
        )
        await retry.refresh()
        guard case let .ready(route) = retry.state else { fatalError("a later activation must be able to retry the same link") }
        expect(route.id == id && route.origin == "Austin" && route.destination == "Dallas", "retry must preserve the original share")
    }

    @MainActor
    private static func permanentFailuresConsumeOnlyTheFailedShare() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = SharedRouteInbox(storageDirectory: directory)
        let now = Date()
        expect(inbox.enqueueAppleShortLink(URL(string: "https://maps.apple/p/example")!, now: now), "save the invalid share")
        let nextID = UUID()
        expect(inbox.enqueueAppleShortLink(URL(string: "https://maps.apple/p/next")!, id: nextID, now: now.addingTimeInterval(1)), "save a later share")
        let coordinator = SharedRouteImportCoordinator(
            inbox: inbox,
            appleShortLinkResolver: StubMapsResolver(result: .failure(MapsShortLinkResolverError.unsupportedRedirect))
        )
        await coordinator.refresh()
        guard case .failed = coordinator.state else { fatalError("unsupported redirects must be reported") }
        expect(inbox.peek()?.id == nextID, "rejecting one redirect must preserve the next share")
    }

    private static func expiredShortLinksArePurged() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = SharedRouteInbox(storageDirectory: directory)
        let now = Date()
        expect(inbox.enqueueAppleShortLink(URL(string: "https://maps.apple/p/example")!, now: now), "save a temporary Apple link")
        expect(inbox.peek(now: now.addingTimeInterval(16 * 60)) == nil, "unresolved Apple links must expire")
        expect((try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.isEmpty == true, "expired links must be physically removed")
    }

    private static func legacyGoogleEntriesStillDecode() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        let id = UUID()
        // Existing installations have entries without an unresolvedAppleURL key.
        let entry: [[String: Any]] = [[
            "id": id.uuidString, "receivedAt": now.timeIntervalSinceReferenceDate,
            "expiresAt": now.addingTimeInterval(60).timeIntervalSinceReferenceDate,
            "unresolvedGoogleURL": "https://maps.app.goo.gl/example"
        ]]
        let data = try! JSONSerialization.data(withJSONObject: entry)
        try! data.write(to: directory.appendingPathComponent("shared-route-inbox-v1.json"))
        guard case let .unresolvedGoogleShortLink(link) = SharedRouteInbox(storageDirectory: directory).peek() else {
            fatalError("adding Apple support must not break previously saved Google links")
        }
        expect(link.id == id, "old inbox entries must preserve their identity")
    }

    private static func candidate(_ value: String) -> SharedRouteCandidate {
        guard case let .ready(route) = SharedRouteImportParser.parse(url: URL(string: value)!) else {
            fatalError("Apple Maps link should parse: \(value)")
        }
        return route
    }

    private static func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }
}

private struct StubMapsResolver: MapsShortLinkResolving {
    let result: Result<URL, Error>
    func resolve(_ url: URL) async throws -> URL { try result.get() }
}
