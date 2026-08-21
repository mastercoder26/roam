import Foundation

/// Everything needed to reconstruct a `RecordedDrive` if the app is
/// terminated mid-drive. Deliberately mirrors only measured quantities —
/// recovery never fabricates data the way a live session's normal end-of-drive
/// summarization would not.
struct InProgressDriveSnapshot: Codable {
    let startedAt: Date
    let recordingTimeZoneIdentifier: String?
    let route: [DriveRoutePoint]
    let events: [DrivingEvent]
    let motionSamples: Int
    let acceptedLocationSamples: Int
    let rejectedLocationSamples: Int
    let distanceMeters: Double
    let topSpeedMetersPerSecond: Double
    let plannedRouteContext: PlannedRouteContext?
    let lastUpdatedAt: Date
    /// Optional so snapshots written before this field existed still decode —
    /// an undecodable snapshot is a lost drive, not a lost flag.
    let recordingSuspendedInBackground: Bool?
}

/// Manages the throttled, incremental persistence of a drive in progress and
/// the recovery of drives interrupted by termination. Extracted from
/// `DriveSessionManager` so crash-recovery is a self-contained concern.
@MainActor
struct DriveSnapshotPersistence {

    private static let inProgressDriveKey = "in-progress-drive-v1"
    /// Holds an interrupted-drive snapshot this build could not decode, so it
    /// survives for a later build instead of being erased on first read.
    private static let quarantinedInProgressDriveKey = "in-progress-drive-v1-quarantined"

    private(set) var lastProgressPersistAt: Date?

    /// Writes a throttled, incremental snapshot of the drive in progress so a
    /// background termination loses at most a few seconds of the newest
    /// samples instead of the entire session. Silent encoding failure is
    /// intentional here — a snapshot write is a best-effort safety net, not a
    /// requirement for `endDrive()`'s own, authoritative save path.
    mutating func persistInProgressSnapshot(
        isRecording: Bool,
        startDate: Date?,
        recordingTimeZoneIdentifier: String?,
        routePoints: [DriveRoutePoint],
        events: [DrivingEvent],
        motionSamples: Int,
        acceptedLocationSamples: Int,
        rejectedLocationSamples: Int,
        distanceMeters: Double,
        topSpeedMetersPerSecond: Double,
        plannedRouteContext: PlannedRouteContext?,
        didSuspendRecordingInBackground: Bool,
        force: Bool = false
    ) {
        guard isRecording, let startDate else { return }
        let now = Date()
        if !force, let last = lastProgressPersistAt, now.timeIntervalSince(last) < 10 {
            return
        }
        lastProgressPersistAt = now

        let snapshot = InProgressDriveSnapshot(
            startedAt: startDate,
            recordingTimeZoneIdentifier: recordingTimeZoneIdentifier,
            route: routePoints,
            events: events,
            motionSamples: motionSamples,
            acceptedLocationSamples: acceptedLocationSamples,
            rejectedLocationSamples: rejectedLocationSamples,
            distanceMeters: distanceMeters,
            topSpeedMetersPerSecond: topSpeedMetersPerSecond,
            plannedRouteContext: plannedRouteContext,
            lastUpdatedAt: now,
            recordingSuspendedInBackground: didSuspendRecordingInBackground ? true : nil
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.inProgressDriveKey)
    }

    /// Resets the persist-throttle timer and clears any stored snapshot.
    mutating func clearSnapshot() {
        lastProgressPersistAt = nil
        UserDefaults.standard.removeObject(forKey: Self.inProgressDriveKey)
    }

    /// Recovers a drive that never reached `endDrive()` because the app was
    /// terminated while recording. This is the difference between silently
    /// losing an entire drive and saving everything measured up to the last
    /// persisted snapshot. Recovery reuses the same scoring and summarization
    /// path as a normal end-of-drive save; it never fabricates a duration or
    /// distance beyond what was actually recorded, and a placement assessment
    /// is not available because the drive never reached a normal `finish`.
    ///
    /// Returns `nil` when there is nothing to recover, or when the snapshot
    /// was quarantined for a future build.
    static func recoverInterruptedSnapshot(isHistoryUnreadable: Bool) -> (drive: RecordedDrive, statusMessage: String)? {
        guard let data = UserDefaults.standard.data(forKey: inProgressDriveKey) else { return nil }
        // Decode before clearing. Removing the key first meant any decode
        // failure — a new build adding a required field, a partial write —
        // destroyed the only copy of the interrupted drive with no retry.
        guard let snapshot = try? JSONDecoder().decode(InProgressDriveSnapshot.self, from: data) else {
            // Keep the bytes for a future build, but move them off the live key
            // so an undecodable payload is not re-read on every launch.
            UserDefaults.standard.set(data, forKey: quarantinedInProgressDriveKey)
            UserDefaults.standard.removeObject(forKey: inProgressDriveKey)
            return nil
        }
        guard !isHistoryUnreadable else {
            return nil
        }
        UserDefaults.standard.removeObject(forKey: inProgressDriveKey)

        let duration = snapshot.lastUpdatedAt.timeIntervalSince(snapshot.startedAt)
        guard duration > 0, DriveHistoryPolicy.shouldSave(duration: duration) else { return nil }

        let usableTraceDuration = DriveExperienceEngine.validTraceSegments(for: snapshot.route)
            .reduce(0) { $0 + $1.duration }
        let result = DriveScoringEngine.score(
            duration: duration,
            distanceMeters: snapshot.distanceMeters,
            events: snapshot.events,
            acceptedLocationSamples: snapshot.acceptedLocationSamples,
            rejectedLocationSamples: snapshot.rejectedLocationSamples,
            motionSamples: snapshot.motionSamples,
            usableTraceDuration: usableTraceDuration
        )
        let dataQuality = DriveDataQuality(
            acceptedLocationSamples: result.quality.acceptedLocationSamples,
            rejectedLocationSamples: result.quality.rejectedLocationSamples,
            motionSamples: result.quality.motionSamples,
            confidence: result.quality.confidence,
            placementQuality: nil,
            recordingSuspendedInBackground: snapshot.recordingSuspendedInBackground
        )
        let score = DrivingScore(
            score: result.score,
            duration: duration,
            distanceMeters: snapshot.distanceMeters,
            topSpeedMetersPerSecond: snapshot.topSpeedMetersPerSecond,
            events: snapshot.events,
            motionSamples: snapshot.motionSamples,
            dataQuality: dataQuality
        )
        let unsummarizedDrive = RecordedDrive(
            startedAt: snapshot.startedAt,
            score: score,
            route: snapshot.route,
            recordingTimeZoneIdentifier: snapshot.recordingTimeZoneIdentifier,
            plannedRouteContext: snapshot.plannedRouteContext
        )
        let initialRouteAnalysis: DriveRouteAnalysis = DriveRouteAnalysisEngine.endpoints(for: unsummarizedDrive) == nil
            ? .unavailable("Route difficulty needs a longer continuous GPS trace from start to destination.")
            : .pending
        let recoveredDrive = RecordedDrive(
            id: unsummarizedDrive.id,
            startedAt: snapshot.startedAt,
            score: score,
            route: snapshot.route,
            recordingTimeZoneIdentifier: snapshot.recordingTimeZoneIdentifier,
            experienceSummary: DriveExperienceEngine.summarize(drive: unsummarizedDrive),
            plannedRouteContext: snapshot.plannedRouteContext,
            routeAnalysis: initialRouteAnalysis
        )
        return (
            drive: recoveredDrive,
            statusMessage: "Recovered a drive that was interrupted before it could finish saving normally."
        )
    }
}
