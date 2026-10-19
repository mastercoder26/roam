import Foundation
import CoreGraphics

@main
struct RouteAnalysisProgressChecks {
    @MainActor
    static func main() throws {
        let suite = "RouteAnalysisProgressChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let timing = RouteAnalysisTimingEstimator(defaults: defaults)
        let initial = timing.estimate(distanceMeters: 20_000, now: now)
        expect(initial >= 10 && initial < 20, "cold-start timing must stay conservative")
        expect(timing.estimate(distanceMeters: 400_000, now: now) > initial, "long routes get a weak complexity prior")
        for _ in 0..<8 { timing.record(duration: 25, distanceMeters: 20_000, now: now) }
        let learned = timing.estimate(distanceMeters: 20_000, now: now)
        expect(learned > initial && learned < 25, "successful slow requests should adjust the prior gradually")
        let restored = RouteAnalysisTimingEstimator(defaults: defaults)
        close(restored.estimate(distanceMeters: 20_000, now: now), learned, "timing history must persist across launches")
        close(timing.estimate(distanceMeters: 20_000, now: now.addingTimeInterval(15 * 86_400)), initial, "expired network conditions must be forgotten")
        for duration in [Double.nan, .infinity, -1, 0, 500] {
            timing.record(duration: duration, distanceMeters: 20_000, now: now)
        }
        close(timing.estimate(distanceMeters: 20_000, now: now), learned, "invalid observations must not contaminate timing")
        timing.record(duration: 180, distanceMeters: 20_000, now: now)
        expect(timing.estimate(distanceMeters: 20_000, now: now) < learned * 1.5, "a single outlier must not dominate")
        for _ in 0..<30 { timing.record(duration: 2, distanceMeters: 20_000, now: now) }
        expect(timing.estimate(distanceMeters: 20_000, now: now) < initial, "recent fast requests should displace old slow history")
        expect(timing.estimate(distanceMeters: .nan, now: now).isFinite, "unavailable preview data must have a finite fallback")
        defaults.set(Data("invalid".utf8), forKey: "roam.route-analysis-timing-v1")
        close(RouteAnalysisTimingEstimator(defaults: defaults).estimate(distanceMeters: 20_000, now: now), initial, "damaged timing storage must fall back safely")

        var progress = RouteAnalysisProgress(startedAt: 100, estimatedDuration: 10)
        close(progress.fraction(at: 100), 0, "a new request begins at the start of the route")
        close(progress.fraction(at: 105), 0.46, "trace should use the request estimate")
        close(progress.fraction(at: 110), 0.92, "reserve completion for a real response")
        var previous = 0.0
        for tick in 0...1000 {
            let value = progress.fraction(at: 100 + Double(tick) / 10)
            expect(value >= previous && value < 1, "an overrun must never rewind, loop or falsely complete")
            previous = value
        }
        expect(progress.timeDescription(at: 111).contains("longer"), "an overrun must not promise zero seconds remaining")
        progress.complete(at: 112)
        close(progress.fraction(at: 112), progress.fraction(at: 111.999), "response arrival must not jump the trace", tolerance: 0.0001)
        close(progress.fraction(at: 112.25), 1, "completion reaches the route endpoint")
        progress.complete(at: 120)
        close(progress.fraction(at: 120), 1, "repeated completion must not restart the finish")
        var fast = RouteAnalysisProgress(startedAt: 100, estimatedDuration: 60)
        fast.complete(at: 100.1)
        close(fast.fraction(at: 100.35), 1, "a fast response must not wait for the estimate")
        close(fast.remainingCompletionTime(at: 200), 0, "offscreen completion should display results immediately")
        expect(!RouteAnalysisProgress(startedAt: 0, estimatedDuration: .greatestFiniteMagnitude).timeDescription(at: 0).isEmpty, "an invalid duration must not overflow the time label")

        let path = RouteTraceGeometry(points: [.zero, CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 90)])
        expect(path.position(at: 0) == .zero, "marker starts at the origin")
        expect(path.position(at: 0.5) == CGPoint(x: 10, y: 40), "marker must follow arc length rather than vertex count")
        expect(path.position(at: 1) == CGPoint(x: 10, y: 90), "marker finishes at the destination")
        expect(RouteTraceGeometry(points: []).position(at: 0.5) == nil, "a missing map preview must be harmless")
        expect(RouteTraceGeometry(points: [.zero, .zero]).position(at: 0.5) == .zero, "duplicate map vertices must not divide by zero")
        print("Route analysis timing, progress and trace geometry checks passed")
    }

    private static func close(_ actual: Double, _ expected: Double, _ message: String, tolerance: Double = 0.00001) {
        expect(abs(actual - expected) < tolerance, message)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }
}
