import CoreGraphics

/// Which live-coaching modules the recording canvas can afford to show.
///
/// The recording canvas is deliberately height-clamped to the viewport — the
/// End Drive control must stay reachable and must never slide under the tab
/// bar — so the live readout has a fixed budget rather than a scroll. This
/// decides what fits instead of letting the stack overflow and clip.
///
/// Kept pure and CoreGraphics-only so the decision can be checked from the
/// command line alongside the scoring engines.
enum LiveDriveCanvasLayout {
    /// Cost of each module at default text size, including the 16pt spacing
    /// above it. These are the authored heights of the views in
    /// `LiveDriveScoreViews` and `FlipClock.Style.active`, not guesses.
    private static let clockCost: CGFloat = 112
    private static let ringCost: CGFloat = 212
    private static let vitalsRowCost: CGFloat = 62
    private static let smoothnessCost: CGFloat = 50
    private static let metricStripCost: CGFloat = 82
    /// Top clearance, the End Drive control, and its inset above the tab bar.
    private static let chromeCost: CGFloat = 164

    /// The floor every recording canvas shows: the clock, the score ring, and
    /// the speed/streak row. Below this the canvas drops the ring rather than
    /// clipping the primary action.
    static let essentialCost: CGFloat = chromeCost + clockCost + vitalsRowCost

    struct Modules: Equatable {
        let showsScoreRing: Bool
        let showsSmoothnessBadge: Bool
        let showsMetricStrip: Bool
    }

    /// - Parameters:
    ///   - availableHeight: the recording canvas's clamped height.
    ///   - usesLargeText: accessibility text sizes inflate every module, so
    ///     they drop the optional ones a tier earlier rather than overlapping.
    static func modules(availableHeight: CGFloat, usesLargeText: Bool) -> Modules {
        // Large text keeps the ring — it is the feature — and sheds the
        // secondary readouts, which are the ones that grow worst.
        guard !usesLargeText else {
            return Modules(
                showsScoreRing: availableHeight >= essentialCost + ringCost,
                showsSmoothnessBadge: false,
                showsMetricStrip: false
            )
        }

        // Strictly ranked, not greedy: a module is only granted once every
        // more important one already fits. Otherwise a canvas too short for
        // the ring would still find room for the badge, and the readout would
        // appear in a different order on a small phone than on a large one.
        var remaining = availableHeight - essentialCost

        guard remaining >= ringCost else {
            return Modules(showsScoreRing: false, showsSmoothnessBadge: false, showsMetricStrip: false)
        }
        remaining -= ringCost

        guard remaining >= smoothnessCost else {
            return Modules(showsScoreRing: true, showsSmoothnessBadge: false, showsMetricStrip: false)
        }
        remaining -= smoothnessCost

        return Modules(
            showsScoreRing: true,
            showsSmoothnessBadge: true,
            showsMetricStrip: remaining >= metricStripCost
        )
    }
}
