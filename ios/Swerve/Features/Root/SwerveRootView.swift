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
    @StateObject private var driveSession = DriveSessionManager.shared
    @Namespace private var tabAnimation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            switch selectedTab {
            case .routes: HomeView()
            case .drive: DriveView()
            case .progress: DriverProgressView()
            }
        }
        .environmentObject(driveSession)
        // This reserves the tab bar's measured height for every tab. Unlike a
        // fixed invisible spacer, it remains correct when Dynamic Type grows
        // the selected tab label and keeps End Drive unobstructed.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            liquidTabBar
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 10)
        }
        .transition(.opacity)
        .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.18), value: selectedTab)
        .onChange(of: driveSession.practiceRoutePresentationRequest) { _, request in
            // The manager emits this only when a Results-screen action queues a
            // route for practice. Keeping the request separate from the route
            // itself avoids coupling tab presentation to transient view state.
            guard request != nil, selectedTab != .drive else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedTab = .drive
        }
    }

    private var liquidTabBar: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases) { tab in
                Button {
                    guard selectedTab != tab else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    selectedTab = tab
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: tab.symbol)
                            .font(.body.weight(.semibold))
                        if selectedTab == tab {
                            Text(tab.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .transition(.opacity)
                        }
                    }
                    .foregroundStyle(selectedTab == tab ? AppDesign.accent : Color.secondary)
                    .padding(.horizontal, selectedTab == tab ? 16 : 14)
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
        .overlay(Capsule(style: .continuous).stroke(.white.opacity(0.35), lineWidth: 0.8))
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
}
