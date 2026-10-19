import Foundation
import CoreGraphics

/// Learns end-to-end latency without retaining addresses, coordinates or account data.
/// The distance prior is deliberately weak: upstream calls run mostly in parallel,
/// so a drive twice as long should not imply twice the processing time.
@MainActor
final class RouteAnalysisTimingEstimator {
    private struct Sample: Codable {
        let baseline: TimeInterval
        let duration: TimeInterval
        let recordedAt: Date
    }

    private static let storageKey = "roam.route-analysis-timing-v1"
    private static let lifetime: TimeInterval = 14 * 24 * 60 * 60
    private let defaults: UserDefaults
    private var samples: [Sample]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey), data.count < 100_000,
           let saved = try? JSONDecoder().decode([Sample].self, from: data) {
            samples = Array(saved.filter(Self.isValid).suffix(20))
        } else {
            samples = []
        }
    }

    func estimate(distanceMeters: Double?, now: Date = Date()) -> TimeInterval {
        let baseline = Self.baseline(distanceMeters: distanceMeters)
        var weightedLogRatio = 0.0
        // Two or three real observations begin to outweigh the cold-start prior.
        var totalWeight = 1.5
        for (index, sample) in recentSamples(at: now).reversed().enumerated() {
            let age = max(0, now.timeIntervalSince(sample.recordedAt))
            let similarity = exp(-2 * abs(log(sample.baseline / baseline)))
            let weight = pow(0.86, Double(index)) * exp(-age / (7 * 24 * 60 * 60)) * similarity
            // Log space and bounded ratios prevent one outage or cached response
            // from dictating every subsequent estimate.
            let ratio = min(5, max(0.1, sample.duration / sample.baseline))
            weightedLogRatio += weight * log(ratio)
            totalWeight += weight
        }
        return min(90, max(1, baseline * exp(weightedLogRatio / totalWeight)))
    }

    func record(duration: TimeInterval, distanceMeters: Double?, now: Date = Date()) {
        let sample = Sample(baseline: Self.baseline(distanceMeters: distanceMeters), duration: duration, recordedAt: now)
        guard Self.isValid(sample) else { return }
        samples = Array((recentSamples(at: now) + [sample]).suffix(20))
        if let data = try? JSONEncoder().encode(samples) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private static func baseline(distanceMeters: Double?) -> TimeInterval {
        guard let distanceMeters, distanceMeters.isFinite, distanceMeters >= 0 else { return 12 }
        return 10 + min(8, 2 * log1p(distanceMeters / 20_000))
    }

    private static func isValid(_ sample: Sample) -> Bool {
        sample.baseline.isFinite && (10...18).contains(sample.baseline)
            && sample.duration.isFinite && (0.05...180).contains(sample.duration)
            && sample.recordedAt.timeIntervalSince1970.isFinite
    }

    private func recentSamples(at now: Date) -> [Sample] {
        samples.filter { (-60...Self.lifetime).contains(now.timeIntervalSince($0.recordedAt)) }
    }
}

/// A monotonic, estimated progress clock. It never reports completion before
/// the response arrives, and never makes a fast response wait for its estimate.
struct RouteAnalysisProgress: Equatable {
    static let completionDuration: TimeInterval = 0.25
    let startedAt: TimeInterval
    let estimatedDuration: TimeInterval
    private(set) var completedAt: TimeInterval?

    init(startedAt: TimeInterval, estimatedDuration: TimeInterval) {
        self.startedAt = startedAt
        self.estimatedDuration = estimatedDuration.isFinite ? min(90, max(1, estimatedDuration)) : 12
    }

    mutating func complete(at time: TimeInterval) {
        guard completedAt == nil else { return }
        completedAt = max(startedAt, time)
    }

    func fraction(at time: TimeInterval) -> Double {
        guard let completedAt else { return pendingFraction(at: time) }
        let start = pendingFraction(at: completedAt)
        let t = min(1, max(0, (time - completedAt) / Self.completionDuration))
        return start + (1 - start) * (1 - pow(1 - t, 3))
    }

    func remainingCompletionTime(at time: TimeInterval) -> TimeInterval {
        guard let completedAt else { return 0 }
        return max(0, completedAt + Self.completionDuration - time)
    }

    func timeDescription(at time: TimeInterval) -> String {
        if completedAt != nil { return "Route ready" }
        let remaining = estimatedDuration - max(0, time - startedAt)
        guard remaining > 0 else { return "Taking longer than estimated" }
        // A rounded estimate, rather than a false second-by-second deadline.
        let seconds = max(1, Int(ceil(remaining / 5)) * 5)
        return "About \(seconds) sec remaining"
    }

    private func pendingFraction(at time: TimeInterval) -> Double {
        let elapsed = max(0, time - startedAt)
        if elapsed <= estimatedDuration { return 0.92 * elapsed / estimatedDuration }
        // Match the linear velocity at the join, then approach 98% smoothly.
        return min(0.98, 0.92 + 0.06 * (1 - exp(-(elapsed - estimatedDuration) * 0.92 / (0.06 * estimatedDuration))))
    }
}

/// Arc-length positioning keeps the marker exactly on the visible stroke,
/// even when the map's route vertices are unevenly spaced.
struct RouteTraceGeometry {
    let points: [CGPoint]
    private let distances: [Double]

    init(points: [CGPoint]) {
        self.points = points
        var distances = [Double]()
        var total = 0.0
        for (index, point) in points.enumerated() {
            if index > 0 {
                let previous = points[index - 1]
                total += hypot(Double(point.x - previous.x), Double(point.y - previous.y))
            }
            distances.append(total)
        }
        self.distances = distances
    }

    func position(at fraction: Double) -> CGPoint? {
        guard let first = points.first, let total = distances.last, total > 0 else { return points.first }
        let target = min(1, max(0, fraction)) * total
        if target == 0 { return first }
        var lower = 1
        var upper = points.count - 1
        while lower < upper {
            let middle = (lower + upper) / 2
            if distances[middle] < target { lower = middle + 1 } else { upper = middle }
        }
        let length = distances[lower] - distances[lower - 1]
        let t = length > 0 ? CGFloat((target - distances[lower - 1]) / length) : 0
        let a = points[lower - 1]
        let b = points[lower]
        return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}
