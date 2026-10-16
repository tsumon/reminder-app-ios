import Foundation
import SwiftData

@MainActor enum ReminderMerge {
    /// Stable identity is searched over the full collection first; legacy fingerprints are only for ID-less items.
    @discardableResult static func apply(_ items: [BackupHelper.BackupItem], current: [Reminder], context: ModelContext) throws -> [Reminder] {
        var all = current
        for item in items {
            let fresh = BackupHelper.makeReminder(from: item)
            let match = all.first { $0.id == fresh.id }
                ?? (item.stableID == nil ? all.first { $0.title == fresh.title && Int($0.nextTriggerAt.timeIntervalSince1970) == Int(fresh.nextTriggerAt.timeIntervalSince1970) } : nil)
            if let r = match { update(fresh, to: r) }
            else { context.insert(fresh); all.append(fresh) }
        }
        do { try context.save() } catch { context.rollback(); throw error }
        return all
    }
    private static func update(_ fresh: Reminder, to r: Reminder) {
        r.title = fresh.title; r.note = fresh.note; r.kind = fresh.kind
        r.cycle = fresh.cycle; r.customDays = fresh.customDays; r.dateType = fresh.dateType
        r.targetMonth = fresh.targetMonth; r.targetDay = fresh.targetDay; r.advanceDays = fresh.advanceDays
        r.reminderHour = fresh.reminderHour; r.reminderMinute = fresh.reminderMinute; r.holidayID = fresh.holidayID
        r.rulePeriod = fresh.rulePeriod; r.ruleWeek = fresh.ruleWeek; r.ruleWeekday = fresh.ruleWeekday
        r.firstTriggerAt = fresh.firstTriggerAt; r.nextTriggerAt = fresh.nextTriggerAt
        r.status = fresh.status; r.priority = fresh.priority; r.isEnabled = fresh.isEnabled; r.holidayAware = fresh.holidayAware
        r.recurrenceMode = fresh.recurrenceMode; r.reminderStyle = fresh.reminderStyle
        r.retryIntervalsMinutes = fresh.retryIntervalsMinutes; r.maxReminderAttempts = fresh.maxReminderAttempts
        r.quietStartMinute = fresh.quietStartMinute; r.quietEndMinute = fresh.quietEndMinute; r.policyMigrated = true
        r.retryStage = fresh.retryStage; r.lastRetryAt = fresh.lastRetryAt; r.lastCompletedAt = fresh.lastCompletedAt
        let existing = Set(r.records.map(\.id))
        r.records.append(contentsOf: fresh.records.filter { !existing.contains($0.id) })
        r.undoCompletion = nil; r.actionRevision += 1; r.updatedAt = fresh.updatedAt
    }
}
