import Foundation
import SwiftData

/// 提醒引擎：周期/日期计算、确认/稍后逻辑、递增重试、提前预告
@MainActor
final class ReminderEngine: ObservableObject {
    static let shared = ReminderEngine()

    private var modelContext: ModelContext?

    func configure(with context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - 计算下一次触发时间

    /// 计算下一次「正式提醒」（D-day）的触发时间
    func calculateNextTrigger(after confirmedDate: Date, reminder: Reminder) -> Date {
        switch reminder.kind {
        case .cycle:
            return calculateNextCycleTrigger(after: confirmedDate, reminder: reminder)
        case .date:
            return calculateNextDateTrigger(from: confirmedDate, reminder: reminder)
        case .rule:
            return calculateNextRuleTrigger(from: confirmedDate, reminder: reminder)
        }
    }

    // MARK: - 判断提醒是否在指定日期触发（日历标记 / 点击某天查看任务）

    /// 判断提醒在指定公历日期（year/month/day，month 1-based）是否触发
    nonisolated func occursOn(reminder: Reminder, year: Int, month: Int, day: Int) -> Bool {
        switch reminder.kind {
        case .cycle: return occursOnCycle(reminder, year: year, month: month, day: day)
        case .date:  return occursOnDate(reminder, year: year, month: month, day: day)
        case .rule:  return occursOnRule(reminder, year: year, month: month, day: day)
        }
    }

    private nonisolated func weekdayMonday(_ date: Date) -> Int {
        let w = Calendar.current.component(.weekday, from: date) // 1=周日..7=周六
        return (w + 5) % 7 + 1 // 1=周一..7=周日
    }

    private nonisolated func startOfDay(_ y: Int, _ m: Int, _ d: Int) -> Date? {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d
        return Calendar.current.date(from: c)
    }

    private nonisolated func daysBetween(_ a: Date, _ b: Date) -> Int {
        Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
    }

    private nonisolated func occursOnCycle(_ r: Reminder, year: Int, month: Int, day: Int) -> Bool {
        guard let target = startOfDay(year, month, day) else { return false }
        let anchor = r.firstTriggerAt
        let aY = Calendar.current.component(.year, from: anchor)
        let aM = Calendar.current.component(.month, from: anchor)
        let aD = Calendar.current.component(.day, from: anchor)
        guard let aStart = startOfDay(aY, aM, aD) else { return false }

        let aWeekday = weekdayMonday(anchor)
        let tWeekday = weekdayMonday(target)
        let diff = daysBetween(aStart, target)
        guard diff >= 0 else { return false }

        // 短月对齐：锚点日 31 在 2 月触发日被回钳到 28/29，日历标记用同一规则
        func effectiveAnchorDay(_ y: Int, _ m: Int, _ aD: Int) -> Int {
            guard let first = startOfDay(y, m, 1),
                  let range = Calendar.current.range(of: .day, in: .month, for: first) else { return aD }
            return min(aD, range.count)
        }

        switch r.cycle {
        case .once:      return diff == 0
        case .daily:     return true
        case .weekly:    return tWeekday == aWeekday
        case .biweekly:  return tWeekday == aWeekday && diff % 14 == 0
        case .monthly:   return day == effectiveAnchorDay(year, month, aD)
        case .quarterly: return day == effectiveAnchorDay(year, month, aD) && (month - aM) % 3 == 0
        case .yearly:
            // 2/29 锚点：非闰年 2 月调度侧跳过（不触发）→ 这里也不显示，避免「显示但不响」幻影
            if aD == 29 && aM == 2 {
                guard month == 2 else { return false }
                let isLeap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
                return isLeap && day == 29
            }
            return month == aM && day == effectiveAnchorDay(year, month, aD)
        case .custom:
            let cd = r.customDays
            // P2 修复：每 N 天提醒不能要求同星期 —— 每 3 天第 2 次起星期必然不同，
            // 加 weekday 条件会让日历格/智能清单/点日期全部漏显（调度按纯天数累加正常）。
            return cd > 0 && diff % cd == 0
        }
    }

    private nonisolated func occursOnDate(_ r: Reminder, year: Int, month: Int, day: Int) -> Bool {
        switch r.dateType {
        case .solarBirthday, .none:
            return month == r.targetMonth && day == r.targetDay
        case .lunarBirthday:
            guard let solar = LunarCalendar.lunarToSolar(lunarYear: year, lunarMonth: r.targetMonth, lunarDay: r.targetDay) else { return false }
            let cm = Calendar.current.component(.month, from: solar)
            let cd = Calendar.current.component(.day, from: solar)
            let cy = Calendar.current.component(.year, from: solar)
            return cy == year && cm == month && cd == day
        case .holiday:
            guard let holiday = HolidayService.find(by: r.holidayID ?? "") else { return false }
            guard let next = HolidayService.nextDate(for: holiday, from: startOfDay(year, month, day) ?? Date()) else { return false }
            let cy = Calendar.current.component(.year, from: next)
            let cm = Calendar.current.component(.month, from: next)
            let cd = Calendar.current.component(.day, from: next)
            return cy == year && cm == month && cd == day
        }
    }

    private nonisolated func occursOnRule(_ r: Reminder, year: Int, month: Int, day: Int) -> Bool {
        guard let target = ruleDateInMonth(
            year: year, month: month,
            week: r.ruleWeek.rawValue, weekday: r.ruleWeekday.rawValue,
            hour: r.reminderHour, minute: r.reminderMinute
        ) else { return false }
        let cy = Calendar.current.component(.year, from: target)
        let cm = Calendar.current.component(.month, from: target)
        let cd = Calendar.current.component(.day, from: target)
        return cy == year && cm == month && cd == day
    }

    // MARK: 规则类：每月/每季度/每年 第N周周X

    /// 计算下一个「第 N 周周 X」的日期，例如每季度第 2 周周二
    private func calculateNextRuleTrigger(from after: Date, reminder: Reminder) -> Date {
        nextRuleDate(
            period: reminder.rulePeriod,
            week: reminder.ruleWeek.rawValue,
            weekday: reminder.ruleWeekday.rawValue,
            hour: reminder.reminderHour,
            minute: reminder.reminderMinute,
            from: after
        )
    }

    /// 规则提醒的首次触发时间（创建时使用）
    func nextRuleDate(
        period: RulePeriod,
        week: Int,
        weekday: Int,
        hour: Int,
        minute: Int,
        from: Date = Date()
    ) -> Date {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: from)
        let year = comps.year ?? 2026
        let month = comps.month ?? 1

        let monthStep: Int
        switch period {
        case .monthly: monthStep = 1
        case .yearly: monthStep = 12
        case .quarterly: monthStep = 3
        }

        // 当前周期单位的起始月
        let startMonth: Int
        switch period {
        case .monthly: startMonth = month
        case .yearly: startMonth = 1
        case .quarterly: startMonth = ((month - 1) / 3) * 3 + 1 // 1/4/7/10 月
        }

        // 从当前周期开始向后找（最多 16 步）
        for i in 0...16 {
            let candMonthIndex = startMonth + i * monthStep
            let candYear = year + (candMonthIndex - 1) / 12
            let candMonth = (candMonthIndex - 1) % 12 + 1

            guard let target = ruleDateInMonth(
                year: candYear,
                month: candMonth,
                week: week,
                weekday: weekday,
                hour: hour,
                minute: minute
            ), target > from else { continue }

            return target
        }
        // fallback：明天
        return calendar.date(byAdding: .day, value: 1, to: from) ?? from
    }

    /// 计算某年某月「第 week 周的 weekday」的日期；该月无此周次则返回 nil
    private nonisolated func ruleDateInMonth(
        year: Int, month: Int, week: Int, weekday: Int, hour: Int, minute: Int
    ) -> Date? {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // 周一为一周开始

        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        comps.hour = hour
        comps.minute = minute
        guard let firstOfMonth = calendar.date(from: comps) else { return nil }

        // Calendar.weekday: 1=周日...7=周六 → 转成 周一=1...周日=7
        let firstDayWeek = (calendar.component(.weekday, from: firstOfMonth) + 5) % 7 + 1
        let day = 1 + ((weekday - firstDayWeek + 7) % 7) + (week - 1) * 7

        guard let range = calendar.range(of: .day, in: .month, for: firstOfMonth),
              day <= range.count else { return nil }

        return calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth)
    }

    // MARK: 周期类：锚点法

    private func calculateNextCycleTrigger(after confirmedDate: Date, reminder: Reminder) -> Date {
        let anchor = reminder.firstTriggerAt
        let days = reminder.effectiveDays
        guard days > 0 else { return anchor }

        switch reminder.cycle {
        case .monthly, .quarterly, .yearly:
            // 按日历月累加，但要把「锚点日号」保持在目标月内：
            // 直接用 date(byAdding:.month) 会漂移（1/31→2/28→3/28 永久停在 28 号），
            // 累加后回钳到「目标月第 anchorDay 天，超出取该月最后一天」。
            // yearly + 2/29（闰日）例外：非闰年 2 月无 29 日 → 跳过该年，下个闰年再触发。
            let amount = reminder.cycle == .monthly ? 1 : (reminder.cycle == .quarterly ? 3 : 12)
            let anchorDay = Calendar.current.component(.day, from: anchor)
            var cursor = anchor
            var attempts = 0
            while cursor <= confirmedDate {
                guard let next = Calendar.current.date(byAdding: .month, value: amount, to: cursor) else { break }
                let nextDay = Calendar.current.component(.day, from: next)
                let maxDay = Calendar.current.range(of: .day, in: .month, for: next)?.count ?? nextDay
                if anchorDay <= maxDay {
                    // 目标月有 anchorDay 天（含 2/29 闰年）→ 设回锚点日
                    cursor = Calendar.current.date(bySetting: .day, value: anchorDay, of: next) ?? next
                } else if reminder.cycle == .yearly && anchorDay == 29 {
                    // 非闰年 2 月没有 29 日 → 保留 2/28 继续累加（下轮跳 12 个月）
                    cursor = next
                } else {
                    // 目标月不足 anchorDay 天（如 2 月）→ 钳到月末
                    cursor = Calendar.current.date(bySetting: .day, value: maxDay, of: next) ?? next
                }
                attempts += 1
                if attempts > 1200 { break } // 防御：最多推进 100 年
            }
            // yearly + 2/29：主循环可能停在「非闰年的 2/28」就退出（cursor > confirmed），
            // 必须继续逐月 +12 找到下一个闰年 2/29，否则提醒永久漂移到 28 号
            if reminder.cycle == .yearly && anchorDay == 29,
               Calendar.current.component(.day, from: cursor) != 29 {
                var leapCursor = cursor
                var leapAttempts = 0
                while Calendar.current.component(.day, from: leapCursor) != 29 {
                    guard let nxt = Calendar.current.date(byAdding: .month, value: 12, to: leapCursor) else { break }
                    leapCursor = nxt
                    let maxD = Calendar.current.range(of: .day, in: .month, for: leapCursor)?.count ?? 28
                    if maxD >= 29 {
                        leapCursor = Calendar.current.date(bySetting: .day, value: 29, of: leapCursor) ?? leapCursor
                        break
                    }
                    leapAttempts += 1
                    if leapAttempts > 1200 { break }
                }
                cursor = leapCursor
            }
            return cursor
        default:
            let elapsedDays = Calendar.current.dateComponents([.day], from: anchor, to: confirmedDate).day ?? 0
            let cyclesPassed = (elapsedDays / days) + 1
            return Calendar.current.date(byAdding: .day, value: cyclesPassed * days, to: anchor) ?? confirmedDate
        }
    }

    // MARK: 日期类：下一次目标日期

    /// 日期类提醒算不出来时的兜底：必须是「远未来」而不是 `after`(≈现在)。
    /// 如果兜底成 now，提醒会在创建后立刻/1 分钟内误触发，这是 v1.8.1 的已知 bug。
    private func farFutureFallback(from after: Date) -> Date {
        Calendar.current.date(byAdding: .year, value: 1, to: after)
            ?? after.addingTimeInterval(365 * 24 * 3600)
    }

    private func calculateNextDateTrigger(from after: Date, reminder: Reminder) -> Date {
        let calendar = Calendar.current

        // 月/日非法（AI 漏传或数据损坏）时不要退化成「马上响」，
        // 推到一年后，等用户在详情页补全真实日期。
        let monthValid = (1...12).contains(reminder.targetMonth)
        let dayValid = (1...31).contains(reminder.targetDay)
        if reminder.dateType != .holiday, !(monthValid && dayValid) {
            return farFutureFallback(from: after)
        }

        switch reminder.dateType {
        case .solarBirthday, .none:
            // 公历固定日期
            var comps = calendar.dateComponents([.year], from: after)
            comps.month = reminder.targetMonth
            comps.day = reminder.targetDay
            comps.hour = reminder.reminderHour
            comps.minute = reminder.reminderMinute

            if let thisYear = calendar.date(from: comps), thisYear > after {
                return thisYear
            }
            // 已过→明年
            comps.year = (comps.year ?? 2026) + 1
            return calendar.date(from: comps) ?? farFutureFallback(from: after)

        case .lunarBirthday:
            // 农历生日→转换为公历
            if let solar = LunarCalendar.nextLunarBirthday(
                month: reminder.targetMonth,
                day: reminder.targetDay,
                from: after
            ) {
                var comps = calendar.dateComponents([.year, .month, .day], from: solar)
                comps.hour = reminder.reminderHour
                comps.minute = reminder.reminderMinute
                return calendar.date(from: comps) ?? solar
            }
            // fallback: 直接用公历
            var fallback = calendar.dateComponents([.year], from: after)
            fallback.month = reminder.targetMonth
            fallback.day = reminder.targetDay
            fallback.hour = reminder.reminderHour
            fallback.minute = reminder.reminderMinute
            if let fb = calendar.date(from: fallback), fb > after { return fb }
            fallback.year = (fallback.year ?? 2026) + 1
            return calendar.date(from: fallback) ?? farFutureFallback(from: after)

        case .holiday:
            // 节假日
            if let holiday = HolidayService.find(by: reminder.holidayID ?? ""),
               let nextDate = HolidayService.nextDate(for: holiday, from: after) {
                var comps = calendar.dateComponents([.year, .month, .day], from: nextDate)
                comps.hour = reminder.reminderHour
                comps.minute = reminder.reminderMinute
                return calendar.date(from: comps) ?? nextDate
            }
            // fallback: 公历
            var fb = calendar.dateComponents([.year], from: after)
            fb.month = reminder.targetMonth
            fb.day = reminder.targetDay
            fb.hour = reminder.reminderHour
            fb.minute = reminder.reminderMinute
            if let d = calendar.date(from: fb), d > after { return d }
            fb.year = (fb.year ?? 2026) + 1
            return calendar.date(from: fb) ?? farFutureFallback(from: after)
        }
    }

    // MARK: - 确认完成

    func confirmReminder(_ reminder: Reminder) {
        guard let context = modelContext else { return }

        let now = Date()

        let record = ReminderRecord(type: "confirm", note: "手动确认")
        reminder.records.append(record)

        // v1.8.7 任务⑥: 埋点
        TelemetryService.logEvent("confirm", params: ["kind": reminder.kind.rawValue, "cycle": reminder.cycle.rawValue])

        // 一次性提醒：确认后直接归档为「已完成」，不再前进周期
        if reminder.kind == .cycle && reminder.cycle == .once {
            reminder.status = .confirmed
            reminder.retryStage = 0
            reminder.lastRetryAt = nil
            reminder.updatedAt = now
            try? context.save()
            SyncStore.touchLocalChange()
            Task { await NotificationManager.shared.removePendingNotification(for: reminder.id) }
            print("[ReminderEngine] 一次性提醒已完成: \(reminder.title)")
            return
        }

        // 计算下一次触发
        reminder.nextTriggerAt = calculateNextTrigger(after: now, reminder: reminder)

        // 重置状态
        reminder.status = .pending
        reminder.retryStage = 0
        reminder.lastRetryAt = nil
        reminder.updatedAt = now

        try? context.save()
        SyncStore.touchLocalChange()

        // 重新调度通知
        Task {
            await scheduleAllNotifications(for: reminder)
        }

        print("[ReminderEngine] 已确认: \(reminder.title), 下次: \(reminder.nextTriggerAt)")
    }

    // MARK: - 重新打开（已完成 → 等待中）

    /// 把已完成的提醒重新打开：若它的下次触发时间已过期，则重新计算下一次触发
    func reopenReminder(_ reminder: Reminder) {
        guard let context = modelContext else { return }

        let now = Date()
        if reminder.nextTriggerAt <= now {
            reminder.nextTriggerAt = calculateNextTrigger(after: now, reminder: reminder)
        }
        reminder.status = .pending
        reminder.retryStage = 0
        reminder.lastRetryAt = nil
        reminder.updatedAt = now

        try? context.save()
        SyncStore.touchLocalChange()

        Task {
            await scheduleAllNotifications(for: reminder)
        }

        print("[ReminderEngine] 重新打开: \(reminder.title), 下次: \(reminder.nextTriggerAt)")
    }

    // MARK: - 稍后提醒

    func snoozeReminder(_ reminder: Reminder) {
        guard let context = modelContext else { return }

        let now = Date()
        let snoozeAt = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now

        let record = ReminderRecord(type: "snooze", note: "推迟15分钟")
        reminder.records.append(record)

        reminder.nextTriggerAt = snoozeAt
        reminder.status = .snoozed
        reminder.updatedAt = now

        try? context.save()
        SyncStore.touchLocalChange()

        Task {
            await NotificationManager.shared.scheduleNotification(for: reminder, badgeCount: self.unconfirmedCount())
        }

        print("[ReminderEngine] 已推迟: \(reminder.title)")
    }

    // MARK: - 递增重试

    func escalateRetry(_ reminder: Reminder) {
        guard let context = modelContext else { return }

        let now = Date()
        reminder.retryStage = min(reminder.retryStage + 1, 5)
        reminder.lastRetryAt = now

        let nextDelay: TimeInterval
        switch reminder.retryStage {
        case 1:  nextDelay = 3600
        case 2:  nextDelay = 14400
        case 3:  nextDelay = 43200
        case 4:  nextDelay = 86400
        default: nextDelay = 86400
        }

        reminder.nextTriggerAt = Date(timeIntervalSinceNow: nextDelay)

        if reminder.retryStage >= 5 {
            reminder.status = .overdue
        } else {
            reminder.status = .active
        }

        reminder.updatedAt = now

        let record = ReminderRecord(type: "trigger", note: Localized("重试阶段 %d", reminder.retryStage))
        reminder.records.append(record)

        try? context.save()
        SyncStore.touchLocalChange()

        Task {
            await NotificationManager.shared.scheduleNotification(for: reminder, badgeCount: self.unconfirmedCount())
        }

        print("[ReminderEngine] 递增重试: \(reminder.title) 阶段 \(reminder.retryStage)")
    }

    // MARK: - 安排全部通知（日期类：提前预告 + D-day）

    /// 当前未确认（待处理）提醒数量，用于设置角标
    func unconfirmedCount() -> Int {
        guard let context = modelContext else { return 0 }
        let all = (try? context.fetch(FetchDescriptor<Reminder>())) ?? []
        return all.filter { $0.status != .confirmed }.count
    }

    func scheduleAllNotifications(for reminder: Reminder) async {
        // 先清除旧通知
        await NotificationManager.shared.removePendingNotification(for: reminder.id)

        guard reminder.isEnabled else { return }

        if reminder.kind == .date {
            // 日期类：安排提前预告通知 + D-day 通知
            await scheduleAdvanceNotifications(reminder: reminder)
        }

        // D-day 通知（带确认/稍后按钮）；角标用真实未确认数量
        let count = unconfirmedCount()
        try? await NotificationManager.shared.addDdayNotification(for: reminder, badgeCount: count)
    }

    /// 日期类的提前预告通知
    private func scheduleAdvanceNotifications(reminder: Reminder) async {
        let calendar = Calendar.current
        // 上限 14：iOS pending 通知上限 64 条/App，30 天预告 ×3 个提醒就会超限被静默丢弃
        let advanceDays = min(max(reminder.advanceDays, 0), 14)

        guard advanceDays > 0 else { return }

        // 从 D-day 往前推
        var triggerComponents = calendar.dateComponents([.year, .month, .day], from: reminder.nextTriggerAt)
        triggerComponents.hour = reminder.reminderHour
        triggerComponents.minute = reminder.reminderMinute

        guard let dDay = calendar.date(from: triggerComponents) else { return }

        for daysBefore in 1...advanceDays {
            guard let advanceDate = calendar.date(byAdding: .day, value: -daysBefore, to: dDay),
                  advanceDate > Date() else { continue }

            let content: String
            if daysBefore == 1 {
                content = Localized("提醒：明天就是「%@」了，别忘了提前准备哦！", reminder.title)
            } else {
                content = Localized("提醒：还有 %d 天就是「%@」了", daysBefore, reminder.title)
            }

            await NotificationManager.shared.scheduleAdvanceNotification(
                for: reminder,
                at: advanceDate,
                daysBefore: daysBefore,
                body: content
            )
        }
    }

    // MARK: - 启动时检查遗漏

    func checkMissedReminders(reminders: [Reminder]) async {
        let now = Date()
        for reminder in reminders {
            guard reminder.isEnabled else { continue }
            guard reminder.status != .confirmed else { continue }
            guard reminder.nextTriggerAt <= now else { continue }

            // 过期未触发：自动推进到下一次触发时间并重新调度。
            // 这样周期提醒即使用户未点「确认完成」也会继续滚动，
            // 不会再每次打开 App 都对旧日期误响。
            if reminder.cycle == .once {
                // 一次性提醒过期未确认 → 标记逾期归档，不再推进/重排：
                // calculateNextTrigger 对 once 会返回过去的锚点，若推进则每次启动立即重弹
                reminder.status = .overdue
                reminder.updatedAt = now
                try? modelContext?.save()
                SyncStore.touchLocalChange()
                print("[ReminderEngine] 一次性提醒已逾期归档: \(reminder.title)")
                continue
            }
            reminder.nextTriggerAt = calculateNextTrigger(after: now, reminder: reminder)
            reminder.status = .pending
            reminder.retryStage = 0
            reminder.lastRetryAt = nil
            reminder.updatedAt = now

            try? modelContext?.save()
            SyncStore.touchLocalChange()

            await scheduleAllNotifications(for: reminder)
            print("[ReminderEngine] 过期提醒已自动推进: \(reminder.title)")
        }
    }
}
