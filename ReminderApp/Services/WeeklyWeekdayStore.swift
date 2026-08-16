import Foundation

/// v2.4.2: 每周提醒的意图星期存储（1=周一..7=周日）。
/// 沿用 CriticalStore 的 UserDefaults 策略——避免改 SwiftData schema 引发迁移风险。
/// 用途：App 启动时检测 weekly 提醒锚点星期与意图不符 → 提示用户一键修正。
enum WeeklyWeekdayStore {
    private static let key = "weekly_weekday_map"

    private static func map() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
    }

    static func get(for id: UUID) -> Int? {
        map()[id.uuidString]
    }

    static func set(_ weekday: Int?, for id: UUID) {
        var m = map()
        if let weekday, (1...7).contains(weekday) {
            m[id.uuidString] = weekday
        } else {
            m.removeValue(forKey: id.uuidString)
        }
        UserDefaults.standard.set(m, forKey: key)
    }

    /// 检测锚点错位：weekly/biweekly 且存了意图星期，但锚点实际星期不符
    static func anchorMismatches(reminders: [Reminder]) -> [Reminder] {
        let m = map()
        return reminders.filter { r in
            guard r.cycle == .weekly || r.cycle == .biweekly,
                  r.isEnabled, r.status != .confirmed,
                  let intended = m[r.id.uuidString] else { return false }
            let cur = ((Calendar.current.component(.weekday, from: r.firstTriggerAt) + 5) % 7) + 1
            return cur != intended
        }
    }
}
