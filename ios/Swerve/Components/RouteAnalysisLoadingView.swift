import SwiftUI

struct RouteAnalysisLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 26) {
                globe
                VStack(spacing: 8) {
                    Text("Reading the road ahead")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Comparing route shape, traffic, road context, and conditions.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.64))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
                ProgressView()
                    .tint(.orange)
            }
            .padding(28)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Analyzing route difficulty")
    }

    private var globe: some View {
        RouteAnalysisGlobeView(reduceMotion: reduceMotion)
            .frame(width: 250, height: 250)
            .accessibilityHidden(true)
    }
}

#Preview {
    RouteAnalysisLoadingView()
}
