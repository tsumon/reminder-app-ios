import Foundation

/// 统计洞察汇总（v1.8.7 任务③）
///
/// 数据完全本地：复用 ReminderRecord（操作记录）按日聚合，无网络依赖。
/// 口径（双端一致，v2.0.17 落文档防漂移）：
/// - 完成率 = 确认天数 / (确认天数 + 漏掉天数)
/// - 「漏掉」= 到点未确认进入重试才算（iOS escalateRetry 写 trigger / Android Worker escalate 写 notified）；
///   按时确认**不**记漏 —— 否则每次发通知都记一条，完成率恒 ≈50%
/// - 连续打卡 = confirm 记录按天去重后的连续天数（当前/最长）
/// - 最常忘记时段 = trigger(未确认) 记录按小时分布 Top3
/// - 月历热力图 = 每月每天 confirm 次数
struct StatsSummary {
    let confirmCount: Int
    let missedCount: Int
    /// 完成率 0-1；无数据时为 nil
    let completionRate: Double?
    let currentStreak: Int
    let longestStreak: Int
    /// 最常忘记的时段（小时 0-23 降序）
    let forgetHours: [(hour: Int, count: Int)]
    /// 月历热力图："yyyy-MM-dd" -> confirm 次数
    let heatmap: [String: Int]
}

enum StatsService {

    static func summarize(records: [ReminderRecord]) -> StatsSummary {
        let confirmDates = Set(records.filter { $0.type == ReminderRecordType.confirm.rawValue }.map { startOfDay($0.performedAt) })
        let missed = records.filter { $0.type == ReminderRecordType.trigger.rawValue }
        // v1.9.6 fix: missed 按天去重——同一次漏掉会有 4 条重试阶段 trigger 记录，
        // 直接用 count 会把一次漏记成 4 次，完成率严重失真（与 confirm 按天去重口径对齐）
        let missedDates = Set(missed.map { startOfDay($0.performedAt) })

        let confirmCount = confirmDates.count
        let missedCount = missedDates.count
        let completionRate: Double? = (confirmCount + missedCount) > 0
            ? Double(confirmCount) / Double(confirmCount + missedCount)
            : nil

        // 连续打卡：当前连续（今天或昨天开始往回数）+ 最长连续
        let sorted = confirmDates.sorted()
        let (current, longest) = streak(sorted)

        // 最常忘记时段：trigger 记录按小时计数，Top3
        var hourCounts: [Int: Int] = [:]
        for r in missed {
            let h = Calendar.current.component(.hour, from: r.performedAt)
            hourCounts[h, default: 0] += 1
        }
        let forgetHours = hourCounts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(3)
            .map { (hour: $0.key, count: $0.value) }

        // 月历热力图：confirm 按天计数
        var heatmap: [String: Int] = [:]
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        for r in records where r.type == ReminderRecordType.confirm.rawValue {
            let key = df.string(from: r.performedAt)
            heatmap[key, default: 0] += 1
        }

        return StatsSummary(
            confirmCount: confirmCount,
            missedCount: missedCount,
            completionRate: completionRate,
            currentStreak: current,
            longestStreak: longest,
            forgetHours: forgetHours,
            heatmap: heatmap
        )
    }

    /// 从日期集合计算连续打卡
    private static func streak(_ sorted: [Date]) -> (current: Int, longest: Int) {
        guard !sorted.isEmpty else { return (0, 0) }
        let calendar = Calendar.current
        let today = startOfDay(Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        // 当前连续：今天有记录从今天数，否则从昨天数（今天还没打卡不算断）
        var cursor = sorted.contains(today) ? today : yesterday
        var current = 0
        while sorted.contains(cursor) {
            current += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }

        // 最长连续：遍历排序后的日期
        var longest = 1
        var run = 1
        for i in 1..<sorted.count {
            let days = calendar.dateComponents([.day], from: sorted[i - 1], to: sorted[i]).day ?? 0
            if days == 1 {
                run += 1
                longest = max(longest, run)
            } else {
                run = 1
            }
        }
        return (current, max(longest, current))
    }

    private static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }
}
