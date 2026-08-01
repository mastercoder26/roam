import SwiftUI

@main
struct RoamApp: App {
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var driveSession = DriveSessionManager.shared

    var body: some Scene {
        WindowGroup {
            RoamRootView()
                .environmentObject(themeManager)
                .environmentObject(driveSession)
        }
    }
}
