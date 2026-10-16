import Foundation

enum RecurrenceMode: String, CaseIterable { case fixed, afterCompletion }
enum ReminderStyle: String, CaseIterable { case gentle, persistent, important }

struct ReminderPolicy: Equatable {
    static let legacyIntervals = [60, 240, 720, 1440]
    var intervals: [Int]
    var attempts: Int
    var quietStart: Int?
    var quietEnd: Int?

    init(intervals: [Int] = legacyIntervals, attempts: Int = 5, quietStart: Int? = nil, quietEnd: Int? = nil) {
        self.intervals = !intervals.isEmpty && intervals.count <= 10 && intervals.allSatisfy { (1...10080).contains($0) }
            ? intervals : Self.legacyIntervals
        self.attempts = (1...10).contains(attempts) ? attempts : 5
        if let s = quietStart, let e = quietEnd, (0...1439).contains(s), (0...1439).contains(e) {
            self.quietStart = s; self.quietEnd = e
        }
    }

    func adjust(_ date: Date, calendar: Calendar = .current) -> Date {
        guard let s = quietStart, let e = quietEnd, s != e else { return date }
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let inside = s < e ? minute >= s && minute < e : minute >= s || minute < e
        guard inside else { return date }
        let end = calendar.date(byAdding: .minute, value: e, to: calendar.startOfDay(for: date)) ?? date
        return s > e && minute >= s ? calendar.date(byAdding: .day, value: 1, to: end) ?? end : end
    }

    func delay(after stage: Int) -> TimeInterval { Double(intervals[min(max(stage - 1, 0), intervals.count - 1)]) * 60 }

    struct CatchUp { let stage: Int; let dueAt: Date; let isOverdue: Bool }
    static func catchUp(_ r: Reminder, now: Date) -> CatchUp {
        let policy = r.policy
        let cap = r.reminderStyle == "gentle" ? 1 : policy.attempts
        var stage = r.retryStage
        var due = policy.adjust(r.nextTriggerAt)
        if r.status == .snoozed && stage >= cap && due <= now { stage = cap - 1 }
        while due <= now && stage < cap {
            stage += 1; due = policy.adjust(due.addingTimeInterval(policy.delay(after: stage)))
        }
        return CatchUp(stage: stage, dueAt: due, isOverdue: stage >= cap)
    }

    static func nextCycle(after date: Date, reminder: Reminder, calendar: Calendar = .current) -> Date {
        let relative = reminder.recurrenceMode == RecurrenceMode.afterCompletion.rawValue
        let anchor = relative ? date : reminder.firstTriggerAt
        if anchor > date && !relative { return anchor }
        let months: Int? = reminder.cycle == .monthly ? 1 : reminder.cycle == .quarterly ? 3 : reminder.cycle == .yearly ? 12 : nil
        if let months {
            let anchorDay = calendar.component(.day, from: anchor)
            for step in 1...1200 {
                var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: anchor)
                components.day = 1
                let start = calendar.date(from: components) ?? anchor
                guard let month = calendar.date(byAdding: .month, value: months * step, to: start),
                      let range = calendar.range(of: .day, in: .month, for: month) else { continue }
                if !relative && reminder.cycle == .yearly && calendar.component(.month, from: anchor) == 2 && anchorDay == 29 && range.count < 29 { continue }
                var target = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: month)
                target.day = min(anchorDay, range.count)
                let next = calendar.date(from: target) ?? month
                if next > date { return next }
            }
        }
        let days = max(1, reminder.effectiveDays)
        var steps = relative ? 1 : max(0, calendar.dateComponents([.day], from: anchor, to: date).day ?? 0) / days
        var next = calendar.date(byAdding: .day, value: steps * days, to: anchor) ?? anchor
        while next <= date { steps += 1; next = calendar.date(byAdding: .day, value: steps * days, to: anchor) ?? date.addingTimeInterval(86400) }
        return next
    }

    enum DeliveryKind: Int { case primary, retry, advance }
    struct Delivery {
        let reminderID: UUID
        let token: String
        let title: String
        let body: String
        let date: Date
        let kind: DeliveryKind
        let index: Int
        let important: Bool
        var identifier: String { "reminder-\(reminderID)-\(kind.rawValue)-\(index)" }
    }

    static func deliveryDates(for r: Reminder, now: Date) -> [Date] {
        guard r.isEnabled, r.status != .confirmed, r.status != .overdue else { return [] }
        let p = r.policy
        let cap = r.reminderStyle == "gentle" ? 1 : p.attempts
        // An explicit snooze is a requested delivery even after gentle's automatic attempt is used.
        guard r.retryStage < cap || r.status == .snoozed else { return [] }
        var dates = [p.adjust(r.nextTriggerAt)]
        var stage = r.retryStage + 1
        while stage < cap { dates.append(p.adjust(dates.last!.addingTimeInterval(p.delay(after: stage)))); stage += 1 }
        return dates.filter { $0 > now }
    }

    static func allocate(_ reminders: [Reminder], now: Date = Date(), limit: Int = 64) -> [Delivery] {
        var deliveries: [Delivery] = []
        for r in reminders {
            for (index, date) in deliveryDates(for: r, now: now).enumerated() {
                deliveries.append(Delivery(reminderID: r.id, token: r.actionToken, title: r.title,
                    body: r.note.isEmpty ? "该完成了，点确认或稍后" : r.note, date: date,
                    kind: index == 0 ? .primary : .retry, index: index, important: r.reminderStyle == "important" && r.useAlarmKit))
            }
            if r.kind == .date && r.isEnabled && r.status == .pending && r.retryStage == 0 {
                for day in 1...max(1, min(r.advanceDays, 14)) where day <= r.advanceDays {
                    guard let raw = Calendar.current.date(byAdding: .day, value: -day, to: r.nextTriggerAt) else { continue }
                    let date = r.policy.adjust(raw)
                    if date > now { deliveries.append(Delivery(reminderID: r.id, token: r.actionToken, title: r.title,
                        body: "还有 \(day) 天：\(r.title)", date: date, kind: .advance, index: day, important: false)) }
                }
            }
        }
        return Array(deliveries.sorted {
            let p0 = $0.kind == .primary ? 0 : 1, p1 = $1.kind == .primary ? 0 : 1
            if p0 != p1 { return p0 < p1 }
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.identifier < $1.identifier
        }.prefix(max(0, limit)))
    }
}

enum LegacyPolicyStore {
    static func isCritical(_ id: UUID) -> Bool { UserDefaults.standard.dictionary(forKey: "critical_reminders")?[id.uuidString] as? Bool ?? false }
    static func setCritical(_ value: Bool, for id: UUID) {
        var dict = UserDefaults.standard.dictionary(forKey: "critical_reminders") ?? [:]
        dict[id.uuidString] = value; UserDefaults.standard.set(dict, forKey: "critical_reminders")
    }
    static func migrate(_ r: Reminder) {
        guard !r.policyMigrated else { return }
        if isCritical(r.id) { r.reminderStyle = "important" }
        let start = "quiet_hours_\(r.id.uuidString)_start", end = "quiet_hours_\(r.id.uuidString)_end"
        if UserDefaults.standard.object(forKey: start) != nil && UserDefaults.standard.object(forKey: end) != nil {
            let p = ReminderPolicy(quietStart: UserDefaults.standard.integer(forKey: start), quietEnd: UserDefaults.standard.integer(forKey: end))
            r.quietStartMinute = p.quietStart; r.quietEndMinute = p.quietEnd
        }
        r.policyMigrated = true
    }
}
