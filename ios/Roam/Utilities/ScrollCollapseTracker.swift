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
    private let directionNoiseFloor: CGFloat = 0.35

    /// Reports the scroll content's top edge relative to its `ScrollView`:
    /// `0` at rest, increasingly negative as the user scrolls down.
    func update(offset: CGFloat) {
        defer { lastOffset = offset }
        guard let lastOffset else { return }

        let delta = offset - lastOffset
        // Collapse on the first real downward movement and expand on the first
        // real upward movement. The tiny floor filters only layout jitter; this
        // interaction intentionally has no distance or top-position threshold.
        if delta < -directionNoiseFloor {
            setCollapsed(true)
        } else if delta > directionNoiseFloor {
            setCollapsed(false)
        }
    }

    /// Restores the full bar immediately, e.g. after switching tabs or
    /// tapping the collapsed glass indicator.
    func expand() {
        lastOffset = nil
        setCollapsed(false)
    }

    /// Clears tracked scroll history without forcing a visible state
    /// change; used when a fresh tab's scroll view is about to report in.
    func reset() {
        expand()
    }



    private func setCollapsed(_ value: Bool) {
        guard isCollapsed != value else { return }
        isCollapsed = value
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
