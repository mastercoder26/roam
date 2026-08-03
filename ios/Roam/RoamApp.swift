import SwiftUI

@main
struct RoamApp: App {
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var driveSession = DriveSessionManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isIntroPlaying = true
    @State private var leftForegroundAt: Date?

    var body: some Scene {
        WindowGroup {
            ZStack {
                RoamRootView()
                    .environmentObject(themeManager)
                    .environmentObject(driveSession)
                    // The app sits very slightly forward behind the intro, so
                    // the handoff settles into place instead of cutting.
                    .scaleEffect(isIntroPlaying && !reduceMotion ? 1.03 : 1)
                    .opacity(isIntroPlaying ? 0 : 1)
                    .allowsHitTesting(!isIntroPlaying)

                if isIntroPlaying {
                    LaunchIntroView(onFinish: finishIntro)
                        .environmentObject(themeManager)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .preferredColorScheme(themeManager.preferredColorScheme)
            .onChange(of: scenePhase) { _, phase in
                handleScenePhase(phase)
            }
        }
    }

    private func finishIntro() {
        withAnimation(.easeOut(duration: LaunchIntroChoreography.exitDuration)) {
            isIntroPlaying = false
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
            guard let leftAt = leftForegroundAt else { return }
            leftForegroundAt = nil
            guard LaunchIntroChoreography.shouldReplay(
                awayFor: Date().timeIntervalSince(leftAt),
                isRecording: driveSession.isRecording
            ) else { return }
            isIntroPlaying = true

        @unknown default:
            break
        }
    }
}
