import SwiftUI

struct RouteAnalysisLoadingView: View {
    @State private var orbiting = false
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
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false)) {
                orbiting = true
            }
        }
    }

    private var globe: some View {
        ZStack {
            Circle()
                .fill(Color.orange)
                .frame(width: 194, height: 194)
            Circle()
                .stroke(Color.black.opacity(0.16), lineWidth: 1)
                .frame(width: 194, height: 194)
            Ellipse()
                .stroke(Color.black.opacity(0.22), lineWidth: 1)
                .frame(width: 190, height: 72)
            Ellipse()
                .stroke(Color.black.opacity(0.22), lineWidth: 1)
                .frame(width: 88, height: 190)
            Capsule()
                .fill(Color(red: 1, green: 0.48, blue: 0.16))
                .frame(width: 78, height: 48)
                .rotationEffect(.degrees(-18))
                .offset(x: -30, y: 18)

            Image(systemName: "car.side.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(.black)
                .padding(11)
                .background(.white, in: Circle())
                .shadow(color: .black.opacity(0.22), radius: 7, y: 4)
                .offset(y: -112)
                .rotationEffect(.degrees(orbiting ? 360 : 0), anchor: .init(x: 0.5, y: 4.1))
        }
        .frame(width: 230, height: 230)
    }
}

#Preview {
    RouteAnalysisLoadingView()
}
