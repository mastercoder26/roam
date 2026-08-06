import Foundation

@main
struct DriveHistorySyncChecks {
    @MainActor
    static func main() async {
        mergeIsIdempotent()
        serverWinsOnConflict()
        await offlineDrivesStayQueuedAndRetry()
        await signedOutSyncMakesZeroNetworkCalls()
        await undecodablePayloadIsSkipped()

        print("Drive history sync checks passed")
    }

    @MainActor
    private static func mergeIsIdempotent() {
        let drive = makeDrive(score: 72)
        let remote = makeDTO(for: drive)
        let once = DriveHistorySyncEngine.merge(local: [drive], remote: [remote])
        let twice = DriveHistorySyncEngine.merge(local: once, remote: [remote])

        expect(once.count == 1, "a drive present on both sides should merge to one entry")
        expect(twice.count == 1, "merging the same server drive twice must stay idempotent")
    }

    @MainActor
    private static func serverWinsOnConflict() {
        let local = makeDrive(score: 40)
        let server = makeDrive(id: local.id, score: 91)
        let merged = DriveHistorySyncEngine.merge(local: [local], remote: [makeDTO(for: server)])

        expect(merged.count == 1, "a conflict should still produce one drive")
        expect(merged.first?.score.score == 91, "the server payload should win a drive conflict")
    }

    @MainActor
    private static func offlineDrivesStayQueuedAndRetry() async {
        let user = AuthUser(id: "offline-user", email: "offline@example.com", displayName: nil)
        let session = AuthSessionStore(automaticallyRestore: false)
        session.setSignedInForTesting(user: user, accessToken: "access-token")
        let transport = FakeDriveHistoryTransport()
        transport.shouldFail = true
        let service = DriveHistorySyncService(
            transport: transport,
            authSession: session,
            userDefaults: isolatedDefaults(),
            retryDelaysNanoseconds: [0]
        )
        let drive = makeDrive(score: 75)

        service.sync(localDrives: [drive], applyLocalDrives: { _ in })
        await waitUntil { service.state == .offline }
        expect(transport.uploadCount == 0, "an offline push must not be treated as successful")

        transport.shouldFail = false
        service.sync(localDrives: [drive], applyLocalDrives: { _ in })
        await waitUntil { service.state == .synced }
        expect(transport.uploadCount == 1, "a queued drive should upload after connectivity returns")
    }

    @MainActor
    private static func signedOutSyncMakesZeroNetworkCalls() async {
        let session = AuthSessionStore(automaticallyRestore: false)
        let transport = FakeDriveHistoryTransport()
        let service = DriveHistorySyncService(
            transport: transport,
            authSession: session,
            userDefaults: isolatedDefaults(),
            retryDelaysNanoseconds: [0]
        )

        service.sync(localDrives: [makeDrive(score: 80)], applyLocalDrives: { _ in })
        await Task.yield()
        expect(transport.fetchCount == 0, "signed-out sync must not fetch drives")
        expect(transport.uploadCount == 0, "signed-out sync must not upload drives")
    }

    @MainActor
    private static func undecodablePayloadIsSkipped() async {
        let user = AuthUser(id: "decode-user", email: "decode@example.com", displayName: nil)
        let session = AuthSessionStore(automaticallyRestore: false)
        session.setSignedInForTesting(user: user, accessToken: "access-token")
        let transport = FakeDriveHistoryTransport()
        transport.page = DriveHistoryPage(
            drives: [DriveHistoryDTO(
                id: UUID().uuidString,
                startedAt: Date(),
                durationSeconds: 60,
                distanceMeters: 100,
                score: 80,
                topSpeedMetersPerSecond: 10,
                eventCount: 0,
                recordingTimeZoneIdentifier: nil,
                payload: ["startedAt": .string("not-a-date")],
                createdAt: Date(),
                updatedAt: Date()
            )],
            nextCursor: nil
        )
        let service = DriveHistorySyncService(
            transport: transport,
            authSession: session,
            userDefaults: isolatedDefaults(),
            retryDelaysNanoseconds: [0]
        )
        var applied: [RecordedDrive] = []

        service.sync(localDrives: [], applyLocalDrives: { applied = $0 })
        await waitUntil { service.state == .synced }
        expect(applied.isEmpty, "an undecodable server payload should be skipped")
        expect(service.state == .synced, "one bad payload must not fail the whole pull")
    }

    private static func makeDrive(id: UUID = UUID(), score: Int) -> RecordedDrive {
        let quality = DriveDataQuality(
            acceptedLocationSamples: 1,
            rejectedLocationSamples: 0,
            motionSamples: 1,
            confidence: .medium
        )
        let drivingScore = DrivingScore(
            score: score,
            duration: 60,
            distanceMeters: 100,
            topSpeedMetersPerSecond: 10,
            events: [],
            motionSamples: 1,
            dataQuality: quality
        )
        return RecordedDrive(id: id, startedAt: Date(timeIntervalSince1970: 1_700_000_000), score: drivingScore, route: [])
    }

    private static func makeDTO(for drive: RecordedDrive) -> DriveHistoryDTO {
        DriveHistoryDTO(
            id: drive.id.uuidString,
            startedAt: drive.startedAt,
            durationSeconds: drive.score.duration,
            distanceMeters: drive.score.distanceMeters,
            score: drive.score.score,
            topSpeedMetersPerSecond: drive.score.topSpeedMetersPerSecond,
            eventCount: drive.score.events.count,
            recordingTimeZoneIdentifier: drive.recordingTimeZoneIdentifier,
            payload: DriveHistoryPayloadCodec.payload(for: drive),
            createdAt: drive.startedAt,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private static func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "drive-history-sync-checks-\(UUID().uuidString)")!
    }

    private static func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<100 {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        fail("timed out waiting for sync state")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        fatalError("Drive history sync check failed: \(message)")
    }
}

@MainActor
private final class FakeDriveHistoryTransport: DriveHistorySyncTransport {
    var shouldFail = false
    var page = DriveHistoryPage(drives: [], nextCursor: nil)
    private(set) var fetchCount = 0
    private(set) var uploadCount = 0

    func fetchDrives(limit: Int, before: String?, accessToken: String) async throws -> DriveHistoryPage {
        fetchCount += 1
        if shouldFail { throw AuthError.offline }
        return page
    }

    func uploadDrives(_ drives: [DriveHistoryInput], accessToken: String) async throws -> [DriveHistoryDTO] {
        uploadCount += 1
        if shouldFail { throw AuthError.offline }
        return drives.map {
            DriveHistoryDTO(
                id: $0.id,
                startedAt: $0.startedAt,
                durationSeconds: $0.durationSeconds,
                distanceMeters: $0.distanceMeters,
                score: $0.score,
                topSpeedMetersPerSecond: $0.topSpeedMetersPerSecond,
                eventCount: $0.eventCount,
                recordingTimeZoneIdentifier: $0.recordingTimeZoneIdentifier,
                payload: $0.payload,
                createdAt: $0.startedAt,
                updatedAt: Date()
            )
        }
    }
}
