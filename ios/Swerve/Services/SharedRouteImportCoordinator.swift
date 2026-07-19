import Combine
import Foundation

/// Coordinates the app-side half of a route shared from the system share
/// sheet. It never calls the scoring backend. Its only job is to turn a saved
/// local handoff into an editable route form when Swerve is active.
@MainActor
final class SharedRouteImportCoordinator: ObservableObject {
    enum State: Equatable {
        case idle
        case resolvingGoogleMapsLink
        case ready(SharedRouteDraft)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let inbox: SharedRouteInbox
    private let shortLinkResolver: any GoogleMapsShortLinkResolving
    private var isRefreshing = false

    init(
        inbox: SharedRouteInbox = SharedRouteInbox(),
        shortLinkResolver: any GoogleMapsShortLinkResolving = GoogleMapsShortLinkResolver()
    ) {
        self.inbox = inbox
        self.shortLinkResolver = shortLinkResolver
    }

    func refresh() async {
        guard !isRefreshing else { return }
        if case .ready = state { return }

        guard let item = inbox.peek() else {
            state = .idle
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        switch item {
        case let .route(route):
            state = .ready(route)

        case let .unresolvedGoogleShortLink(link):
            state = .resolvingGoogleMapsLink
            do {
                let finalURL = try await shortLinkResolver.resolve(link.url)
                guard case let .ready(candidate) = SharedRouteImportParser.parse(url: finalURL, text: nil) else {
                    throw GoogleMapsShortLinkResolverError.unsupportedRedirect
                }
                let route = SharedRouteDraft(
                    id: link.id,
                    provider: candidate.provider,
                    origin: candidate.origin,
                    destination: candidate.destination,
                    importedAt: link.receivedAt,
                    waypointCount: candidate.waypointCount
                )
                guard inbox.replaceGoogleShortLink(id: link.id, with: route) else {
                    throw GoogleMapsShortLinkResolverError.invalidLink
                }
                state = .ready(route)
            } catch {
                inbox.acknowledge(id: link.id)
                state = .failed(error.localizedDescription)
            }
        }
    }

    func acknowledgeReadyRoute(id: UUID) {
        guard case let .ready(route) = state, route.id == id else { return }
        inbox.acknowledge(id: id)
        state = .idle
    }

    func dismissFailure() {
        guard case .failed = state else { return }
        state = .idle
    }
}
