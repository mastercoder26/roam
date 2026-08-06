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

    init(drives: [DriveHistoryDTO], nextCursor: String?) {
        self.drives = drives
        self.nextCursor = nextCursor
    }
}

private struct DriveHistoryBatch: Encodable {
    let drives: [DriveHistoryInput]
}

@MainActor
protocol DriveHistorySyncTransport {
    func fetchDrives(limit: Int, before: String?, accessToken: String) async throws -> DriveHistoryPage
    func uploadDrives(_ drives: [DriveHistoryInput], accessToken: String) async throws -> [DriveHistoryDTO]
}

struct APIClientDriveHistoryTransport: DriveHistorySyncTransport {
    let client: APIClient

    nonisolated init(client: APIClient = APIClient()) {
        self.client = client
    }

    func fetchDrives(limit: Int, before: String?, accessToken: String) async throws -> DriveHistoryPage {
        var path = "api/drives?limit=\(min(max(limit, 1), 200))"
        if let before, let encoded = before.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&before=\(encoded)"
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
    static func payload(for drive: RecordedDrive) -> [String: JSONValue] {
        guard let data = try? APIClient.makeDateEncoder().encode(drive),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              case let .object(payload) = value else {
            return [:]
        }
        return payload
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
            let drive = decoded.drive

            if let index = indexes[remoteID] {
                merged[index] = drive
            } else {
                indexes[remoteID] = merged.count
                merged.append(drive)
            }
        }
        return merged
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
        var lastSyncedAt: Date?
    }

    private let transport: any DriveHistorySyncTransport
    private let authSession: AuthSessionStore
    private let userDefaults: UserDefaults
    private let metadataKey = "drive-history-sync-v1"
    private let retryDelaysNanoseconds: [UInt64]

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
        if let data = userDefaults.data(forKey: metadataKey),
           let saved = try? APIClient.makeDateDecoder().decode(SyncMetadata.self, from: data) {
            metadata = saved
        } else {
            metadata = SyncMetadata(syncedDriveIDs: [], lastSyncedAt: nil)
        }
    }

    /// Schedules work and returns immediately. The caller has already written
    /// the drive locally, so a slow or unavailable network can never delay a
    /// drive save or remove it from the on-device history.
    func sync(
        localDrives: [RecordedDrive],
        applyLocalDrives: @escaping ([RecordedDrive]) -> Void
    ) {
        guard authSession.isSignedIn else { return }

        latestLocalDrives = localDrives
        self.applyLocalDrives = applyLocalDrives
        let localIDs = Set(localDrives.map(\.id))
        pendingDrives = pendingDrives.filter { localIDs.contains($0.key) }
        for drive in localDrives where !metadata.syncedDriveIDs.contains(drive.id.uuidString) {
            pendingDrives[drive.id] = drive
        }
        needsSync = true
        guard syncTask == nil else { return }

        syncTask = Task { @MainActor [weak self] in
            await self?.runSyncLoop()
        }
    }

    /// Clears only the remote confirmation metadata. Local history intentionally
    /// remains available on the device after sign-out.
    func didSignOut() {
        syncTask?.cancel()
        syncTask = nil
        needsSync = false
        pendingDrives = [:]
        latestLocalDrives = []
        applyLocalDrives = nil
        metadata = SyncMetadata(syncedDriveIDs: [], lastSyncedAt: nil)
        userDefaults.removeObject(forKey: metadataKey)
        state = .idle
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
        var remoteDrives: [DriveHistoryDTO] = []
        var cursor: String?
        var seenCursors = Set<String>()

        repeat {
            let page = try await authSession.performAuthenticated { token in
                try await self.transport.fetchDrives(limit: 200, before: cursor, accessToken: token)
            }
            remoteDrives.append(contentsOf: page.drives)
            cursor = page.nextCursor
        } while cursor != nil && seenCursors.insert(cursor!).inserted

        let merged = DriveHistorySyncEngine.merge(local: latestLocalDrives, remote: remoteDrives)
        latestLocalDrives = merged
        applyLocalDrives?(merged)

        let remoteIDs = remoteDrives.compactMap {
            DriveHistorySyncEngine.decodedRemoteDrive(from: $0)?.id.uuidString
        }
        metadata.syncedDriveIDs.formUnion(remoteIDs)
        pendingDrives = pendingDrives.filter { !metadata.syncedDriveIDs.contains($0.key.uuidString) }

        let pendingIDs = Set(pendingDrives.keys)
        let inputs = merged
            .filter { pendingIDs.contains($0.id) && !metadata.syncedDriveIDs.contains($0.id.uuidString) }
            .map(Self.input(for:))

        for batchStart in stride(from: 0, to: inputs.count, by: 100) {
            let batch = Array(inputs[batchStart..<min(batchStart + 100, inputs.count)])
            let response = try await authSession.performAuthenticated { token in
                try await self.transport.uploadDrives(batch, accessToken: token)
            }
            let confirmedIDs = response.compactMap { UUID(uuidString: $0.id)?.uuidString }
            metadata.syncedDriveIDs.formUnion(confirmedIDs)
            pendingDrives = pendingDrives.filter { !metadata.syncedDriveIDs.contains($0.key.uuidString) }
            persistMetadata()
        }

        metadata.lastSyncedAt = Date()
        persistMetadata()
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
        guard let data = try? APIClient.makeDateEncoder().encode(metadata) else { return }
        userDefaults.set(data, forKey: metadataKey)
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
