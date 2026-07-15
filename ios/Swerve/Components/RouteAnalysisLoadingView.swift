import SwiftUI

/// A short visual explanation of what Swerve is doing: trace a route, assemble
/// its signal points into a car, then send that car on its way to the results.
struct RouteAnalysisLoadingView: View {
    let isFinishing: Bool
    let onDepartureComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var routeProgress: CGFloat = 0
    @State private var dotsAreFormed = false
    @State private var departureRequested = false
    @State private var isDrivingAway = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
                DotCarIllustration(
                    routeProgress: routeProgress,
                    dotsAreFormed: dotsAreFormed,
                    isDrivingAway: isDrivingAway,
                    reduceMotion: reduceMotion
                )
                .frame(width: 320, height: 190)

                VStack(spacing: 8) {
                    Text(statusTitle)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Tracing the route, then matching its road signals to your drive.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.64))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 290)
                }

                ProgressView()
                    .tint(.orange)
            }
            .padding(28)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Analyzing route difficulty")
        .onAppear(perform: startSequence)
        .onChange(of: isFinishing) { _, finishing in
            guard finishing else { return }
            requestDeparture()
        }
    }

    private var statusTitle: String {
        if isDrivingAway { return "Your route is ready" }
        if dotsAreFormed { return "Reading the road ahead" }
        return "Tracing your route"
    }

    private func startSequence() {
        guard !reduceMotion else {
            routeProgress = 1
            dotsAreFormed = true
            return
        }

        withAnimation(.linear(duration: 0.72)) {
            routeProgress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
            withAnimation(.spring(response: 0.52, dampingFraction: 0.86)) {
                dotsAreFormed = true
            }
            if departureRequested {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: driveAway)
            }
        }
    }

    private func requestDeparture() {
        guard !isDrivingAway else { return }
        guard dotsAreFormed else {
            departureRequested = true
            return
        }
        driveAway()
    }

    private func driveAway() {
        guard !isDrivingAway else { return }
        guard !reduceMotion else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: onDepartureComplete)
            return
        }

        withAnimation(.easeIn(duration: 0.72)) {
            isDrivingAway = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.76, execute: onDepartureComplete)
    }
}

private struct DotCarIllustration: View {
    let routeProgress: CGFloat
    let dotsAreFormed: Bool
    let isDrivingAway: Bool
    let reduceMotion: Bool

    private let canvasSize = CGSize(width: 320, height: 190)

    var body: some View {
        ZStack {
            routeLine
            dotCar
                .offset(x: isDrivingAway ? -390 : 0)
                .opacity(isDrivingAway ? 0.85 : 1)
                .animation(.easeIn(duration: 0.72), value: isDrivingAway)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .clipped()
    }

    private var routeLine: some View {
        Path { path in
            path.move(to: CGPoint(x: 12, y: 145))
            path.addCurve(
                to: CGPoint(x: 308, y: 145),
                control1: CGPoint(x: 82, y: 128),
                control2: CGPoint(x: 212, y: 164)
            )
        }
        .trim(from: 0, to: routeProgress)
        .stroke(
            Color.orange,
            style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round)
        )
        .shadow(color: .orange.opacity(0.35), radius: 12)
    }

    private var dotCar: some View {
        ZStack {
            ForEach(CarDots.shell) { dot in
                FloatingDot(
                    size: dot.size,
                    color: dot.isAccent ? .orange : .white,
                    phase: dot.phase,
                    isVisible: dotsAreFormed,
                    isBobbing: dotsAreFormed && !isDrivingAway && !reduceMotion
                )
                .position(
                    x: dotsAreFormed ? dot.x : dot.x * 0.92 + 12,
                    y: dotsAreFormed ? dot.y : 145
                )
                .animation(
                    .spring(response: 0.48, dampingFraction: 0.82)
                        .delay(dot.phase * 0.028),
                    value: dotsAreFormed
                )
            }

            DotWheel(
                center: CGPoint(x: 92, y: 126),
                phase: 0,
                isVisible: dotsAreFormed,
                isBobbing: dotsAreFormed && !isDrivingAway && !reduceMotion,
                isSpinning: isDrivingAway
            )
            DotWheel(
                center: CGPoint(x: 231, y: 126),
                phase: 8,
                isVisible: dotsAreFormed,
                isBobbing: dotsAreFormed && !isDrivingAway && !reduceMotion,
                isSpinning: isDrivingAway
            )
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }
}

private struct FloatingDot: View {
    let size: CGFloat
    let color: Color
    let phase: Double
    let isVisible: Bool
    let isBobbing: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let bob = isBobbing ? sin(time * 2.2 + phase) * 2.2 : 0

            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .offset(y: bob)
                .opacity(isVisible ? 1 : 0)
                .scaleEffect(isVisible ? 1 : 0.72)
                .animation(
                    .spring(response: 0.42, dampingFraction: 0.82)
                        .delay(phase * 0.024),
                    value: isVisible
                )
        }
    }
}

private struct DotWheel: View {
    let center: CGPoint
    let phase: Double
    let isVisible: Bool
    let isBobbing: Bool
    let isSpinning: Bool

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                let angle = Double(index) * .pi / 4
                FloatingDot(
                    size: index.isMultiple(of: 2) ? 8 : 6,
                    color: index.isMultiple(of: 2) ? .orange : .white.opacity(0.88),
                    phase: phase + Double(index),
                    isVisible: isVisible,
                    isBobbing: isBobbing
                )
                .offset(
                    x: CGFloat(cos(angle) * 16),
                    y: CGFloat(sin(angle) * 16)
                )
            }
        }
        .frame(width: 42, height: 42)
        .rotationEffect(.degrees(isSpinning ? -720 : 0))
        .animation(.easeIn(duration: 0.72), value: isSpinning)
        .position(x: isVisible ? center.x : center.x * 0.92 + 12, y: isVisible ? center.y : 145)
        .animation(
            .spring(response: 0.48, dampingFraction: 0.82).delay(phase * 0.028),
            value: isVisible
        )
    }
}

private struct CarDot: Identifiable {
    let id: Int
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let phase: Double
    let isAccent: Bool
}

private enum CarDots {
    static let shell: [CarDot] = [
        .init(id: 0, x: 44, y: 116, size: 8, phase: 0, isAccent: true),
        .init(id: 1, x: 58, y: 106, size: 7, phase: 1, isAccent: false),
        .init(id: 2, x: 73, y: 99, size: 8, phase: 2, isAccent: false),
        .init(id: 3, x: 91, y: 96, size: 7, phase: 3, isAccent: true),
        .init(id: 4, x: 108, y: 91, size: 8, phase: 4, isAccent: false),
        .init(id: 5, x: 119, y: 76, size: 7, phase: 5, isAccent: true),
        .init(id: 6, x: 133, y: 65, size: 8, phase: 6, isAccent: false),
        .init(id: 7, x: 151, y: 58, size: 7, phase: 7, isAccent: false),
        .init(id: 8, x: 172, y: 57, size: 8, phase: 8, isAccent: true),
        .init(id: 9, x: 192, y: 64, size: 7, phase: 9, isAccent: false),
        .init(id: 10, x: 207, y: 77, size: 8, phase: 10, isAccent: false),
        .init(id: 11, x: 221, y: 91, size: 7, phase: 11, isAccent: true),
        .init(id: 12, x: 244, y: 96, size: 8, phase: 12, isAccent: false),
        .init(id: 13, x: 263, y: 104, size: 7, phase: 13, isAccent: false),
        .init(id: 14, x: 277, y: 115, size: 8, phase: 14, isAccent: true),
        .init(id: 15, x: 271, y: 126, size: 7, phase: 15, isAccent: false),
        .init(id: 16, x: 250, y: 132, size: 8, phase: 16, isAccent: false),
        .init(id: 17, x: 210, y: 134, size: 7, phase: 17, isAccent: true),
        .init(id: 18, x: 185, y: 134, size: 8, phase: 18, isAccent: false),
        .init(id: 19, x: 157, y: 134, size: 7, phase: 19, isAccent: false),
        .init(id: 20, x: 130, y: 134, size: 8, phase: 20, isAccent: true),
        .init(id: 21, x: 70, y: 132, size: 7, phase: 21, isAccent: false),
        .init(id: 22, x: 49, y: 127, size: 8, phase: 22, isAccent: false)
    ]
}

#Preview {
    RouteAnalysisLoadingView(isFinishing: false, onDepartureComplete: {})
}
