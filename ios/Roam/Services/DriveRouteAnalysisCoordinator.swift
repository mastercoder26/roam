import Foundation

/// Coordinates post-drive route analysis requests: initial attempts, retries,
/// stall detection, and debug-info bookkeeping. Extracted from
/// `DriveSessionManager` so the recording lifecycle and the network-bound
/// analysis lifecycle are separate concerns.
@MainActor
final class DriveRouteAnalysisCoordinator {

    /// Called when a drive's route analysis is resolved (success, failure, or
    /// stall), so the session manager can persist the updated drive.
    var onDriveUpdated: ((UUID, DriveRouteAnalysis) -> Void)?

    /// Called after persisting analysis results so the sync service can push
    /// the update to the server.
    var onSyncRequested: (() -> Void)?

    /// The most recent `/api/route/difficulty` attempt per drive, kept only
    /// for on-screen debugging when a drive is stuck `.pending`.
    private(set) var debugInfo: [UUID: RouteAnalysisDebugInfo] = [:]

    private var tasks: [UUID: Task<Void, Never>] = [:]
    private let authSession: AuthSessionStore

    init(authSession: AuthSessionStore = .shared) {
        self.authSession = authSession
    }

    /// Restarts analyses that outlived their request — a drive left `.pending`
    /// by a terminated app, or one whose retry became due. Called at launch and
    /// again on every foreground.
    func resumeIfNeeded(for drives: [RecordedDrive]) {
        for drive in drives where drive.routeAnalysis?.shouldRetry() == true
            || drive.routeAnalysis?.isStalled() == true {
            beginAnalysis(for: drive)
        }
    }

    /// Cancels an in-flight analysis for a drive that was deleted.
    func cancelAnalysis(for driveID: UUID) {
        tasks[driveID]?.cancel()
        tasks[driveID] = nil
    }

    /// Analyzes only the start and destination of a completed drive after its
    /// local record is safely persisted. Any unavailable network or provider
    /// result is recorded as analysis context; it never removes the drive.
    func beginAnalysis(for drive: RecordedDrive) {
        guard tasks[drive.id] == nil,
              let currentAnalysis = drive.routeAnalysis else {
            return
        }
        guard currentAnalysis.shouldRetry() else {
            // No task is in flight and no retry is left, so a drive still
            // marked `.pending` here — killed mid-request, or out of retries —
            // has nothing that can ever complete it. Resolve it rather than
            // leaving the UI spinning "Analyzing route" indefinitely.
            if currentAnalysis.isStalled() {
                onDriveUpdated?(
                    drive.id,
                    .unavailable(
                        "Route difficulty could not be analyzed for this drive. The drive and its coaching score are still saved."
                    )
                )
            }
            return
        }
        guard let endpoints = DriveRouteAnalysisEngine.endpoints(for: drive) else {
            onDriveUpdated?(
                drive.id,
                .unavailable("Route difficulty needs a longer continuous GPS trace from start to destination.")
            )
            return
        }

        // Route analysis proxies a metered upstream API, so the backend only
        // serves signed-in accounts. Signing in later should analyze this
        // drive, so the attempt stays retry-eligible rather than being spent.
        guard authSession.isSignedIn else {
            debugInfo[drive.id] = RouteAnalysisDebugInfo(
                endpointPath: "api/route/difficulty",
                attemptedAt: Date(),
                durationSeconds: 0,
                retryCount: currentAnalysis.retryCount ?? 0,
                outcome: .other("Not attempted: no signed-in account")
            )
            onDriveUpdated?(
                drive.id,
                .unavailable(
                    "Sign in to analyze this route's difficulty. The drive and its coaching score are still saved.",
                    retryEligible: true,
                    lastAttemptAt: currentAnalysis.lastAttemptAt,
                    retryCount: currentAnalysis.retryCount ?? 0
                )
            )
            return
        }

        let attemptedAnalysis = currentAnalysis.recordingAttempt()
        onDriveUpdated?(drive.id, attemptedAnalysis)

        let attemptStartedAt = Date()
        let task = Task { [weak self] in
            defer { self?.tasks[drive.id] = nil }
            guard let self else { return }

            do {
                let response = try await self.authSession.performAuthenticated { token in
                    try await APIClient().analyzeRoute(
                        origin: endpoints.origin,
                        destination: endpoints.destination,
                        accessToken: token,
                        includeAlternates: false,
                        continuousDriveMinutes: drive.score.duration / 60
                    )
                }
                guard !Task.isCancelled else { return }
                self.debugInfo[drive.id] = RouteAnalysisDebugInfo(
                    endpointPath: "api/route/difficulty",
                    attemptedAt: attemptStartedAt,
                    durationSeconds: Date().timeIntervalSince(attemptStartedAt),
                    retryCount: attemptedAnalysis.retryCount ?? 1,
                    outcome: .success
                )
                self.onDriveUpdated?(
                    drive.id,
                    DriveRouteAnalysisEngine.result(from: response.primaryRoute)
                )
            } catch {
                guard !Task.isCancelled else { return }
                self.debugInfo[drive.id] = RouteAnalysisDebugInfo(
                    endpointPath: "api/route/difficulty",
                    attemptedAt: attemptStartedAt,
                    durationSeconds: Date().timeIntervalSince(attemptStartedAt),
                    retryCount: attemptedAnalysis.retryCount ?? 1,
                    outcome: RouteAnalysisDebugInfo.outcome(for: error)
                )
                self.onDriveUpdated?(
                    drive.id,
                    .unavailable(
                        "Route difficulty could not be analyzed right now. The drive and its coaching score are still saved.",
                        retryEligible: true,
                        lastAttemptAt: attemptedAnalysis.lastAttemptAt,
                        retryCount: attemptedAnalysis.retryCount ?? 1
                    )
                )
            }
        }
        tasks[drive.id] = task
    }
}
