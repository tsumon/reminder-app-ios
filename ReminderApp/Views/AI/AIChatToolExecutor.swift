import Foundation
import SwiftData

/// AI 工具执行器：纯业务落库与提醒增删改查逻辑，与 UI 层彻底解耦
@MainActor
enum AIChatToolExecutor {

    static func execute(name: String, argsJSON: String, context: ModelContext) async -> (String, ImportPreview?) {
        guard let data = argsJSON.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ("参数解析失败", nil)
        }
        let reminders = (try? context.fetch(FetchDescriptor<Reminder>(sortBy: [SortDescriptor(\.title)]))) ?? []

        switch name {
        case "create_reminder":
            return (await handleCreate(args: args, context: context), nil)
        case "list_reminders":
            return (handleList(reminders: reminders), nil)
        case "confirm_reminder":
            return (handleConfirm(args: args, reminders: reminders), nil)
        case "snooze_reminder":
            return (handleSnooze(args: args, reminders: reminders), nil)
        case "delete_reminder":
            return (await handleDelete(args: args, reminders: reminders, context: context), nil)
        case "update_reminder":
            return (await handleUpdate(args: args, reminders: reminders, context: context), nil)
        case "import_tasks":
            return handleImportTasks(args: args)
        case "get_stats_context":
            return (handleStatsContext(reminders: reminders), nil)
        default:
            return (Localized("未知工具: %@", name), nil)
        }
    }

    static func describeReminder(_ r: Reminder) -> String {
        switch r.kind {
        case .date:  return r.dateDisplayText
        case .rule:  return r.cycle.rawValue
        case .cycle: return r.cycle.rawValue
        }
    }

    static func commitImport(_ items: [Reminder], context: ModelContext) async {
        for r in items { context.insert(r) }
        try? context.save()
        for r in items {
            if r.cycle == .weekly || r.cycle == .biweekly {
                let anchorDow = ((Calendar.current.component(.weekday, from: r.firstTriggerAt) + 5) % 7) + 1
                WeeklyWeekdayStore.set(anchorDow, for: r.id)
            }
            r.nextTriggerAt = ReminderEngine.shared.calculateNextTrigger(after: Date(), reminder: r)
        }
        try? context.save()
        SyncStore.touchLocalChange()
        for r in items {
            await ReminderEngine.shared.scheduleAllNotifications(for: r)
        }
    }

    // MARK: - 参数解析构造

    private static func buildReminder(from args: [String: Any]) -> (Reminder?, String?) {
        let title = args["title"] as? String ?? "未命名提醒"
        let kind = args["kind"] as? String ?? "cycle"
        let note = args["note"] as? String ?? ""
        let cycle = args["cycle"] as? String ?? "weekly"
        let customDays = args["custom_days"] as? Int ?? 0
        if cycle == "custom", customDays < 1 {
            return (nil, "自定义周期需要指定间隔天数（如：每3天），custom_days 至少为 1。")
        }
        let dateType = args["date_type"] as? String
        let targetMonth = (args["target_month"] as? Int) ?? (args["target_month"] as? Double).map(Int.init) ?? (args["target_month"] as? String).flatMap(Int.init) ?? 0
        let targetDay = (args["target_day"] as? Int) ?? (args["target_day"] as? Double).map(Int.init) ?? (args["target_day"] as? String).flatMap(Int.init) ?? 0
        let advanceDays = args["advance_days"] as? Int ?? 3
        let reminderHour = args["reminder_hour"] as? Int ?? 9
        let reminderMinute = args["reminder_minute"] as? Int ?? 0
        let holidayName = args["holiday_name"] as? String
        let holidayAware: Bool = {
            if let b = args["holiday_aware"] as? Bool { return b }
            if let str = args["holiday_aware"] as? String { return str.lowercased() == "true" }
            return false
        }()
        let rulePeriodRaw = args["rule_period"] as? String
        let ruleWeekRaw = (args["rule_week"] as? Int) ?? (args["rule_week"] as? Double).map(Int.init) ?? (args["rule_week"] as? String).flatMap(Int.init)
        let ruleWeekdayRaw = (args["rule_weekday"] as? Int) ?? (args["rule_weekday"] as? Double).map(Int.init) ?? (args["rule_weekday"] as? String).flatMap(Int.init)
        let weekdayParam = (args["weekday"] as? Int) ?? (args["weekday"] as? Double).map(Int.init) ?? (args["weekday"] as? String).flatMap(Int.init)

        if kind == "date" {
            if dateType == "holiday" {
                if (holidayName ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                    return (nil, "需要指定节假日名称（例如：春节、中秋节）才能创建节假日提醒。")
                }
            } else if !(1...12).contains(targetMonth) || !(1...31).contains(targetDay) {
                return (nil, "需要具体的公历/农历月日才能创建日期提醒（例如：农历八月十五、公历5月1日）。请补充月日，我再为你创建。")
            } else if dateType == "lunar_birthday" && targetDay > 30 {
                return (nil, "农历日期没有 31 日，日期或历法可能有误。请与用户确认是新历还是农历后再创建。")
            }
        }
        if kind == "rule" {
            guard let rp = rulePeriodRaw, let rw = ruleWeekRaw, let rwd = ruleWeekdayRaw else {
                return (nil, "规则提醒需要指定频率（每月/每季度/每年）、第几周和星期几，例如：每季度第一周周四。")
            }
            guard ["monthly", "quarterly", "yearly"].contains(rp), (1...5).contains(rw), (1...7).contains(rwd) else {
                return (nil, "规则提醒参数不合法：频率应为每月/每季度/每年，第几周 1-5，星期几 1=周一...7=周日。")
            }
        }
        if kind == "cycle", (cycle == "weekly" || cycle == "biweekly"), weekdayParam == nil {
            return (nil, "每周/每两周提醒需要指定星期几（weekday: 1=周一…7=周日）。请补充后重试。")
        }

        let now = Date()
        var anchor = Calendar.current.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: now) ?? now
        if (cycle == "weekly" || cycle == "biweekly"), let wd = weekdayParam, (1...7).contains(wd) {
            let cal = Calendar.current
            let cur = ((cal.component(.weekday, from: anchor) + 5) % 7) + 1
            var diff = (wd - cur + 7) % 7
            if diff == 0 && anchor <= now { diff = 7 }
            anchor = cal.date(byAdding: .day, value: diff, to: anchor) ?? anchor
        } else {
            if let dateStr = args["trigger_date"] as? String {
                let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
                if let d = f.date(from: dateStr.trimmingCharacters(in: .whitespaces)), d > now {
                    anchor = Calendar.current.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: d) ?? d
                }
            }
            if anchor <= now { anchor = Calendar.current.date(byAdding: .day, value: 1, to: anchor) ?? anchor }
        }

        let reminderKind: ReminderKind = kind == "date" ? .date : (kind == "rule" ? .rule : .cycle)
        let cycleEnum: ReminderCycle = {
            switch cycle {
            case "once": return .once
            case "daily": return .daily
            case "weekly": return .weekly
            case "biweekly": return .biweekly
            case "monthly": return .monthly
            case "quarterly": return .quarterly
            case "yearly": return .yearly
            case "custom": return .custom
            default: return .weekly
            }
        }()
        let dateTypeEnum: DateReminderType? = {
            switch dateType {
            case "solar_birthday": return .solarBirthday
            case "lunar_birthday": return .lunarBirthday
            case "holiday": return .holiday
            default: return nil
            }
        }()

        let reminder = Reminder(
            title: title, note: note, kind: reminderKind, cycle: cycleEnum, customDays: customDays,
            dateType: dateTypeEnum, targetMonth: targetMonth, targetDay: targetDay, advanceDays: advanceDays,
            reminderHour: reminderHour, reminderMinute: reminderMinute,
            holidayID: holidayName.flatMap { HolidayService.search(by: $0)?.id },
            rulePeriod: rulePeriodRaw == "monthly" ? .monthly : (rulePeriodRaw == "yearly" ? .yearly : .quarterly),
            ruleWeek: ruleWeekRaw.flatMap(RuleWeek.init(rawValue:)) ?? .w1,
            ruleWeekday: ruleWeekdayRaw.flatMap(RuleWeekday.init(rawValue:)) ?? .mon,
            firstTriggerAt: anchor, nextTriggerAt: anchor, holidayAware: holidayAware
        )
        return (reminder, nil)
    }

    // MARK: - 各工具处理器

    private static func handleCreate(args: [String: Any], context: ModelContext) async -> String {
        let (reminder, err) = buildReminder(from: args)
        guard let reminder else { return err ?? "创建失败" }
        context.insert(reminder)
        do { try context.save() } catch { NSLog("[AIChat] create save#1 failed: \(error)") }
        if reminder.cycle == .weekly || reminder.cycle == .biweekly {
            let anchorDow = ((Calendar.current.component(.weekday, from: reminder.firstTriggerAt) + 5) % 7) + 1
            WeeklyWeekdayStore.set(anchorDow, for: reminder.id)
        } else {
            WeeklyWeekdayStore.set(nil, for: reminder.id)
        }
        reminder.nextTriggerAt = ReminderEngine.shared.calculateNextTrigger(after: Date(), reminder: reminder)
        do { try context.save() } catch { NSLog("[AIChat] create save#2 failed: \(error)") }
        SyncStore.touchLocalChange()
        await ReminderEngine.shared.scheduleAllNotifications(for: reminder)
        return Localized("已创建提醒：「%@」", reminder.title)
    }

    private static func handleImportTasks(args: [String: Any]) -> (String, ImportPreview?) {
        guard let items = args["items"] as? [[String: Any]], !items.isEmpty else {
            return ("没有解析到可批量创建的提醒。", nil)
        }
        var built: [Reminder] = []
        var skippedReasons: [String] = []
        for item in items {
            let (r, err) = buildReminder(from: item)
            if let r { built.append(r) } else { skippedReasons.append(err ?? "格式无法识别") }
        }
        guard !built.isEmpty else { return ("解析失败：所有条目都无法识别为有效提醒。", nil) }
        var preview = Localized("已解析出 %d 条提醒，请确认后批量创建：", built.count)
        for (i, r) in built.enumerated() { preview += "\n\(i + 1). \(r.title) 〔\(describeReminder(r))〕" }
        if !skippedReasons.isEmpty {
            preview += "\n（\(skippedReasons.count) 条无法解析已跳过）"
        }
        return (preview, ImportPreview(items: built))
    }

    private static func handleList(reminders: [Reminder]) -> String {
        let list = reminders.map { " · \($0.title) [\($0.dateDisplayText)] — \($0.status.rawValue)" }
        if list.isEmpty { return "当前没有提醒。" }
        return Localized("当前共有 %d 个提醒：\n%@", list.count, list.joined(separator: "\n"))
    }

    private static func handleStatsContext(reminders: [Reminder]) -> String {
        let allRecords = reminders.flatMap(\.records)
        let summary = StatsService.summarize(records: allRecords)
        let cal = Calendar.current
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        let weekConfirm = allRecords.filter { $0.type == ReminderRecordType.confirm.rawValue && $0.performedAt >= weekStart }.count
        let weekMissed = Set(allRecords.filter { $0.type == ReminderRecordType.trigger.rawValue && $0.performedAt >= weekStart }
            .map { cal.startOfDay(for: $0.performedAt) }).count
        let rate: String = weekConfirm + weekMissed > 0 ? "\(Int(Double(weekConfirm) / Double(weekConfirm + weekMissed) * 100))%" : "暂无数据"
        let df = DateFormatter(); df.locale = Locale(identifier: "zh_CN"); df.dateFormat = "M月d日"
        return "本周统计（\(df.string(from: weekStart)) 起）：确认 \(weekConfirm) 次，错过 \(weekMissed) 天，完成率 \(rate)。当前连续 \(summary.currentStreak) 天，最长连续 \(summary.longestStreak) 天。"
    }

    private static func handleConfirm(args: [String: Any], reminders: [Reminder]) -> String {
        let keyword = (args["title_keyword"] as? String ?? "").lowercased()
        guard !keyword.isEmpty else { return "请指定要确认的提醒标题。" }
        guard let match = reminders.first(where: { $0.title.lowercased().contains(keyword) }) else {
            return Localized("未找到包含「%@」的提醒", keyword)
        }
        guard ReminderEngine.shared.confirmReminder(match, expectedToken: match.actionToken) else {
            return "提醒已被其他操作修改，请重新确认"
        }
        return Localized("已确认「%@」，下次提醒时间已更新。", match.title)
    }

    private static func handleSnooze(args: [String: Any], reminders: [Reminder]) -> String {
        let keyword = (args["title_keyword"] as? String ?? "").lowercased()
        guard !keyword.isEmpty else { return "请指定要推迟的提醒标题。" }
        guard let match = reminders.first(where: { $0.title.lowercased().contains(keyword) }) else {
            return Localized("未找到包含「%@」的提醒", keyword)
        }
        guard ReminderEngine.shared.snoozeReminder(match, afterMinutes: 15, expectedToken: match.actionToken) else {
            return "提醒已被其他操作修改，请重新确认"
        }
        return Localized("已推迟「%@」，15 分钟后再次提醒。", match.title)
    }

    private static func handleDelete(args: [String: Any], reminders: [Reminder], context: ModelContext) async -> String {
        let keyword = (args["title_keyword"] as? String ?? "").lowercased()
        guard !keyword.isEmpty else { return "请指定要删除的提醒标题。" }
        guard let match = reminders.first(where: { $0.title.lowercased().contains(keyword) }) else {
            return Localized("未找到包含「%@」的提醒", keyword)
        }
        let id = match.id
        let title = match.title
        guard ReminderActions.delete(match, context: context, expectedToken: match.actionToken) else {
            return "提醒已被其他操作修改，请重新确认"
        }
        await NotificationManager.shared.removePendingNotification(for: id)
        await ReminderEngine.shared.ensureRetryChains()
        return Localized("已删除「%@」", title)
    }

    private static func handleUpdate(args: [String: Any], reminders: [Reminder], context: ModelContext) async -> String {
        let keyword = (args["title_keyword"] as? String ?? "").lowercased()
        guard !keyword.isEmpty else { return "请指定要修改的提醒标题。" }
        let cycleRaw = args["cycle"] as? String
        let customDaysRaw = (args["custom_days"] as? Int) ?? (args["custom_days"] as? Double).map(Int.init)
        guard let match = reminders.first(where: { $0.title.lowercased().contains(keyword) }) else {
            return Localized("未找到包含「%@」的提醒", keyword)
        }
        if cycleRaw == "custom", (customDaysRaw ?? 0) < 1 {
            return "自定义周期需要指定间隔天数（如：每3天），custom_days 至少为 1。"
        }
        let weekdayParam = (args["weekday"] as? Int) ?? (args["weekday"] as? Double).map(Int.init) ?? (args["weekday"] as? String).flatMap(Int.init)
        if cycleRaw == "weekly" || cycleRaw == "biweekly" {
            guard let wd = weekdayParam, (1...7).contains(wd) else {
                return "修改为每周/每两周提醒时需要指定星期几（weekday: 1=周一…7=周日）。请补充后重试。"
            }
        }
        let expectedToken = match.actionToken
        let scheduleKeys = ["cycle", "custom_days", "rule_period", "rule_week", "rule_weekday", "date_type", "target_month", "target_day", "holiday_name", "reminder_hour", "reminder_minute", "weekday", "holiday_aware"]
        let scheduleChanged = scheduleKeys.contains { args[$0] != nil }

        if !scheduleChanged {
            let advance = (args["advance_days"] as? Int) ?? (args["advance_days"] as? Double).map(Int.init)
            guard ReminderEdits.applyMetadata(to: match, expectedToken: expectedToken, title: args["new_title"] as? String, note: args["note"] as? String, advanceDays: advance, context: context) else {
                return "提醒已被其他操作修改，请重新编辑"
            }
            await ReminderEngine.shared.scheduleAllNotifications(for: match)
            return Localized("已修改「%@」", match.title)
        }

        if let nt = args["new_title"] as? String { match.title = nt }
        if let n = args["note"] as? String { match.note = n }
        if let c = cycleRaw {
            switch c {
            case "once": match.cycle = .once
            case "daily": match.cycle = .daily
            case "weekly": match.cycle = .weekly
            case "biweekly": match.cycle = .biweekly
            case "monthly": match.cycle = .monthly
            case "quarterly": match.cycle = .quarterly
            case "yearly": match.cycle = .yearly
            case "custom": match.cycle = .custom
            default: break
            }
        }
        if let cd = customDaysRaw { match.customDays = cd }
        if let tm = (args["target_month"] as? Int) ?? (args["target_month"] as? Double).map(Int.init) { match.targetMonth = tm }
        if let td = (args["target_day"] as? Int) ?? (args["target_day"] as? Double).map(Int.init) { match.targetDay = td }
        if let ah = (args["advance_days"] as? Int) ?? (args["advance_days"] as? Double).map(Int.init) { match.advanceDays = ah }
        if let ha = args["holiday_aware"] as? Bool { match.holidayAware = ha }
        if let rh = (args["reminder_hour"] as? Int) ?? (args["reminder_hour"] as? Double).map(Int.init) { match.reminderHour = rh }
        if let rm = (args["reminder_minute"] as? Int) ?? (args["reminder_minute"] as? Double).map(Int.init) { match.reminderMinute = rm }

        if match.kind == .cycle, (match.cycle == .weekly || match.cycle == .biweekly), let wd = weekdayParam {
            let cal = Calendar.current
            let anchor = cal.date(bySettingHour: match.reminderHour, minute: match.reminderMinute, second: 0, of: Date()) ?? Date()
            let cur = ((cal.component(.weekday, from: anchor) + 5) % 7) + 1
            var diff = (wd - cur + 7) % 7
            if diff == 0 { diff = 7 }
            if let newAnchor = cal.date(byAdding: .day, value: diff, to: anchor) { match.firstTriggerAt = newAnchor }
            WeeklyWeekdayStore.set(wd, for: match.id)
        }
        if match.status == .overdue {
            match.status = .pending; match.retryStage = 0; match.lastRetryAt = nil
        }
        match.nextTriggerAt = ReminderEngine.shared.calculateNextTrigger(after: Date(), reminder: match)
        ReminderEngine.HolidayAdjustStore.setNote(nil, for: match.id)
        _ = ReminderActions.changed(match, context: context)
        await ReminderEngine.shared.scheduleAllNotifications(for: match)
        return Localized("已修改「%@」", match.title)
    }
}
