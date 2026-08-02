import SwiftUI
import UIKit

struct RoamRootView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case routes
        case drive
        case progress

        var id: String { rawValue }
        var title: String {
            switch self {
            case .routes: "Routes"
            case .drive: "Drive"
            case .progress: "Progress"
            }
        }

        var symbol: String {
            switch self {
            case .routes: "map.fill"
            case .drive: "steeringwheel"
            case .progress: "chart.line.uptrend.xyaxis"
            }
        }
    }

    @State private var selectedTab: Tab = .routes
    @State private var showingThemePicker = false
    @EnvironmentObject private var driveSession: DriveSessionManager
    @EnvironmentObject private var themeManager: ThemeManager
    @StateObject private var routeForm = RoutePlanningFormModel()
    @StateObject private var sharedRouteImport = SharedRouteImportCoordinator()
    @StateObject private var scrollCollapse = ScrollCollapseTracker()
    @Namespace private var tabAnimation
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum LiquidTabBarMetrics {
        static let expandedHeight: CGFloat = 76
        static let collapsedDiameter: CGFloat = 60
    }

    private var shouldCollapseTabBar: Bool {
        // Reduced Motion changes how this state transition is animated; it
        // must not disable the navigation behavior itself.
        scrollCollapse.isCollapsed
    }

    private var tabBarFootprintHeight: CGFloat {
        shouldCollapseTabBar
            ? LiquidTabBarMetrics.collapsedDiameter
            : LiquidTabBarMetrics.expandedHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            topBrandBar

            Group {
                switch selectedTab {
                case .routes: HomeView(form: routeForm)
                case .drive: DriveView()
                case .progress: DriverProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environmentObject(driveSession)
        .environmentObject(themeManager)
        .environmentObject(scrollCollapse)
        .preferredColorScheme(themeManager.preferredColorScheme)
        // The inset follows the glass surface as it changes size, so a
        // collapsed circle both looks and behaves like a smaller control.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            liquidTabBar
                .frame(height: tabBarFootprintHeight, alignment: .bottomTrailing)
                .padding(.horizontal, shouldCollapseTabBar ? 20 : 24)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .animation(
                    reduceMotion ? .easeOut(duration: 0.16) : AppAnimation.liquidMorph,
                    value: shouldCollapseTabBar
                )
        }
        .sheet(isPresented: $showingThemePicker) {
            ThemePickerSheet(themeManager: themeManager)
                .environmentObject(driveSession)
        }
        .transition(.opacity)
        .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.18), value: selectedTab)
        .animation(reduceMotion ? .easeOut(duration: 0.16) : AppAnimation.content, value: themeManager.currentID)
        .onChange(of: driveSession.practiceRoutePresentationRequest) { _, request in
            // The manager emits this only when a Results-screen action queues a
            // route for practice. Keeping the request separate from the route
            // itself avoids coupling tab presentation to transient view state.
            guard request != nil, selectedTab != .drive else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedTab = .drive
        }
        .onAppear {
            refreshSharedRouteIfSafe()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshSharedRouteIfSafe()
        }
        .onChange(of: driveSession.isRecording) { _, isRecording in
            guard !isRecording else { return }
            refreshSharedRouteIfSafe()
        }
        .onChange(of: sharedRouteImport.state) { _, state in
            applySharedRouteStateIfSafe(state)
        }
        .onChange(of: selectedTab) { _, _ in
            scrollCollapse.reset()
        }
    }

    /// A compact, ordinary layout element rather than an overlay. That makes
    /// its occupied height explicit to every tab and prevents the active
    /// screen's title from disappearing behind a safe-area inset.
    private var topBrandBar: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showingThemePicker = true
        } label: {
            HStack(spacing: 10) {
                BrandWordmark(compact: true)
                Spacer(minLength: 8)
                Image(systemName: "paintpalette.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppDesign.Ink.secondary)
                    .frame(width: 36, height: 36)
                    .background(AppDesign.cardSurface, in: Circle())
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(PressableScaleStyle())
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(themeManager.palette.canvas.color)
        .accessibilityLabel("Roam color schemes")
        .accessibilityHint("Opens color scheme options without changing this screen")
    }

    private func refreshSharedRouteIfSafe() {
        // A route import must never pull someone out of a manually started
        // drive. The inbox remains local and will be read after the drive ends.
        guard !driveSession.isRecording else { return }
        Task {
            await sharedRouteImport.refresh()
        }
    }

    private func applySharedRouteStateIfSafe(_ state: SharedRouteImportCoordinator.State) {
        guard !driveSession.isRecording else { return }

        switch state {
        case let .ready(route):
            routeForm.apply(route)
            sharedRouteImport.acknowledgeReadyRoute(id: route.id)
            selectedTab = .routes

        case let .failed(message):
            routeForm.presentImportError(message)
            sharedRouteImport.dismissFailure()
            selectedTab = .routes

        case .idle, .resolvingGoogleMapsLink:
            break
        }
    }

    private var usesLargeText: Bool {
        dynamicTypeSize.isAccessibilitySize || dynamicTypeSize >= .xxLarge
    }

    /// One continuous material surface: a full labelled navigation bar at rest
    /// that reshapes into the active tab's circular icon while the content is
    /// moving away. Keeping both states in the same hierarchy prevents the
    /// abrupt swap that made the previous version feel disconnected.
    private var liquidTabBar: some View {
        GeometryReader { geometry in
            let isCollapsed = shouldCollapseTabBar
            let barHeight = isCollapsed
                ? LiquidTabBarMetrics.collapsedDiameter
                : LiquidTabBarMetrics.expandedHeight
            let barWidth = isCollapsed
                ? LiquidTabBarMetrics.collapsedDiameter
                : geometry.size.width
            let cornerRadius = barHeight / 2
            let showsCompactTabs = LayoutResponsiveness.usesCompactTabBar(
                availableWidth: geometry.size.width,
                usesLargeText: usesLargeText
            )
            let glassShape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

            ZStack {
                tabBarSurface(shape: glassShape)

                tabBarButtons(showsCompactTabs: showsCompactTabs)
                    .opacity(isCollapsed ? 0 : 1)
                    .scaleEffect(isCollapsed ? 0.94 : 1)
                    .allowsHitTesting(!isCollapsed)

                collapsedTabIndicator
                    .opacity(isCollapsed ? 1 : 0)
                    .scaleEffect(isCollapsed ? 1 : 0.72)
                    .allowsHitTesting(isCollapsed)
            }
            .frame(width: barWidth, height: barHeight)
            .clipShape(glassShape)
            .elevation(isCollapsed ? AppDesign.Elevation.medium : AppDesign.Elevation.high)
            // The collapsed puck settles into the thumb's natural corner
            // rather than the far side of the screen.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .animation(
                reduceMotion ? .easeOut(duration: 0.16) : AppAnimation.liquidMorph,
                value: isCollapsed
            )
        }
    }

    /// The bar's material. iOS 26 renders genuine Liquid Glass, which already
    /// carries its own lensing and lit edge, so the hand-drawn highlight is
    /// applied only on the older material path that has to fake it.
    @ViewBuilder
    private func tabBarSurface(shape: RoundedRectangle) -> some View {
        if reduceTransparency {
            shape
                .fill(AppDesign.cardSurfaceElevated)
                .overlay { shape.stroke(AppDesign.cardStrokeStrong, lineWidth: 1) }
        } else if #available(iOS 26.0, *) {
            shape
                .fill(.clear)
                .glassEffect(.regular, in: shape)
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay { shape.stroke(AppDesign.glassHighlight, lineWidth: 1) }
                .overlay { shape.stroke(AppDesign.cardStrokeStrong.opacity(0.72), lineWidth: 0.8) }
        }
    }

    private func tabBarButtons(showsCompactTabs: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                Button {
                    guard selectedTab != tab else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    selectedTab = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: showsCompactTabs ? 18 : 20, weight: .semibold))
                            .frame(height: 24)
                        Text(tab.title)
                            .font(.system(size: showsCompactTabs ? 10 : 11, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .foregroundStyle(selectedTab == tab ? AppDesign.accent : AppDesign.Ink.secondary)
                    // Apple tab bars make the entire equal-width segment the
                    // target, not only the visible symbol and label.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .background {
                        if selectedTab == tab {
                            if reduceMotion {
                                selectedPill
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 5)
                            } else {
                                selectedPill
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 5)
                                    .matchedGeometryEffect(id: "liquid-selection", in: tabAnimation)
                            }
                        }
                    }
                }
                .buttonStyle(PressableScaleStyle())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The collapsed state's only content: the current tab's icon, centered
    /// in the shrunken glass circle. Tapping it re-expands the full bar
    /// immediately, so scrolling down never strands someone without labels.
    private var collapsedTabIndicator: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(reduceMotion ? .easeOut(duration: 0.16) : AppAnimation.liquidMorph) {
                scrollCollapse.expand()
            }
        } label: {
            Image(systemName: selectedTab.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppDesign.accent)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: LiquidTabBarMetrics.collapsedDiameter, height: LiquidTabBarMetrics.collapsedDiameter)
        }
        .buttonStyle(PressableScaleStyle())
        .accessibilityLabel("\(selectedTab.title), tab bar collapsed")
        .accessibilityHint("Double tap to expand the navigation bar")
    }

    private var selectedPill: some View {
        let radius = LiquidTabBarMetrics.expandedHeight / 2
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        return shape
            .fill(AppDesign.accent.opacity(0.14))
            .overlay {
                shape.stroke(AppDesign.glassHighlight.opacity(0.72), lineWidth: 0.8)
            }
    }
}

#Preview {
    RoamRootView()
        .environmentObject(ThemeManager.shared)
        .environmentObject(DriveSessionManager.shared)
}
