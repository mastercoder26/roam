import CoreLocation
import Foundation

@main
struct DriveHistorySyncChecks {
    @MainActor
    static func main() async {
        setvbuf(stdout, nil, _IONBF, 0)
        mergeIsIdempotent()
        serverWinsOnConflict()
        mergedHistoryIsNewestFirst()
        cloudPayloadNeverContainsCoordinates()
        await offlineDrivesStayQueuedAndRetry()
        await signedOutSyncMakesZeroNetworkCalls()
        await undecodablePayloadIsSkipped()
        await missingLocalHistoryNeverDeletesRemoteRecords()
        await deletingALocalDriveDeletesItRemotely()
        await aFailedDeletionSurvivesRelaunchAndDoesNotResurrect()
        await aFailedDeletionSurvivesSignOutAndSameAccountReturn()
        await pendingDeletionsNeverCrossAccounts()

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
    private static func mergedHistoryIsNewestFirst() {
        let olderLocal = makeDrive(
            score: 62,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let newerRemote = makeDrive(
            score: 81,
            startedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let merged = DriveHistorySyncEngine.merge(
            local: [olderLocal],
            remote: [makeDTO(for: newerRemote)]
        )

        expect(merged.map(\.id) == [newerRemote.id, olderLocal.id], "synced history should always present the newest drive first")
    }

    @MainActor
    private static func cloudPayloadNeverContainsCoordinates() {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let coordinate = DriveCoordinate(
            CLLocationCoordinate2D(latitude: 30.2672, longitude: -97.7431)
        )
        let quality = DriveDataQuality(
            acceptedLocationSamples: 2,
            rejectedLocationSamples: 0,
            motionSamples: 1,
            confidence: .medium
        )
        let score = DrivingScore(
            score: 84,
            duration: 10,
            distanceMeters: 42,
            topSpeedMetersPerSecond: 8,
            events: [DrivingEvent(
                kind: .hardBrake,
                timestamp: startedAt.addingTimeInterval(5),
                source: .fused,
                coordinate: coordinate
            )],
            motionSamples: 1,
            dataQuality: quality
        )
        let local = RecordedDrive(
            startedAt: startedAt,
            score: score,
            route: [
                DriveRoutePoint(timestamp: startedAt, coordinate: coordinate, speedMetersPerSecond: 6),
                DriveRoutePoint(
                    timestamp: startedAt.addingTimeInterval(5),
                    coordinate: DriveCoordinate(
                        CLLocationCoordinate2D(latitude: 30.2676, longitude: -97.7427)
                    ),
                    speedMetersPerSecond: 8
                )
            ]
        )

        let payload = DriveHistoryPayloadCodec.payload(for: local)
        guard let restored = DriveHistoryPayloadCodec.drive(from: payload) else {
            fail("a privacy-preserving cloud payload should remain decodable")
        }

        expect(restored.route.isEmpty, "precise GPS traces must never enter the cloud payload")
        expect(
            restored.score.events.allSatisfy { $0.coordinate == nil },
            "coaching-event coordinates must never enter the cloud payload"
        )
        expect(
            restored.experienceSummary != nil,
            "the cloud copy should retain a coordinate-free experience summary"
        )

        let merged = DriveHistorySyncEngine.merge(local: [local], remote: [makeDTO(for: local)])
        expect(
            merged.first?.route == local.route,
            "syncing a redacted cloud copy must not erase the device's private route trace"
        )
        expect(
            merged.first?.score.events.first?.coordinate == coordinate,
            "syncing a redacted cloud copy must preserve local event coordinates"
        )
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

    @MainActor
    private static func missingLocalHistoryNeverDeletesRemoteRecords() async {
        let user = AuthUser(id: "missing-local-user", email: "missing-local@example.com", displayName: nil)
        let session = AuthSessionStore(automaticallyRestore: false)
        session.setSignedInForTesting(user: user, accessToken: "access-token")
        let transport = FakeDriveHistoryTransport()
        let drive = makeDrive(score: 64)
        transport.page = DriveHistoryPage(drives: [makeDTO(for: drive)], nextCursor: nil)
        let service = DriveHistorySyncService(
            transport: transport,
            authSession: session,
            userDefaults: isolatedDefaults(),
            retryDelaysNanoseconds: [0]
        )

        var applied: [RecordedDrive] = [drive]
        service.sync(localDrives: [drive], applyLocalDrives: { applied = $0 })
        await waitUntil { service.state == .synced }

        // An empty or incomplete local snapshot can mean unreadable storage,
        // retention, or an interrupted load. Only an explicit user delete is
        // allowed to remove the server backup.
        service.sync(localDrives: [], applyLocalDrives: { applied = $0 })
        await waitUntil { service.state == .synced }

        expect(transport.deletedIDs.isEmpty, "a drive missing locally without an explicit tombstone must stay on the server")
        expect(applied.contains { $0.id == drive.id }, "the server copy should restore a drive that was only missing locally")
    }

    @MainActor
    private static func deletingALocalDriveDeletesItRemotely() async {
        let user = AuthUser(id: "delete-user", email: "delete@example.com", displayName: nil)
        let session = AuthSessionStore(automaticallyRestore: false)
        session.setSignedInForTesting(user: user, accessToken: "access-token")
        let transport = FakeDriveHistoryTransport()
        let drive = makeDrive(score: 60)
        transport.page = DriveHistoryPage(drives: [makeDTO(for: drive)], nextCursor: nil)
        let defaults = isolatedDefaults()
        let service = DriveHistorySyncService(
            transport: transport,
            authSession: session,
            userDefaults: defaults,
            retryDelaysNanoseconds: [0]
        )

        // First sync: the drive comes down from the server and is confirmed synced.
        var applied: [RecordedDrive] = [drive]
        service.sync(localDrives: [drive], applyLocalDrives: { applied = $0 })
        await waitUntil { service.state == .synced }
        expect(applied.contains { $0.id == drive.id }, "the drive should be present after the first sync")

        // User deletes it locally, then a sync runs with the drive already removed.
        service.markDriveDeleted(id: drive.id)
        service.sync(localDrives: [], applyLocalDrives: { applied = $0 })
        await waitUntil { service.state == .synced }

        expect(transport.deletedIDs == [drive.id.uuidString], "a locally removed drive must be deleted remotely")
        expect(applied.isEmpty, "a deleted drive must not be re-merged back into local history")
    }

    @MainActor
    private static func aFailedDeletionSurvivesRelaunchAndDoesNotResurrect() async {
        let user = AuthUser(id: "delete-retry-user", email: "delete-retry@example.com", displayName: nil)
        let session = AuthSessionStore(automaticallyRestore: false)
        session.setSignedInForTesting(user: user, accessToken: "access-token")
        let transport = FakeDriveHistoryTransport()
        let drive = makeDrive(score: 55)
        transport.page = DriveHistoryPage(drives: [makeDTO(for: drive)], nextCursor: nil)
        let defaults = isolatedDefaults()
        // No retries here: state flips to `.offline` on the first failed
        // attempt, before any retry sleep, so an in-flight retry task could
        // still be running (and could still succeed) after this returns.
        // Using zero retries keeps the task's lifetime deterministic for
        // the assertions below.
        let service = DriveHistorySyncService(
            transport: transport,
            authSession: session,
            userDefaults: defaults,
            retryDelaysNanoseconds: []
        )

        var applied: [RecordedDrive] = [drive]
        service.sync(localDrives: [drive], applyLocalDrives: { applied = $0 })
        await waitUntil { service.state == .synced }

        // The delete call fails (simulating no connectivity at delete time).
        transport.shouldFail = true
        service.markDriveDeleted(id: drive.id)
        service.sync(localDrives: [], applyLocalDrives: { applied = $0 })
        await waitUntil { service.state == .offline }
        expect(transport.deletedIDs.isEmpty, "a failed delete must not be recorded as sent")

        // "Relaunch": a fresh service instance reads the same persisted metadata.
        transport.shouldFail = false
        let relaunched = DriveHistorySyncService(
            transport: transport,
            authSession: session,
            userDefaults: defaults,
            retryDelaysNanoseconds: [0]
        )
        relaunched.sync(localDrives: [], applyLocalDrives: { applied = $0 })
        await waitUntil { relaunched.state == .synced }

        expect(transport.deletedIDs == [drive.id.uuidString], "the pending deletion must survive relaunch and retry")
        expect(applied.isEmpty, "the drive must stay deleted after the retried sync")
    }

    @MainActor
    private static func aFailedDeletionSurvivesSignOutAndSameAccountReturn() async {
        let user = AuthUser(id: "delete-sign-out-user", email: "delete-sign-out@example.com", displayName: nil)
        let session = AuthSessionStore(automaticallyRestore: false)
        session.setSignedInForTesting(user: user, accessToken: "access-token")
        let transport = FakeDriveHistoryTransport()
        let drive = makeDrive(score: 58)
        transport.page = DriveHistoryPage(drives: [makeDTO(for: drive)], nextCursor: nil)
        let defaults = isolatedDefaults()
        let service = DriveHistorySyncService(
            transport: transport,
            authSession: session,
            userDefaults: defaults,
            retryDelaysNanoseconds: []
        )

        var applied: [RecordedDrive] = [drive]
        service.sync(localDrives: [drive], applyLocalDrives: { applied = $0 })
        await waitUntil { service.state == .synced }

        transport.shouldFail = true
        service.markDriveDeleted(id: drive.id)
        service.sync(localDrives: [], applyLocalDrives: { applied = $0 })
        await waitUntil { service.state == .offline }

        // The network request is still pending when the user signs out. That
        // must stop in-flight work without erasing the user's explicit delete.
        service.didSignOut()

        transport.shouldFail = false
        let returnedToSameAccount = DriveHistorySyncService(
            transport: transport,
            authSession: session,
            userDefaults: defaults,
            retryDelaysNanoseconds: [0]
        )
        returnedToSameAccount.sync(localDrives: [], applyLocalDrives: { applied = $0 })
        await waitUntil { returnedToSameAccount.state == .synced }

        expect(
            transport.deletedIDs == [drive.id.uuidString],
            "signing out must not erase an offline deletion queued for the same account"
        )
        expect(applied.isEmpty, "returning to the same account must not resurrect the deleted drive")
    }

    @MainActor
    private static func pendingDeletionsNeverCrossAccounts() async {
        let firstUser = AuthUser(id: "first-account", email: "first@example.com", displayName: nil)
        let session = AuthSessionStore(automaticallyRestore: false)
        session.setSignedInForTesting(user: firstUser, accessToken: "first-token")
        let transport = FakeDriveHistoryTransport()
        let sharedID = UUID()
        let firstDrive = makeDrive(id: sharedID, score: 52)
        transport.page = DriveHistoryPage(drives: [makeDTO(for: firstDrive)], nextCursor: nil)
        let defaults = isolatedDefaults()
        let firstService = DriveHistorySyncService(
            transport: transport,
            authSession: session,
            userDefaults: defaults,
            retryDelaysNanoseconds: []
        )

        firstService.sync(localDrives: [firstDrive], applyLocalDrives: { _ in })
        await waitUntil { firstService.state == .synced }
        transport.shouldFail = true
        firstService.markDriveDeleted(id: sharedID)
        firstService.sync(localDrives: [], applyLocalDrives: { _ in })
        await waitUntil { firstService.state == .offline }
        firstService.didSignOut()

        // A UUID collision is extraordinarily unlikely, but using one here
        // proves that isolation comes from the account boundary, not the ID.
        let secondUser = AuthUser(id: "second-account", email: "second@example.com", displayName: nil)
        session.setSignedInForTesting(user: secondUser, accessToken: "second-token")
        let secondDrive = makeDrive(id: sharedID, score: 88)
        transport.page = DriveHistoryPage(drives: [makeDTO(for: secondDrive)], nextCursor: nil)
        transport.shouldFail = false
        let secondService = DriveHistorySyncService(
            transport: transport,
            authSession: session,
            userDefaults: defaults,
            retryDelaysNanoseconds: [0]
        )
        var applied: [RecordedDrive] = []
        secondService.sync(localDrives: [], applyLocalDrives: { applied = $0 })
        await waitUntil { secondService.state == .synced }

        expect(transport.deletedIDs.isEmpty, "one account's pending deletion must never be sent to another account")
        expect(applied.first?.score.score == 88, "the second account's remote drive must remain intact")
    }

    private static func makeDrive(
        id: UUID = UUID(),
        score: Int,
        startedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> RecordedDrive {
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
        return RecordedDrive(id: id, startedAt: startedAt, score: drivingScore, route: [])
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
    private(set) var deletedIDs: [String] = []

    func fetchDrives(limit: Int, before: String?, beforeId: String?, accessToken: String) async throws -> DriveHistoryPage {
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

    func deleteDrive(id: String, accessToken: String) async throws {
        if shouldFail { throw AuthError.offline }
        deletedIDs.append(id)
        page = DriveHistoryPage(drives: page.drives.filter { $0.id != id }, nextCursor: page.nextCursor)
    }
}
