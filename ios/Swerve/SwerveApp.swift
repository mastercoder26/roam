import SwiftUI

@main
struct SwerveApp: App {
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var driveSession = DriveSessionManager.shared

    var body: some Scene {
        WindowGroup {
            SwerveRootView()
                .environmentObject(themeManager)
                .environmentObject(driveSession)
        }
    }
}
