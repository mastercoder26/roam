import Combine
import Foundation

enum RoutePlanningOriginMode: Equatable {
    case currentLocation
    case manual
}

/// The visible planning step. Keeping this pure means the origin-to-
/// destination progression stays consistent whether the start comes from the
/// current-location flow, manual entry, or a shared Maps route.
enum RoutePlanningStage: Equatable {
    case chooseOrigin
    case chooseDestination
    case readyToAnalyze

    init(origin: String, destination: String) {
        let hasOrigin = !origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasDestination = !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if !hasOrigin {
            self = .chooseOrigin
        } else if !hasDestination {
            self = .chooseDestination
        } else {
            self = .readyToAnalyze
        }
    }
}

/// The primary route-planning action, including the account boundary required
/// by the authenticated analysis API. Keeping this decision pure prevents a
/// completed signed-out form from looking actionable only to fail afterward.
enum RoutePlanningPrimaryAction: Equatable {
    case chooseOrigin
    case chooseDestination
    case waitingForAccount
    case signIn
    case analyze
    case analyzing

    init(
        stage: RoutePlanningStage,
        isSignedIn: Bool,
        isAccountRestoring: Bool,
        isLoading: Bool
    ) {
        if isLoading {
            self = .analyzing
            return
        }

        switch stage {
        case .chooseOrigin:
            self = .chooseOrigin
        case .chooseDestination:
            self = .chooseDestination
        case .readyToAnalyze where isAccountRestoring:
            self = .waitingForAccount
        case .readyToAnalyze where !isSignedIn:
            self = .signIn
        case .readyToAnalyze:
            self = .analyze
        }
    }

    var isEnabled: Bool {
        self == .signIn || self == .analyze
    }
}

/// The visual state for the Apple Maps planning preview. It deliberately
/// follows the same endpoint validation as the form so the map never invents
/// a route before the user has supplied both endpoints.
enum RoutePlanningMapPreviewStage: Equatable {
    /// A neutral Apple Maps viewport shown until a real origin exists. The
    /// map remains mounted so planning always has geographic context.
    case locationPrompt
    case startingPoint
    case route

    init(origin: String, destination: String, usesCurrentLocation: Bool) {
        let hasOrigin = usesCurrentLocation || !origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasDestination = !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if hasOrigin && hasDestination {
            self = .route
        } else if hasOrigin {
            self = .startingPoint
        } else {
            self = .locationPrompt
        }
    }
}

/// Pure presentation decisions for the first route screen. The form remains
/// useful when people enter a destination first, but the next action stays
/// explicit: select or type the origin before analysis can begin.
struct RoutePlanningFormPresentation: Equatable {
    let stage: RoutePlanningStage
    let mapPreviewStage: RoutePlanningMapPreviewStage

    init(origin: String, destination: String, usesCurrentLocation: Bool) {
        stage = RoutePlanningStage(origin: origin, destination: destination)
        mapPreviewStage = RoutePlanningMapPreviewStage(
            origin: origin,
            destination: destination,
            usesCurrentLocation: usesCurrentLocation
        )
    }

    /// Keep both endpoints in view from the first frame. This avoids making a
    /// route look like a one-field task and helps people who know their
    /// destination before deciding where to start.
    var showsDestination: Bool { true }

    /// Location permission is requested only from a deliberate, labelled tap.
    var showsCurrentLocationAction: Bool { stage == .chooseOrigin }
}

struct RouteImportNotice: Equatable {
    let title: String
    let message: String
    let isError: Bool
}

struct RoutePlanningFormState: Equatable {
    var origin: String
    var destination: String
    var originMode: RoutePlanningOriginMode
    var departureTime: Date
    var importedRouteID: UUID?
    var importNotice: RouteImportNotice?

    init(
        origin: String = "",
        destination: String = "",
        originMode: RoutePlanningOriginMode = .manual,
        departureTime: Date = Date().addingTimeInterval(15 * 60),
        importedRouteID: UUID? = nil,
        importNotice: RouteImportNotice? = nil
    ) {
        self.origin = origin
        self.destination = destination
        self.originMode = originMode
        self.departureTime = departureTime
        self.importedRouteID = importedRouteID
        self.importNotice = importNotice
    }
}

enum RoutePlanningFormReducer {
    static func applying(
        _ route: SharedRouteDraft,
        to current: RoutePlanningFormState
    ) -> RoutePlanningFormState {
        guard current.importedRouteID != route.id else { return current }

        let usesCurrentLocation = route.origin == nil
        let extraStopsMessage: String
        if route.waypointCount > 0 {
            extraStopsMessage = " This shared route has \(route.waypointCount) additional stop\(route.waypointCount == 1 ? "" : "s"). Roam will analyze the start and final destination."
        } else {
            extraStopsMessage = ""
        }

        return RoutePlanningFormState(
            origin: route.origin ?? "",
            destination: route.destination,
            originMode: usesCurrentLocation ? .currentLocation : .manual,
            departureTime: current.departureTime,
            importedRouteID: route.id,
            importNotice: RouteImportNotice(
                title: "Imported from \(route.provider.displayName)",
                message: "Check the start and destination. Roam may choose a different route.\(extraStopsMessage)",
                isError: false
            )
        )
    }
}

@MainActor
final class RoutePlanningFormModel: ObservableObject {
    @Published var origin: String
    @Published var destination: String
    @Published var originMode: RoutePlanningOriginMode
    @Published var departureTime: Date
    @Published private(set) var importedRouteID: UUID?
    @Published private(set) var importNotice: RouteImportNotice?

    init(initialState: RoutePlanningFormState = RoutePlanningFormState()) {
        origin = initialState.origin
        destination = initialState.destination
        originMode = initialState.originMode
        departureTime = initialState.departureTime
        importedRouteID = initialState.importedRouteID
        importNotice = initialState.importNotice
    }

    var usesCurrentLocation: Bool {
        get { originMode == .currentLocation }
        set { originMode = newValue ? .currentLocation : .manual }
    }

    func apply(_ route: SharedRouteDraft) {
        let next = RoutePlanningFormReducer.applying(route, to: state)
        apply(next)
    }

    func presentImportError(_ message: String) {
        importNotice = RouteImportNotice(
            title: "Map route could not be imported",
            message: message,
            isError: true
        )
    }

    func clearImportNotice() {
        importNotice = nil
    }

    func reset() {
        apply(RoutePlanningFormState())
    }

    private var state: RoutePlanningFormState {
        RoutePlanningFormState(
            origin: origin,
            destination: destination,
            originMode: originMode,
            departureTime: departureTime,
            importedRouteID: importedRouteID,
            importNotice: importNotice
        )
    }

    private func apply(_ state: RoutePlanningFormState) {
        origin = state.origin
        destination = state.destination
        originMode = state.originMode
        departureTime = state.departureTime
        importedRouteID = state.importedRouteID
        importNotice = state.importNotice
    }
}

struct RouteAnalysisResult: Hashable {
    let origin: String
    let destination: String
    let departureTime: Date
    let primaryRoute: ScoredRoute
    let alternateRoutes: [ScoredRoute]
}

/// Owned by the root, so switching tabs cannot cancel work or discard results.
@MainActor
final class RoutePlanningAnalysisModel: ObservableObject {
    typealias Analyze = (String, String, Date, String) async throws -> RouteDifficultyResponse

    @Published private(set) var isLoading = false
    @Published private(set) var result: RouteAnalysisResult?
    @Published private(set) var errorMessage: String?
    private var task: Task<Void, Never>?
    private var accountObservation: AnyCancellable?
    private var generation = 0
    private let analyze: Analyze

    init(analyze: @escaping Analyze = { origin, destination, departure, token in
        try await APIClient().analyzeRoute(
            origin: origin, destination: destination, departureTime: departure,
            accessToken: token, includeAlternates: true
        )
    }) {
        self.analyze = analyze
    }

    func start(form: RoutePlanningFormModel, auth: AuthSessionStore, recentRoutes: RecentRouteStore) {
        guard !isLoading, auth.isSignedIn else { return }
        let origin = form.origin
        let destination = form.destination
        let departure = form.departureTime
        let accountGeneration = auth.accountDataGeneration
        let requestGeneration = generation
        isLoading = true
        result = nil
        errorMessage = nil
        accountObservation = auth.$accountDataGeneration.dropFirst().sink { [weak self] _ in
            self?.cancel()
        }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await auth.performAuthenticated { token in
                    try await self.analyze(origin, destination, departure, token)
                }
                guard !Task.isCancelled, self.generation == requestGeneration,
                      auth.accountDataGeneration == accountGeneration, auth.isSignedIn else { return }
                recentRoutes.record(origin: origin, destination: destination, departureTime: departure, route: response.primaryRoute)
                self.result = RouteAnalysisResult(
                    origin: origin, destination: destination, departureTime: departure,
                    primaryRoute: response.primaryRoute, alternateRoutes: response.alternateRoutes
                )
            } catch {
                guard !Task.isCancelled, self.generation == requestGeneration,
                      auth.accountDataGeneration == accountGeneration, auth.isSignedIn else { return }
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
            self.task = nil
        }
    }

    func takeResult() -> RouteAnalysisResult? {
        guard let result else { return nil }
        self.result = nil
        isLoading = false
        accountObservation = nil
        return result
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
        accountObservation = nil
        result = nil
        errorMessage = nil
        isLoading = false
    }
}
