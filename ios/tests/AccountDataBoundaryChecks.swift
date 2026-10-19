import Foundation

@main
struct AccountDataBoundaryChecks {
    @MainActor
    static func main() async throws {
        let suite = "AccountDataBoundaryChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let boundary = AccountLocalDataBoundary(defaults: defaults)
        boundary.transition(to: "account-a")
        for key in AccountLocalDataBoundary.contentKeys { defaults.set(Data("private".utf8), forKey: key) }
        defaults.set("dark", forKey: "roam.theme-id-v1")
        expect(!boundary.transition(to: "account-a"), "refreshing the same account must preserve local data")
        expect(defaults.data(forKey: "recorded-drives-v1") != nil, "same-account history must survive")
        let profile = DriverProfileStore(defaults: defaults)
        let session = AuthSessionStore(profileStore: profile, userDefaults: defaults, automaticallyRestore: false)
        session.setSignedInForTesting(user: AuthUser(id: "backend-a", email: "a@example.com", displayName: nil), accessToken: "token", stableAccountID: "account-a")
        profile.displayName = "Private Driver"
        profile.stage = .licensed
        var resets = 0
        session.configureAccountDataReset { resets += 1 }
        let generation = session.accountDataGeneration
        try await session.signOut()
        expect(resets == 1, "sign-out must reset live caches exactly once")
        expect(session.accountDataGeneration > generation, "sign-out must invalidate pending results")
        expect(profile.snapshot == .empty, "sign-out must remove profile identity")
        for key in AccountLocalDataBoundary.contentKeys { expect(defaults.object(forKey: key) == nil, "sign-out must remove \(key)") }
        expect(defaults.string(forKey: "roam.theme-id-v1") == "dark", "appearance is a device preference")
        defaults.set(Data("guest drive".utf8), forKey: "recorded-drives-v1")
        try await session.signOut()
        expect(resets == 1, "repeated signed-out reconciliation must not erase fresh guest work")
        expect(defaults.data(forKey: "recorded-drives-v1") != nil, "fresh guest work must survive")
        boundary.transition(to: "account-b")
        expect(defaults.data(forKey: "recorded-drives-v1") == nil, "guest history must not upload into another account")
        defaults.set(Data("B private".utf8), forKey: "recentRoutes.v1")
        let relaunched = AccountLocalDataBoundary(defaults: defaults)
        relaunched.transition(to: nil)
        expect(defaults.data(forKey: "recentRoutes.v1") == nil, "expired sessions must clear account caches on cold launch")
        print("Account data boundary checks passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }
}
