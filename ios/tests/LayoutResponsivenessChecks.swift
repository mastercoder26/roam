import CoreGraphics
import Foundation

@main
struct LayoutResponsivenessChecks {
    static func main() {
        tabBarUsesItsCompactFormBeforeLabelsCanCollide()
        inlineControlsStackForNarrowOrLargeTextLayouts()
        loadingSceneNeverOutgrowsTheAvailableWidth()

        print("Layout responsiveness checks passed")
    }

    private static func tabBarUsesItsCompactFormBeforeLabelsCanCollide() {
        expect(
            LayoutResponsiveness.usesCompactTabBar(availableWidth: 252, usesLargeText: false),
            "a 320-point iPhone must collapse tab labels before they compete for width"
        )
        expect(
            !LayoutResponsiveness.usesCompactTabBar(availableWidth: 346, usesLargeText: false),
            "a regular-width phone should keep the selected tab label"
        )
        expect(
            LayoutResponsiveness.usesCompactTabBar(availableWidth: 346, usesLargeText: true),
            "large Dynamic Type must not force the tab labels into one horizontal row"
        )
    }

    private static func inlineControlsStackForNarrowOrLargeTextLayouts() {
        expect(
            LayoutResponsiveness.stacksInlineControls(availableWidth: 288, usesLargeText: false),
            "the break-plan selector must stack before its segmented control crowds its title"
        )
        expect(
            !LayoutResponsiveness.stacksInlineControls(availableWidth: 360, usesLargeText: false),
            "a regular-width control row should retain its compact horizontal presentation"
        )
        expect(
            LayoutResponsiveness.stacksInlineControls(availableWidth: 360, usesLargeText: true),
            "large Dynamic Type must use the vertical control arrangement"
        )
    }

    private static func loadingSceneNeverOutgrowsTheAvailableWidth() {
        let sceneWidth = LayoutResponsiveness.loadingSceneWidth(
            availableWidth: 320,
            horizontalPadding: 28
        )
        expect(
            sceneWidth == 264,
            "the loading illustration must account for the surrounding padding on narrow phones"
        )
        expect(
            LayoutResponsiveness.loadingSceneWidth(availableWidth: 430, horizontalPadding: 28) == 320,
            "the loading illustration should preserve its intended maximum size on regular phones"
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError("Layout responsiveness check failed: \(message)")
        }
    }
}
