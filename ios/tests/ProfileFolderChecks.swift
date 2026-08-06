import Foundation

@main
struct ProfileFolderChecks {
    static func main() {
        checkFolderOrderMatchesTheProfileJourney()
        checkEveryFolderHasUsefulVisibleCopy()

        print("ProfileFolder checks passed")
    }

    private static func checkFolderOrderMatchesTheProfileJourney() {
        expect(
            ProfileFolder.allCases == [.progress, .drivingInsights, .preferences],
            "profile folders should lead with progress, then evidence, then personal settings"
        )
    }

    private static func checkEveryFolderHasUsefulVisibleCopy() {
        for folder in ProfileFolder.allCases {
            expect(!folder.title.isEmpty, "every folder needs a visible title")
            expect(!folder.subtitle.isEmpty, "every folder needs a concise explanation")
            expect(!folder.symbol.isEmpty, "every folder needs a recognizable system symbol")
            expect(!folder.summary.isEmpty, "every folder needs an at-a-glance summary")
        }

        expect(ProfileFolder.progress.title == "Goals & progress", "the first folder should describe progress clearly")
        expect(ProfileFolder.drivingInsights.title == "Driving insights", "the evidence folder should use plain language")
        expect(ProfileFolder.preferences.title == "Preferences", "settings should be grouped under a familiar label")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError("ProfileFolder check failed: \(message)")
        }
    }
}
