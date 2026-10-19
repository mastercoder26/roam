import Foundation
import CoreLocation

@main
struct DriveRecordingClockChecks {
    static func main() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        var clock = DriveRecordingClock()
        precondition(clock.elapsed(at: start) == 0)
        clock.start(at: start)
        precondition(clock.elapsed(at: start.addingTimeInterval(15)) == 15)
        clock.pause(at: start.addingTimeInterval(15))
        clock.pause(at: start.addingTimeInterval(25))
        precondition(clock.elapsed(at: start.addingTimeInterval(80)) == 15, "Repeated pause must not restart the pause boundary")
        clock.resume(at: start.addingTimeInterval(80))
        clock.resume(at: start.addingTimeInterval(90))
        precondition(clock.elapsed(at: start.addingTimeInterval(100)) == 35, "Resume excludes the paused 65 seconds exactly once")
        clock.pause(at: start.addingTimeInterval(110))
        precondition(clock.elapsed(at: start.addingTimeInterval(500)) == 45, "Ending or recovering while paused uses active duration")
        clock.start(at: start.addingTimeInterval(600))
        precondition(clock.elapsed(at: start.addingTimeInterval(610)) == 10, "A new session must clear prior pauses")

        let a = DriveRoutePoint(timestamp: start, coordinate: DriveCoordinate(CLLocationCoordinate2D(latitude: 41.9, longitude: -87.63)), speedMetersPerSecond: 10)
        let b = DriveRoutePoint(timestamp: start.addingTimeInterval(3), coordinate: DriveCoordinate(CLLocationCoordinate2D(latitude: 41.9002, longitude: -87.63)), speedMetersPerSecond: 10, startsNewSegment: true)
        let c = DriveRoutePoint(timestamp: start.addingTimeInterval(6), coordinate: DriveCoordinate(CLLocationCoordinate2D(latitude: 41.9004, longitude: -87.63)), speedMetersPerSecond: 10)
        let segments = DriveExperienceEngine.validTraceSegments(for: [a, b, c])
        precondition(segments.count == 1 && segments[0].startIndex == 1, "A short pause must not manufacture a connecting trace, distance or exposure")
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let original = try encoder.encode(a)
        let decodedOriginal = try decoder.decode(DriveRoutePoint.self, from: original)
        precondition(decodedOriginal.startsNewSegment == nil)
        let boundary = try encoder.encode(b)
        let decodedBoundary = try decoder.decode(DriveRoutePoint.self, from: boundary)
        precondition(decodedBoundary.startsNewSegment == true)
        print("Drive recording clock and pause-boundary checks passed")
    }
}
