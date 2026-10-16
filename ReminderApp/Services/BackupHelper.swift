import Foundation
import SwiftData

/// 提醒数据导入/导出（JSON 格式，与 Android 端统一）
enum BackupHelper {

    /// 导入结果
    struct ImportResult {
        let imported: Int
        let skipped: Int
        let inserted: [Reminder]
        let error: String?   // I8: 写入失败原因（区别于「重复跳过」），nil 表示成功
    }

    /// 兼容旧 JSON 的 id 字段：Android 旧导出是本地自增数字（无跨端意义 → nil），
    /// iOS 旧导出是 UUID 字符串（→ 沿用）。协议 v2 的跨端 ID 请用 syncId。
    struct LooseID: Codable, Equatable {
        var stringValue: String?
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) {
                stringValue = s
            } else if (try? c.decode(Int.self)) != nil {
                stringValue = nil
            }
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            try c.encodeNil()
        }
    }

    /// 导出的单条提醒（纯值类型，便于 JSON 编解码）
    struct BackupItem: Codable {
        /// 阶段2: 跨端稳定 ID（UUID 字符串；旧文件缺省 nil → 导入时重新生成）
        var syncId: String?
        /// 兼容旧字段（数字忽略；旧 iOS 导出的 UUID 字符串兜底）
        var id: LooseID?
        var title: String
        var note: String
        var kind: String
        var cycle: String
        var customDays: Int = 0
        var dateType: String?
        var targetMonth: Int?
        var targetDay: Int?
        /// 阶段2: 跨端统一为稳定节假日 ID（旧文件只有 holidayName，且 iOS 旧导出实际塞的是 ID）→ 导入兜底
        var holidayId: String?
        var holidayName: String?
        var advanceDays: Int = 3
        var reminderHour: Int = 9
        var reminderMinute: Int = 0
        var rulePeriod: String?
        var ruleWeek: Int?
        var ruleWeekday: Int?
        var priority: String = "normal"
        var firstTriggerAt: Double
        var nextTriggerAt: Double
        var status: String
        var isActive: Bool
        /// H1: 关键提醒标记（iOS 存 UserDefaults CriticalStore，不动 schema；
        /// Optional 兼容旧文件缺 isCritical 键——旧协议是 is_critical snake_case，读取为 nil → false）
        var isCritical: Bool? = nil
        /// v2.4.10: 避开节假日/周末（缺省 false，旧备份兼容）
        var holidayAware: Bool? = nil
        var retryCount: Int? = nil
        var recurrenceMode: String? = nil
        var reminderStyle: String? = nil
        var retryIntervalsMinutes: [Int]? = nil
        var maxReminderAttempts: Int? = nil
        var quietStartMinute: Int? = nil
        var quietEndMinute: Int? = nil
        var createdAt: Double? = nil
        var updatedAt: Double? = nil
        var lastRetryAt: Double? = nil
        var lastCompletedAt: Double? = nil
        var records: [RecordItem]? = nil

        var stableID: UUID? { syncId.flatMap(UUID.init(uuidString:)) ?? id?.stringValue.flatMap(UUID.init(uuidString:)) }

        enum CodingKeys: String, CodingKey {
            case syncId, id, title, note, kind, cycle, customDays, dateType, targetMonth, targetDay, holidayId, holidayName
            case advanceDays, reminderHour, reminderMinute, rulePeriod, ruleWeek, ruleWeekday, priority
            case firstTriggerAt, nextTriggerAt, status, isActive, isCritical, holidayAware
            case retryCount, recurrenceMode, reminderStyle, retryIntervalsMinutes, maxReminderAttempts, quietStartMinute, quietEndMinute
            case createdAt, updatedAt, lastRetryAt, lastCompletedAt, records
        }
        // Defaults must also apply while decoding minimal Android/legacy envelopes.
        init() { title = ""; note = ""; kind = "cycle"; cycle = "weekly"; firstTriggerAt = 0; nextTriggerAt = 0; status = "pending"; isActive = true }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            syncId = try c.decodeIfPresent(String.self, forKey: .syncId)
id = try c.decodeIfPresent(LooseID.self, forKey: .id)
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "cycle"
cycle = try c.decodeIfPresent(String.self, forKey: .cycle) ?? "weekly"
customDays = try c.decodeIfPresent(Int.self, forKey: .customDays) ?? 0
advanceDays = try c.decodeIfPresent(Int.self, forKey: .advanceDays) ?? 3
reminderHour = try c.decodeIfPresent(Int.self, forKey: .reminderHour) ?? 9
reminderMinute = try c.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? 0
priority = try c.decodeIfPresent(String.self, forKey: .priority) ?? "normal"
firstTriggerAt = try c.decodeIfPresent(Double.self, forKey: .firstTriggerAt) ?? 0
nextTriggerAt = try c.decodeIfPresent(Double.self, forKey: .nextTriggerAt) ?? 0
status = try c.decodeIfPresent(String.self, forKey: .status) ?? "pending"
isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
            dateType = try c.decodeIfPresent(String.self, forKey: .dateType)
targetMonth = try c.decodeIfPresent(Int.self, forKey: .targetMonth)
targetDay = try c.decodeIfPresent(Int.self, forKey: .targetDay)
holidayId = try c.decodeIfPresent(String.self, forKey: .holidayId)
holidayName = try c.decodeIfPresent(String.self, forKey: .holidayName)
rulePeriod = try c.decodeIfPresent(String.self, forKey: .rulePeriod)
ruleWeek = try c.decodeIfPresent(Int.self, forKey: .ruleWeek)
ruleWeekday = try c.decodeIfPresent(Int.self, forKey: .ruleWeekday)
isCritical = try c.decodeIfPresent(Bool.self, forKey: .isCritical)
holidayAware = try c.decodeIfPresent(Bool.self, forKey: .holidayAware)
retryCount = try c.decodeIfPresent(Int.self, forKey: .retryCount)
recurrenceMode = try c.decodeIfPresent(String.self, forKey: .recurrenceMode)
reminderStyle = try c.decodeIfPresent(String.self, forKey: .reminderStyle)
retryIntervalsMinutes = try c.decodeIfPresent([Int].self, forKey: .retryIntervalsMinutes)
maxReminderAttempts = try c.decodeIfPresent(Int.self, forKey: .maxReminderAttempts)
quietStartMinute = try c.decodeIfPresent(Int.self, forKey: .quietStartMinute)
quietEndMinute = try c.decodeIfPresent(Int.self, forKey: .quietEndMinute)
createdAt = try c.decodeIfPresent(Double.self, forKey: .createdAt)
updatedAt = try c.decodeIfPresent(Double.self, forKey: .updatedAt)
lastRetryAt = try c.decodeIfPresent(Double.self, forKey: .lastRetryAt)
lastCompletedAt = try c.decodeIfPresent(Double.self, forKey: .lastCompletedAt)
records = try c.decodeIfPresent([RecordItem].self, forKey: .records)
        }
    }
    struct RecordItem: Codable {
        var id: UUID; var performedAt: Double; var type: String; var note: String
    }


    struct BackupRoot: Codable {
        var version: Int
        /// 阶段2: 协议版本（2 = id/holidayId；缺省视为 1——旧协议）
        var schemaVersion: Int?
        var exportedAt: Double
        /// v2.0.17: 本地单调版本（判新主依据；Optional 兼容旧文件缺字段）
        var dataVersion: Int?
        var reminders: [BackupItem]
    }

    /// 将 [Reminder] 导出为 JSON 字符串
    static func exportJSON(_ reminders: [Reminder]) -> String {
        exportJSON(reminders, exportedAt: Date().timeIntervalSince1970)
    }

    /// 批次3 功能6: 单条提醒分享卡片 —— 复用备份信封格式导出单条
    static func exportSingle(_ reminder: Reminder) -> String {
        exportJSON([reminder])
    }

    /// 批次3 功能6: 从分享卡片 JSON 解析出单条（解析失败返回 nil）
    static func importSingle(_ json: String) -> BackupItem? {
        importJSON(json)?.first
    }

    /// 带指定 exportedAt（秒）的导出，用于同步时保证版本递增
    static func exportJSON(_ reminders: [Reminder], exportedAt: TimeInterval) -> String {
        let items = reminders.map { r in
            var item = BackupItem()
            item.syncId = r.id.uuidString.lowercased()
            item.title = r.title
            item.note = r.note
            item.kind = r.kind.rawValue == "周期提醒" ? "cycle" : (r.kind.rawValue == "规则提醒" ? "rule" : "date")
            item.cycle = r.cycle.rawValue == "自定义" ? "custom" : cycleCode(r.cycle)
            item.customDays = r.customDays
            item.dateType = dateTypeCode(r.dateType)
            item.targetMonth = r.kind == .date ? r.targetMonth : nil
            item.targetDay = r.kind == .date ? r.targetDay : nil
            item.holidayId = r.holidayID
            item.holidayName = r.holidayID
            item.advanceDays = r.advanceDays
            item.reminderHour = r.reminderHour
            item.reminderMinute = r.reminderMinute
            item.rulePeriod = r.kind == .rule ? rulePeriodCode(r.rulePeriod) : nil
            item.ruleWeek = r.kind == .rule ? r.ruleWeek.rawValue : nil
            item.ruleWeekday = r.kind == .rule ? r.ruleWeekday.rawValue : nil
            item.priority = r.priority.rawValue == "高" ? "high" : (r.priority.rawValue == "低" ? "low" : "normal")
            item.firstTriggerAt = r.firstTriggerAt.timeIntervalSince1970 * 1000
            item.nextTriggerAt = r.nextTriggerAt.timeIntervalSince1970 * 1000
            item.status = statusCode(r.status)
            item.isActive = r.isEnabled
            item.isCritical = r.reminderStyle == "important"
            item.holidayAware = r.holidayAware
            item.retryCount = r.retryStage
            item.recurrenceMode = r.recurrenceMode
            item.reminderStyle = r.reminderStyle
            item.retryIntervalsMinutes = r.policy.intervals
            item.maxReminderAttempts = r.policy.attempts
            item.quietStartMinute = r.policy.quietStart
            item.quietEndMinute = r.policy.quietEnd
            item.createdAt = r.createdAt.timeIntervalSince1970 * 1000
            item.updatedAt = r.updatedAt.timeIntervalSince1970 * 1000
            item.lastRetryAt = r.lastRetryAt.map { $0.timeIntervalSince1970 * 1000 }
            item.lastCompletedAt = r.lastCompletedAt.map { $0.timeIntervalSince1970 * 1000 }
            item.records = r.records.map { RecordItem(id: $0.id, performedAt: $0.performedAt.timeIntervalSince1970 * 1000, type: $0.type, note: $0.note) }
            return item
        }
        let root = BackupRoot(
            version: 1,
            // 阶段2: 协议版本 2（id/holidayId/isCritical camelCase）
            schemaVersion: 3,
            exportedAt: exportedAt * 1000,
            // v2.0.17: 单调版本随导出带上（判新主依据）
            dataVersion: SyncStore.localVersion,
            reminders: items
        )
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

    /// 读取 JSON 中的 dataVersion（v2.0.17 单调版本；旧文件缺字段返回 0）
    static func dataVersion(of json: String) -> Int {
        guard let data = json.data(using: .utf8),
              let root = try? JSONDecoder().decode(BackupRoot.self, from: data) else {
            return 0
        }
        return root.dataVersion ?? 0
    }

    /// 读取 JSON 内的提醒条数（v2.0.21 F1：首次同步冲突判定用；解析失败返回 0）
    static func itemCount(of json: String) -> Int {
        guard let data = json.data(using: .utf8),
              let root = try? JSONDecoder().decode(BackupRoot.self, from: data) else {
            return 0
        }
        return root.reminders.count
    }

    /// 阶段2: 读取协议 schemaVersion（缺省视为 1——旧协议无 id/holidayId）
    static func schemaVersion(of json: String) -> Int {
        guard let data = json.data(using: .utf8),
              let root = try? JSONDecoder().decode(BackupRoot.self, from: data) else {
            return 1
        }
        return root.schemaVersion ?? 1
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

            if existingIDs.contains(reminder.id) || (item.stableID == nil && existingFingerprints.contains(fingerprint)) {
                skippedCount += 1
                continue
            }

            existingIDs.insert(reminder.id)
            existingFingerprints.insert(fingerprint)
            context.insert(reminder)
            inserted.append(reminder)
            importedCount += 1
        }
        // E3: save 失败不能 touch——否则本地版本抬高 → 下轮 WebDAV 判「本地新」→
        // 上传不含这批提醒的 JSON 覆盖远程（丢数据链）；导入应报失败
        do {
            try context.save()
        } catch {
            // I8: 写入失败 → 回滚已 insert 但未保存的对象，避免后续任意成功 save 意外落库；
            //     并返回 error 区分于「重复跳过」，调用方据此提示而非误报「已存在」
            context.rollback()
            return ImportResult(imported: 0, skipped: 0, inserted: [], error: "导入保存失败：\(error.localizedDescription)")
        }
        SyncStore.touchLocalChange()

        return ImportResult(imported: importedCount, skipped: skippedCount, inserted: inserted, error: nil)
    }

    // MARK: - 编码映射（与 Android 的字符串值对齐）

    /// E5: 导出状态写合法值——原实现把 active/snoozed/overdue 全写成 "notifying"（非法），
    /// 导入时落 default→pending：重试中状态丢失、逾期提醒被当成待触发复活
    private static func statusCode(_ s: ReminderStatus) -> String {
        switch s {
        case .pending:   return "pending"
        case .active:    return "notifying"
        case .snoozed:   return "snoozed"
        case .confirmed: return "confirmed"
        case .overdue:   return "overdue"
        }
    }

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
            case "active", "notifying": return .active
            case "snoozed": return .snoozed
            default: return .pending
            }
        }()

        // 阶段2: 跨端稳定 ID 沿用（syncId 优先，旧 iOS 导出的 id 字符串兜底，都没有 → 重新生成）；
        // holidayId 优先，旧文件只有 holidayName（iOS 旧导出实际塞的是 ID）→ 兜底
        let resolvedID = item.syncId.flatMap(UUID.init(uuidString:))
            ?? item.id?.stringValue.flatMap(UUID.init(uuidString:))
            ?? UUID()
        let resolvedHolidayID = item.holidayId ?? item.holidayName

        let reminder = Reminder(
            id: resolvedID,
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
            holidayID: resolvedHolidayID,
            rulePeriod: rulePeriod,
            ruleWeek: RuleWeek(rawValue: item.ruleWeek ?? 2) ?? .w2,
            ruleWeekday: RuleWeekday(rawValue: item.ruleWeekday ?? 2) ?? .tue,
            firstTriggerAt: Date(timeIntervalSince1970: item.firstTriggerAt / 1000),
            nextTriggerAt: Date(timeIntervalSince1970: item.nextTriggerAt / 1000),
            status: status,
            priority: priority,
            isEnabled: item.isActive,
            holidayAware: item.holidayAware ?? false
        )
        reminder.recurrenceMode = RecurrenceMode(rawValue: item.recurrenceMode ?? "")?.rawValue ?? "fixed"
        reminder.reminderStyle = ReminderStyle(rawValue: item.reminderStyle ?? "")?.rawValue ?? (item.isCritical == true ? "important" : "persistent")
        let policy = ReminderPolicy(intervals: item.retryIntervalsMinutes ?? ReminderPolicy.legacyIntervals,
            attempts: item.maxReminderAttempts ?? 5, quietStart: item.quietStartMinute, quietEnd: item.quietEndMinute)
        reminder.retryIntervalsMinutes = policy.intervals; reminder.maxReminderAttempts = policy.attempts
        reminder.quietStartMinute = policy.quietStart; reminder.quietEndMinute = policy.quietEnd
        reminder.retryStage = min(10, max(0, item.retryCount ?? 0))
        reminder.policyMigrated = true
        if let date = item.createdAt { reminder.createdAt = Date(timeIntervalSince1970: date / 1000) }
        if let date = item.updatedAt { reminder.updatedAt = Date(timeIntervalSince1970: date / 1000) }
        reminder.lastRetryAt = item.lastRetryAt.map { Date(timeIntervalSince1970: $0 / 1000) }
        reminder.lastCompletedAt = item.lastCompletedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
        reminder.records = (item.records ?? []).compactMap { value in
            guard let type = ReminderRecordType(rawValue: value.type) else { return nil }
            return ReminderRecord(id: value.id, performedAt: Date(timeIntervalSince1970: value.performedAt / 1000), type: type, note: value.note)
        }
        return reminder
    }
}
