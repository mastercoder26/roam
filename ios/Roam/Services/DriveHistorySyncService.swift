import Combine
import Foundation

enum DriveHistorySyncState: Equatable {
    case idle
    case syncing
    case synced
    case offline
    case failed(String)
}

struct DriveHistoryInput: Encodable {
    let id: String
    let startedAt: Date
    let durationSeconds: TimeInterval
    let distanceMeters: Double
    let score: Int
    let topSpeedMetersPerSecond: Double
    let eventCount: Int
    let recordingTimeZoneIdentifier: String?
    let payload: [String: JSONValue]
}

struct DriveHistoryDTO: Decodable {
    let id: String
    let startedAt: Date
    let durationSeconds: TimeInterval
    let distanceMeters: Double
    let score: Int
    let topSpeedMetersPerSecond: Double
    let eventCount: Int
    let recordingTimeZoneIdentifier: String?
    let payload: [String: JSONValue]
    let createdAt: Date
    let updatedAt: Date

    init(
        id: String,
        startedAt: Date,
        durationSeconds: TimeInterval,
        distanceMeters: Double,
        score: Int,
        topSpeedMetersPerSecond: Double,
        eventCount: Int = 0,
        recordingTimeZoneIdentifier: String?,
        payload: [String: JSONValue],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.score = score
        self.topSpeedMetersPerSecond = topSpeedMetersPerSecond
        self.eventCount = eventCount
        self.recordingTimeZoneIdentifier = recordingTimeZoneIdentifier
        self.payload = payload
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, startedAt, durationSeconds, distanceMeters, score
        case topSpeedMetersPerSecond, eventCount, recordingTimeZoneIdentifier
        case payload, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(String.self, forKey: .id),
            startedAt: try values.decode(Date.self, forKey: .startedAt),
            durationSeconds: try values.decode(Double.self, forKey: .durationSeconds),
            distanceMeters: try values.decode(Double.self, forKey: .distanceMeters),
            score: try values.decode(Int.self, forKey: .score),
            topSpeedMetersPerSecond: try values.decode(Double.self, forKey: .topSpeedMetersPerSecond),
            eventCount: try values.decodeIfPresent(Int.self, forKey: .eventCount) ?? 0,
            recordingTimeZoneIdentifier: try values.decodeIfPresent(String.self, forKey: .recordingTimeZoneIdentifier),
            payload: try values.decode([String: JSONValue].self, forKey: .payload),
            createdAt: try values.decode(Date.self, forKey: .createdAt),
            updatedAt: try values.decode(Date.self, forKey: .updatedAt)
        )
    }
}

struct DriveHistoryPage: Decodable {
    let drives: [DriveHistoryDTO]
    let nextCursor: String?
    /// Paired with `nextCursor` so a page boundary that falls inside a group of
    /// drives sharing one start timestamp does not skip the rest of that group.
    let nextCursorId: String?

    init(drives: [DriveHistoryDTO], nextCursor: String?, nextCursorId: String? = nil) {
        self.drives = drives
        self.nextCursor = nextCursor
        self.nextCursorId = nextCursorId
    }

    private enum CodingKeys: String, CodingKey {
        case drives, nextCursor, nextCursorId
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            drives: try values.decode([DriveHistoryDTO].self, forKey: .drives),
            nextCursor: try values.decodeIfPresent(String.self, forKey: .nextCursor),
            nextCursorId: try values.decodeIfPresent(String.self, forKey: .nextCursorId)
        )
    }
}

private struct DriveHistoryBatch: Encodable {
    let drives: [DriveHistoryInput]
}

@MainActor
protocol DriveHistorySyncTransport {
    func fetchDrives(limit: Int, before: String?, beforeId: String?, accessToken: String) async throws -> DriveHistoryPage
    func uploadDrives(_ drives: [DriveHistoryInput], accessToken: String) async throws -> [DriveHistoryDTO]
    /// Idempotent: a drive already deleted (or never uploaded) is treated as success.
    func deleteDrive(id: String, accessToken: String) async throws
}

struct APIClientDriveHistoryTransport: DriveHistorySyncTransport {
    let client: APIClient

    nonisolated init(client: APIClient = APIClient()) {
        self.client = client
    }

    func fetchDrives(limit: Int, before: String?, beforeId: String?, accessToken: String) async throws -> DriveHistoryPage {
        var path = "api/drives?limit=\(min(max(limit, 1), 200))"
        if let before, let encoded = before.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&before=\(encoded)"
            if let beforeId, let encodedId = beforeId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                path += "&beforeId=\(encodedId)"
            }
        }
        let response = try await client.requestData(
            path: path,
            method: "GET",
            headers: ["Authorization": "Bearer \(accessToken)"],
            host: .data
        )
        try validate(response)
        do {
            return try APIClient.makeDateDecoder().decode(DriveHistoryPage.self, from: response.data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func uploadDrives(_ drives: [DriveHistoryInput], accessToken: String) async throws -> [DriveHistoryDTO] {
        let body = try APIClient.makeDateEncoder().encode(DriveHistoryBatch(drives: Array(drives.prefix(100))))
        let response = try await client.requestData(
            path: "api/drives",
            method: "POST",
            body: body,
            headers: [
                "Authorization": "Bearer \(accessToken)",
                "Content-Type": "application/json"
            ],
            host: .data
        )
        try validate(response)
        do {
            struct Response: Decodable { let drives: [DriveHistoryDTO] }
            return try APIClient.makeDateDecoder().decode(Response.self, from: response.data).drives
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func deleteDrive(id: String, accessToken: String) async throws {
        let response = try await client.requestData(
            path: "api/drives/\(id)",
            method: "DELETE",
            headers: ["Authorization": "Bearer \(accessToken)"],
            host: .data
        )
        if response.response.statusCode == 404 { return }
        try validate(response)
    }

    private func validate(_ response: APIClient.HTTPResponseData) throws {
        guard (200...299).contains(response.response.statusCode) else {
            if response.response.statusCode == 401 {
                throw AuthError.from(statusCode: response.response.statusCode, data: response.data)
            }
            throw APIError.httpError(
                statusCode: response.response.statusCode,
                message: APIClient.userFacingErrorMessage(from: response.data)
            )
        }
    }
}

enum DriveHistoryPayloadCodec {
    /// Increment when the shape or privacy guarantees of the cloud payload
    /// change. Sync metadata uses this value to replace legacy server copies
    /// once instead of leaving older, more revealing payloads in storage.
    static let currentVersion = 2
    private static let versionKey = "_roamCloudPayloadVersion"

    static func payload(for drive: RecordedDrive) -> [String: JSONValue] {
        let redactedEvents = drive.score.events.map { event in
            DrivingEvent(
                id: event.id,
                kind: event.kind,
                timestamp: event.timestamp,
                source: event.source,
                coordinate: nil
            )
        }
        let redactedScore = DrivingScore(
            score: drive.score.score,
            duration: drive.score.duration,
            distanceMeters: drive.score.distanceMeters,
            topSpeedMetersPerSecond: drive.score.topSpeedMetersPerSecond,
            events: redactedEvents,
            motionSamples: drive.score.motionSamples,
            dataQuality: drive.score.dataQuality
        )
        let cloudDrive = RecordedDrive(
            id: drive.id,
            startedAt: drive.startedAt,
            score: redactedScore,
            route: [],
            recordingTimeZoneIdentifier: drive.recordingTimeZoneIdentifier,
            experienceSummary: drive.experienceSummary ?? DriveExperienceEngine.summarize(drive: drive),
            plannedRouteContext: drive.plannedRouteContext,
            routeAnalysis: drive.routeAnalysis
        )

        guard let data = try? APIClient.makeDateEncoder().encode(cloudDrive),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              case let .object(encodedPayload) = value else {
            return [:]
        }
        // Keep this metadata outside `RecordedDrive`: synthesized decoding
        // ignores unknown keys, while the sync layer can inspect the version
        // without making it part of the on-device history model.
        var payload = encodedPayload
        payload[versionKey] = .number(Double(currentVersion))
        return payload
    }

    static func version(in payload: [String: JSONValue]) -> Int {
        guard case let .number(value)? = payload[versionKey],
              value.isFinite,
              value.rounded() == value else {
            return 0
        }
        return Int(exactly: value) ?? 0
    }

    static func drive(from payload: [String: JSONValue]) -> RecordedDrive? {
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return try? APIClient.makeDateDecoder().decode(RecordedDrive.self, from: data)
    }
}

enum DriveHistorySyncEngine {
    /// Server records are applied after local records. Because the local model
    /// has no remote revision field, a returned server payload is the only
    /// authoritative conflict version available to this client.
    static func merge(local: [RecordedDrive], remote: [DriveHistoryDTO]) -> [RecordedDrive] {
        var merged: [RecordedDrive] = []
        var indexes: [UUID: Int] = [:]
        for drive in local where indexes[drive.id] == nil {
            indexes[drive.id] = merged.count
            merged.append(drive)
        }

        for dto in remote {
            guard let decoded = decodedRemoteDrive(from: dto) else {
                continue
            }
            let remoteID = decoded.id
            let remoteDrive = decoded.drive

            if let index = indexes[remoteID] {
                merged[index] = reconciled(local: merged[index], remote: remoteDrive)
            } else {
                indexes[remoteID] = merged.count
                merged.append(remoteDrive)
            }
        }
        return merged.sorted { left, right in
            if left.startedAt != right.startedAt {
                return left.startedAt > right.startedAt
            }
            return left.id.uuidString < right.id.uuidString
        }
    }

    /// A fetched remote payload can lag a device that already resolved this
    /// drive's route analysis but has not re-uploaded it yet (the upload
    /// happens later in the same sync cycle). Applying that stale remote
    /// payload as-is would regress the analysis back to `.pending`, which is
    /// exactly the "stuck analyzing" state this exists to prevent — so a
    /// local analysis that is no longer pending always wins over a remote one
    /// that still is.
    private static func reconciled(local: RecordedDrive, remote: RecordedDrive) -> RecordedDrive {
        let routeAnalysis: DriveRouteAnalysis?
        if let localAnalysis = local.routeAnalysis,
           localAnalysis.status != .pending,
           remote.routeAnalysis?.status == .pending {
            routeAnalysis = localAnalysis
        } else {
            routeAnalysis = remote.routeAnalysis
        }

        // Server payloads intentionally contain no coordinates. A response
        // for a drive that already exists on this phone may update its shared
        // fields, but it must never replace the device-only trace or erase the
        // coordinates used by local replay.
        let localEventCoordinates = local.score.events.reduce(into: [UUID: DriveCoordinate]()) { coordinates, event in
            if let coordinate = event.coordinate {
                coordinates[event.id] = coordinate
            }
        }
        let reconciledScore = DrivingScore(
            score: remote.score.score,
            duration: remote.score.duration,
            distanceMeters: remote.score.distanceMeters,
            topSpeedMetersPerSecond: remote.score.topSpeedMetersPerSecond,
            events: remote.score.events.map { event in
                DrivingEvent(
                    id: event.id,
                    kind: event.kind,
                    timestamp: event.timestamp,
                    source: event.source,
                    coordinate: localEventCoordinates[event.id]
                )
            },
            motionSamples: remote.score.motionSamples,
            dataQuality: remote.score.dataQuality
        )
        return RecordedDrive(
            id: remote.id,
            startedAt: remote.startedAt,
            score: reconciledScore,
            route: local.route,
            recordingTimeZoneIdentifier: remote.recordingTimeZoneIdentifier,
            experienceSummary: remote.experienceSummary ?? local.experienceSummary,
            plannedRouteContext: remote.plannedRouteContext,
            routeAnalysis: routeAnalysis
        )
    }

    static func decodedRemoteDrive(from dto: DriveHistoryDTO) -> (id: UUID, drive: RecordedDrive)? {
        guard let remoteID = UUID(uuidString: dto.id),
              let drive = DriveHistoryPayloadCodec.drive(from: dto.payload),
              drive.id == remoteID else {
            return nil
        }
        return (remoteID, drive)
    }
}

@MainActor
final class DriveHistorySyncService: ObservableObject {
    static let shared = DriveHistorySyncService()

    @Published private(set) var state: DriveHistorySyncState = .idle

    private struct SyncMetadata: Codable {
        var syncedDriveIDs: Set<String>
        /// Drives removed locally whose remote deletion hasn't been confirmed
        /// yet. Kept across launches so a delete made offline still reaches
        /// the server, and checked on every sync so a remote copy already
        /// fetched before the delete confirms can't resurrect it.
        var pendingDeletionIDs: Set<String>
        /// The `DriveRouteAnalysisStatus` raw value the server was last known
        /// to hold for a synced drive. A drive is only marked "synced" for a
        /// given route analysis snapshot — once the local status moves past
        /// what's recorded here (e.g. `.pending` resolving to `.available`),
        /// the drive is re-queued for upload rather than treated as up to
        /// date. Without this, a drive uploaded once while still `.pending`
        /// would never send its resolved analysis, and the next fetch would
        /// keep re-merging the stale `.pending` server copy back over the
        /// resolved local one.
        var syncedRouteAnalysisStatus: [String: String]
        /// Cloud payload schema last confirmed for each drive. A missing value
        /// means a pre-redaction payload and schedules a one-time replacement.
        var syncedPayloadVersions: [String: Int]
        var lastSyncedAt: Date?

        init(
            syncedDriveIDs: Set<String>,
            pendingDeletionIDs: Set<String> = [],
            syncedRouteAnalysisStatus: [String: String] = [:],
            syncedPayloadVersions: [String: Int] = [:],
            lastSyncedAt: Date?
        ) {
            self.syncedDriveIDs = syncedDriveIDs
            self.pendingDeletionIDs = pendingDeletionIDs
            self.syncedRouteAnalysisStatus = syncedRouteAnalysisStatus
            self.syncedPayloadVersions = syncedPayloadVersions
            self.lastSyncedAt = lastSyncedAt
        }

        private enum CodingKeys: String, CodingKey {
            case syncedDriveIDs, pendingDeletionIDs, syncedRouteAnalysisStatus, syncedPayloadVersions, lastSyncedAt
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            syncedDriveIDs = try values.decode(Set<String>.self, forKey: .syncedDriveIDs)
            pendingDeletionIDs = try values.decodeIfPresent(Set<String>.self, forKey: .pendingDeletionIDs) ?? []
            syncedRouteAnalysisStatus = try values.decodeIfPresent([String: String].self, forKey: .syncedRouteAnalysisStatus) ?? [:]
            syncedPayloadVersions = try values.decodeIfPresent([String: Int].self, forKey: .syncedPayloadVersions) ?? [:]
            lastSyncedAt = try values.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        }
    }

    /// Remote confirmations belong to the Clerk account that produced them.
    /// Keeping one metadata record per account preserves offline work across
    /// sign-out without letting a later account inherit another account's
    /// tombstones or "already uploaded" markers.
    private struct AccountMetadataStore: Codable {
        var accounts: [String: SyncMetadata]
        var lastActiveAccountID: String?
    }

    private let transport: any DriveHistorySyncTransport
    private let authSession: AuthSessionStore
    private let userDefaults: UserDefaults
    private let legacyMetadataKey = "drive-history-sync-v1"
    private let accountMetadataKey = "drive-history-sync-v2"
    private let retryDelaysNanoseconds: [UInt64]

    private var accountMetadataStore: AccountMetadataStore
    private var activeAccountID: String?
    private var legacyMetadata: SyncMetadata?
    private var metadata: SyncMetadata
    private var pendingDrives: [UUID: RecordedDrive] = [:]
    private var latestLocalDrives: [RecordedDrive] = []
    private var applyLocalDrives: (([RecordedDrive]) -> Void)?
    private var syncTask: Task<Void, Never>?
    private var needsSync = false

    init(
        transport: any DriveHistorySyncTransport = APIClientDriveHistoryTransport(),
        authSession: AuthSessionStore = .shared,
        userDefaults: UserDefaults = .standard,
        retryDelaysNanoseconds: [UInt64] = [1_000_000_000, 4_000_000_000, 16_000_000_000]
    ) {
        self.transport = transport
        self.authSession = authSession
        self.userDefaults = userDefaults
        self.retryDelaysNanoseconds = retryDelaysNanoseconds
        if let data = userDefaults.data(forKey: accountMetadataKey),
           let saved = try? APIClient.makeDateDecoder().decode(AccountMetadataStore.self, from: data) {
            accountMetadataStore = saved
            activeAccountID = saved.lastActiveAccountID
            metadata = saved.lastActiveAccountID
                .flatMap { saved.accounts[$0] }
                ?? SyncMetadata(syncedDriveIDs: [], lastSyncedAt: nil)
            legacyMetadata = nil
        } else {
            accountMetadataStore = AccountMetadataStore(accounts: [:], lastActiveAccountID: nil)
            activeAccountID = nil
            metadata = SyncMetadata(syncedDriveIDs: [], lastSyncedAt: nil)
            if let data = userDefaults.data(forKey: legacyMetadataKey) {
                legacyMetadata = try? APIClient.makeDateDecoder().decode(SyncMetadata.self, from: data)
            } else {
                legacyMetadata = nil
            }
        }
    }

    /// Schedules work and returns immediately. The caller has already written
    /// the drive locally, so a slow or unavailable network can never delay a
    /// drive save or remove it from the on-device history.
    func sync(
        localDrives: [RecordedDrive],
        applyLocalDrives: @escaping ([RecordedDrive]) -> Void
    ) {
        guard authSession.isSignedIn, let accountID = authSession.currentUser?.id else { return }
        activateAccount(accountID)

        latestLocalDrives = localDrives
        self.applyLocalDrives = applyLocalDrives
        let localIDs = Set(localDrives.map(\.id))
        pendingDrives = pendingDrives.filter { localIDs.contains($0.key) }
        for drive in localDrives {
            let idString = drive.id.uuidString
            let notYetSynced = !metadata.syncedDriveIDs.contains(idString)
            // A drive already marked synced still needs re-upload if its route
            // analysis has moved past what the server was last confirmed to
            // hold (most commonly `.pending` resolving to `.available` or
            // `.unavailable` after the drive's first, pending-state upload).
            let routeAnalysisStale = metadata.syncedRouteAnalysisStatus[idString] != drive.routeAnalysis?.status.rawValue
            let payloadStale = metadata.syncedPayloadVersions[idString] != DriveHistoryPayloadCodec.currentVersion
            if notYetSynced || routeAnalysisStale || payloadStale {
                pendingDrives[drive.id] = drive
            }
        }

        needsSync = true
        guard syncTask == nil else { return }

        syncTask = Task { @MainActor [weak self] in
            await self?.runSyncLoop()
        }
    }

    /// Records an intentional user deletion independently of the current
    /// local snapshot. Absence alone is not a deletion signal: history can be
    /// temporarily empty because persistence is unreadable, a load was
    /// interrupted, or the on-device retention window was trimmed.
    func markDriveDeleted(id: UUID) {
        if let accountID = authSession.currentUser?.id {
            activateAccount(accountID)
        }
        // A drive created and deleted before any account has ever been active
        // has no remote copy to delete. Once an account has been active, the
        // last account remains selected so an offline signed-out deletion can
        // still be delivered when that same account returns.
        guard activeAccountID != nil else { return }
        let idString = id.uuidString
        metadata.pendingDeletionIDs.insert(idString)
        metadata.syncedDriveIDs.remove(idString)
        metadata.syncedRouteAnalysisStatus.removeValue(forKey: idString)
        metadata.syncedPayloadVersions.removeValue(forKey: idString)
        pendingDrives.removeValue(forKey: id)
        persistMetadata()
    }

    /// Stops account work without erasing it. Local history intentionally
    /// remains available after sign-out, and account-scoped metadata must also
    /// remain so offline uploads and explicit deletions resume if that account
    /// returns later.
    func didSignOut() {
        syncTask?.cancel()
        syncTask = nil
        needsSync = false
        pendingDrives = [:]
        latestLocalDrives = []
        applyLocalDrives = nil
        persistMetadata()
        state = .idle
    }

    private func activateAccount(_ accountID: String) {
        guard activeAccountID != accountID else { return }

        // Save the previous account before switching the in-memory view.
        persistMetadata()
        activeAccountID = accountID
        accountMetadataStore.lastActiveAccountID = accountID

        if let saved = accountMetadataStore.accounts[accountID] {
            metadata = saved
        } else if let legacyMetadata {
            // The v1 format had no owner. Assign it once to the first account
            // that becomes active after upgrading, then remove the legacy key
            // only after the account-scoped store has been written.
            metadata = legacyMetadata
            self.legacyMetadata = nil
        } else {
            metadata = SyncMetadata(syncedDriveIDs: [], lastSyncedAt: nil)
        }
        persistMetadata()
    }

    private func runSyncLoop() async {
        defer { syncTask = nil }

        while needsSync && !Task.isCancelled {
            needsSync = false
            do {
                try await attemptSyncWithRetry()
            } catch {
                guard !Task.isCancelled, authSession.isSignedIn else { return }
                state = state(for: error)
                return
            }
        }
    }

    private func attemptSyncWithRetry() async throws {
        var retryIndex = 0
        while true {
            do {
                state = .syncing
                try await syncOnce()
                state = .synced
                return
            } catch {
                state = state(for: error)
                guard retryIndex < retryDelaysNanoseconds.count else { throw error }
                let delay = retryDelaysNanoseconds[retryIndex]
                retryIndex += 1
                try await Task.sleep(nanoseconds: delay)
            }
        }
    }

    private func syncOnce() async throws {
        try await pushPendingDeletions()

        var remoteDrives: [DriveHistoryDTO] = []
        var cursor: String?
        var cursorId: String?
        var seenCursors = Set<String>()

        repeat {
            let currentCursor = cursor
            let currentCursorId = cursorId
            let page = try await authSession.performAuthenticated { token in
                try await self.transport.fetchDrives(
                    limit: 200,
                    before: currentCursor,
                    beforeId: currentCursorId,
                    accessToken: token
                )
            }
            remoteDrives.append(contentsOf: page.drives)
            cursor = page.nextCursor
            cursorId = page.nextCursorId
            // The pair is what advances, so the loop guard has to key on both.
        } while cursor != nil && seenCursors.insert("\(cursor!)|\(cursorId ?? "")").inserted

        // Defensive: a deletion pushed above but not yet reflected in this
        // fetch (or one still pending from a prior failed attempt) must not
        // be re-merged back into local history.
        if !metadata.pendingDeletionIDs.isEmpty {
            remoteDrives = remoteDrives.filter { !metadata.pendingDeletionIDs.contains($0.id) }
        }

        let merged = DriveHistorySyncEngine.merge(local: latestLocalDrives, remote: remoteDrives)
        latestLocalDrives = merged
        applyLocalDrives?(merged)

        let remoteStatusByID: [String: String?] = Dictionary(
            uniqueKeysWithValues: remoteDrives.compactMap { dto -> (String, String?)? in
                guard let decoded = DriveHistorySyncEngine.decodedRemoteDrive(from: dto) else { return nil }
                return (decoded.id.uuidString, decoded.drive.routeAnalysis?.status.rawValue)
            }
        )
        metadata.syncedDriveIDs.formUnion(remoteStatusByID.keys)
        for (id, status) in remoteStatusByID {
            metadata.syncedRouteAnalysisStatus[id] = status
        }
        for dto in remoteDrives {
            metadata.syncedPayloadVersions[dto.id] = DriveHistoryPayloadCodec.version(in: dto.payload)
        }
        // A drive can exist remotely and still need re-upload: it only counts
        // as caught up once the server's confirmed route analysis status
        // matches what's local right now. Otherwise a drive that was uploaded
        // once while `.pending` would be dropped here just because *some*
        // version of it already exists remotely, and its resolved analysis
        // would never reach the server.
        pendingDrives = pendingDrives.filter { id, drive in
            let idString = id.uuidString
            guard metadata.syncedDriveIDs.contains(idString) else { return true }
            return metadata.syncedRouteAnalysisStatus[idString] != drive.routeAnalysis?.status.rawValue
                || metadata.syncedPayloadVersions[idString] != DriveHistoryPayloadCodec.currentVersion
        }

        let pendingIDs = Set(pendingDrives.keys)
        let inputs = merged
            .filter { pendingIDs.contains($0.id) }
            .map(Self.input(for:))

        for batchStart in stride(from: 0, to: inputs.count, by: 100) {
            let batch = Array(inputs[batchStart..<min(batchStart + 100, inputs.count)])
            let response = try await authSession.performAuthenticated { token in
                try await self.transport.uploadDrives(batch, accessToken: token)
            }
            let confirmedIDs = response.compactMap { UUID(uuidString: $0.id)?.uuidString }
            metadata.syncedDriveIDs.formUnion(confirmedIDs)
            for idString in confirmedIDs {
                guard let uuid = UUID(uuidString: idString) else { continue }
                metadata.syncedRouteAnalysisStatus[idString] = pendingDrives[uuid]?.routeAnalysis?.status.rawValue
                metadata.syncedPayloadVersions[idString] = DriveHistoryPayloadCodec.currentVersion
            }
            pendingDrives = pendingDrives.filter { !confirmedIDs.contains($0.key.uuidString) }
            persistMetadata()
        }

        metadata.lastSyncedAt = Date()
        persistMetadata()
    }

    private func pushPendingDeletions() async throws {
        guard !metadata.pendingDeletionIDs.isEmpty else { return }
        // Snapshot the set before iterating — the loop removes confirmed IDs
        // from the live set, and iterating a collection while mutating it is
        // fragile even when Swift's value semantics make it safe today.
        let idsToDelete = metadata.pendingDeletionIDs
        for id in idsToDelete {
            try await authSession.performAuthenticated { token in
                try await self.transport.deleteDrive(id: id, accessToken: token)
            }
            metadata.pendingDeletionIDs.remove(id)
            // Also scrub the synced status so a re-uploaded drive with the same
            // UUID (unlikely but possible after a sign-out/sign-in cycle) is
            // not incorrectly treated as already synced.
            metadata.syncedRouteAnalysisStatus.removeValue(forKey: id)
            metadata.syncedPayloadVersions.removeValue(forKey: id)
            persistMetadata()
        }
    }

    private static func input(for drive: RecordedDrive) -> DriveHistoryInput {
        DriveHistoryInput(
            id: drive.id.uuidString,
            startedAt: drive.startedAt,
            durationSeconds: drive.score.duration,
            distanceMeters: drive.score.distanceMeters,
            score: drive.score.score,
            topSpeedMetersPerSecond: drive.score.topSpeedMetersPerSecond,
            eventCount: drive.score.events.count,
            recordingTimeZoneIdentifier: drive.recordingTimeZoneIdentifier,
            payload: DriveHistoryPayloadCodec.payload(for: drive)
        )
    }

    private func persistMetadata() {
        guard let activeAccountID else { return }
        accountMetadataStore.accounts[activeAccountID] = metadata
        accountMetadataStore.lastActiveAccountID = activeAccountID
        guard let data = try? APIClient.makeDateEncoder().encode(accountMetadataStore) else { return }
        userDefaults.set(data, forKey: accountMetadataKey)
        userDefaults.removeObject(forKey: legacyMetadataKey)
    }

    private func state(for error: Error) -> DriveHistorySyncState {
        if error is APIError {
            if case APIError.networkError = error { return .offline }
        }
        if let error = error as? AuthError {
            switch error {
            case .offline, .serverUnavailable, .serviceUnavailable:
                return .offline
            default:
                return .failed(error.localizedDescription)
            }
        }
        if error is URLError { return .offline }
        return .failed(error.localizedDescription)
    }
}
