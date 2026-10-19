import Foundation

@MainActor
private final class HeldAnalysis {
    var continuation: CheckedContinuation<RouteDifficultyResponse, Error>?
    var requests = 0
    func analyze() async throws -> RouteDifficultyResponse {
        requests += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func finish(_ response: RouteDifficultyResponse) { continuation?.resume(returning: response); continuation = nil }
    func fail() { continuation?.resume(throwing: URLError(.notConnectedToInternet)); continuation = nil }
}

@MainActor
private final class AnalysisClock { var time: TimeInterval = 100 }

@main
struct RoutePlanningAnalysisChecks {
    @MainActor
    static func main() async throws {
        let suite = "RoutePlanningAnalysisChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let auth = AuthSessionStore(profileStore: DriverProfileStore(defaults: defaults), userDefaults: defaults, automaticallyRestore: false)
        auth.setSignedInForTesting(user: AuthUser(id: "account-a", email: "a@example.com", displayName: nil), accessToken: "token")
        let recent = RecentRouteStore(userDefaults: defaults)
        auth.configureAccountDataReset { recent.clear() }
        let held = HeldAnalysis()
        let timing = RouteAnalysisTimingEstimator(defaults: defaults)
        let clock = AnalysisClock()
        let model = RoutePlanningAnalysisModel(timingEstimator: timing, uptime: { clock.time }) { _, _, _, _ in try await held.analyze() }
        let form = RoutePlanningFormModel(initialState: .init(origin: "Start", destination: "Finish"))
        let response = try JSONDecoder().decode(RouteDifficultyResponse.self, from: Data(fixture.utf8))
        model.start(form: form, auth: auth, recentRoutes: recent)
        await waitUntil { held.continuation != nil }
        expect(model.progress?.startedAt == 100, "the progress clock must begin with the request, not when its view mounts")
        // No view owns this task: leaving the tab has no cancellation callback.
        model.start(form: form, auth: auth, recentRoutes: recent)
        expect(held.requests == 1, "a tab returning while loading must not duplicate the request")
        form.destination = "Later edit"
        clock.time = 106
        held.finish(response)
        await waitUntil { model.result != nil }
        expect(model.result?.destination == "Finish", "the result must preserve submitted endpoints")
        expect(recent.entries.count == 1, "offscreen completion must record exactly one recent route")
        expect(model.progress?.completedAt == 106, "the trace completes only after a real response")
        let timingHistory = defaults.data(forKey: "roam.route-analysis-timing-v1")
        expect(timingHistory != nil, "successful latency must train future estimates")
        expect(model.takeResult() != nil && model.takeResult() == nil, "returning to the tab consumes the result once")
        expect(!model.isLoading, "completion must clear loading")
        expect(model.progress == nil, "consuming the result must clear the progress clock")

        model.start(form: form, auth: auth, recentRoutes: recent)
        await waitUntil { held.continuation != nil }
        try await auth.signOut()
        auth.setSignedInForTesting(user: AuthUser(id: "account-a", email: "a@example.com", displayName: nil), accessToken: "new-token")
        held.finish(response)
        for _ in 0..<20 { await Task.yield() }
        expect(model.result == nil && !model.isLoading, "even signing back into the same account must reject an old response")
        expect(model.progress == nil, "account changes must clear progress")
        expect(recent.entries.isEmpty, "late responses must not repopulate cleared history")

        model.start(form: form, auth: auth, recentRoutes: recent)
        await waitUntil { held.continuation != nil }
        held.fail()
        await waitUntil { !model.isLoading }
        expect(model.errorMessage != nil, "offscreen failure must remain available when the tab returns")
        expect(model.progress == nil, "failure must dismiss progress without reporting success")
        model.start(form: form, auth: auth, recentRoutes: recent)
        await waitUntil { held.continuation != nil }
        model.cancel()
        held.finish(response)
        for _ in 0..<20 { await Task.yield() }
        expect(model.result == nil && recent.entries.isEmpty, "import replacement must invalidate the previous route request")
        expect(defaults.data(forKey: "roam.route-analysis-timing-v1") == timingHistory, "failed, canceled and stale requests must never train the estimator")
        print("Route planning analysis checks passed")
    }
    @MainActor
    private static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        fatalError("Timed out waiting for route analysis")
    }
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }
    private static let fixture = #"""
    {"primaryRoute":{"score":3,"label":"Easy","reasons":[],"breakdown":{"traffic":0,"highway":0,"maneuvers":0,"navDensity":0,"effort":0},"distanceMeters":2000,"durationSeconds":300,"staticDurationSeconds":300,"trafficDelaySeconds":0,"polyline":"abc","bounds":{"southwest":{"lat":40,"lng":-74},"northeast":{"lat":41,"lng":-73}}},"alternateRoutes":[]}
    """#
}
