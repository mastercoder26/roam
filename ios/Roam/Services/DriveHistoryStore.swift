import Foundation

/// Manages the persistence and loading of recorded drive history from
/// `UserDefaults`. Extracted from `DriveSessionManager` so drive recording
/// and drive persistence are independent responsibilities.
@MainActor
enum DriveHistoryStore {

    struct LoadResult {
        let drives: [RecordedDrive]
        /// Set when the stored history could not be decoded. While true the
        /// caller must refuse to write — an in-memory list that is empty only
        /// because decoding failed must never replace the real one.
        let isUnreadable: Bool
        /// A status message to display if loading produced a user-visible
        /// condition (quarantined history, for example).
        let statusMessage: String?
    }

    private static let historyKey = "recorded-drives-v1"
    /// Holds a history blob this build could not decode, so it survives for a
    /// later build to recover instead of being overwritten with an empty list.
    private static let quarantinedHistoryKey = "recorded-drives-v1-quarantined"

    /// Loads the full recorded-drive history from `UserDefaults`, quarantining
    /// an unreadable blob rather than losing it silently.
    static func loadRecordedDrives() -> LoadResult {
        guard let data = UserDefaults.standard.data(forKey: historyKey) else {
            return LoadResult(drives: [], isUnreadable: false, statusMessage: nil)
        }
        do {
            let drives = try JSONDecoder().decode([RecordedDrive].self, from: data)
            let backfilled = backfillHistoricalRouteAnalysis(drives)
            return LoadResult(drives: backfilled, isUnreadable: false, statusMessage: nil)
        } catch {
            // Decoding `[RecordedDrive]` is all-or-nothing, so one unreadable
            // element — or one added non-optional field in a new build — used to
            // present as "no history". The next save then wrote that empty list
            // straight over an intact blob, permanently destroying every drive.
            // Keep the original bytes, refuse to write over them, and say so.
            UserDefaults.standard.set(data, forKey: quarantinedHistoryKey)
            return LoadResult(
                drives: [],
                isUnreadable: true,
                statusMessage: "Saved drives could not be opened in this version. They are kept on the device and are not being overwritten."
            )
        }
    }

    /// Saves the current drive list unless the history was flagged unreadable.
    /// Never overwrite a history this build could not read. `drives` is empty
    /// in that case only because decoding failed, and writing it back would
    /// destroy every stored drive irreversibly.
    static func saveRecordedDrives(_ drives: [RecordedDrive], isHistoryUnreadable: Bool) {
        guard !isHistoryUnreadable else { return }
        guard let data = try? JSONEncoder().encode(drives) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }

    /// Older drives are assessed locally from their saved trace. This gives
    /// existing history a transparent score contribution without uploading past
    /// endpoints simply because the app was updated.
    private static func backfillHistoricalRouteAnalysis(_ drives: [RecordedDrive]) -> [RecordedDrive] {
        let updated = drives.map { drive -> RecordedDrive in
            guard drive.routeAnalysis == nil,
                  let localEstimate = DriveRouteAnalysisEngine.estimated(from: drive) else {
                return drive
            }
            return drive.replacingRouteAnalysis(with: localEstimate)
        }
        guard zip(drives, updated).contains(where: { $0.routeAnalysis != $1.routeAnalysis }) else {
            return drives
        }
        // Persist the backfilled drives so the next load doesn't repeat the work.
        if let data = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
        return updated
    }
}
