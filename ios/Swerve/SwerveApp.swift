import SwiftUI

@main
struct SwerveApp: App {
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    /// The iOS Simulator can reach a server on the Mac through 127.0.0.1.
    @AppStorage("backendBaseURL") var backendBaseURL = "http://127.0.0.1:3000"
}
