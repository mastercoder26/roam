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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Skip") { dismiss() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("walkthrough.skip")
                }
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
        ZStack {
            VStack(alignment: .leading, spacing: AppDesign.space20) {
                Spacer(minLength: 200)

                VStack(alignment: .leading, spacing: AppDesign.space12) {
                    Text(step.progressLabel.uppercased())
                        .font(AppDesign.Typography.microLabel)
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.75))

                    Text(step.title)
                        .font(AppDesign.Typography.display)
                        .tracking(-0.9)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(step.detail)
                        .font(AppDesign.Typography.body)
                        .foregroundStyle(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppDesign.space24)
                .background(textBackdrop)
            }
            .frame(maxWidth: .infinity, minHeight: cardHeight, alignment: .bottomLeading)
            .background(walkthroughIllustration(for: step))
            .id(step)
            .zIndex(Double(FeatureWalkthroughStep.allCases.firstIndex(of: step) ?? 0) + 1)
            .transition(storyTransition)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.75)
        }
        .accessibilityElement(children: .combine)
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

    private var textBackdrop: some View {
        GeometryReader { geometry in
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.7), location: 64 / (geometry.size.height + 64)),
                    .init(color: .black.opacity(0.85), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: geometry.size.width, height: geometry.size.height + 64)
            .offset(y: -64)
        }
        .accessibilityHidden(true)
    }

    private func artworkName(for step: FeatureWalkthroughStep) -> String {
        switch step {
        case .plan: "WalkthroughPlan"
        case .understand: "WalkthroughUnderstand"
        case .drive: "WalkthroughDrive"
        case .grow: "WalkthroughGrow"
        }
    }

    private func walkthroughIllustration(for step: FeatureWalkthroughStep) -> some View {
        GeometryReader { geometry in
            ZStack {
                Image(artworkName(for: step))
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)

                Color.black.opacity(0.04)
            }
            .clipped()
        }
        .accessibilityHidden(true)
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
            .padding(.horizontal, AppDesign.space16)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(AppDesign.accent, in: RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous))
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
