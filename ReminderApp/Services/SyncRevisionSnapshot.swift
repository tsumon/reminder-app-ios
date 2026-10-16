import Foundation

/// Immutable wire data and its generation are captured in one non-suspending actor turn.
@MainActor struct SyncRevisionSnapshot {
    let json: String
    let generation: Int
    init(reminders: [Reminder], now: Date = Date()) {
        generation = SyncStore.localVersion
        json = BackupHelper.exportJSON(reminders, exportedAt: now.timeIntervalSince1970)
    }
    func acknowledge() { SyncStore.setLastSyncVersion(generation) }
}
