import SwiftUI

/// Tracks vertical movement of the active tab's scroll content and exposes a
/// single "should collapse" flag for the floating liquid tab bar.
///
/// Collapsing is deliberately eager: a small downward movement hides the bar,
/// because the bar's whole purpose when reading is to get out of the way. The
/// guards below exist only to stop the two things that make an eager rule feel
/// broken — rubber-band bounce at the top, and momentum settling at the end of
/// a fling.
final class ScrollCollapseTracker: ObservableObject {
    @Published private(set) var isCollapsed = false

    private var lastOffset: CGFloat?
    /// Signed travel since the last direction change, so only movement that
    /// keeps going the same way counts toward a state change.
    private var travelInDirection: CGFloat = 0

    /// Ignores sub-pixel layout jitter without swallowing a real drag.
    private let noiseFloor: CGFloat = 0.5
    /// Downward travel before the bar hides. Small on purpose.
    private let collapseThreshold: CGFloat = 10
    /// Upward travel before it returns — smaller still, so reaching for
    /// navigation always feels immediate.
    private let expandThreshold: CGFloat = 8
    /// Content within this distance of the top always shows the full bar.
    /// Overscroll bounce here otherwise reads as a downward drag and hides
    /// the bar while the user is sitting still at the top of the list.
    private let topRestZone: CGFloat = 12

    /// Distance the content has been scrolled down from the top: `0` at rest,
    /// growing positive as the user moves down the page.
    func update(scrollDistance: CGFloat) {
        defer { lastOffset = scrollDistance }

        if scrollDistance < topRestZone {
            travelInDirection = 0
            setCollapsed(false)
            return
        }

        guard let lastOffset else { return }
        let delta = scrollDistance - lastOffset
        guard abs(delta) > noiseFloor else { return }

        // A direction change restarts the count, so deceleration wobble cannot
        // accumulate its way past a threshold and flicker the bar.
        if (delta > 0) != (travelInDirection > 0) {
            travelInDirection = 0
        }
        travelInDirection += delta

        if travelInDirection >= collapseThreshold {
            setCollapsed(true)
            travelInDirection = 0
        } else if travelInDirection <= -expandThreshold {
            setCollapsed(false)
            travelInDirection = 0
        }
    }

    /// Restores the full bar immediately — after a tab switch, or when the
    /// collapsed puck is tapped.
    func expand() {
        lastOffset = nil
        travelInDirection = 0
        setCollapsed(false)
    }

    /// Clears tracked scroll history without forcing a visible state change;
    /// used when a fresh tab's scroll view is about to report in.
    func reset() {
        expand()
    }

    /// Animating here rather than at each call site guarantees every path into
    /// the state — scrolling, tab switches, tapping the puck — morphs with the
    /// same curve instead of some snapping instantly.
    private func setCollapsed(_ value: Bool) {
        guard isCollapsed != value else { return }
        withAnimation(AppAnimation.liquidMorph) {
            isCollapsed = value
        }
    }
}

extension View {
    /// Reports scrolling to a `ScrollCollapseTracker`. Apply directly to a
    /// tab's primary `ScrollView`.
    ///
    /// This reads the scroll view's real content offset rather than measuring a
    /// child's frame through a `GeometryReader` preference. The measurement
    /// approach this replaced only published while SwiftUI happened to re-run
    /// layout on the observed child, so it missed most of a fling and reported
    /// nothing at all during momentum — which is why the bar appeared never to
    /// collapse.
    func trackingScrollCollapse(_ tracker: ScrollCollapseTracker) -> some View {
        onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, distance in
            tracker.update(scrollDistance: distance)
        }
    }
}
