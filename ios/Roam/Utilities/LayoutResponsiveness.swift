import CoreGraphics

/// Shared width thresholds for layouts that otherwise contain fixed-size,
/// horizontal controls. Keeping the decisions here makes compact-phone and
/// large-text behavior deterministic and straightforward to regression-test.
enum LayoutResponsiveness {
    private static let compactTabBarThreshold: CGFloat = 300
    private static let stackedControlThreshold: CGFloat = 320
    private static let maximumLoadingSceneWidth: CGFloat = 320

    static func usesCompactTabBar(availableWidth: CGFloat, usesLargeText: Bool) -> Bool {
        usesLargeText || availableWidth < compactTabBarThreshold
    }

    static func stacksInlineControls(availableWidth: CGFloat, usesLargeText: Bool) -> Bool {
        usesLargeText || availableWidth < stackedControlThreshold
    }

    static func usesCompactRoutePlanningTitle(usesLargeText: Bool) -> Bool {
        usesLargeText
    }

    static func loadingSceneWidth(availableWidth: CGFloat, horizontalPadding: CGFloat) -> CGFloat {
        min(maximumLoadingSceneWidth, max(0, availableWidth - (horizontalPadding * 2)))
    }
}
