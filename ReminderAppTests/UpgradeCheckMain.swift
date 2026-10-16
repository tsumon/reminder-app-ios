import Foundation
import SwiftData

@main struct UpgradeCheck {
    @MainActor static func main() async throws {
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
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(_ month: Int, _ day: Int, hour: Int = 9) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
        }
        let monthly = Reminder(title: "Monthly", cycle: .monthly, firstTriggerAt: date(1, 31), nextTriggerAt: date(1, 31))
        precondition(ReminderPolicy.nextCycle(after: date(2, 1), reminder: monthly, calendar: calendar) == date(2, 28))
        precondition(ReminderPolicy.nextCycle(after: date(2, 28), reminder: monthly, calendar: calendar) == date(3, 31))
        monthly.recurrenceMode = "afterCompletion"
        precondition(ReminderPolicy.nextCycle(after: date(2, 5), reminder: monthly, calendar: calendar) == date(3, 5))
        let daily = Reminder(title: "Daily", cycle: .daily, firstTriggerAt: date(1, 1), nextTriggerAt: date(1, 1))
        precondition(ReminderPolicy.nextCycle(after: date(1, 2, hour: 12), reminder: daily, calendar: calendar) == date(1, 3))
        daily.recurrenceMode = "afterCompletion"
        precondition(ReminderPolicy.nextCycle(after: date(1, 2, hour: 12), reminder: daily, calendar: calendar) == date(1, 3, hour: 12))
        let quiet = ReminderPolicy(intervals: [15], attempts: 3, quietStart: 1320, quietEnd: 480)
        precondition(quiet.adjust(date(1, 1, hour: 23), calendar: calendar) == date(1, 2, hour: 8))
        precondition(quiet.adjust(date(1, 2, hour: 3), calendar: calendar) == date(1, 2, hour: 8))
        precondition(ReminderPolicy(intervals: [0], attempts: 0, quietStart: -1, quietEnd: 480).intervals == [60, 240, 720, 1440])
        let runtime = Reminder(title: "Original", cycle: .monthly, firstTriggerAt: date(1, 31), nextTriggerAt: date(2, 2), status: .snoozed, retryStage: 2)
        runtime.lastCompletedAt = date(1, 1); runtime.lastRetryAt = date(2, 1)
        context.insert(runtime); try context.save()
        let editToken = runtime.actionToken
        let draft = Reminder(title: "Renamed", note: "Metadata", cycle: .monthly, firstTriggerAt: date(1, 31), nextTriggerAt: now)
        precondition(ReminderEdits.apply(draft, to: runtime, expectedToken: editToken, scheduleChanged: false, context: context,
            calculate: { _, _ in fatalError("Metadata edit must never recalculate") }))
        precondition(runtime.nextTriggerAt == date(2, 2) && runtime.firstTriggerAt == date(1, 31))
        precondition(runtime.retryStage == 2 && runtime.status == .snoozed && runtime.lastCompletedAt == date(1, 1))
        precondition(!ReminderEdits.apply(draft, to: runtime, expectedToken: editToken, scheduleChanged: false, context: context, calculate: { date, r in ReminderPolicy.nextCycle(after: date, reminder: r) }))
        let chainToken = runtime.actionToken
        let caught = ReminderPolicy.catchUp(runtime, now: runtime.nextTriggerAt.addingTimeInterval(60))
        runtime.retryStage = caught.stage; runtime.nextTriggerAt = caught.dueAt; runtime.status = .active
        precondition(ReminderActions.accepts(runtime, token: chainToken), "Reconciliation must retain pre-scheduled chain tokens")
        precondition(ReminderActions.complete(runtime, expectedToken: chainToken, now: now, context: context) != nil)
        precondition(!ReminderActions.accepts(runtime, token: chainToken))
        _ = ReminderActions.changed(runtime, context: context)
        precondition(!ReminderActions.undo(runtime, context: context), "Edit supersedes undo")
        let once = Reminder(title: "Once", cycle: .once, firstTriggerAt: now, nextTriggerAt: now)
        context.insert(once); try context.save()
        precondition(!ReminderActions.skip(once, context: context))
        precondition(ReminderActions.complete(once, now: now, context: context) != nil && once.status == .confirmed)
        precondition(ReminderActions.complete(once, now: now, context: context) == nil)
        let frozen = SyncRevisionSnapshot(reminders: [runtime])
        let concurrentEdit = Task { @MainActor in
            runtime.title = "Edit during upload"; _ = ReminderActions.changed(runtime, context: context)
        }
        await concurrentEdit.value
        frozen.acknowledge()
        precondition(SyncStore.lastSyncVersion == frozen.generation && SyncStore.localVersion > frozen.generation)
        precondition(BackupHelper.importJSON(frozen.json)!.first!.title == "Renamed", "Snapshot must contain immutable values")
        let json = try String(contentsOfFile: "ReminderAppTests/fixtures/protocol_v3.json", encoding: .utf8)
        let imported = BackupHelper.makeReminder(from: BackupHelper.importJSON(json)!.first!)
        precondition(imported.retryStage == 2 && imported.status == .active)
        precondition(imported.recurrenceMode == "afterCompletion" && imported.policy.attempts == 4)
        precondition(imported.policy.intervals == [15, 60, 240])
        let roundtrip = BackupHelper.makeReminder(from: BackupHelper.importJSON(BackupHelper.exportJSON([imported]))!.first!)
        precondition(roundtrip.nextTriggerAt == imported.nextTriggerAt && roundtrip.retryStage == 2)
        context.insert(imported); try context.save()
        let another = Reminder(title: imported.title, firstTriggerAt: imported.firstTriggerAt, nextTriggerAt: imported.nextTriggerAt)
        context.insert(another); try context.save()
        var sameID = BackupHelper.importJSON(json)!.first!
        sameID.syncId = imported.id.uuidString.uppercased(); sameID.title = "Stable ID wins over earlier fingerprint"
        let merged = try ReminderMerge.apply([sameID], current: [another, imported, runtime], context: context)
        precondition(merged.count == 3 && imported.title == sameID.title && another.title != sameID.title)
        var differentID = sameID; differentID.syncId = UUID().uuidString; differentID.title = another.title
        let mergedDistinct = try ReminderMerge.apply([differentID], current: merged, context: context)
        precondition(mergedDistinct.count == 4, "Distinct known UUIDs cannot collapse by fingerprint")
        precondition(mergedDistinct.contains { $0.id == runtime.id }, "Local-only reminder must survive merge")
        var legacy = sameID; legacy.syncId = nil; legacy.id = nil; legacy.title = another.title
        let mergedLegacy = try ReminderMerge.apply([legacy], current: mergedDistinct, context: context)
        precondition(mergedLegacy.count == 4)
        try BackupHelper.exportJSON([roundtrip], exportedAt: 1_792_112_400).write(toFile: "ios-export-v3.json", atomically: true, encoding: .utf8)
        precondition(BackupHelper.importJSON(BackupHelper.exportJSON([imported]))!.first!.syncId == "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
        let legacyID = UUID()
        let legacyRow = Reminder(id: legacyID, title: "Legacy preferences", firstTriggerAt: now, nextTriggerAt: now)
        LegacyPolicyStore.setCritical(true, for: legacyID)
        UserDefaults.standard.set(1320, forKey: "quiet_hours_\(legacyID.uuidString)_start")
        UserDefaults.standard.set(480, forKey: "quiet_hours_\(legacyID.uuidString)_end")
        LegacyPolicyStore.migrate(legacyRow)
        precondition(legacyRow.reminderStyle == "important" && legacyRow.quietStartMinute == 1320 && legacyRow.quietEndMinute == 480)
        legacyRow.reminderStyle = "gentle"; legacyRow.quietStartMinute = nil; legacyRow.quietEndMinute = nil
        LegacyPolicyStore.migrate(legacyRow)
        precondition(legacyRow.reminderStyle == "gentle" && legacyRow.quietStartMinute == nil, "One-time migration cannot overwrite imported/edited policy")
        LegacyPolicyStore.setCritical(false, for: legacyID)
        UserDefaults.standard.removeObject(forKey: "quiet_hours_\(legacyID.uuidString)_start")
        UserDefaults.standard.removeObject(forKey: "quiet_hours_\(legacyID.uuidString)_end")
        print("Upgrade policy/actions/global allocation/v3 checks passed")
    }
}
