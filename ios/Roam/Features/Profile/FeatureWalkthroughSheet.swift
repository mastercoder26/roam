import SwiftUI

/// A compact, replayable guided tour. It is intentionally an on-demand sheet:
/// the app's launch experience stays fast, while the full product story is
/// always available from Settings.
struct FeatureWalkthroughSheet: View {
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentStep: FeatureWalkthroughStep = .plan

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: AppDesign.space16) {
                    progressRail
                        .padding(.horizontal, AppDesign.space20)
                        .padding(.top, AppDesign.space12)

                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            featureStory(step: currentStep, cardHeight: max(360, geometry.size.height - 155))
                                .id("walkthrough.story")
                                .padding(.horizontal, AppDesign.contentPadding)
                                .padding(.bottom, AppDesign.space24)
                        }
                        .onChange(of: currentStep) { _, _ in
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                scrollProxy.scrollTo("walkthrough.story", anchor: .top)
                            }
                        }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    primaryAction
                        .padding(.horizontal, AppDesign.contentPadding)
                        .padding(.top, AppDesign.space12)
                        .padding(.bottom, AppDesign.space20)
                        .background(AppDesign.canvas)
                }
            }
            .background(AppCanvasBackground())
            .navigationTitle("Explore Roam")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var progressRail: some View {
        HStack(spacing: AppDesign.space8) {
            ForEach(FeatureWalkthroughStep.allCases) { step in
                Capsule(style: .continuous)
                    .fill(step == currentStep ? AppDesign.accent : AppDesign.trackSurface)
                    .frame(maxWidth: .infinity)
                    .frame(height: 5)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Guide progress, \(currentStep.progressLabel)")
        .accessibilityIdentifier("walkthrough.progress")
    }

    private func featureStory(step: FeatureWalkthroughStep, cardHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.space20) {
            Image(systemName: featureSymbol(for: step))
                .font(.title2.weight(.medium))
                .foregroundStyle(AppDesign.accent)
                .frame(width: 52, height: 52)
                .background(AppDesign.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppDesign.space12) {
                Text(step.progressLabel)
                    .font(.footnote)
                    .foregroundStyle(AppDesign.Ink.secondary)
                Text(step.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppDesign.Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(step.detail)
                    .font(.body)
                    .foregroundStyle(AppDesign.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: min(cardHeight, 360), alignment: .topLeading)
        .heroCard()
        .id(step)
        .transition(storyTransition)
        .accessibilityElement(children: .combine)
    }

    private func featureSymbol(for step: FeatureWalkthroughStep) -> String {
        switch step {
        case .plan: "map"
        case .understand: "slider.horizontal.3"
        case .drive: "steeringwheel"
        case .grow: "chart.line.uptrend.xyaxis"
        }
    }

    private var storyTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 32)).combined(with: .scale(scale: 0.98)),
            removal: .opacity.combined(with: .offset(x: -24))
        )
    }

    private var primaryAction: some View {
        Button(action: advance) {
            HStack(spacing: AppDesign.space8) {
                Text(currentStep.actionTitle)
                Spacer(minLength: 0)
                Image(systemName: currentStep.next == nil ? "checkmark" : "arrow.right")
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(AppDesign.primarySurfaceForeground)
            .padding(.horizontal, AppDesign.space20)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(AppDesign.Ink.primary, in: Capsule())
        }
        .buttonStyle(PressableScaleStyle())
        .accessibilityHint(currentStep.next == nil ? "Closes the Roam guide" : "Shows the next part of the Roam guide")
        .accessibilityIdentifier(currentStep.next == nil ? "walkthrough.finish" : "walkthrough.next")
    }

    private func advance() {
        guard let next = currentStep.next else {
            dismiss()
            return
        }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 1)) {
            currentStep = next
        }
    }
}

#Preview {
    FeatureWalkthroughSheet()
}
