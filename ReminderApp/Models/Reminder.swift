import Foundation
import SwiftData

/// 提醒大类
enum ReminderKind: String, Codable, CaseIterable {
    case cycle = "周期提醒"    // 每N天/周/月循环
    case date  = "日期提醒"    // 固定日期（生日、节假日等）
}

/// 日期提醒子类型
enum DateReminderType: String, Codable, CaseIterable {
    case solarBirthday = "新历生日"
    case lunarBirthday = "农历生日"
    case holiday       = "节假日"
}

/// 提醒周期类型（仅 cycle 类使用）
enum ReminderCycle: String, Codable, CaseIterable {
    case daily = "每天"
    case weekly = "每周"
    case biweekly = "每两周"
    case monthly = "每月"
    case quarterly = "每季度"
    case yearly = "每年"
    case custom = "自定义"

    var days: Int {
        switch self {
        case .daily:    return 1
        case .weekly:   return 7
        case .biweekly: return 14
        case .monthly:  return 30
        case .quarterly: return 90
        case .yearly:   return 365
        case .custom:   return 0
        }
    }
}

/// 提醒状态
enum ReminderStatus: String, Codable {
    case pending   = "等待中"    // 还未到提醒时间
    case active    = "提醒中"    // 已触发，等待确认
    case snoozed   = "已推迟"    // 用户点了稍后
    case confirmed = "已完成"    // 用户已确认
    case overdue   = "已过期"    // 超过递增重试上限
}

/// 确认/操作记录
@Model
final class ReminderRecord {
    var id: UUID
    var performedAt: Date
    var type: String        // "confirm" | "snooze" | "trigger" | "advance"
    var note: String

    init(id: UUID = UUID(), performedAt: Date = Date(), type: String, note: String = "") {
        self.id = id
        self.performedAt = performedAt
        self.type = type
        self.note = note
    }
}

/// 提醒主体模型（SwiftData）
@Model
final class Reminder {
    var id: UUID
    var title: String
    var note: String

    // MARK: - 提醒大类
    var kind: ReminderKind

    // MARK: - 周期提醒字段（kind == .cycle 时有效）
    var cycle: ReminderCycle
    var customDays: Int

    // MARK: - 日期提醒字段（kind == .date 时有效）
    var dateType: DateReminderType?
    var targetMonth: Int       // 1-12，目标月份
    var targetDay: Int         // 1-31，目标日期
    var advanceDays: Int       // 提前几天开始提醒（默认 3）
    var reminderHour: Int      // 提醒时间-小时（默认 9）
    var reminderMinute: Int    // 提醒时间-分钟（默认 0）
    var holidayID: String?     // 节假日 ID（dateType == .holiday 时有效）

    // MARK: - 通用字段
    /// 首次触发时间的锚点——用于防止周期漂移
    var firstTriggerAt: Date
    var nextTriggerAt: Date
    var status: ReminderStatus
    var retryStage: Int
    var lastRetryAt: Date?
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    /// 所有操作记录
    @Relationship(deleteRule: .cascade) var records: [ReminderRecord] = []

    // MARK: - Init

    init(
        id: UUID = UUID(),
        title: String,
        note: String = "",
        kind: ReminderKind = .cycle,
        cycle: ReminderCycle = .weekly,
        customDays: Int = 0,
        dateType: DateReminderType? = nil,
        targetMonth: Int = 1,
        targetDay: Int = 1,
        advanceDays: Int = 3,
        reminderHour: Int = 9,
        reminderMinute: Int = 0,
        holidayID: String? = nil,
        firstTriggerAt: Date,
        nextTriggerAt: Date,
        status: ReminderStatus = .pending,
        retryStage: Int = 0,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.kind = kind
        self.cycle = cycle
        self.customDays = customDays
        self.dateType = dateType
        self.targetMonth = targetMonth
        self.targetDay = targetDay
        self.advanceDays = advanceDays
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.holidayID = holidayID
        self.firstTriggerAt = firstTriggerAt
        self.nextTriggerAt = nextTriggerAt
        self.status = status
        self.retryStage = retryStage
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - 计算属性

    var effectiveDays: Int {
        cycle == .custom ? customDays : cycle.days
    }

    /// 日期提醒的显示文本
    var dateDisplayText: String {
        let df = DateFormatter(); df.locale = Locale(identifier: "zh_CN")
        switch kind {
        case .cycle:
            if cycle == .custom { return "每 \(customDays) 天" }
            return cycle.rawValue
        case .date:
            switch dateType {
            case .solarBirthday:
                return "\(targetMonth)月\(targetDay)日"
            case .lunarBirthday:
                let monthNames = ["", "正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]
                let dayNames = ["", "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
                                "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
                                "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"]
                let m = min(max(targetMonth, 1), 12)
                let d = min(max(targetDay, 1), 30)
                return monthNames[m] + dayNames[d]
            case .holiday:
                return HolidayService.find(by: holidayID ?? "")?.name ?? holidayID ?? ""
            case .none:
                return ""
            }
        }
    }

    /// 提醒类型的图标
    var kindIcon: String {
        switch kind {
        case .cycle: return "repeat"
        case .date:
            switch dateType {
            case .solarBirthday: return "gift"
            case .lunarBirthday: return "moon.stars"
            case .holiday:       return "flag"
            case .none:          return "calendar"
            }
        }
    }
}
