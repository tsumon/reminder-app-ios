import Foundation
import SwiftData
enum Migration28Values {
    @MainActor static func bytes(_ context: ModelContext) throws -> Data {
        let rows=try context.fetch(FetchDescriptor<Reminder>()).sorted { $0.id.uuidString<$1.id.uuidString }.map { r -> [String:Any] in
            ["id":r.id.uuidString,"mode":r.recurrenceMode,"style":r.reminderStyle,"intervals":r.retryIntervalsMinutes,
             "attempts":r.maxReminderAttempts,"quietStart":r.quietStartMinute ?? -1,"quietEnd":r.quietEndMinute ?? -1,
             "alarm":r.useAlarmKit,"migrated":r.policyMigrated,"revision":r.actionRevision,
             "completed":r.lastCompletedAt?.timeIntervalSince1970 ?? -1,"undo":r.undoCompletion?.base64EncodedString() ?? ""]
        }
        return try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys])
    }
}
