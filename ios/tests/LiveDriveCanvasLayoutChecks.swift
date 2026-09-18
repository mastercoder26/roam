import CoreGraphics
import Foundation

@main
struct LiveDriveCanvasLayoutChecks {
    static func main() {
        checkTinyViewportKeepsPrimaryAction()
        checkOrderingOfSacrifices()
        checkTypicalPhone()
        checkLargeText()
        print("LiveDriveCanvasLayout checks passed")
    }

    /// The End Drive control's budget is reserved before any module is
    /// granted, so a short canvas sheds readouts rather than the action.
    private static func checkTinyViewportKeepsPrimaryAction() {
        let modules = LiveDriveCanvasLayout.modules(availableHeight: 380, usesLargeText: false)
        expect(!modules.showsScoreRing, "a very short canvas must drop the ring")
        expect(!modules.showsSmoothnessBadge, "a very short canvas must drop the smoothness badge")
        expect(!modules.showsMetricStrip, "a very short canvas must drop the metric strip")
    }

    /// Modules are shed from least to most important, never out of order, and
    /// a canvas that grows never loses one it already had.
    private static func checkOrderingOfSacrifices() {
        var height: CGFloat = 300
        var previous = LiveDriveCanvasLayout.modules(availableHeight: height, usesLargeText: false)
        while height <= 1_400 {
            let modules = LiveDriveCanvasLayout.modules(availableHeight: height, usesLargeText: false)

            if modules.showsMetricStrip {
                expect(modules.showsSmoothnessBadge, "the strip must never outrank the badge at \(height)")
            }
            if modules.showsSmoothnessBadge {
                expect(modules.showsScoreRing, "the badge must never outrank the score ring at \(height)")
            }

            expect(!previous.showsScoreRing || modules.showsScoreRing, "growing the canvas must not drop the ring at \(height)")
            expect(!previous.showsSmoothnessBadge || modules.showsSmoothnessBadge, "growing the canvas must not drop the badge at \(height)")
            expect(!previous.showsMetricStrip || modules.showsMetricStrip, "growing the canvas must not drop the strip at \(height)")

            previous = modules
            height += 10
        }
    }

    /// The canvas a modern phone actually gets — measured at 684pt on an
    /// iPhone 17 — must show the whole live readout.
    private static func checkTypicalPhone() {
        let modules = LiveDriveCanvasLayout.modules(availableHeight: 684, usesLargeText: false)
        expect(modules.showsScoreRing, "a typical phone must show the score ring")
        expect(modules.showsSmoothnessBadge, "a typical phone must show the smoothness badge")
        expect(modules.showsMetricStrip, "a typical phone must show the metric strip")
    }

    private static func checkLargeText() {
        let modules = LiveDriveCanvasLayout.modules(availableHeight: 684, usesLargeText: true)
        expect(modules.showsScoreRing, "large text keeps the score ring")
        expect(!modules.showsSmoothnessBadge, "large text sheds the smoothness badge")
        expect(!modules.showsMetricStrip, "large text sheds the metric strip")

        let short = LiveDriveCanvasLayout.modules(availableHeight: 380, usesLargeText: true)
        expect(!short.showsScoreRing, "large text on a short canvas drops the ring too")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError("LiveDriveCanvasLayout check failed: \(message)")
        }
    }
}
