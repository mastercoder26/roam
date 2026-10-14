import Combine
import Foundation

#if canImport(ClerkKit)
import ClerkKit
#endif

enum ProfileSyncAction: Equatable {
    case pullRemote
    case pushLocal
    case none
}

enum ProfileSyncConflictResolver {
    static func resolve(
        local: DriverProfile,
        localUpdatedAt: Date,
        remote: RemoteProfile?
    ) -> ProfileSyncAction {
        let localIsEmpty = local.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && local.stage == .permit

        guard let remote else { return localIsEmpty ? .none : .pushLocal }

        let remoteIsEmpty = remote.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && remote.stage == .permit
            && remote.payload.isEmpty
        if remoteIsEmpty { return localIsEmpty ? .none : .pushLocal }
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

    private let client: ClerkBackendClient
    private let profileStore: DriverProfileStore
    private var testAccessToken: String?
    private var hasStartedRestore = false
    private var isProfileSyncInFlight = false
    /// Invalidates profile and identity requests that finish after a session
    /// transition. The remote request may ignore task cancellation.
    private var sessionGeneration = 0
    /// Clerk's identity and the data API's user ID are different namespaces.
    /// Keep Clerk's ID separately while app state contains the backend user.
    private var activeClerkUserID: String?
    private var driveHistorySyncRequest: (() -> Void)?

    init(
        client: ClerkBackendClient = ClerkBackendClient(),
        profileStore: DriverProfileStore? = nil,
        automaticallyRestore: Bool = true
    ) {
        self.client = client
        self.profileStore = profileStore ?? .shared
        guard automaticallyRestore else { return }
        Task { @MainActor [weak self] in
            await self?.restoreIfNeeded()
        }
    }

    var currentUser: AuthUser? {
        switch state {
        case let .signedIn(user), let .signedInOffline(user): user
        case .restoring, .signedOut, .authenticating: nil
        }
    }

    var isSignedIn: Bool {
        switch state {
        case .signedIn, .signedInOffline: true
        case .restoring, .signedOut, .authenticating: false
        }
    }

    /// Stable owner for cloud-drive sync. `/api/auth/me` returns a database UUID,
    /// while an offline Clerk session initially has only the Clerk user ID.
    /// The Clerk ID stays the same across that transition.
    var driveHistoryAccountID: String? {
        guard isSignedIn else { return nil }
        return activeClerkUserID ?? currentUser?.id
    }

    /// Synchronizes the app-facing state with Clerk's observable user. This is
    /// called on launch and whenever the prebuilt views activate or end a
    /// Clerk session.
    func synchronizeWithClerk() async {
        #if canImport(ClerkKit)
        guard let clerkUser = Clerk.shared.user else {
            markSignedOut()
            return
        }

        let clerkIdentity = AuthUser(
            id: clerkUser.id,
            email: clerkUser.primaryEmailAddress?.emailAddress ?? "",
            displayName: [clerkUser.firstName, clerkUser.lastName]
                .compactMap { $0 }
                .joined(separator: " ")
                .nilIfEmpty
        )
        sessionGeneration &+= 1
        let generation = sessionGeneration
        isProfileSyncInFlight = false
        activeClerkUserID = clerkIdentity.id
        state = .signedIn(clerkIdentity)

        do {
            let backendUser = try await performAuthenticated { token in
                try await self.client.currentUser(accessToken: token)
            }
            guard applyBackendIdentity(
                backendUser,
                generation: generation,
                replacingUserID: clerkIdentity.id
            ) else { return }
            await syncProfile(expectedGeneration: generation)
            guard isCurrentSession(generation: generation, userID: backendUser.id) else { return }
            requestDriveHistorySync()
        } catch {
            guard isCurrentSession(generation: generation, userID: clerkIdentity.id) else { return }
            state = .signedInOffline(clerkIdentity)
            syncStatus = .workingOffline
            requestDriveHistorySync()
        }
        #else
        if !isSignedIn { state = .signedOut }
        #endif
    }

    func restoreIfNeeded() async {
        guard !hasStartedRestore else { return }
        hasStartedRestore = true
        state = .restoring
        await synchronizeWithClerk()
    }

    /// Clerk owns sign-in and sign-up through AuthView. These methods are
    /// intentionally absent: the app must never call the removed custom
    /// /api/auth/signup or /api/auth/login endpoints.

    func signOut() async throws {
        #if canImport(ClerkKit)
        try await Clerk.shared.auth.signOut()
        #endif
        markSignedOut()
    }

    func deleteAccount() async throws {
        try await performAuthenticated { token in
            try await self.client.deleteAccount(accessToken: token)
        }
        profileStore.reset()
        #if canImport(ClerkKit)
        try await Clerk.shared.auth.signOut()
        #endif
        markSignedOut()
    }

    func retryProfileSync() async {
        await synchronizeWithClerk()
    }

    func requestDriveHistorySync() {
        guard isSignedIn else { return }
        driveHistorySyncRequest?()
    }

    /// Re-runs profile reconciliation outside the cold-launch path.
    ///
    /// `restoreIfNeeded()` runs once per process, so without this a profile
    /// edit made in one session — advancing a learner stage, changing a display
    /// name — stayed local until the app was fully killed and relaunched.
    /// `syncProfile()` resolves conflicts in both directions, so repeating it
    /// on foreground is safe and simply converges.
    @discardableResult
    func requestProfileSync() -> Task<Void, Never>? {
        guard let userID = currentUser?.id, !isProfileSyncInFlight else { return nil }
        isProfileSyncInFlight = true
        let generation = sessionGeneration
        return Task { [weak self] in
            guard let self else { return }
            defer {
                if self.sessionGeneration == generation { self.isProfileSyncInFlight = false }
            }
            guard self.isCurrentSession(generation: generation, userID: userID) else { return }
            await self.syncProfile(expectedGeneration: generation)
        }
    }

    func configureDriveHistorySync(_ request: @escaping () -> Void) {
        driveHistorySyncRequest = request
        if isSignedIn { request() }
    }

    /// Stable contract used by DriveHistorySyncService. Clerk returns a
    /// short-lived session token and refreshes it internally; this method only
    /// hands that current token to the authenticated operation.
    func performAuthenticated<Response>(
        _ operation: @escaping (String) async throws -> Response
    ) async throws -> Response {
        #if canImport(ClerkKit)
        guard Clerk.shared.user != nil else {
            throw AuthError.unauthorized(message: "Sign in to continue.")
        }
        guard let token = try await Clerk.shared.auth.getToken() else {
            throw AuthError.unauthorized(message: "Your Clerk session is not available. Sign in again.")
        }
        return try await operation(token)
        #else
        guard let token = testAccessToken else {
            throw AuthError.unauthorized(message: "Sign in to continue.")
        }
        return try await operation(token)
        #endif
    }

    /// Test-only state injection for the standalone drive-sync checks. It does
    /// not persist credentials or participate in production Clerk state.
    func setSignedInForTesting(
        user: AuthUser,
        accessToken: String,
        stableAccountID: String? = nil
    ) {
        sessionGeneration &+= 1
        isProfileSyncInFlight = false
        activeClerkUserID = stableAccountID
        testAccessToken = accessToken
        state = .signedIn(user)
    }

    /// Exercises the same identity transition as `/api/auth/me` without
    /// requiring ClerkKit in the standalone Swift checks.
    func applyBackendIdentityForTesting(_ backendUser: AuthUser) -> Bool {
        guard let currentID = currentUser?.id else { return false }
        return applyBackendIdentity(
            backendUser,
            generation: sessionGeneration,
            replacingUserID: currentID
        )
    }

    private func applyBackendIdentity(
        _ backendUser: AuthUser,
        generation: Int,
        replacingUserID: String
    ) -> Bool {
        guard isCurrentSession(generation: generation, userID: replacingUserID) else { return false }
        state = .signedIn(backendUser)
        return true
    }

    private func isCurrentSession(generation: Int, userID: String) -> Bool {
        guard sessionGeneration == generation, currentUser?.id == userID else { return false }
        #if canImport(ClerkKit)
        guard let activeClerkUserID else { return false }
        return Clerk.shared.user?.id == activeClerkUserID
        #else
        return testAccessToken != nil
        #endif
    }

    private func syncProfile(expectedGeneration: Int) async {
        guard let user = currentUser else { return }
        guard isCurrentSession(generation: expectedGeneration, userID: user.id) else { return }
        syncStatus = .syncing

        do {
            let remote = try await performAuthenticated { token in
                try await self.client.profile(accessToken: token)
            }
            guard isCurrentSession(generation: expectedGeneration, userID: user.id) else { return }
            let localStore = profileStore
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
                guard isCurrentSession(generation: expectedGeneration, userID: user.id) else { return }
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
            guard isCurrentSession(generation: expectedGeneration, userID: user.id) else { return }
            if error.isTransient {
                state = .signedInOffline(user)
                syncStatus = .workingOffline
            } else {
                syncStatus = .failed(error.localizedDescription)
            }
        } catch {
            guard isCurrentSession(generation: expectedGeneration, userID: user.id) else { return }
            syncStatus = .failed("Profile sync failed. Try again.")
        }
    }

    private func markSignedOut() {
        sessionGeneration &+= 1
        isProfileSyncInFlight = false
        activeClerkUserID = nil
        testAccessToken = nil
        state = .signedOut
        syncStatus = .synced
        DriveHistorySyncService.shared.didSignOut()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

typealias AuthSessionState = AuthSessionStore.State
