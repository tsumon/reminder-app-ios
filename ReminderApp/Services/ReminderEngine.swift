import Foundation
import SwiftData
import WidgetKit

/// 提醒引擎：周期/日期计算、确认/稍后逻辑、递增重试、提前预告
@MainActor
final class ReminderEngine: ObservableObject {
    static let shared = ReminderEngine()

    private var modelContext: ModelContext?

    func configure(with context: ModelContext) {
        self.modelContext = context
        for r in (try? context.fetch(FetchDescriptor<Reminder>())) ?? [] { LegacyPolicyStore.migrate(r) }
        try? context.save()
    }

    /// 引擎是否已就绪（modelContext 已注入）。冷启动期间 didReceive 据此决定是否立即排空动作队列。
    func token(for id: UUID) -> String? {
        let all = (try? modelContext?.fetch(FetchDescriptor<Reminder>())) ?? []
        return all.first { $0.id == id }?.actionToken
    }

    var isConfigured: Bool { modelContext != nil }

    // MARK: - 冷启动通知动作排空

    /// 排空 NotificationManager 持久化队列中的通知动作（确认/稍后/消除）。
    /// 冷启动：App 经通知按钮拉起时 didReceive 早于视图订阅，动作已入队，待引擎就绪后此处统一处理。
    /// 热启动：scenePhase.active 或 didReceive 引擎已就绪时调用，逻辑一致。
    func drainPendingNotificationActions() {
        guard let context = modelContext else { return }
        let actions = NotificationManager.shared.dequeueAllPendingActions()
        guard !actions.isEmpty else { return }
        for item in actions {
            guard let uuid = UUID(uuidString: item.reminderID) else { continue }
            let descriptor = FetchDescriptor<Reminder>(predicate: #Predicate { $0.id == uuid })
            guard let reminder = try? context.fetch(descriptor).first else {
                print("[ReminderEngine] 排空动作时未找到提醒 \(item.reminderID)，跳过")
                continue
            }
            guard let token = item.token, ReminderActions.accepts(reminder, token: token) else { continue }
            switch item.action {
            case .confirm: confirmReminder(reminder)
            case .snooze:  snoozeReminder(reminder, afterMinutes: 15)
            case .dismiss: escalateRetry(reminder)
            }
            print("[ReminderEngine] 已排空通知动作: \(item.action.rawValue) \(reminder.title)")
        }
    }

    // MARK: - 计算下一次触发时间

    /// 计算下一次「正式提醒」（D-day）的触发时间
    func calculateNextTrigger(after confirmedDate: Date, reminder: Reminder) -> Date {
        let raw: Date
        switch reminder.kind {
        case .cycle:
            raw = calculateNextCycleTrigger(after: confirmedDate, reminder: reminder)
        case .date:
            raw = calculateNextDateTrigger(from: confirmedDate, reminder: reminder)
        case .rule:
            raw = calculateNextRuleTrigger(from: confirmedDate, reminder: reminder)
        }
        // v2.4.10: 避开节假日/周末——触发日落在周六日或法定节假日 → 顺延到下一个工作日
        guard reminder.holidayAware else { return raw }
        return deferToWorkday(raw)
    }

    /// v2.4.10: 顺延到下一个工作日（跳过周六日与法定节假日，保留时分）
    private func deferToWorkday(_ date: Date) -> Date {
        let calendar = Calendar.current
        var cursor = date
        var guardCount = 0
        while guardCount < 30 {
            let comps = calendar.dateComponents([.weekday, .year, .month, .day], from: cursor)
            let isWeekend = comps.weekday == 1 || comps.weekday == 7 // 1=周日 7=周六
            let isHoliday = HolidayRemoteService.status(
                year: comps.year ?? 0,
                month: comps.month ?? 0,
                day: comps.day ?? 0
            )?.isHoliday == true
            if !isWeekend && !isHoliday { return cursor }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor.addingTimeInterval(86400)
            guardCount += 1
        }
        return cursor
    }

    /// v2.1.1: 未来 N 次触发时间预览（详情页展示，验证周期计算是否正确）。
    /// 已完成/已逾期/已停用 → 空；once → 仅当前一次。
    func futureTriggers(for reminder: Reminder, count: Int = 10) -> [Date] {
        guard reminder.status != .confirmed, reminder.status != .overdue, reminder.isEnabled else { return [] }
        if reminder.cycle == .once { return [reminder.nextTriggerAt] }
        var dates: [Date] = []
        var cursor = reminder.nextTriggerAt
        for _ in 0..<count {
            dates.append(cursor)
            let next = calculateNextTrigger(after: cursor, reminder: reminder)
            if next <= cursor { break } // 防死循环
            cursor = next
        }
        return dates
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
        let anchor = r.recurrenceMode == "afterCompletion" ? (r.lastCompletedAt ?? r.firstTriggerAt) : r.firstTriggerAt
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
        if reminder.cycle == .once { return reminder.firstTriggerAt }
        return ReminderPolicy.nextCycle(after: confirmedDate, reminder: reminder)
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

    /// - Parameter source: 记录备注来源。默认「手动确认」；补打卡入口传「补打卡」，
    ///   统计口径仍算 .confirm（计入完成 / 连续天数），只在历史里区分是不是事后补的。
    func confirmReminder(_ reminder: Reminder, source: String = "手动确认") {
        guard let context = modelContext,
              ReminderActions.complete(reminder, context: context, next: calculateNextTrigger, source: source) != nil else { return }
        HolidayAdjustStore.setNote(nil, for: reminder.id)
        NotificationCenter.default.post(name: .reminderConfirmed, object: reminder)
        Task {
            await NotificationManager.shared.removePendingNotification(for: reminder.id)
            await self.scheduleAllNotifications(for: reminder)
        }
    }

    func skipReminder(_ reminder: Reminder) {
        guard let context = modelContext, ReminderActions.skip(reminder, context: context, next: calculateNextTrigger) else { return }
        Task {
            await NotificationManager.shared.removePendingNotification(for: reminder.id)
            await self.scheduleAllNotifications(for: reminder)
        }
    }
    func undoCompletion(_ reminder: Reminder) {
        guard let context = modelContext, ReminderActions.undo(reminder, context: context) else { return }
        Task {
            await NotificationManager.shared.removePendingNotification(for: reminder.id)
            await self.scheduleAllNotifications(for: reminder)
        }
    }

    // MARK: - 重新打开（已完成 → 等待中）

    /// 把已完成的提醒重新打开：若它的下次触发时间已过期，则重新计算下一次触发
    func reopenReminder(_ reminder: Reminder) {
        guard let context = modelContext else { return }

        let now = Date()
        if reminder.nextTriggerAt <= now {
            reminder.nextTriggerAt = calculateNextTrigger(after: now, reminder: reminder)
        }
        // Item 2: 重新打开时清空前移备注
        HolidayAdjustStore.setNote(nil, for: reminder.id)
        reminder.status = .pending
        reminder.retryStage = 0
        reminder.lastRetryAt = nil
        reminder.updatedAt = now

        _ = ReminderActions.changed(reminder, context: context)

        Task {
            await scheduleAllNotifications(for: reminder)
        }

        print("[ReminderEngine] 重新打开: \(reminder.title), 下次: \(reminder.nextTriggerAt)")
    }

    // MARK: - 稍后提醒

    /// 稍后 N 分钟（v2.1.0: 支持任意分钟数，原固定 15 分钟）
    func snoozeReminder(_ reminder: Reminder, afterMinutes minutes: Int) {
        let now = Date()
        let snoozeAt = Calendar.current.date(byAdding: .minute, value: minutes, to: now) ?? now
        snoozeTo(reminder, at: snoozeAt, note: "推迟\(minutes)分钟")
    }

    /// 稍后到明天提醒时刻（reminderHour:reminderMinute；已过则顺延一天）
    func snoozeReminderTomorrow(_ reminder: Reminder) {
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = reminder.reminderHour
        comps.minute = reminder.reminderMinute
        comps.second = 0
        var snoozeAt = cal.date(from: comps) ?? now
        if snoozeAt <= now {
            snoozeAt = cal.date(byAdding: .day, value: 1, to: snoozeAt) ?? snoozeAt
        }
        snoozeTo(reminder, at: snoozeAt, note: "推迟到明天")
    }

    private func snoozeTo(_ reminder: Reminder, at snoozeAt: Date, note: String) {
        guard let context = modelContext,
              ReminderActions.snooze(reminder, until: snoozeAt, context: context) else { return }
        Task {
            await NotificationManager.shared.removePendingNotification(for: reminder.id)
            await self.scheduleAllNotifications(for: reminder)
        }
    }

    // MARK: - 递增重试

    func escalateRetry(_ reminder: Reminder) {
        // Dismissal does not create an extra retry. The system already holds this occurrence's chain.
        Task { await self.checkMissedReminders(reminders: [reminder]) }
    }

    // MARK: - 安排全部通知（日期类：提前预告 + D-day）

    /// 当前未确认（待处理）提醒数量，用于设置角标
    func unconfirmedCount() -> Int {
        guard let context = modelContext else { return 0 }
        let all = (try? context.fetch(FetchDescriptor<Reminder>())) ?? []
        return all.filter { $0.status != .confirmed }.count
    }

    private var replanning = false
    private var replanRequested = false
    @Published var scheduledPrimaryCount = 0
    @Published var eligiblePrimaryCount = 0

    func scheduleAllNotifications(for reminder: Reminder) async { await ensureRetryChains() }

    func ensureRetryChains() async {
        replanRequested = true
        guard !replanning, let context = modelContext else { return }
        replanning = true
        defer { replanning = false }
        while replanRequested {
            replanRequested = false
            let generation = SyncStore.localVersion
            let reminders = (try? context.fetch(FetchDescriptor<Reminder>())) ?? []
            let now = Date()
            let next = reminders.filter { $0.isEnabled && $0.status != .confirmed }.min { $0.nextTriggerAt < $1.nextTriggerAt }
            let unhandled = reminders.filter { $0.isEnabled && ($0.status == .active || $0.status == .snoozed || $0.status == .overdue || $0.nextTriggerAt <= now) }.count
            WidgetSnapshot.save(WidgetReminderData(unhandledCount: unhandled, nextTitle: next?.title ?? "暂无提醒",
                nextTime: next?.nextTriggerAt, updatedAt: now, nextReminderID: next?.id.uuidString, nextActionToken: next?.actionToken))
            WidgetCenter.shared.reloadAllTimelines()
            let all = ReminderPolicy.allocate(reminders, now: now, limit: Int.max)
            let reserved = await NotificationManager.shared.unmanagedPendingCount()
            if generation != SyncStore.localVersion { replanRequested = true; continue }
            let tokens = Dictionary(uniqueKeysWithValues: reminders.map { ($0.id.uuidString, $0.actionToken) })
            if #available(iOS 26.0, *) { await ImportantAlarmService.shared.removeStale(validTokens: tokens) }
            var alarmCovered = Set<String>()
            if #available(iOS 26.0, *) {
                for delivery in all where delivery.important {
                    if generation != SyncStore.localVersion { replanRequested = true; break }
                    if await ImportantAlarmService.shared.schedule(delivery) { alarmCovered.insert(delivery.identifier) }
                }
            }
            if generation != SyncStore.localVersion { replanRequested = true; continue }
            let queue = Array(all.filter { !alarmCovered.contains($0.identifier) }.prefix(max(0, 64 - reserved)))
            eligiblePrimaryCount = all.filter { $0.kind == .primary }.count
            scheduledPrimaryCount = all.filter { $0.kind == .primary && alarmCovered.contains($0.identifier) }.count + queue.filter { $0.kind == .primary }.count
            await NotificationManager.shared.removeManagedRequests()
            for delivery in queue {
                if generation != SyncStore.localVersion { replanRequested = true; break }
                await NotificationManager.shared.addDelivery(delivery, badgeCount: eligiblePrimaryCount)
            }
            if generation != SyncStore.localVersion { replanRequested = true }
        }
    }

    // MARK: - 启动时检查遗漏

    /// 启动/回前台时补偿「到期未确认」的提醒。
    ///
    /// P1-2（v2.0.8）：从「自动推进到下一周期」改为「递增重试追赶」，与 Android 完全对齐 ——
    /// 到期未确认 → 1h → 4h → 12h → 24h → 24h → overdue，
    /// **重试期间不推进周期**，周期只在「确认完成 / 重新打开」时前进。
    ///
    /// 为什么要追赶：iOS 没有 WorkManager，App 被杀期间只有系统在按预排的时间发通知，
    /// 数据库里的 retryStage / status 不会自己动。回到 App 时按错过的次数把阶段一次性补齐，
    /// 保证「通知发了几次」和「库里记了几阶段」一致。
    func checkMissedReminders(reminders: [Reminder]) async {
        let now = Date()
        for reminder in reminders {
            guard reminder.isEnabled else { continue }
            guard reminder.status != .confirmed, reminder.status != .overdue else { continue }
            guard reminder.nextTriggerAt <= now else { continue }

            // 每错过一次触发就前进一个重试阶段，直到下次触发落在未来或达到上限
            let caught = ReminderPolicy.catchUp(reminder, now: now)
            let stage = caught.stage
            let due = caught.dueAt

            reminder.undoCompletion = nil
            reminder.retryStage = stage
            reminder.lastRetryAt = now
            reminder.updatedAt = now

            if caught.isOverdue {
                // 达到上限：标逾期停止轰炸，留在列表等用户手动确认 / 重新打开
                reminder.status = .overdue
                reminder.nextTriggerAt = due
                try? modelContext?.save()
                SyncStore.touchLocalChange()
                await NotificationManager.shared.removePendingNotification(for: reminder.id)
                print("[ReminderEngine] 递增重试已达上限，标记逾期: \(reminder.title)")
                continue
            }

            reminder.nextTriggerAt = due
            reminder.status = .active
            try? modelContext?.save()
            SyncStore.touchLocalChange()

            await scheduleAllNotifications(for: reminder)
            print("[ReminderEngine] 过期提醒进入重试阶段 \(stage): \(reminder.title), 下次: \(due)")
        }
    }

    // MARK: - 节假日前移预检（Item 2）

    /// 节假日前移备注的本地存储。
    /// 为避免改动 SwiftData schema 引发无法本地验证的迁移崩溃，
    /// 仅把「本次触发被前移」的备注存到 UserDefaults（按提醒 UUID 索引）。
    /// 备注为空即表示当前这次触发未被前移。
    struct HolidayAdjustStore {
        private static let key = "holiday_adjust_notes"
        static func note(for id: UUID) -> String? {
            guard let raw = UserDefaults.standard.dictionary(forKey: key)?[id.uuidString] as? String,
                  !raw.isEmpty else { return nil }
            return raw
        }
        static func setNote(_ note: String?, for id: UUID) {
            var dict = UserDefaults.standard.dictionary(forKey: key) ?? [:]
            if let note, !note.isEmpty {
                dict[id.uuidString] = note
            } else {
                dict.removeValue(forKey: id.uuidString)
            }
            UserDefaults.standard.set(dict, forKey: key)
        }
    }

    // MARK: - 关键提醒（批次3 功能5）

    /// 关键提醒标记（critical）的本地存储。
    /// 与 HolidayAdjustStore 同理：为避免改动 SwiftData schema 引发无法本地验证的迁移崩溃，
    /// 把「是否为关键提醒」存到 UserDefaults（按提醒 UUID 索引）。
    /// 关键提醒用于触发更激进的提醒策略（重复 alert 脉冲），确保重要事项不被漏看。
    typealias CriticalStore = LegacyPolicyStore

    /// 节假日前移预检：对未完成的 cycle / rule 提醒，
    /// 若下次触发落在 ~31 天内且恰逢法定节假日，则前移到假期前最近工作日
    /// （循环锚点 firstTriggerAt 不变，确认完成后备注清空、下一周期照常推进）。
    /// 仅非生日循环/规则提醒参与；日期提醒（生日、节假日本身）不参与。
    func runHolidayPreCheck() async {
        guard let context = modelContext else { return }
        let now = Date()
        let window: TimeInterval = 31 * 86400
        let reminders = (try? context.fetch(FetchDescriptor<Reminder>())) ?? []

        for r in reminders {
            guard r.isEnabled, r.status != .confirmed, r.status != .overdue else { continue }
            guard r.kind == .cycle || r.kind == .rule else { continue }
            // 本次已前移过则跳过，避免重复
            if HolidayAdjustStore.note(for: r.id) != nil { continue }

            let occ = r.nextTriggerAt
            guard occ > now, occ.timeIntervalSince(now) <= window else { continue }

            let cal = Calendar.current
            let y = cal.component(.year, from: occ)
            let m = cal.component(.month, from: occ)
            let d = cal.component(.day, from: occ)

            // Fetch may suspend while the user completes/edits/syncs this reminder.
            let token = r.actionToken
            await HolidayRemoteService.refresh(year: y)
            guard ReminderActions.accepts(r, token: token), r.nextTriggerAt == occ,
                  r.status != .confirmed, r.status != .overdue else { continue }

            guard let st = HolidayRemoteService.status(year: y, month: m, day: d),
                  st.isHoliday else { continue }

            // 前移到假期前最近工作日
            guard let shifted = lastWorkingDay(before: occ), shifted > now else { continue }

            // 保留原触发时间的「时分」
            var comps = cal.dateComponents([.hour, .minute], from: occ)
            let shiftedAt = cal.date(bySettingHour: comps.hour ?? r.reminderHour,
                                      minute: comps.minute ?? r.reminderMinute,
                                      second: 0, of: shifted) ?? shifted

            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "zh_CN")
            fmt.dateFormat = "M月d日"
            let note = Localized("因%@放假，已前移至假期前最近工作日（%@）", st.name, fmt.string(from: shiftedAt))

            r.nextTriggerAt = shiftedAt
            r.actionRevision += 1; r.undoCompletion = nil
            r.updatedAt = Date()
            HolidayAdjustStore.setNote(note, for: r.id)
            try? context.save()
            SyncStore.touchLocalChange()

            await scheduleAllNotifications(for: r)
            print("[ReminderEngine] 节假日前移: \(r.title) → \(fmt.string(from: shiftedAt))")
        }
    }

    /// 返回 date 之前（不含）最近的一个工作日；极端情况下找不到返回 nil
    private func lastWorkingDay(before date: Date) -> Date? {
        var cursor = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        for _ in 0..<10 {
            if !isOffDay(cursor) { return cursor }
            guard let prev = Calendar.current.date(byAdding: .day, value: -1, to: cursor) else { return nil }
            cursor = prev
        }
        return nil
    }

    /// 某天是否休息日：法定节假日(isHoliday) 或 普通周末（远端无数据时按星期判断）。
    /// 远端 holiday-cn 只列出法定节假日与调休上班日，普通周末 status 为 nil，
    /// 故 nil 时按星期判断周末；调休上班日(isHoliday=false)视为工作日。
    private func isOffDay(_ date: Date) -> Bool {
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        if let st = HolidayRemoteService.status(year: y, month: m, day: d) {
            return st.isHoliday
        }
        let w = cal.component(.weekday, from: date) // 1=周日..7=周六
        return w == 1 || w == 7
    }
}
