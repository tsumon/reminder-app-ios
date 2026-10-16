import Foundation
import SwiftData

@MainActor enum ReminderEdits {
    /// AI metadata/advance-window updates deliberately preserve the current occurrence and retry state.
    static func applyMetadata(to r: Reminder, expectedToken: String, title: String? = nil, note: String? = nil,
                              advanceDays: Int? = nil, context: ModelContext) -> Bool {
        guard r.actionToken == expectedToken else { return false }
        if let title { r.title = title }
        if let note { r.note = note }
        if let advanceDays { r.advanceDays = max(0, advanceDays) }
        return ReminderActions.changed(r, context: context)
    }

    /// Draft is detached. Compare and save happen without an await, so an external action cannot be overwritten.
    static func apply(_ draft: Reminder, to r: Reminder, expectedToken: String, scheduleChanged: Bool,
                      context: ModelContext, calculate: (Date, Reminder) -> Date) -> Bool {
        guard r.actionToken == expectedToken else { return false }
        r.title = draft.title; r.note = draft.note; r.priority = draft.priority
        r.recurrenceMode = draft.recurrenceMode; r.reminderStyle = draft.reminderStyle
        r.retryIntervalsMinutes = draft.retryIntervalsMinutes; r.maxReminderAttempts = draft.maxReminderAttempts
        r.quietStartMinute = draft.quietStartMinute; r.quietEndMinute = draft.quietEndMinute
        r.policyMigrated = true; r.useAlarmKit = draft.useAlarmKit
        if scheduleChanged {
            r.kind = draft.kind; r.cycle = draft.cycle; r.customDays = draft.customDays
            r.dateType = draft.dateType; r.targetMonth = draft.targetMonth; r.targetDay = draft.targetDay
            r.holidayID = draft.holidayID; r.advanceDays = draft.advanceDays
            r.reminderHour = draft.reminderHour; r.reminderMinute = draft.reminderMinute
            r.rulePeriod = draft.rulePeriod; r.ruleWeek = draft.ruleWeek; r.ruleWeekday = draft.ruleWeekday
            r.holidayAware = draft.holidayAware; r.firstTriggerAt = draft.firstTriggerAt
            r.nextTriggerAt = calculate(draft.firstTriggerAt.addingTimeInterval(-1), r)
            r.status = .pending; r.retryStage = 0; r.lastRetryAt = nil
        }
        return ReminderActions.changed(r, context: context)
    }
}
