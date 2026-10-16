import Foundation
import SwiftData

@main struct UpgradeCheck {
    @MainActor static func main() throws {
        let container = try ModelContainer(for: Reminder.self, ReminderRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let r = Reminder(title: "Filter", cycle: .daily, firstTriggerAt: now, nextTriggerAt: now)
        context.insert(r)
        try context.save()
        let token = r.actionToken
        precondition(ReminderActions.complete(r, expectedToken: token, now: now, context: context) != nil)
        precondition(ReminderActions.complete(r, expectedToken: token, now: now, context: context) == nil)
        precondition(r.records.filter { $0.type == "confirm" }.count == 1)
        precondition(ReminderActions.undo(r, context: context))
        precondition(r.records.isEmpty && r.nextTriggerAt == now)
        precondition(ReminderActions.skip(r, now: now, context: context))
        precondition(r.records.allSatisfy { $0.type != "confirm" })
        precondition(!ReminderActions.undo(r, context: context))
        r.reminderStyle = "gentle"; r.retryStage = 1; r.status = .snoozed
        precondition(ReminderPolicy.deliveryDates(for: r, now: now.addingTimeInterval(-1)).count == 1)
        let many = (0..<80).map { i in
            Reminder(title: "\(i)", firstTriggerAt: now, nextTriggerAt: now.addingTimeInterval(Double(i + 1) * 60))
        }
        let queue = ReminderPolicy.allocate(many, now: now, limit: 64)
        precondition(queue.count == 64 && queue.allSatisfy { $0.kind == .primary })
        precondition(Set(queue.map(\.reminderID)).count == 64)
        let json = try String(contentsOfFile: "ReminderAppTests/fixtures/protocol_v3.json", encoding: .utf8)
        let imported = BackupHelper.makeReminder(from: BackupHelper.importJSON(json)!.first!)
        precondition(imported.retryStage == 2 && imported.status == .active)
        precondition(imported.recurrenceMode == "afterCompletion" && imported.policy.attempts == 4)
        precondition(imported.policy.intervals == [15, 60, 240])
        let roundtrip = BackupHelper.makeReminder(from: BackupHelper.importJSON(BackupHelper.exportJSON([imported]))!.first!)
        precondition(roundtrip.nextTriggerAt == imported.nextTriggerAt && roundtrip.retryStage == 2)
        try BackupHelper.exportJSON([imported], exportedAt: 1_792_112_400).write(toFile: "ios-export-v3.json", atomically: true, encoding: .utf8)
        precondition(BackupHelper.importJSON(BackupHelper.exportJSON([imported]))!.first!.syncId == "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
        print("Upgrade policy/actions/global allocation/v3 checks passed")
    }
}
