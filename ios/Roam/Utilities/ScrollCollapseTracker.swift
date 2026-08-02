import SwiftUI

/// Coordinate space shared by every tab's primary `ScrollView` so scroll
/// position can be reported to `ScrollCollapseTracker` without each screen
/// hard-coding its own string literal.
enum RoamScrollSpace {
    static let name = "roamPrimaryScroll"
}

/// Tracks vertical movement of the active tab's scroll content and exposes a
/// single "should collapse" flag for the floating liquid tab bar. Small,
/// noisy deltas (a shaky drag, momentum settling) are ignored so the bar
/// doesn't flicker between its expanded and collapsed states.
final class ScrollCollapseTracker: ObservableObject {
    @Published private(set) var isCollapsed = false

    private var lastOffset: CGFloat?
    /// Signed travel in the current direction. Reset whenever the finger
    /// reverses, so only sustained movement counts toward a state change.
    private var travelInDirection: CGFloat = 0

    /// Ignores sub-pixel layout jitter without swallowing real drags.
    private let noiseFloor: CGFloat = 1.0
    /// Sustained downward travel before the bar collapses.
    private let collapseThreshold: CGFloat = 36
    /// Upward travel before it returns. Smaller than `collapseThreshold` so
    /// reaching for navigation feels immediate while idle jitter does not
    /// bounce the bar open.
    private let expandThreshold: CGFloat = 18
    /// Content within this distance of the top always shows the full bar.
    /// Without it, rubber-band overscroll at rest reads as a downward drag
    /// and collapses the bar while the user is sitting still at the top.
    private let topRestZone: CGFloat = 24

    /// Reports the scroll content's top edge relative to its `ScrollView`:
    /// `0` at rest, increasingly negative as the user scrolls down.
    func update(offset: CGFloat) {
        defer { lastOffset = offset }

        // Near the top there is nothing worth hiding chrome for, and bounce
        // here is the single biggest source of spurious toggles.
        if offset > -topRestZone {
            travelInDirection = 0
            setCollapsed(false)
            return
        }

        guard let lastOffset else { return }
        let delta = offset - lastOffset
        guard abs(delta) > noiseFloor else { return }

        // A direction change restarts the count, so momentum settling cannot
        // accumulate its way past a threshold.
        if (delta < 0) != (travelInDirection < 0) {
            travelInDirection = 0
        }
        travelInDirection += delta

        if travelInDirection <= -collapseThreshold {
            setCollapsed(true)
            travelInDirection = 0
        } else if travelInDirection >= expandThreshold {
            setCollapsed(false)
            travelInDirection = 0
        }
    }

    /// Restores the full bar immediately, e.g. after switching tabs or
    /// tapping the collapsed glass indicator.
    func expand() {
        lastOffset = nil
        travelInDirection = 0
        setCollapsed(false)
    }

    /// Clears tracked scroll history without forcing a visible state
    /// change; used when a fresh tab's scroll view is about to report in.
    func reset() {
        expand()
    }

    /// Animating here rather than at each call site guarantees every path into
    /// the state — scrolling, tab switches, the collapsed indicator — morphs
    /// with the same curve instead of some snapping instantly.
    private func setCollapsed(_ value: Bool) {
        guard isCollapsed != value else { return }
        withAnimation(AppAnimation.liquidMorph) {
            isCollapsed = value
        }
    }
}

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ScrollCollapseReader: ViewModifier {
    @ObservedObject var tracker: ScrollCollapseTracker

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: proxy.frame(in: .named(RoamScrollSpace.name)).minY
                        )
                }
            )
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { tracker.update(offset: $0) }
    }
}

extension View {
    /// Reports this view's position within the shared `RoamScrollSpace`
    /// coordinate space to a `ScrollCollapseTracker`. Apply to the first
    /// child inside a tab's primary `ScrollView`, and apply
    /// `.coordinateSpace(name: RoamScrollSpace.name)` to that `ScrollView`.
    func trackingScrollCollapse(_ tracker: ScrollCollapseTracker) -> some View {
        modifier(ScrollCollapseReader(tracker: tracker))
    }
}
