import SwiftUI
import UIKit

struct SwerveRootView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case routes
        case drive

        var id: String { rawValue }
        var title: String { self == .routes ? "Routes" : "Drive" }
        var symbol: String { self == .routes ? "map.fill" : "steeringwheel" }
    }

    @State private var selectedTab: Tab = .routes
    @StateObject private var driveSession = DriveSessionManager()
    @Namespace private var tabAnimation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .routes: HomeView()
                case .drive: DriveView()
                }
            }
            .environmentObject(driveSession)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 76).allowsHitTesting(false)
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985)))

            liquidTabBar
                .padding(.horizontal, 28)
                .padding(.bottom, 10)
        }
        .animation(reduceMotion ? .easeOut(duration: 0.18) : AppAnimation.spring, value: selectedTab)
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
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                    .foregroundStyle(selectedTab == tab ? AppDesign.accent : Color.secondary)
                    .padding(.horizontal, selectedTab == tab ? 16 : 14)
                    .padding(.vertical, 12)
                    .background {
                        if selectedTab == tab {
                            Capsule(style: .continuous)
                                .fill(AppDesign.accent.opacity(0.12))
                                .overlay(Capsule(style: .continuous).stroke(AppDesign.accent.opacity(0.12), lineWidth: 0.8))
                                .matchedGeometryEffect(id: "liquid-selection", in: tabAnimation)
                        }
                    }
                }
                .buttonStyle(PressableScaleStyle())
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(.white.opacity(0.35), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    SwerveRootView()
}
