import Foundation
import SwiftData

/// Main-actor transactions are shared by app, notification, widget, AI and AlarmKit.
/// No suspension is permitted between token validation and persistence.
@MainActor enum ReminderActions {
    struct Runtime: Codable {
        let next: Date; let status: ReminderStatus; let stage: Int; let retry: Date?
        let completed: Date?; let recordID: UUID; let revision: Int
    }

    @discardableResult static func complete(_ r: Reminder, expectedToken: String? = nil, now: Date = Date(),
        context: ModelContext, next: ((Date, Reminder) -> Date)? = nil, source: String = "手动确认") -> UUID? {
        guard accepts(r, token: expectedToken), r.status != .confirmed else { return nil }
        // A double tap on an already advanced future occurrence is not a second completion.
        guard r.lastCompletedAt == nil || r.nextTriggerAt <= now || r.status != .pending else { return nil }
        let record = ReminderRecord(performedAt: now, type: .confirm, note: source)
        let old = Runtime(next: r.nextTriggerAt, status: r.status, stage: r.retryStage, retry: r.lastRetryAt,
            completed: r.lastCompletedAt, recordID: record.id, revision: r.actionRevision + 1)
        r.records.append(record)
        r.lastCompletedAt = now
        if r.kind == .cycle && r.cycle == .once { r.status = .confirmed }
        else { r.nextTriggerAt = next?(now, r) ?? ReminderPolicy.nextCycle(after: now, reminder: r); r.status = .pending }
        r.retryStage = 0; r.lastRetryAt = nil
        r.actionRevision += 1; r.updatedAt = now
        r.undoCompletion = try? JSONEncoder().encode(old)
        guard save(context) else { return nil }
        return record.id
    }

    static func accepts(_ r: Reminder, token: String?) -> Bool { r.isEnabled && (token == nil || token == r.actionToken) }
    @discardableResult static func snooze(_ r: Reminder, until: Date, expectedToken: String? = nil, context: ModelContext) -> Bool {
        guard accepts(r, token: expectedToken), r.status != .confirmed else { return false }
        r.nextTriggerAt = until; r.status = .snoozed
        r.records.append(ReminderRecord(type: .snooze))
        return changed(r, context: context)
    }
    @discardableResult static func skip(_ r: Reminder, now: Date = Date(), context: ModelContext,
        next: ((Date, Reminder) -> Date)? = nil) -> Bool {
        guard r.isEnabled, !(r.kind == .cycle && r.cycle == .once) else { return false }
        r.nextTriggerAt = next?(max(now, r.nextTriggerAt), r) ?? ReminderPolicy.nextCycle(after: max(now, r.nextTriggerAt), reminder: r)
        r.status = .pending; r.retryStage = 0; r.lastRetryAt = nil
        return changed(r, context: context)
    }
    @discardableResult static func undo(_ r: Reminder, context: ModelContext) -> Bool {
        guard let data = r.undoCompletion, let old = try? JSONDecoder().decode(Runtime.self, from: data),
              old.revision == r.actionRevision,
              let record = r.records.first(where: { $0.id == old.recordID && $0.type == "confirm" }) else { return false }
        r.records.removeAll { $0.id == old.recordID }; context.delete(record)
        r.nextTriggerAt = old.next; r.status = old.status; r.retryStage = old.stage
        r.lastRetryAt = old.retry; r.lastCompletedAt = old.completed
        return changed(r, context: context)
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
