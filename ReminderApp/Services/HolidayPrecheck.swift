import Foundation
import SwiftData

enum HolidayNoteStore {
    private static let key = "holiday_adjust_notes"
    static func note(for id: UUID) -> String? {
        UserDefaults.standard.dictionary(forKey: key)?[id.uuidString] as? String
    }
    static func setNote(_ note: String?, for id: UUID) {
        var values = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        values[id.uuidString] = note
        UserDefaults.standard.set(values, forKey: key)
    }
}

/// The same post-completion/startup processor reads the real holiday cache and persists the adjustment.
@MainActor enum HolidayPrecheck {
    @discardableResult static func adjust(_ r: Reminder, expectedToken: String, expectedDue: Date,
        now: Date = Date(), context: ModelContext,
        refresh: (Int) async -> Void = { await HolidayRemoteService.refresh(year: $0) }) async -> Bool {
        guard eligible(r, token: expectedToken, due: expectedDue, now: now) else { return false }
        let calendar = Calendar.current
        let year = calendar.component(.year, from: expectedDue)
        await refresh(year)
        guard eligible(r, token: expectedToken, due: expectedDue, now: now) else { return false }
        guard let holiday = Self.status(expectedDue), holiday.isHoliday else { return false }
        var cursor = expectedDue
        var target: Date?
        for _ in 0..<10 {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
            let off = Self.status(cursor)?.isHoliday ?? [1, 7].contains(calendar.component(.weekday, from: cursor))
            if !off { target = cursor; break }
        }
        guard let target, target > now else { return false }
        r.nextTriggerAt = target
        r.updatedAt = Date()
        // This is part of the completed occurrence's automatic scheduling, not a newer user action.
        // Preserve actionRevision and its exact undo snapshot; a subsequent user action still invalidates both.
        do { try context.save() } catch { context.rollback(); return false }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "M月d日"
        HolidayNoteStore.setNote(Localized("因%@放假，已前移至假期前最近工作日（%@）", holiday.name, formatter.string(from: target)), for: r.id)
        SyncStore.touchLocalChange()
        return true
    }
    private static func eligible(_ r: Reminder, token: String, due: Date, now: Date) -> Bool {
        ReminderActions.accepts(r, token: token) && r.status != .confirmed && r.status != .overdue
            && (r.kind == .cycle || r.kind == .rule) && r.nextTriggerAt == due
            && due > now && due.timeIntervalSince(now) <= 31 * 86400 && HolidayNoteStore.note(for: r.id) == nil
    }
    private static func status(_ date: Date) -> HolidayRemoteService.DayStatus? {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return HolidayRemoteService.status(year: c.year!, month: c.month!, day: c.day!)
    }
}
