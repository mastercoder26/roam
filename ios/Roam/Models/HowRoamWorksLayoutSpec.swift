import Foundation

/// Shared spacing rules for the explanation sheet. Keeping these values in a
/// testable model prevents its many sections from slowly developing different
/// row and edge spacing as content changes.
enum HowRoamWorksLayoutSpec {
    static let topPadding: Double = 20
    static let bottomPadding: Double = 48
    static let sectionSpacing: Double = 24
    static let titleContentSpacing: Double = 12
    static let rowVerticalPadding: Double = 12
    static let entryRowVerticalPadding: Double = 16
    static let iconSize: Double = 36
    static let iconSpacing: Double = 12
    static let rowTextInset = iconSize + iconSpacing
    static let maximumContentWidth: Double = 640
}
