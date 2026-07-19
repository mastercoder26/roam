import Foundation

@main
struct SharedRouteImportChecks {
    static func main() async {
        appleDrivingDirectionsDecodeBothEndpoints()
        destinationOnlyAppleLinkUsesCurrentLocation()
        googleDirectionsDecodeRouteAndWaypoints()
        googleShortLinksRequireResolution()
        nonDrivingLinksAreRejected()
        textFallbackFindsAMapLink()
        untrustedLinksAreRejected()
        inboxIsFIFOAndAcknowledgesPrecisely()
        formReducerPreservesUserControl()
        await googleShortLinkResolutionStaysOutsideTheScoringBackend()

        print("Shared route import checks passed")
    }

    private static func appleDrivingDirectionsDecodeBothEndpoints() {
        let url = URL(string: "https://maps.apple.com/?saddr=1+Infinite+Loop%2C+Cupertino%2C+CA&daddr=Apple+Park%2C+Cupertino%2C+CA&dirflg=d")!

        guard case let .ready(route) = SharedRouteImportParser.parse(url: url, text: nil) else {
            fail("an Apple Maps driving route should parse")
        }

        expect(route.provider == .appleMaps, "the Apple Maps provider should be retained")
        expect(route.origin == "1 Infinite Loop, Cupertino, CA", "the Apple Maps origin should decode plus signs")
        expect(route.destination == "Apple Park, Cupertino, CA", "the Apple Maps destination should decode")
        expect(route.travelMode == .driving, "the Apple Maps travel mode should be driving")
    }

    private static func destinationOnlyAppleLinkUsesCurrentLocation() {
        let url = URL(string: "https://maps.apple.com/?daddr=500+Congress+Ave%2C+Austin%2C+TX&dirflg=d")!

        guard case let .ready(route) = SharedRouteImportParser.parse(url: url, text: nil) else {
            fail("a destination-only Apple Maps route should parse")
        }

        expect(route.origin == nil, "a destination-only map link must not invent an origin")
        expect(route.destination == "500 Congress Ave, Austin, TX", "the destination should remain usable")
    }

    private static func googleDirectionsDecodeRouteAndWaypoints() {
        let url = URL(string: "https://www.google.com/maps/dir/?api=1&origin=Austin%2C+TX&destination=Dallas%2C+TX&waypoints=Waco%2C+TX%7CTemple%2C+TX&travelmode=driving")!

        guard case let .ready(route) = SharedRouteImportParser.parse(url: url, text: nil) else {
            fail("a canonical Google Maps route should parse")
        }

        expect(route.provider == .googleMaps, "the Google Maps provider should be retained")
        expect(route.origin == "Austin, TX", "the Google Maps origin should decode")
        expect(route.destination == "Dallas, TX", "the Google Maps destination should decode")
        expect(route.waypointCount == 2, "extra stops must be disclosed instead of silently claimed as preserved")
    }

    private static func googleShortLinksRequireResolution() {
        let url = URL(string: "https://maps.app.goo.gl/abc123")!
        let result = SharedRouteImportParser.parse(url: url, text: nil)

        guard case let .needsGoogleShortLinkResolution(shortURL) = result else {
            fail("a Google Maps short link must ask for a constrained resolution step")
        }

        expect(shortURL == url, "the short URL should be preserved only until it is resolved")
    }

    private static func nonDrivingLinksAreRejected() {
        let url = URL(string: "https://www.google.com/maps/dir/?api=1&origin=Austin&destination=Dallas&travelmode=transit")!
        let result = SharedRouteImportParser.parse(url: url, text: nil)

        guard case let .unsupportedTravelMode(mode) = result else {
            fail("a transit link must not silently become a driving analysis")
        }

        expect(mode == .transit, "the unsupported travel mode should be explained accurately")
    }

    private static func textFallbackFindsAMapLink() {
        let text = "Try this route: https://maps.apple.com/?saddr=Austin&daddr=San+Antonio&dirflg=d"

        guard case let .ready(route) = SharedRouteImportParser.parse(url: nil, text: text) else {
            fail("a plain-text map link should be accepted when a host does not provide a URL attachment")
        }

        expect(route.origin == "Austin", "the text fallback should preserve the origin")
        expect(route.destination == "San Antonio", "the text fallback should preserve the destination")
    }

    private static func untrustedLinksAreRejected() {
        let url = URL(string: "https://example.com/?origin=Austin&destination=Dallas")!
        let result = SharedRouteImportParser.parse(url: url, text: nil)

        guard case .unsupported = result else {
            fail("an unrelated web link must not be treated as a route")
        }
    }

    private static func inboxIsFIFOAndAcknowledgesPrecisely() {
        let suiteName = "SharedRouteImportChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = SharedRouteDraft(
            id: UUID(),
            provider: .appleMaps,
            origin: "Austin, TX",
            destination: "Dallas, TX",
            importedAt: Date(timeIntervalSince1970: 100),
            waypointCount: 0
        )
        let second = SharedRouteDraft(
            id: UUID(),
            provider: .googleMaps,
            origin: nil,
            destination: "Houston, TX",
            importedAt: Date(timeIntervalSince1970: 101),
            waypointCount: 0
        )
        let inbox = SharedRouteInbox(defaults: defaults)

        inbox.enqueue(route: first, now: first.importedAt)
        inbox.enqueue(route: second, now: second.importedAt)

        expect(inbox.peek(now: Date(timeIntervalSince1970: 102))?.id == first.id, "the first shared route should be delivered first")
        inbox.acknowledge(id: second.id, now: Date(timeIntervalSince1970: 102))
        expect(inbox.peek(now: Date(timeIntervalSince1970: 102))?.id == first.id, "acknowledging a later route must not remove an earlier route")
        inbox.acknowledge(id: first.id, now: Date(timeIntervalSince1970: 102))
        expect(inbox.peek(now: Date(timeIntervalSince1970: 102)) == nil, "acknowledging the active route should remove it")
    }

    private static func formReducerPreservesUserControl() {
        let importedRoute = SharedRouteDraft(
            id: UUID(),
            provider: .googleMaps,
            origin: "Austin, TX",
            destination: "Dallas, TX",
            importedAt: Date(),
            waypointCount: 1
        )
        let currentLocationRoute = SharedRouteDraft(
            id: UUID(),
            provider: .appleMaps,
            origin: nil,
            destination: "Houston, TX",
            importedAt: Date(),
            waypointCount: 0
        )

        let manualState = RoutePlanningFormReducer.applying(
            importedRoute,
            to: RoutePlanningFormState(origin: "Old origin", destination: "Old destination", originMode: .currentLocation)
        )
        expect(manualState.originMode == .manual, "an explicit shared origin should use manual origin mode")
        expect(manualState.origin == "Austin, TX", "an imported manual origin should replace stale form text")
        expect(manualState.destination == "Dallas, TX", "an imported destination should fill the planning form")
        expect(manualState.importedRouteID == importedRoute.id, "an import should be applied only once by its stable ID")

        let currentState = RoutePlanningFormReducer.applying(currentLocationRoute, to: manualState)
        expect(currentState.originMode == .currentLocation, "a destination-only link should retain the normal current-location flow")
        expect(currentState.origin.isEmpty, "a destination-only link should not retain a stale manual origin")
        expect(currentState.destination == "Houston, TX", "a destination-only link should still fill its destination")
    }

    @MainActor
    private static func googleShortLinkResolutionStaysOutsideTheScoringBackend() async {
        let suiteName = "SharedRouteImportCoordinatorChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let shortURL = URL(string: "https://maps.app.goo.gl/abc123")!
        let inbox = SharedRouteInbox(defaults: defaults)
        expect(inbox.enqueueGoogleShortLink(shortURL, id: UUID()), "a Google short link should be queued locally")

        let resolvedURL = URL(string: "https://www.google.com/maps/dir/?api=1&origin=Austin&destination=Dallas&travelmode=driving")!
        let coordinator = SharedRouteImportCoordinator(
            inbox: inbox,
            shortLinkResolver: StubGoogleShortLinkResolver(url: resolvedURL)
        )
        await coordinator.refresh()

        guard case let .ready(route) = coordinator.state else {
            fail("a resolved Google short link should become a local editable route")
        }
        expect(route.origin == "Austin", "the resolver should preserve the parsed origin")
        expect(route.destination == "Dallas", "the resolver should preserve the parsed destination")
        expect(inbox.peek()?.id == route.id, "the resolved route should remain local until the form accepts it")

        coordinator.acknowledgeReadyRoute(id: route.id)
        expect(inbox.peek() == nil, "accepting the route should consume only the saved local handoff")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        fatalError("Shared route import check failed: \(message)")
    }
}

private struct StubGoogleShortLinkResolver: GoogleMapsShortLinkResolving {
    let url: URL

    func resolve(_ url: URL) async throws -> URL {
        self.url
    }
}
