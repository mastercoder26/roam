import SwiftUI
import UIKit

struct SwerveRootView: View {
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
    @Namespace private var tabAnimation
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        .preferredColorScheme(themeManager.preferredColorScheme)
        // This reserves the tab bar's measured height for every tab. Unlike a
        // fixed invisible spacer, it remains correct when Dynamic Type grows
        // the selected tab label and keeps End Drive unobstructed.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            liquidTabBar
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 10)
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
        .accessibilityLabel("Swerve color schemes")
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

    private var liquidTabBar: some View {
        GeometryReader { geometry in
            let showsCompactTabs = LayoutResponsiveness.usesCompactTabBar(
                availableWidth: geometry.size.width,
                usesLargeText: usesLargeText
            )

            tabBarContent(showsCompactTabs: showsCompactTabs)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 60)
    }

    private func tabBarContent(showsCompactTabs: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases) { tab in
                Button {
                    guard selectedTab != tab else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    selectedTab = tab
                } label: {
                    HStack(spacing: showsCompactTabs ? 0 : 7) {
                        Image(systemName: tab.symbol)
                            .font(.body.weight(.semibold))
                        if selectedTab == tab, !showsCompactTabs {
                            Text(tab.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .transition(.opacity)
                        }
                    }
                    .foregroundStyle(selectedTab == tab ? AppDesign.accent : Color.secondary)
                    .frame(minWidth: showsCompactTabs ? 44 : nil)
                    .padding(.horizontal, showsCompactTabs ? 10 : (selectedTab == tab ? 16 : 14))
                    .padding(.vertical, 12)
                    .background {
                        if selectedTab == tab {
                            if reduceMotion {
                                selectedCapsule
                            } else {
                                selectedCapsule
                                    .matchedGeometryEffect(id: "liquid-selection", in: tabAnimation)
                            }
                        }
                    }
                }
                .buttonStyle(PressableScaleStyle())
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(6)
        .background {
            Capsule(style: .continuous)
                .fill(
                    reduceTransparency
                        ? AnyShapeStyle(Color(.systemBackground))
                        : AnyShapeStyle(.ultraThinMaterial)
                )
        }
        .overlay(
            Capsule(style: .continuous)
                .stroke(AppDesign.cardStrokeStrong.opacity(themeManager.palette.appearance == .light ? 1 : 0.9), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        .accessibilityElement(children: .contain)
    }

    private var selectedCapsule: some View {
        Capsule(style: .continuous)
            .fill(AppDesign.accent.opacity(0.12))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(AppDesign.accent.opacity(0.12), lineWidth: 0.8)
            )
    }
}

#Preview {
    SwerveRootView()
        .environmentObject(ThemeManager.shared)
        .environmentObject(DriveSessionManager.shared)
}
