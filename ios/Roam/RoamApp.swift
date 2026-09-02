import SwiftUI
import ClerkKit

@main
struct RoamApp: App {
    private actor BootstrapWaitState {
        private var didResolve = false

        func resolve(
            _ continuation: CheckedContinuation<Bool, Never>,
            with result: Bool
        ) {
            guard !didResolve else { return }
            didResolve = true
            continuation.resume(returning: result)
        }
    }

    @StateObject private var themeManager = ThemeManager.shared
    // Services are deliberately obtained after the first launch surface has
    // appeared. DriveSessionManager's initializer restores local history and
    // starts recovery work, so constructing it as an App property would make
    // the intro wait behind the very work it is meant to cover.
    @State private var driveSession: DriveSessionManager?
    @State private var authSession: AuthSessionStore?
    @Environment(\.scenePhase) private var scenePhase

    @State private var isIntroPlaying = true
    /// Once the first launch gate releases, keep the root mounted forever so
    /// a later intro replay cannot discard tab/navigation/workflow state.
    @State private var hasMountedRoot = false
    @State private var didStartLaunchBootstrap = false
    @State private var hasBootstrapTerminalState = false
    @State private var launchGate: LaunchReadinessGate
    @State private var visualGeneration: LaunchReadinessGate.VisualGeneration
    @State private var leftForegroundAt: Date?
    /// The header frame is normally supplied by the root after handoff. The
    /// intro therefore starts with `.zero`, which makes its choreography use
    /// the authored inset until real preference data exists.
    @State private var headerWordmarkFrame: CGRect = .zero

    init() {
        Clerk.configure(publishableKey: "pk_test_Y2FwYWJsZS1zd2FuLTM1LmNsZXJrLmFjY291bnRzLmRldiQ")

        let gate = LaunchReadinessGate()
        _launchGate = State(initialValue: gate)
        _visualGeneration = State(initialValue: gate.beginVisualGeneration())
    }

    var body: some Scene {
        WindowGroup {
            let presentation = LaunchPresentationState.resolve(
                hasMountedRoot: hasMountedRoot,
                servicesAvailable: driveSession != nil && authSession != nil,
                isIntroPlaying: isIntroPlaying
            )

            ZStack {
                if presentation.shouldMountRoot,
                   let driveSession,
                   let authSession {
                    RoamRootView()
                        .environmentObject(themeManager)
                        .environmentObject(driveSession)
                        .environmentObject(authSession)
                        .environment(Clerk.shared)
                        .opacity(presentation.rootIsVisuallyHidden ? 0 : 1)
                        .allowsHitTesting(presentation.rootAllowsInteraction)
                        .accessibilityHidden(presentation.rootIsAccessibilityHidden)
                        .transition(.opacity)
                }

                if presentation.showsIntro {
                    LaunchIntroView(
                        onVisualComplete: { finishIntro(for: visualGeneration) },
                        dockTargetFrame: headerWordmarkFrame,
                        isWaitingForBootstrap: !hasBootstrapTerminalState
                    )
                    .environmentObject(themeManager)
                    // The opaque generation token is Hashable, so it can
                    // restart the intro without reaching into gate internals.
                    .id(visualGeneration)
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .coordinateSpace(name: LaunchIntroDockSpace.name)
            .onPreferenceChange(HeaderWordmarkFrameKey.self) { headerWordmarkFrame = $0 }
            .preferredColorScheme(themeManager.preferredColorScheme)
            .onOpenURL(perform: handleIncomingURL)
            .task {
                await prepareLaunch()
            }
            .onChange(of: scenePhase) { _, phase in
                handleScenePhase(phase)
            }
        }
    }

    @MainActor
    private func prepareLaunch() async {
        guard !didStartLaunchBootstrap else { return }
        didStartLaunchBootstrap = true
        let generation = visualGeneration

        // Let SwiftUI commit the loading surface before service singletons are
        // touched. This is important on a cold launch where drive recovery can
        // otherwise delay the first frame.
        await Task.yield()

        let authSession = AuthSessionStore.shared
        let driveSession = DriveSessionManager.shared
        self.driveSession = driveSession
        self.authSession = authSession

        authSession.configureDriveHistorySync {
            DriveHistorySyncService.shared.sync(
                localDrives: driveSession.recordedDrives,
                applyLocalDrives: { drives in
                    driveSession.applySyncedRecordedDrives(drives)
                }
            )
        }

        // Keep both operations alive independently. The bounded waiter below
        // may finish with a degraded result, but it must never cancel an auth
        // restore that can still make the signed-in session usable later.
        let driveBootstrap = Task { @MainActor in
            await driveSession.bootstrap()
        }
        let authRestore = Task { @MainActor in
            await authSession.restoreIfNeeded()
            // AuthSessionStore may have started its one-shot restore from its
            // singleton initializer. In that case restoreIfNeeded() returns
            // immediately; wait for that in-flight operation to publish its
            // terminal state without extending the launch surface forever.
            await waitForAuthTerminalState(authSession)
        }

        let completed = await waitForBootstrap(
            driveBootstrap: driveBootstrap,
            authRestore: authRestore
        )
        let terminalState: LaunchReadinessGate.BootstrapTerminalState
        if completed {
            terminalState = bootstrapTerminalState(for: authSession)
        } else {
            terminalState = .timedOut
        }
        markBootstrapTerminal(terminalState, for: generation)
    }

    @MainActor
    private func waitForAuthTerminalState(_ authSession: AuthSessionStore) async {
        for _ in 0..<100 {
            switch authSession.state {
            case .restoring, .authenticating:
                do {
                    try await Task.sleep(nanoseconds: 50_000_000)
                } catch {
                    return
                }
            case .signedOut, .signedIn, .signedInOffline:
                return
            }
        }
    }

    @MainActor
    private func waitForBootstrap(
        driveBootstrap: Task<Void, Never>,
        authRestore: Task<Void, Never>
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let waitState = BootstrapWaitState()

            Task { @MainActor in
                _ = await driveBootstrap.value
                _ = await authRestore.value
                await waitState.resolve(continuation, with: true)
            }

            Task { @MainActor in
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    // The service waiter is intentionally independent. If
                    // this task is cancelled, it must not cancel auth restore.
                }
                await waitState.resolve(continuation, with: false)
            }
        }
    }

    @MainActor
    private func bootstrapTerminalState(
        for authSession: AuthSessionStore
    ) -> LaunchReadinessGate.BootstrapTerminalState {
        switch authSession.state {
        case .signedOut:
            return .signedOut
        case .signedIn:
            return .ready
        case .signedInOffline:
            return .offline
        case .restoring, .authenticating:
            return .recoverableFailure
        }
    }

    private func finishIntro(for generation: LaunchReadinessGate.VisualGeneration) {
        guard launchGate.markVisualComplete(for: generation) else { return }
        hasMountedRoot = true
        withAnimation(.easeOut(duration: LaunchIntroChoreography.exitDuration)) {
            isIntroPlaying = false
        }
    }

    private func markBootstrapTerminal(
        _ state: LaunchReadinessGate.BootstrapTerminalState,
        for generation: LaunchReadinessGate.VisualGeneration
    ) {
        guard launchGate.markBootstrapTerminal(state, for: generation) else {
            // `markBootstrapTerminal` also returns false while waiting for the
            // visual. The state flag still needs to update so VoiceOver can
            // describe the now-terminal loading surface.
            if launchGate.currentGeneration == generation, launchGate.bootstrapState != nil {
                hasBootstrapTerminalState = true
            }
            return
        }
        hasBootstrapTerminalState = true
        hasMountedRoot = true
        withAnimation(.easeOut(duration: LaunchIntroChoreography.exitDuration)) {
            isIntroPlaying = false
        }
    }

    /// Clerk callbacks can arrive while the root is not mounted (including a
    /// cold-launch or replay intro). Keep this handler at the scene boundary;
    /// once the root exists, its Clerk observation remains responsible for
    /// normal session changes and avoids a duplicate reconciliation request.
    @MainActor
    private func handleIncomingURL(_ url: URL) {
        Task { @MainActor in
            _ = try? await Clerk.shared.handle(url)
            guard !hasMountedRoot, let authSession else { return }
            await authSession.synchronizeWithClerk()
        }
    }

    /// iOS rarely terminates an app, so "every time it is opened" has to mean
    /// returning after a real absence rather than every task-switcher glance —
    /// and never in the middle of a recorded drive.
    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background, .inactive:
            guard !isIntroPlaying, leftForegroundAt == nil else { return }
            leftForegroundAt = Date()

        case .active:
            authSession?.requestDriveHistorySync()
            authSession?.requestProfileSync()
            driveSession?.resumeRouteAnalysesIfNeeded()
            guard let leftAt = leftForegroundAt else { return }
            leftForegroundAt = nil
            guard LaunchIntroChoreography.shouldReplay(
                awayFor: Date().timeIntervalSince(leftAt),
                isRecording: driveSession?.isRecording ?? false
            ) else { return }
            visualGeneration = launchGate.beginVisualGeneration()
            isIntroPlaying = true

        @unknown default:
            break
        }
    }
}
