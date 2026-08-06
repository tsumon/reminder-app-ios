import Foundation
import SwiftData

/// 提醒数据导入/导出（JSON 格式，与 Android 端统一）
enum BackupHelper {

    /// 导入结果
    struct ImportResult {
        let imported: Int
        let skipped: Int
        let inserted: [Reminder]
    }

    /// 导出的单条提醒（纯值类型，便于 JSON 编解码）
    struct BackupItem: Codable {
        var title: String
        var note: String
        var kind: String
        var cycle: String
        var customDays: Int
        var dateType: String?
        var targetMonth: Int?
        var targetDay: Int?
        var holidayName: String?
        var advanceDays: Int
        var reminderHour: Int
        var reminderMinute: Int
        var rulePeriod: String?
        var ruleWeek: Int?
        var ruleWeekday: Int?
        var priority: String
        var firstTriggerAt: Double
        var nextTriggerAt: Double
        var status: String
        var isActive: Bool
    }

    struct BackupRoot: Codable {
        var version: Int
        var exportedAt: Double
        var reminders: [BackupItem]
    }

    /// 将 [Reminder] 导出为 JSON 字符串
    static func exportJSON(_ reminders: [Reminder]) -> String {
        exportJSON(reminders, exportedAt: Date().timeIntervalSince1970)
    }

    /// 带指定 exportedAt（秒）的导出，用于同步时保证版本递增
    static func exportJSON(_ reminders: [Reminder], exportedAt: TimeInterval) -> String {
        let items = reminders.map { r in
            BackupItem(
                title: r.title,
                note: r.note,
                kind: r.kind.rawValue == "周期提醒" ? "cycle" : (r.kind.rawValue == "规则提醒" ? "rule" : "date"),
                cycle: r.cycle.rawValue == "自定义" ? "custom" : cycleCode(r.cycle),
                customDays: r.customDays,
                dateType: dateTypeCode(r.dateType),
                targetMonth: r.kind == .date ? r.targetMonth : nil,
                targetDay: r.kind == .date ? r.targetDay : nil,
                holidayName: r.holidayID,
                advanceDays: r.advanceDays,
                reminderHour: r.reminderHour,
                reminderMinute: r.reminderMinute,
                rulePeriod: r.kind == .rule ? rulePeriodCode(r.rulePeriod) : nil,
                ruleWeek: r.kind == .rule ? r.ruleWeek.rawValue : nil,
                ruleWeekday: r.kind == .rule ? r.ruleWeekday.rawValue : nil,
                priority: r.priority.rawValue == "高" ? "high" : (r.priority.rawValue == "低" ? "low" : "normal"),
                firstTriggerAt: r.firstTriggerAt.timeIntervalSince1970 * 1000,
                nextTriggerAt: r.nextTriggerAt.timeIntervalSince1970 * 1000,
                status: r.status.rawValue == "等待中" ? "pending" : (r.status.rawValue == "已完成" ? "confirmed" : "notifying"),
                isActive: r.isEnabled
            )
        }
        let root = BackupRoot(version: 1, exportedAt: exportedAt, reminders: items)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(root) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// 读取 JSON 中的 exportedAt（秒）
    static func exportedAt(of json: String) -> TimeInterval? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONDecoder().decode(BackupRoot.self, from: data) else {
            return nil
        }
        return root.exportedAt
    }

    /// 从 JSON 解析提醒列表
    static func importJSON(_ json: String) -> [BackupItem]? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let root = try? JSONDecoder().decode(BackupRoot.self, from: data) else { return nil }
        return root.reminders
    }

    /// 通用导入（文件导入 / 近场接收共用）：
    /// 去重（id + 标题|触发时间指纹）→ 过期重算（once 标记逾期）→ 插入 → 保存 → touch 本地变更
    @MainActor
    static func importItems(_ items: [BackupItem], existing: [Reminder], into context: ModelContext) -> ImportResult {
        var existingIDs = Set(existing.map(\.id))
        var existingFingerprints = Set(
            existing.map { "\($0.title)|\(Int($0.nextTriggerAt.timeIntervalSince1970))" }
        )

        var importedCount = 0
        var skippedCount = 0
        var inserted: [Reminder] = []
        let now = Date()

        for item in items {
            let reminder = makeReminder(from: item)
            let fingerprint = "\(reminder.title)|\(Int(reminder.nextTriggerAt.timeIntervalSince1970))"

            if existingIDs.contains(reminder.id) || existingFingerprints.contains(fingerprint) {
                skippedCount += 1
                continue
            }

            // 备份可能来自其他设备，nextTriggerAt 已过期——
            // 直接调度会用过去的日期排通知 → 导入瞬间弹一堆通知。
            // 过期且可重复的提醒先推到未来；一次性已过期则标记逾期不再弹。
            if reminder.nextTriggerAt <= now {
                if reminder.cycle == .once {
                    reminder.status = .overdue
                } else {
                    reminder.nextTriggerAt = ReminderEngine.shared.calculateNextTrigger(after: now, reminder: reminder)
                }
            }

            existingIDs.insert(reminder.id)
            existingFingerprints.insert(fingerprint)
            context.insert(reminder)
            inserted.append(reminder)
            importedCount += 1
        }
        try? context.save()
        SyncStore.touchLocalChange()

        return ImportResult(imported: importedCount, skipped: skippedCount, inserted: inserted)
    }

    // MARK: - 编码映射（与 Android 的字符串值对齐）

    private static func cycleCode(_ c: ReminderCycle) -> String {
        switch c {
        case .once: return "once"
        case .daily: return "daily"
        case .weekly: return "weekly"
        case .biweekly: return "biweekly"
        case .monthly: return "monthly"
        case .quarterly: return "quarterly"
        case .yearly: return "yearly"
        case .custom: return "custom"
        }
    }

    private static func dateTypeCode(_ t: DateReminderType?) -> String? {
        switch t {
        case .solarBirthday: return "solar_birthday"
        case .lunarBirthday: return "lunar_birthday"
        case .holiday: return "holiday"
        case .none: return nil
        }
    }

    private static func rulePeriodCode(_ p: RulePeriod) -> String {
        switch p {
        case .monthly: return "monthly"
        case .quarterly: return "quarterly"
        case .yearly: return "yearly"
        }
    }

    /// 从导入项构造 Reminder（未插入 context）
    static func makeReminder(from item: BackupItem) -> Reminder {
        let kind: ReminderKind = item.kind == "date" ? .date : (item.kind == "rule" ? .rule : .cycle)
        let cycle: ReminderCycle = {
            switch item.cycle {
            case "once": return .once
            case "daily": return .daily
            case "biweekly": return .biweekly
            case "monthly": return .monthly
            case "quarterly": return .quarterly
            case "yearly": return .yearly
            case "custom": return .custom
            default: return .weekly
            }
        }()
        let dateType: DateReminderType? = {
            switch item.dateType {
            case "solar_birthday": return .solarBirthday
            case "lunar_birthday": return .lunarBirthday
            case "holiday": return .holiday
            default: return nil
            }
        }()
        let rulePeriod: RulePeriod = {
            switch item.rulePeriod {
            case "monthly": return .monthly
            case "yearly": return .yearly
            default: return .quarterly
            }
        }()
        let priority: ReminderPriority = item.priority == "high" ? .high : (item.priority == "low" ? .low : .normal)
        // v1.9.6 fix: 恢复 status——导出时写了该字段但导入从未解析，
        // 导致已完成的提醒同步/导入后全部变「等待中」
        let status: ReminderStatus = {
            switch item.status {
            case "confirmed": return .confirmed
            case "overdue": return .overdue
            case "active": return .active
            case "snoozed": return .snoozed
            default: return .pending
            }
        }()

        return Reminder(
            title: item.title,
            note: item.note,
            kind: kind,
            cycle: cycle,
            customDays: item.customDays,
            dateType: dateType,
            targetMonth: item.targetMonth ?? 1,
            targetDay: item.targetDay ?? 1,
            advanceDays: item.advanceDays,
            reminderHour: item.reminderHour,
            reminderMinute: item.reminderMinute,
            holidayID: item.holidayName,
            rulePeriod: rulePeriod,
            ruleWeek: RuleWeek(rawValue: item.ruleWeek ?? 2) ?? .w2,
            ruleWeekday: RuleWeekday(rawValue: item.ruleWeekday ?? 2) ?? .tue,
            firstTriggerAt: Date(timeIntervalSince1970: item.firstTriggerAt / 1000),
            nextTriggerAt: Date(timeIntervalSince1970: item.nextTriggerAt / 1000),
            status: status,
            priority: priority,
            isEnabled: item.isActive
        )
    }
}
