import Foundation
import SwiftData

/// Main-actor transactions are shared by app, notification, widget, AI and AlarmKit.
/// No suspension is permitted between token validation and persistence.
@MainActor enum ReminderActions {
    struct Runtime: Codable {
        let next: Date; let status: ReminderStatus; let stage: Int; let retry: Date?
        let completed: Date?; let recordID: UUID; let revision: Int; let holidayNote: String?
    }

    @discardableResult static func complete(_ r: Reminder, expectedToken: String, now: Date = Date(),
        context: ModelContext, next: ((Date, Reminder) -> Date)? = nil, source: String = "手动确认") -> UUID? {
        guard accepts(r, token: expectedToken), r.status != .confirmed else { return nil }
        // Pending stage zero identifies the actual scheduled occurrence; a retry/snooze timestamp
        // must never become the fixed recurrence anchor. Relative cycles always use actual completion.
        let reference = r.kind == .cycle && r.recurrenceMode == "fixed" && r.status == .pending && r.retryStage == 0
            ? max(now, r.nextTriggerAt) : now
        let record = ReminderRecord(performedAt: now, type: .confirm, note: source)
        let old = Runtime(next: r.nextTriggerAt, status: r.status, stage: r.retryStage, retry: r.lastRetryAt,
            completed: r.lastCompletedAt, recordID: record.id, revision: r.actionRevision + 1, holidayNote: HolidayNoteStore.note(for: r.id))
        r.records.append(record)
        r.lastCompletedAt = now
        if r.kind == .cycle && r.cycle == .once { r.status = .confirmed }
        else { r.nextTriggerAt = next?(reference, r) ?? ReminderPolicy.nextCycle(after: reference, reminder: r); r.status = .pending }
        r.retryStage = 0; r.lastRetryAt = nil
        r.actionRevision += 1; r.updatedAt = now
        r.undoCompletion = try? JSONEncoder().encode(old)
        guard save(context) else { return nil }
        HolidayNoteStore.setNote(nil, for: r.id)
        return record.id
    }

    static func accepts(_ r: Reminder, token: String?) -> Bool { r.isEnabled && (token == nil || token == r.actionToken) }
    @discardableResult static func snooze(_ r: Reminder, until: Date, expectedToken: String, context: ModelContext) -> Bool {
        guard accepts(r, token: expectedToken), r.status != .confirmed else { return false }
        r.nextTriggerAt = until; r.status = .snoozed
        r.records.append(ReminderRecord(type: .snooze))
        return changed(r, context: context)
    }
    @discardableResult static func skip(_ r: Reminder, expectedToken: String, now: Date = Date(), context: ModelContext,
        next: ((Date, Reminder) -> Date)? = nil) -> Bool {
        guard accepts(r, token: expectedToken), !(r.kind == .cycle && r.cycle == .once) else { return false }
        // Relative cycles restart from the actual skip time. For fixed/date/rule reminders,
        // only an untriggered primary may move the reference into the future; retry/snooze cannot.
        let relative = r.kind == .cycle && r.recurrenceMode == "afterCompletion"
        let reference = !relative && r.status == .pending && r.retryStage == 0 ? max(now, r.nextTriggerAt) : now
        r.nextTriggerAt = next?(reference, r) ?? ReminderPolicy.nextCycle(after: reference, reminder: r)
        r.status = .pending; r.retryStage = 0; r.lastRetryAt = nil
        return changed(r, context: context)
    }
    @discardableResult static func undo(_ r: Reminder, expectedToken: String, context: ModelContext) -> Bool {
        guard accepts(r, token: expectedToken), let data = r.undoCompletion, let old = try? JSONDecoder().decode(Runtime.self, from: data),
              old.revision == r.actionRevision,
              let record = r.records.first(where: { $0.id == old.recordID && $0.type == "confirm" }) else { return false }
        r.records.removeAll { $0.id == old.recordID }; context.delete(record)
        r.nextTriggerAt = old.next; r.status = old.status; r.retryStage = old.stage
        r.lastRetryAt = old.retry; r.lastCompletedAt = old.completed
        guard changed(r, context: context) else { return false }
        HolidayNoteStore.setNote(old.holidayNote, for: r.id)
        return true
    }
    @discardableResult static func changed(_ r: Reminder, context: ModelContext) -> Bool {
        r.actionRevision += 1; r.undoCompletion = nil; r.updatedAt = Date()
        return save(context)
    }
    static func save(_ context: ModelContext) -> Bool {
        do { try context.save(); SyncStore.touchLocalChange(); return true }
        catch { context.rollback(); return false }
    }
}
