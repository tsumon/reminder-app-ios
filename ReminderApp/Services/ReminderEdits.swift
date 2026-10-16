import Foundation
import SwiftData

@MainActor enum ReminderEdits {
    static func cycleAnchor(date: Date, time: Date, editing: Bool, now: Date = Date(), calendar: Calendar = .current) -> Date {
        var parts = calendar.dateComponents([.year, .month, .day], from: date)
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        parts.hour = clock.hour; parts.minute = clock.minute
        let anchor = calendar.date(from: parts) ?? date
        return editing || anchor > now ? anchor : calendar.date(byAdding: .minute, value: 1, to: now) ?? now.addingTimeInterval(60)
    }
    static func scheduleChanged(_ draft: Reminder, from r: Reminder) -> Bool {
        if draft.kind != r.kind || draft.holidayAware != r.holidayAware { return true }
        switch r.kind {
        case .cycle:
            let fields: Set<Calendar.Component> = [.era, .year, .month, .day, .hour, .minute]
            return draft.cycle != r.cycle || (draft.cycle == .custom && draft.customDays != r.customDays) ||
                draft.recurrenceMode != r.recurrenceMode ||
                Calendar.current.dateComponents(fields, from: draft.firstTriggerAt) != Calendar.current.dateComponents(fields, from: r.firstTriggerAt)
        case .rule:
            return draft.rulePeriod != r.rulePeriod || draft.ruleWeek != r.ruleWeek || draft.ruleWeekday != r.ruleWeekday ||
                draft.reminderHour != r.reminderHour || draft.reminderMinute != r.reminderMinute
        case .date:
            return draft.dateType != r.dateType || draft.targetMonth != r.targetMonth || draft.targetDay != r.targetDay ||
                draft.holidayID != r.holidayID || draft.reminderHour != r.reminderHour || draft.reminderMinute != r.reminderMinute
        }
    }
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
                      context: ModelContext, now: Date = Date(), calculate: (Date, Reminder) -> Date) -> Bool {
        guard r.actionToken == expectedToken else { return false }
        r.advanceDays = draft.advanceDays
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
            // Anchor and delivery boundary have separate roles during editing.
            let boundary = max(now, draft.firstTriggerAt.addingTimeInterval(-1))
            if r.kind == .cycle && r.recurrenceMode == "afterCompletion" && r.firstTriggerAt <= now {
                r.recurrenceMode = "fixed"
                r.nextTriggerAt = calculate(boundary, r)
                r.recurrenceMode = draft.recurrenceMode
            } else { r.nextTriggerAt = calculate(boundary, r) }
            r.status = .pending; r.retryStage = 0; r.lastRetryAt = nil
        }
        return ReminderActions.changed(r, context: context)
    }
}
