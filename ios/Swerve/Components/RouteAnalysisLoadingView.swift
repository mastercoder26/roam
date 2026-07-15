import SwiftUI

struct RouteAnalysisLoadingView: View {
    @State private var orbitPhase = 0.0
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
            orbitPhase = 0
            withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) {
                orbitPhase = 1
            }
        }
    }

    private var globe: some View {
        ZStack {
            Circle()
                .stroke(
                    Color.white.opacity(0.18),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 5])
                )
                .frame(width: 228, height: 228)
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

            orbitingCar
        }
        .frame(width: 250, height: 250)
    }

    private var orbitingCar: some View {
        let angle = orbitPhase * 2 * .pi - (.pi / 2)
        let orbitRadius: CGFloat = 114
        let center: CGFloat = 125

        return Image(systemName: "car.side.fill")
            .font(.title2.weight(.bold))
            .foregroundStyle(.black)
            .padding(11)
            .background(.white, in: Circle())
            .shadow(color: .black.opacity(0.22), radius: 7, y: 4)
            .rotationEffect(.radians(orbitPhase * 2 * .pi))
            .position(
                x: center + CGFloat(cos(angle)) * orbitRadius,
                y: center + CGFloat(sin(angle)) * orbitRadius
            )
    }
}

#Preview {
    RouteAnalysisLoadingView()
}
