import Foundation

/// 勿扰时段（v2.1.1）：单条提醒的每日静默窗口。
/// 存 UserDefaults（按提醒 UUID 索引）——沿用 CriticalStore 的既有策略，
/// 避免改动 SwiftData schema 引发无法本地验证的迁移崩溃。
/// 语义：start 到 end（分钟，0..1439）之间不弹通知；end < start 表示跨天窗口（如 22:00–08:00）。
enum QuietHoursStore {
    private static func key(_ id: UUID, _ suffix: String) -> String {
        "quiet_hours_\(id.uuidString)_\(suffix)"
    }

    static func isEnabled(for id: UUID) -> Bool {
        UserDefaults.standard.object(forKey: key(id, "start")) != nil
    }

    static func startMinute(for id: UUID) -> Int? {
        let v = UserDefaults.standard.integer(forKey: key(id, "start"))
        return UserDefaults.standard.object(forKey: key(id, "start")) == nil ? nil : v
    }

    static func endMinute(for id: UUID) -> Int? {
        let v = UserDefaults.standard.integer(forKey: key(id, "end"))
        return UserDefaults.standard.object(forKey: key(id, "end")) == nil ? nil : v
    }

    /// 设置勿扰窗口；传 nil 关闭
    static func set(start: Int?, end: Int?, for id: UUID) {
        if let start, let end {
            UserDefaults.standard.set(start, forKey: key(id, "start"))
            UserDefaults.standard.set(end, forKey: key(id, "end"))
        } else {
            UserDefaults.standard.removeObject(forKey: key(id, "start"))
            UserDefaults.standard.removeObject(forKey: key(id, "end"))
        }
    }

    /// 触发时间落在窗口内时顺延到窗口结束（未启用/不在窗口内原样返回）
    static func adjust(_ date: Date, for id: UUID) -> Date {
        guard let s = startMinute(for: id), let e = endMinute(for: id) else { return date }
        let cal = Calendar.current
        let mins = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        let day = cal.startOfDay(for: date)

        if s < e {
            // 当天窗口：s ≤ mins < e → 顺延到 e
            if mins >= s && mins < e {
                return cal.date(byAdding: .minute, value: e - mins, to: date) ?? date
            }
        } else {
            // 跨天窗口（22:00–08:00）：mins ≥ s（深夜）或 mins < e（凌晨）
            let todayEnd = cal.date(byAdding: .minute, value: e, to: day) ?? date
            if mins >= s {
                return cal.date(byAdding: .day, value: 1, to: todayEnd) ?? todayEnd
            }
            if mins < e {
                return todayEnd
            }
        }
        return date
    }
}
