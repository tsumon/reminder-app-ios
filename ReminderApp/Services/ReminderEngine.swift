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
    private func ruleDateInMonth(
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

        let elapsedDays = Calendar.current.dateComponents([.day], from: anchor, to: confirmedDate).day ?? 0
        let cyclesPassed = (elapsedDays / days) + 1

        return Calendar.current.date(byAdding: .day, value: cyclesPassed * days, to: anchor) ?? confirmedDate
    }

    // MARK: 日期类：下一次目标日期

    private func calculateNextDateTrigger(from after: Date, reminder: Reminder) -> Date {
        let calendar = Calendar.current

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
            return calendar.date(from: comps) ?? after

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
            return calendar.date(from: fallback) ?? after

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
            return calendar.date(from: fb) ?? after
        }
    }

    // MARK: - 确认完成

    func confirmReminder(_ reminder: Reminder) {
        guard let context = modelContext else { return }

        let now = Date()

        let record = ReminderRecord(type: "confirm", note: "手动确认")
        reminder.records.append(record)

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
            await NotificationManager.shared.scheduleNotification(for: reminder)
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

        let record = ReminderRecord(type: "trigger", note: "重试阶段 \(reminder.retryStage)")
        reminder.records.append(record)

        try? context.save()
        SyncStore.touchLocalChange()

        Task {
            await NotificationManager.shared.scheduleNotification(for: reminder)
        }

        print("[ReminderEngine] 递增重试: \(reminder.title) 阶段 \(reminder.retryStage)")
    }

    // MARK: - 安排全部通知（日期类：提前预告 + D-day）

    func scheduleAllNotifications(for reminder: Reminder) async {
        // 先清除旧通知
        await NotificationManager.shared.removePendingNotification(for: reminder.id)

        guard reminder.isEnabled else { return }

        if reminder.kind == .date {
            // 日期类：安排提前预告通知 + D-day 通知
            await scheduleAdvanceNotifications(reminder: reminder)
        }

        // D-day 通知（带确认/稍后按钮）
        await NotificationManager.shared.scheduleNotification(for: reminder)
    }

    /// 日期类的提前预告通知
    private func scheduleAdvanceNotifications(reminder: Reminder) async {
        let calendar = Calendar.current
        let advanceDays = min(max(reminder.advanceDays, 0), 30)

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
                content = "提醒：明天就是「\(reminder.title)」了，别忘了提前准备哦！"
            } else {
                content = "提醒：还有 \(daysBefore) 天就是「\(reminder.title)」了"
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
            guard reminder.status == .pending || reminder.status == .active || reminder.status == .snoozed else { continue }

            if reminder.nextTriggerAt <= now {
                reminder.status = .active
                reminder.updatedAt = now
                try? modelContext?.save()

                await scheduleAllNotifications(for: reminder)
                print("[ReminderEngine] 发现遗漏提醒: \(reminder.title)")
            }
        }
    }
}
