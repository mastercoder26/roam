import Foundation

@main
struct AuthChecks {
    @MainActor
    static func main() async {
        await tokenStoreRoundTripsCredentials()
        errorCodesMapToPlainMessages()
        await networkFailureDuringRestoreKeepsCachedSessionOffline()
        await tokenExpiryRefreshesOnceAndRetries()
        profileConflictRulePrefersTheNewerSource()

        print("Auth checks passed")
    }

    @MainActor
    private static func tokenStoreRoundTripsCredentials() async {
        let service = "roam.auth-checks.\(UUID().uuidString)"
        let store = TokenStore(service: service, backend: InMemoryTokenStoreBackend())
        defer { try? store.clear() }

        let user = AuthUser(id: "user-1", email: "driver@example.com", displayName: "Driver")
        try? store.clear()
        do {
            try store.save(refreshToken: "refresh-one", user: user)
            let saved = try store.load()
            expect(saved?.refreshToken == "refresh-one", "refresh token should round-trip through Keychain")
            expect(saved?.userID == user.id, "user id should round-trip through Keychain")
            expect(saved?.user == user, "cached user should round-trip for offline restoration")
        } catch {
            fail("token store round-trip failed: \(error)")
        }
    }

    private static func errorCodesMapToPlainMessages() {
        let body = Data(#"{"error":"That email is already in use.","code":"EMAIL_TAKEN","requestId":"req-1"}"#.utf8)
        let error = AuthError.from(statusCode: 409, data: body)
        expect(error.code == .emailTaken, "EMAIL_TAKEN should remain branchable")
        expect(error.errorDescription == "That email is already in use.", "EMAIL_TAKEN should use the backend's plain message")

        let expired = AuthError.from(
            statusCode: 401,
            data: Data(#"{"error":"Your session has expired.","code":"TOKEN_EXPIRED","requestId":"req-2"}"#.utf8)
        )
        expect(expired.code == .tokenExpired, "TOKEN_EXPIRED should remain branchable")
        expect(expired.errorDescription == "Your session has expired.", "token expiry should explain the next step plainly")
    }

    @MainActor
    private static func networkFailureDuringRestoreKeepsCachedSessionOffline() async {
        let service = "roam.auth-checks.restore.\(UUID().uuidString)"
        let store = TokenStore(service: service, backend: InMemoryTokenStoreBackend())
        defer { try? store.clear() }
        let user = AuthUser(id: "user-2", email: "offline@example.com", displayName: "Offline Driver")
        try? store.save(refreshToken: "refresh-two", user: user)

        let session = AuthSessionStore(
            client: FakeAuthClient(refreshResult: .failure(AuthError.offline)),
            tokenStore: store,
            automaticallyRestore: false
        )
        await session.restoreIfNeeded()

        guard case let .signedInOffline(restoredUser) = session.state else {
            fail("network failure during restore must keep the cached user signed in offline")
        }
        expect(restoredUser == user, "offline restore should retain the cached account identity")
    }

    @MainActor
    private static func tokenExpiryRefreshesOnceAndRetries() async {
        let service = "roam.auth-checks.refresh.\(UUID().uuidString)"
        let store = TokenStore(service: service, backend: InMemoryTokenStoreBackend())
        defer { try? store.clear() }
        let user = AuthUser(id: "user-3", email: "retry@example.com", displayName: "Retry Driver")
        try? store.save(refreshToken: "old-refresh", user: user)

        let client = FakeAuthClient(
            refreshResult: .success(AuthTokenResponse(accessToken: "new-access", refreshToken: "new-refresh", expiresIn: 900)),
            protectedResults: [
                .failure(.tokenExpired(message: "Your session has expired.")),
                .success(user)
            ]
        )
        let session = AuthSessionStore(client: client, tokenStore: store, automaticallyRestore: false)
        session.setSignedInForTesting(user: user, accessToken: "old-access")

        do {
            let returnedUser = try await session.performAuthenticated { token in
                expect(token == "old-access" || token == "new-access", "the request should receive an access token")
                return try await client.currentUser(accessToken: token)
            }
            expect(returnedUser == user, "the retried request should return the user")
            expect(client.refreshCount == 1, "parallel-expiry protection should perform one refresh")
            let saved = try store.load()
            expect(saved?.refreshToken == "new-refresh", "rotated refresh token must replace the old token")
        } catch {
            fail("token expiry retry failed: \(error)")
        }
    }

    private static func profileConflictRulePrefersTheNewerSource() {
        let local = DriverProfile(displayName: "Local", stage: .permit)
        let remote = RemoteProfile(displayName: "Remote", stage: .licensed, payload: [:], updatedAt: Date(timeIntervalSince1970: 200))

        expect(
            ProfileSyncConflictResolver.resolve(local: local, localUpdatedAt: Date(timeIntervalSince1970: 100), remote: remote) == .pullRemote,
            "a newer remote profile should replace the local profile"
        )
        expect(
            ProfileSyncConflictResolver.resolve(local: local, localUpdatedAt: Date(timeIntervalSince1970: 300), remote: remote) == .pushLocal,
            "a newer local profile should be pushed to the server"
        )
        expect(
            ProfileSyncConflictResolver.resolve(local: local, localUpdatedAt: Date(timeIntervalSince1970: 300), remote: RemoteProfile(displayName: "", stage: .permit, payload: [:], updatedAt: Date(timeIntervalSince1970: 400))) == .pushLocal,
            "a non-empty local profile should be pushed when the remote profile is empty"
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        fatalError("Auth check failed: \(message)")
    }
}

private final class FakeAuthClient: AuthServicing, @unchecked Sendable {
    let refreshResult: Result<AuthTokenResponse, AuthError>
    var protectedResults: [Result<AuthUser, AuthError>]
    private(set) var refreshCount = 0

    init(
        refreshResult: Result<AuthTokenResponse, AuthError>,
        protectedResults: [Result<AuthUser, AuthError>] = []
    ) {
        self.refreshResult = refreshResult
        self.protectedResults = protectedResults
    }

    func signUp(email: String, password: String, displayName: String?) async throws -> AuthResponse { fatalError("unused") }
    func login(email: String, password: String) async throws -> AuthResponse { fatalError("unused") }
    func refresh(refreshToken: String) async throws -> AuthTokenResponse {
        refreshCount += 1
        return try refreshResult.get()
    }
    func logout(refreshToken: String) async throws {}
    func currentUser(accessToken: String) async throws -> AuthUser {
        guard !protectedResults.isEmpty else { fatalError("missing fake protected result") }
        return try protectedResults.removeFirst().get()
    }
    func profile(accessToken: String) async throws -> RemoteProfile { fatalError("unused") }
    func updateProfile(accessToken: String, displayName: String?, stage: DriverProfile.Stage?, payload: [String: JSONValue]?) async throws -> RemoteProfile { fatalError("unused") }
    func deleteAccount(accessToken: String) async throws {}
    func health() async throws -> HealthResponse { fatalError("unused") }
}

private final class InMemoryTokenStoreBackend: TokenStoreBackend, @unchecked Sendable {
    private var data: Data?

    func save(data: Data, service: String, account: String) throws {
        self.data = data
    }

    func load(service: String, account: String) throws -> Data? {
        data
    }

    func clear(service: String, account: String) throws {
        data = nil
    }
}
