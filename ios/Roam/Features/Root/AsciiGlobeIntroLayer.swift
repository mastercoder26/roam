import SwiftUI

/// The opening beat of the launch intro: a globe built entirely from
/// monospaced text glyphs, spinning as a route arcs across it, that hands
/// off into `LaunchIntroView`'s wordmark reveal.
///
/// This replaces the old pre-rendered video clip. Same silhouette — globe
/// settles in, a route draws across it, the whole scene fades to canvas —
/// but drawn live from the active theme's own palette instead of six baked
/// renders that had to be re-exported whenever a theme changed.
struct AsciiGlobeIntroLayer: View {
    let themeID: ThemeID
    let onFinished: () -> Void

    var body: some View {
        AsciiGlobeScene(palette: ThemeCatalog.palette(for: themeID))
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + LaunchIntroChoreography.videoDuration) {
                    onFinished()
                }
            }
    }
}

// MARK: - Scene

private struct AsciiGlobeScene: View {
    let palette: ThemePalette

    @State private var startDate = Date()

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height * 0.39)

            TimelineView(.periodic(from: startDate, by: AsciiGlobeMetrics.frameInterval)) { timeline in
                let elapsed = timeline.date.timeIntervalSince(startDate)

                Canvas { context, _ in
                    draw(in: &context, center: center, elapsed: elapsed)
                }
            }
        }
        .background(palette.canvas.color)
    }

    private func draw(in context: inout GraphicsContext, center: CGPoint, elapsed: TimeInterval) {
        let sceneOpacity = AsciiGlobeMetrics.sceneOpacity(elapsed: elapsed)
        guard sceneOpacity > 0 else { return }

        drawAtmosphere(in: &context, center: center, sceneOpacity: sceneOpacity)
        drawGlobe(in: &context, center: center, elapsed: elapsed, sceneOpacity: sceneOpacity)
        drawRoute(in: &context, center: center, elapsed: elapsed, sceneOpacity: sceneOpacity)
    }

    /// A soft bloom behind the globe so the glyphs read as a lit sphere
    /// rather than text pasted on a flat background.
    private func drawAtmosphere(in context: inout GraphicsContext, center: CGPoint, sceneOpacity: Double) {
        let radius = AsciiGlobeMetrics.radius * 1.35
        let bloom = Path(ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        context.opacity = sceneOpacity
        context.fill(
            bloom,
            with: .radialGradient(
                Gradient(colors: [palette.accent.color.opacity(0.16), palette.accent.color.opacity(0)]),
                center: center,
                startRadius: 0,
                endRadius: radius
            )
        )
    }

    /// Each glyph's density character is resolved fresh every frame because
    /// its *level* changes as the sphere spins; resolving all seven levels
    /// once up front (rather than once per glyph) keeps that cheap.
    private func drawGlobe(in context: inout GraphicsContext, center: CGPoint, elapsed: TimeInterval, sceneOpacity: Double) {
        let phase = elapsed * AsciiGlobeMetrics.rotationSpeed
        let levels = AsciiGlobe.charset.map { char in
            context.resolve(
                Text(char)
                    .font(AsciiGlobeMetrics.glyphFont)
                    .foregroundColor(palette.accent.color)
            )
        }

        for glyph in AsciiGlobe.glyphs {
            let shade = glyph.shade(phase: phase)
            let level = min(levels.count - 1, Int(shade * Double(levels.count)))
            context.opacity = sceneOpacity * (0.16 + shade * 0.84)
            context.draw(
                levels[level],
                at: CGPoint(x: center.x + glyph.offset.x, y: center.y + glyph.offset.y)
            )
        }
    }

    /// The road-trip through-line: a route arcing over the globe, tracing in
    /// once as the glyphs settle. Same start-dot / travelling-head / gradient
    /// stroke language as `RoadTrace` uses for the non-globe fallback.
    private func drawRoute(in context: inout GraphicsContext, center: CGPoint, elapsed: TimeInterval, sceneOpacity: Double) {
        let route = AsciiGlobeRoute(center: center, radius: AsciiGlobeMetrics.radius)
        let progress = AsciiGlobeMetrics.routeProgress(elapsed: elapsed)
        guard progress > 0 else { return }

        context.opacity = sceneOpacity
        context.stroke(
            route.path.trimmedPath(from: 0, to: progress),
            with: .linearGradient(
                Gradient(colors: [palette.accent.color, palette.safety.color]),
                startPoint: route.start,
                endPoint: route.end
            ),
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
        )

        context.fill(
            Path(ellipseIn: CGRect(x: route.start.x - 3, y: route.start.y - 3, width: 6, height: 6)),
            with: .color(palette.accent.color)
        )

        drawCar(
            in: &context,
            at: route.point(at: progress),
            heading: route.heading(at: progress),
            color: palette.safety.color
        )
    }

    /// The travelling head is a car, not an arrowhead — this is a road-trip
    /// app, and the globe intro's route should read the same way `RoadTrace`'s
    /// travelling light does in the Reduce Motion fallback. Drawn from plain
    /// shapes (as `RoadTrace`'s own head is) rather than an SF Symbol, since
    /// `GraphicsContext.draw` needs a concrete `Image` and a tinted symbol
    /// loses that type the moment `.foregroundColor` is chained onto it.
    private func drawCar(in context: inout GraphicsContext, at point: CGPoint, heading: Double, color: Color) {
        let body = Path(roundedRect: CGRect(x: -11, y: -6, width: 22, height: 12), cornerRadius: 4)
        var wheels = Path()
        wheels.addEllipse(in: CGRect(x: -7, y: 4, width: 4.6, height: 4.6))
        wheels.addEllipse(in: CGRect(x: 2.4, y: 4, width: 4.6, height: 4.6))

        context.drawLayer { layer in
            layer.translateBy(x: point.x, y: point.y)
            layer.fill(
                Path(ellipseIn: CGRect(x: -14, y: -14, width: 28, height: 28)),
                with: .color(color.opacity(0.4))
            )
            layer.rotate(by: .radians(heading))
            layer.fill(body, with: .color(palette.inkPrimary.color))
            layer.fill(wheels, with: .color(palette.inkPrimary.color.opacity(0.85)))
        }
    }
}

// MARK: - Globe texture

/// A single glyph's fixed position on the sphere, precomputed once — only
/// its *shade* (and therefore which character represents it) changes frame
/// to frame as the globe spins.
private struct GlobeGlyph {
    let offset: CGPoint
    let depth: Double
    let dxNormalized: Double
    let latitude: Double

    /// `phase` rotates the texture's longitude, which is what reads as the
    /// sphere spinning even though every glyph stays put on screen — only
    /// the character drawn at each position changes.
    func shade(phase: Double) -> Double {
        let longitude = atan2(dxNormalized, depth) + phase
        let pattern = 0.5 + 0.5 * sin(longitude * 3 + latitude * 3.2)
        let lit = depth * 0.55 - latitude * 0.25
        return (pattern * 0.5 + lit * 0.5).clampedToUnit
    }
}

private enum AsciiGlobe {
    /// Sparse to dense, matching the reference: a lightly-stippled edge
    /// thickening into solid glyphs toward the lit face.
    static let charset = [".", ":", "%", "&", "0", "#", "@"]

    static let glyphs: [GlobeGlyph] = {
        let radius = AsciiGlobeMetrics.radius
        let spacing = AsciiGlobeMetrics.spacing
        var result: [GlobeGlyph] = []

        var y = -radius
        while y <= radius {
            var x = -radius
            while x <= radius {
                defer { x += spacing }
                let r = (x * x + y * y).squareRoot() / radius
                guard r <= 1 else { continue }
                let depth = max(0, 1 - r * r).squareRoot()
                result.append(GlobeGlyph(
                    offset: CGPoint(x: x, y: y),
                    depth: depth,
                    dxNormalized: x / radius,
                    latitude: y / radius
                ))
            }
            y += spacing
        }
        return result
    }()
}

// MARK: - Route arc

/// The curved flight-path-style arc drawn across the globe. Kept as a plain
/// cubic Bézier in view space (rather than reusing `LaunchIntroChoreography`'s
/// road curve, which is authored for the full-width fallback canvas) since
/// this arc is scoped to the globe's own radius.
private struct AsciiGlobeRoute {
    let start: CGPoint
    let control1: CGPoint
    let control2: CGPoint
    let end: CGPoint

    init(center: CGPoint, radius: CGFloat) {
        start = CGPoint(x: center.x - radius * 0.62, y: center.y + radius * 0.22)
        control1 = CGPoint(x: center.x - radius * 0.18, y: center.y - radius * 1.05)
        control2 = CGPoint(x: center.x + radius * 0.18, y: center.y - radius * 1.05)
        end = CGPoint(x: center.x + radius * 0.62, y: center.y + radius * 0.05)
    }

    var path: Path {
        Path { path in
            path.move(to: start)
            path.addCurve(to: end, control1: control1, control2: control2)
        }
    }

    /// Position along the curve at `t` in 0...1, for placing the travelling car.
    func point(at t: Double) -> CGPoint {
        let clamped = t.clampedToUnit
        let inverse = 1 - clamped

        func channel(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
            CGFloat(inverse * inverse * inverse) * a
                + CGFloat(3 * inverse * inverse * clamped) * b
                + CGFloat(3 * inverse * clamped * clamped) * c
                + CGFloat(clamped * clamped * clamped) * d
        }

        return CGPoint(
            x: channel(start.x, control1.x, control2.x, end.x),
            y: channel(start.y, control1.y, control2.y, end.y)
        )
    }

    /// Tangent direction at `t`, for orienting the car along its travel.
    func heading(at t: Double) -> Double {
        let clamped = t.clampedToUnit
        let inverse = 1 - clamped

        func derivative(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
            3 * CGFloat(inverse * inverse) * (b - a)
                + 6 * CGFloat(inverse * clamped) * (c - b)
                + 3 * CGFloat(clamped * clamped) * (d - c)
        }

        let dx = derivative(start.x, control1.x, control2.x, end.x)
        let dy = derivative(start.y, control1.y, control2.y, end.y)
        guard dx != 0 || dy != 0 else { return 0 }
        return atan2(Double(dy), Double(dx))
    }
}

// MARK: - Timing

private enum AsciiGlobeMetrics {
    static let radius: CGFloat = 132
    static let spacing: CGFloat = 6
    static let rotationSpeed: Double = 0.55
    static let glyphFont = Font.system(size: 9, weight: .semibold, design: .monospaced)
    /// A slower cadence than the display's own refresh reads as deliberately
    /// text-rendered rather than a smoothed-out imitation of video.
    static let frameInterval: TimeInterval = 1.0 / 12.0

    private static let entranceDuration: TimeInterval = 0.3
    private static let routeStartDelay: TimeInterval = 0.32
    private static let routeDuration: TimeInterval = 0.85
    private static let fadeStartsAt = LaunchIntroChoreography.videoFadeStartsAt
    private static let totalDuration = LaunchIntroChoreography.videoDuration

    static func sceneOpacity(elapsed: TimeInterval) -> Double {
        let entrance = (elapsed / entranceDuration).clampedToUnit
        let exit = elapsed <= fadeStartsAt
            ? 1
            : 1 - ((elapsed - fadeStartsAt) / (totalDuration - fadeStartsAt)).clampedToUnit
        return min(entrance, exit)
    }

    static func routeProgress(elapsed: TimeInterval) -> Double {
        ((elapsed - routeStartDelay) / routeDuration).clampedToUnit
    }
}

private extension Double {
    var clampedToUnit: Double { max(0, min(1, self)) }
}
