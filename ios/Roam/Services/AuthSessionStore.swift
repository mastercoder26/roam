import Combine
import Foundation

enum ProfileSyncAction: Equatable {
    case pullRemote
    case pushLocal
    case none
}

enum ProfileSyncConflictResolver {
    /// Local edits win only when their timestamp is newer. A non-empty local
    /// profile also wins over an empty remote profile so an initial offline
    /// profile is not erased by a newly-created server row.
    static func resolve(
        local: DriverProfile,
        localUpdatedAt: Date,
        remote: RemoteProfile?
    ) -> ProfileSyncAction {
        let localIsEmpty = local.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && local.stage == .permit

        guard let remote else {
            return localIsEmpty ? .none : .pushLocal
        }

        let remoteIsEmpty = remote.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && remote.stage == .permit
            && remote.payload.isEmpty
        if remoteIsEmpty {
            return localIsEmpty ? .none : .pushLocal
        }
        if localIsEmpty { return .pullRemote }
        return remote.updatedAt >= localUpdatedAt ? .pullRemote : .pushLocal
    }
}

@MainActor
final class AuthSessionStore: ObservableObject {
    enum State: Equatable {
        case restoring
        case signedOut
        case authenticating
        case signedIn(AuthUser)
        case signedInOffline(AuthUser)
    }

    enum SyncStatus: Equatable {
        case synced
        case syncing
        case workingOffline
        case failed(String)
    }

    static let shared = AuthSessionStore()

    @Published private(set) var state: State = .restoring
    @Published private(set) var syncStatus: SyncStatus = .synced

    private let client: any AuthServicing
    private let tokenStore: TokenStore
    private var accessToken: String?
    private var refreshTask: Task<String, Error>?
    private var hasStartedRestore = false

    init(
        client: any AuthServicing = AuthClient(),
        tokenStore: TokenStore = TokenStore(),
        automaticallyRestore: Bool = true
    ) {
        self.client = client
        self.tokenStore = tokenStore
        guard automaticallyRestore else { return }
        Task { @MainActor [weak self] in
            await self?.restoreIfNeeded()
        }
    }

    var currentUser: AuthUser? {
        switch state {
        case .signedIn(let user), .signedInOffline(let user): user
        case .restoring, .signedOut, .authenticating: nil
        }
    }

    var isSignedIn: Bool {
        switch state {
        case .signedIn, .signedInOffline: true
        case .restoring, .signedOut, .authenticating: false
        }
    }

    func restoreIfNeeded() async {
        guard !hasStartedRestore else { return }
        hasStartedRestore = true
        state = .restoring

        do {
            guard let stored = try tokenStore.load() else {
                state = .signedOut
                return
            }

            let cachedUser = stored.user ?? AuthUser(id: stored.userID, email: "", displayName: nil)
            do {
                _ = try await refreshAccessToken()
            } catch let error as AuthError where error.code == .unauthorized {
                // Only refresh's genuine UNAUTHORIZED reaches this branch.
                state = .signedOut
                return
            } catch {
                state = .signedInOffline(cachedUser)
                syncStatus = .workingOffline
                return
            }

            do {
                let user = try await performAuthenticated { accessToken in
                    try await self.client.currentUser(accessToken: accessToken)
                }
                state = .signedIn(user)
                await syncProfile()
            } catch {
                state = .signedInOffline(cachedUser)
                syncStatus = .workingOffline
            }
        } catch let error as TokenStoreError {
            state = .signedOut
            syncStatus = .failed(error.localizedDescription)
        } catch {
            state = .signedOut
            syncStatus = .failed("Your saved session could not be restored. Sign in again.")
        }
    }

    func signIn(email: String, password: String) async throws {
        state = .authenticating
        do {
            let response = try await client.login(email: email, password: password)
            try save(response: response)
            state = .signedIn(response.user)
            await syncProfile()
        } catch let error as AuthError {
            state = .signedOut
            throw error
        } catch let error as TokenStoreError {
            state = .signedOut
            throw AuthError.keychain(message: error.localizedDescription)
        } catch {
            state = .signedOut
            throw AuthError.serverUnavailable
        }
    }

    func signUp(email: String, password: String, displayName: String?) async throws {
        state = .authenticating
        do {
            let response = try await client.signUp(email: email, password: password, displayName: displayName)
            try save(response: response)
            state = .signedIn(response.user)
            await syncProfile()
        } catch let error as AuthError {
            state = .signedOut
            throw error
        } catch let error as TokenStoreError {
            state = .signedOut
            throw AuthError.keychain(message: error.localizedDescription)
        } catch {
            state = .signedOut
            throw AuthError.serverUnavailable
        }
    }

    func signOut() async throws {
        let stored = try tokenStore.load()
        var failure: Error?
        if let stored {
            do {
                try await client.logout(refreshToken: stored.refreshToken)
            } catch {
                failure = error
            }
        }

        do {
            try tokenStore.clear()
        } catch {
            failure = failure ?? error
        }
        accessToken = nil
        refreshTask = nil
        state = .signedOut

        if let failure {
            throw asAuthError(failure)
        }
    }

    func deleteAccount() async throws {
        try await performAuthenticated { token in
            try await self.client.deleteAccount(accessToken: token)
        }
        DriverProfileStore.shared.reset()
        do {
            try tokenStore.clear()
        } catch let error as TokenStoreError {
            throw AuthError.keychain(message: error.localizedDescription)
        }
        accessToken = nil
        refreshTask = nil
        state = .signedOut
        syncStatus = .synced
    }

    func retryProfileSync() async {
        await syncProfile()
    }

    /// Runs one authenticated operation, refreshing once when the backend
    /// explicitly says the short-lived access token expired.
    func performAuthenticated<Response>(
        _ operation: @escaping (String) async throws -> Response
    ) async throws -> Response {
        let token = try await currentAccessToken()
        do {
            return try await operation(token)
        } catch let error as AuthError where error.code == .tokenExpired {
            let refreshedToken = try await refreshAccessToken()
            return try await operation(refreshedToken)
        }
    }

    /// Test hook for the pure session state-machine checks. It never persists
    /// a token and is intentionally internal to this app module.
    func setSignedInForTesting(user: AuthUser, accessToken: String) {
        self.accessToken = accessToken
        state = .signedIn(user)
    }

    private func currentAccessToken() async throws -> String {
        if let accessToken { return accessToken }
        return try await refreshAccessToken()
    }

    private func refreshAccessToken() async throws -> String {
        if let refreshTask {
            return try await refreshTask.value
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { throw AuthError.serverUnavailable }
            return try await self.performRefresh()
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func performRefresh() async throws -> String {
        let stored: TokenStore.StoredSession
        do {
            guard let value = try tokenStore.load() else {
                throw AuthError.unauthorized(message: "Your saved session is missing. Sign in again.")
            }
            stored = value
        } catch let error as TokenStoreError {
            throw AuthError.keychain(message: error.localizedDescription)
        }

        do {
            let response = try await client.refresh(refreshToken: stored.refreshToken)
            let user = currentUser ?? stored.user ?? AuthUser(id: stored.userID, email: "", displayName: nil)
            try tokenStore.save(refreshToken: response.refreshToken, user: user)
            accessToken = response.accessToken
            return response.accessToken
        } catch let error as AuthError where error.code == .unauthorized {
            // This is the one sign-out path for a server response: the
            // refresh token is genuinely rejected, not merely unreachable.
            do {
                try tokenStore.clear()
            } catch let error as TokenStoreError {
                accessToken = nil
                state = .signedOut
                throw AuthError.keychain(message: error.localizedDescription)
            }
            accessToken = nil
            state = .signedOut
            throw AuthError.unauthorized(message: "Your session has ended. Sign in again.")
        } catch let error as TokenStoreError {
            throw AuthError.keychain(message: error.localizedDescription)
        }
    }

    private func syncProfile() async {
        guard let user = currentUser else { return }
        syncStatus = .syncing

        do {
            let remote = try await performAuthenticated { token in
                try await self.client.profile(accessToken: token)
            }
            let localStore = DriverProfileStore.shared
            switch ProfileSyncConflictResolver.resolve(
                local: localStore.snapshot,
                localUpdatedAt: localStore.lastUpdatedAt,
                remote: remote
            ) {
            case .pullRemote:
                localStore.applyRemoteProfile(
                    displayName: remote.displayName,
                    stage: remote.stage,
                    updatedAt: remote.updatedAt
                )
            case .pushLocal:
                let local = localStore.snapshot
                let updated = try await performAuthenticated { token in
                    try await self.client.updateProfile(
                        accessToken: token,
                        displayName: local.displayName,
                        stage: local.stage,
                        payload: nil
                    )
                }
                localStore.applyRemoteProfile(
                    displayName: updated.displayName,
                    stage: updated.stage,
                    updatedAt: updated.updatedAt
                )
            case .none:
                break
            }
            state = .signedIn(user)
            syncStatus = .synced
        } catch let error as AuthError {
            if isReachabilityFailure(error) {
                state = .signedInOffline(user)
                syncStatus = .workingOffline
            } else {
                syncStatus = .failed(error.localizedDescription)
            }
        } catch {
            syncStatus = .failed("Profile sync failed. Try again.")
        }
    }

    private func save(response: AuthResponse) throws {
        do {
            try tokenStore.save(refreshToken: response.refreshToken, user: response.user)
        } catch let error as TokenStoreError {
            throw error
        }
        accessToken = response.accessToken
    }

    private func isReachabilityFailure(_ error: AuthError) -> Bool {
        switch error {
        case .offline, .serverUnavailable, .serviceUnavailable:
            true
        default:
            false
        }
    }

    private func asAuthError(_ error: Error) -> AuthError {
        if let error = error as? AuthError { return error }
        if let error = error as? TokenStoreError { return .keychain(message: error.localizedDescription) }
        return .serverUnavailable
    }
}

typealias AuthSessionState = AuthSessionStore.State
