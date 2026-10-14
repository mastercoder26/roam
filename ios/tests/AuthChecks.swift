import Foundation

@main
struct AuthChecks {
    @MainActor
    static func main() async {
        await authenticatedOperationUsesClerkSessionTokenContract()
        await signedOutOperationsAreRejected()
        await signingOutEndsTheSessionWithoutDeletingTheAccount()
        await staleProfileResponseCannotRestoreSignedOutSession()
        await staleProfileResponseCannotOverwriteAnotherAccount()
        backendIdentityCanDifferFromClerkIdentity()
        errorResponsesRemainSafeAndBranchable()
        remoteProfileDecoderTreatsNullStageAsPermit()
        profileConflictRulePrefersTheNewerSource()

        print("Auth checks passed")
    }

    @MainActor
    private static func authenticatedOperationUsesClerkSessionTokenContract() async {
        let user = AuthUser(id: "clerk-user", email: "driver@example.com", displayName: "Driver")
        let session = AuthSessionStore(automaticallyRestore: false)
        session.setSignedInForTesting(user: user, accessToken: "clerk-session-token")

        do {
            let returned = try await session.performAuthenticated { token in
                expect(token == "clerk-session-token", "authenticated work must receive the current Clerk session token")
                return token
            }
            expect(returned == "clerk-session-token", "authenticated work should return its result")
        } catch {
            fail("Clerk session token contract failed: \(error)")
        }
    }

    @MainActor
    private static func signedOutOperationsAreRejected() async {
        let session = AuthSessionStore(automaticallyRestore: false)
        do {
            _ = try await session.performAuthenticated { _ in "unexpected" }
            fail("signed-out authenticated work must not run")
        } catch let error as AuthError {
            expect(error.code == .unauthorized, "signed-out authenticated work should report unauthorized")
        } catch {
            fail("signed-out authenticated work returned the wrong error: \(error)")
        }
    }

    @MainActor
    private static func signingOutEndsTheSessionWithoutDeletingTheAccount() async {
        let user = AuthUser(id: "clerk-user", email: "driver@example.com", displayName: "Driver")
        let session = AuthSessionStore(automaticallyRestore: false)
        session.setSignedInForTesting(user: user, accessToken: "clerk-session-token")

        do {
            try await session.signOut()
        } catch {
            fail("sign out should end the local session without failing: \(error)")
        }

        expect(session.state == .signedOut, "sign out should clear the signed-in state")
        expect(session.currentUser == nil, "sign out should clear the current user")

        do {
            _ = try await session.performAuthenticated { _ in "unexpected" }
            fail("authenticated work must not run after sign out")
        } catch let error as AuthError {
            expect(error.code == .unauthorized, "authenticated work after sign out should be unauthorized")
        } catch {
            fail("sign out returned the wrong follow-up error: \(error)")
        }
    }

    @MainActor
    private static func staleProfileResponseCannotRestoreSignedOutSession() async {
        let (session, profile) = makeHeldProfileSession()
        session.setSignedInForTesting(
            user: AuthUser(id: "old-user", email: "old@example.com", displayName: nil),
            accessToken: "old-token"
        )
        let original = profile.snapshot
        let task = session.requestProfileSync()
        await waitUntil { HeldProfileURLProtocol.hasPendingRequest }

        do { try await session.signOut() } catch { fail("sign-out failed: \(error)") }
        HeldProfileURLProtocol.release()
        if let task { await task.value }

        expect(session.state == .signedOut, "a stale profile response must not sign the user back in")
        expect(profile.snapshot == original, "a stale profile response must not change the local profile after sign-out")
        expect(session.syncStatus == .synced, "a stale profile response must not change signed-out sync status")
    }

    @MainActor
    private static func staleProfileResponseCannotOverwriteAnotherAccount() async {
        let (session, profile) = makeHeldProfileSession()
        session.setSignedInForTesting(
            user: AuthUser(id: "first-user", email: "first@example.com", displayName: nil),
            accessToken: "first-token"
        )
        let original = profile.snapshot
        let task = session.requestProfileSync()
        await waitUntil { HeldProfileURLProtocol.hasPendingRequest }

        let secondUser = AuthUser(id: "second-user", email: "second@example.com", displayName: nil)
        session.setSignedInForTesting(user: secondUser, accessToken: "second-token")
        HeldProfileURLProtocol.release()
        if let task { await task.value }

        expect(session.state == .signedIn(secondUser), "a previous account's response must not replace the current session")
        expect(profile.snapshot == original, "a previous account's response must not overwrite the current profile")
    }

    @MainActor
    private static func backendIdentityCanDifferFromClerkIdentity() {
        let session = AuthSessionStore(automaticallyRestore: false)
        session.setSignedInForTesting(
            user: AuthUser(id: "user_clerk123", email: "driver@example.com", displayName: nil),
            accessToken: "token"
        )
        let backendUser = AuthUser(id: "b96fd03c-614e-46ab-a4ca-c2cd426e1520", email: "driver@example.com", displayName: nil)

        expect(session.applyBackendIdentityForTesting(backendUser), "a valid backend identity should replace the Clerk placeholder")
        expect(session.state == .signedIn(backendUser), "the backend user ID should be retained even when it differs from Clerk's ID")

        let stableSession = AuthSessionStore(automaticallyRestore: false)
        stableSession.setSignedInForTesting(
            user: AuthUser(id: "user_clerk123", email: "driver@example.com", displayName: nil),
            accessToken: "token",
            stableAccountID: "user_clerk123"
        )
        expect(stableSession.applyBackendIdentityForTesting(backendUser), "the backend identity transition should succeed")
        expect(stableSession.driveHistoryAccountID == "user_clerk123", "drive sync must retain the Clerk account key after backend identity arrives")
    }

    @MainActor
    private static func makeHeldProfileSession() -> (AuthSessionStore, DriverProfileStore) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HeldProfileURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)
        let backend = ClerkBackendClient(
            candidateBaseURLs: [URL(string: "https://test.example")!],
            dataCandidateBaseURLs: [URL(string: "https://test.example")!],
            session: urlSession
        )
        let defaults = UserDefaults(suiteName: "auth-checks-\(UUID().uuidString)")!
        let profile = DriverProfileStore(defaults: defaults)
        return (AuthSessionStore(client: backend, profileStore: profile, automaticallyRestore: false), profile)
    }

    @MainActor
    private static func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        fail("timed out waiting for held profile request")
    }

    private static func errorResponsesRemainSafeAndBranchable() {
        let body = Data(#"{"error":"Your Clerk session is not authorized for Roam.","code":"UNAUTHORIZED","requestId":"req-1"}"#.utf8)
        let error = AuthError.from(statusCode: 401, data: body)
        expect(error.code == .unauthorized, "UNAUTHORIZED should remain branchable")
        expect(error.localizedDescription == "Your Clerk session is not authorized for Roam.", "backend messages should remain user-facing")

        let malformed = AuthError.from(statusCode: 502, data: Data("<html>bad gateway</html>".utf8))
        expect(malformed.localizedDescription.count < 200, "untrusted error bodies must not become an oversized UI message")
    }

    private static func remoteProfileDecoderTreatsNullStageAsPermit() {
        let response = Data(#"{"displayName":null,"stage":null,"payload":{},"updatedAt":"2026-08-06T18:00:00.000Z"}"#.utf8)
        let profile = try? APIClient.makeDateDecoder().decode(RemoteProfile.self, from: response)

        expect(profile?.stage == .permit, "a newly-created server profile with a null stage should use the local permit default")

        let licensedResponse = Data(#"{"displayName":"Driver","stage":"licensed","payload":{},"updatedAt":"2026-08-06T18:00:00.000Z"}"#.utf8)
        let licensedProfile = try? APIClient.makeDateDecoder().decode(RemoteProfile.self, from: licensedResponse)

        expect(licensedProfile?.stage == .licensed, "a non-null server stage should remain unchanged")
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
            ProfileSyncConflictResolver.resolve(
                local: local,
                localUpdatedAt: Date(timeIntervalSince1970: 300),
                remote: RemoteProfile(displayName: "", stage: .permit, payload: [:], updatedAt: Date(timeIntervalSince1970: 400))
            ) == .pushLocal,
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

private final class HeldProfileURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var pending: HeldProfileURLProtocol?

    static var hasPendingRequest: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pending != nil
    }

    static func release() {
        lock.lock()
        let request = pending
        pending = nil
        lock.unlock()
        guard let request,
              let url = request.request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else { return }
        let body = Data(#"{"profile":{"displayName":"Old account profile","stage":"licensed","payload":{},"updatedAt":"2100-01-01T00:00:00.000Z"}}"#.utf8)
        request.client?.urlProtocol(request, didReceive: response, cacheStoragePolicy: .notAllowed)
        request.client?.urlProtocol(request, didLoad: body)
        request.client?.urlProtocolDidFinishLoading(request)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.pending = self
        Self.lock.unlock()
    }

    override func stopLoading() {}
}
