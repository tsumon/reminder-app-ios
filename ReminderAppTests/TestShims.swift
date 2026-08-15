import Foundation

/// 测试替身（仅 BackupProtocolCheck target 编译）：
/// BackupHelper 依赖 ReminderEngine.CriticalStore（UserDefaults 关键提醒标记），
/// 完整 ReminderEngine 会拖入 NotificationManager/LunarCalendar 等产品依赖，
/// 此处只 stub 出 BackupHelper 用到的符号，协议编解码测试不涉及重试/调度逻辑。
/// 测试替身：仅实现 BackupHelper 用到的符号（下一次触发重算 + CriticalStore）。
/// 完整 ReminderEngine 在 ReminderEngine.swift（依赖 NotificationManager/LunarCalendar 等
/// 产品代码，协议编解码测试不需要），此处用 class 便于无参构造。
final class ReminderEngine {
    static let shared = ReminderEngine()
    func calculateNextTrigger(after now: Date, reminder: Reminder) -> Date {
        // 周期提醒：按 cycle 推到未来（测试只用 once/可重复的状态机，不校验精确周期）
        let next = reminder.nextTriggerAt
        if next > now { return next }
        switch reminder.cycle {
        case .daily: return Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        case .weekly: return Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        default: return Calendar.current.date(byAdding: .month, value: 1, to: now) ?? now
        }
    }

    struct CriticalStore {
        private static let key = "critical_reminders_test"
        static func isCritical(_ id: UUID) -> Bool {
            UserDefaults.standard.dictionary(forKey: key)?[id.uuidString] as? Bool ?? false
        }
        static func setCritical(_ value: Bool, for id: UUID) {
            var dict = UserDefaults.standard.dictionary(forKey: key) ?? [:]
            if value {
                dict[id.uuidString] = true
            } else {
                dict.removeValue(forKey: id.uuidString)
            }
            UserDefaults.standard.set(dict, forKey: key)
        }
    }
}
