import Foundation
import SwiftData

/// 智能频率建议（功能8）——两者结合：
///  1) 同类（标题字符级相似）提醒的历史频率；
///  2) 这些提醒的「confirm」记录时间分布（打卡完成历史）。
/// 加权结合后给出 cycle + customDays 建议，并附可解释文案。
///
/// 纯同步、无网络。创建页在 Task 中取好全部提醒后传入。
/// 加权策略：打卡间隔更贴近真实行为 → 0.6 权重；同类历史频率 → 0.4 权重。
enum FrequencySuggester {

    struct Suggestion {
        let cycle: ReminderCycle
        let customDays: Int
        let reason: String
        /// false 表示无足够历史，给了默认「每周」
        let hasSuggestion: Bool
    }

    /// 周期 → 标准天数（I19: 用显式常量，双端必须与 Android 硬编码 1/7/14/30/90/365 对齐，
    /// 不依赖 ReminderCycle.days 枚举值，避免枚举改动导致双端口径分歧）
    private static let CYCLE_DAYS: [ReminderCycle: Int] = [
        .daily: 1, .weekly: 7, .biweekly: 14, .monthly: 30, .quarterly: 90, .yearly: 365
    ]
    private static func cycleDays(_ cycle: ReminderCycle, customDays: Int) -> Int {
        switch cycle {
        case .custom: return max(1, customDays)
        case .once:   return 0   // 与 Android 一致：once/其它视为无周期信号
        default:      return CYCLE_DAYS[cycle] ?? 0
        }
    }

    private static let CANONICAL = [1, 7, 14, 30, 90, 365]

    /// 把任意天数贴近到最相近的标准周期；偏差 > 容差则建议 custom
    private static func snapToCycle(_ days: Double) -> (ReminderCycle, Int) {
        guard days > 0 else { return (.weekly, 7) }
        var best = CANONICAL.first!
        var bestDiff = Double.greatestFiniteMagnitude
        for c in CANONICAL {
            let d = abs(Double(c) - days)
            if d < bestDiff { bestDiff = d; best = c }
        }
        // 容差：与最近标准点差距 > 该标准点的 35% → 走自定义
        if bestDiff > Double(best) * 0.35 {
            let cd = max(1, Int(days.rounded()))
            // I21: 四舍五入后若等价「每天」则归并为 daily，避免返回「每 1 天」自定义
            return cd <= 1 ? (.daily, 1) : (.custom, cd)
        }
        switch best {
        case 1:   return (.daily, 1)
        case 7:   return (.weekly, 7)
        case 14:  return (.biweekly, 14)
        case 30:  return (.monthly, 30)
        case 90:  return (.quarterly, 90)
        case 365: return (.yearly, 365)
        default:  return (.weekly, 7)
        }
    }

    /// 字符级 Jaccard 相似度（中英文通用，无需分词）
    private static func similarity(_ a: String, _ b: String) -> Double {
        let sa = Set(a.filter { !$0.isWhitespace })
        let sb = Set(b.filter { !$0.isWhitespace })
        guard !sa.isEmpty, !sb.isEmpty else { return 0 }
        let inter = sa.intersection(sb).count
        return Double(inter) / Double(sa.union(sb).count)
    }

    // I18: 显式传入 confirm 记录时间戳（秒），对齐 Android 显式传入；缺省时回退读 SwiftData 惰性关系
    static func suggest(title: String, reminders: [Reminder],
                        confirmTimestampsByReminder: [UUID: [TimeInterval]] = [:]) -> Suggestion {
        guard !reminders.isEmpty else {
            return Suggestion(cycle: .weekly, customDays: 7,
                              reason: "暂无历史数据，已为你默认「每周」".localized,
                              hasSuggestion: false)
        }

        // 1) 同类提醒（仅 cycle 类参与频率统计）
        let similar = reminders.filter { $0.kind == .cycle && similarity(title, $0.title) >= 0.2 }
        let similarDays = similar.map { cycleDays($0.cycle, customDays: $0.customDays) }.filter { $0 > 0 }

        // 2) 打卡历史间隔（天）
        let pool = similar.isEmpty ? reminders.filter { $0.kind == .cycle } : similar
        var intervals: [Double] = []
        for r in pool {
            // I18: 优先用调用方显式预取的 confirm 时间戳（强制 SwiftData 惰性关系在调用方 context 解析），
            //     与 Android 显式传入对齐；缺省回退读 r.records
            let times: [TimeInterval]
            if let list = confirmTimestampsByReminder[r.id] {
                times = list.sorted()
            } else {
                times = r.records
                    .filter { $0.type == ReminderRecordType.confirm.rawValue }
                    .map { $0.performedAt.timeIntervalSince1970 }
                    .sorted()
            }
            for i in 1..<times.count {
                let gap = (times[i] - times[i - 1]) / (24 * 3600)
                if gap >= 0.5 && gap <= 400 { intervals.append(gap) }
            }
        }

        let fromHistory = similarDays.isEmpty ? nil : modeOrMedian(similarDays)
        // I23: median 空输入返回 nil（而非 0），直接作为可选值
        let fromCheckin = median(intervals)

        if let fh = fromHistory, let fc = fromCheckin {
            let blended = Double(fh) * 0.4 + fc * 0.6
            let (cyc, cd) = snapToCycle(blended)
            // I22: fromHistory 非 nil ⇒ similar 非空，similar.isEmpty 分支恒不可达，删死分支
            // I20: 实际是中位数，文案改为「中位间隔」
            let reason = Localized("参考 %d 条同类提醒与你的打卡节奏（中位间隔 %.1f 天），建议每 %@",
                                  similar.count, fc, label(cyc, cd))
            return Suggestion(cycle: cyc, customDays: cd, reason: reason, hasSuggestion: true)
        } else if let fh = fromHistory {
            let (cyc, cd) = snapToCycle(Double(fh))
            // I22: fromHistory 非 nil ⇒ similar 非空，similar.isEmpty 分支恒不可达，删死分支
            let reason = Localized("你有 %d 条类似「%@」的提醒多为每 %@，建议保持一致",
                                   similar.count, similar.first!.title, label(cyc, cd))
            return Suggestion(cycle: cyc, customDays: cd, reason: reason, hasSuggestion: true)
        } else if let fc = fromCheckin {
            let (cyc, cd) = snapToCycle(fc)
            // I20: 实际是中位数，文案改为「中位间隔」
            return Suggestion(cycle: cyc, customDays: cd,
                              reason: Localized("根据打卡记录（中位间隔 %.1f 天），建议每 %@", fc, label(cyc, cd)),
                              hasSuggestion: true)
        } else {
            return Suggestion(cycle: .weekly, customDays: 7,
                              reason: "暂无足够历史，已为你默认「每周」".localized,
                              hasSuggestion: false)
        }
    }

    private static func label(_ cycle: ReminderCycle, _ customDays: Int) -> String {
        cycle == .custom ? Localized("每 %d 天", customDays) : cycle.rawValue.localized
    }

    // I23: 空输入返回 nil（而非 0），避免未来误造「0 天」建议
    private static func median(_ xs: [Double]) -> Double? {
        let s = xs.sorted()
        let n = s.count
        guard n > 0 else { return nil }
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2.0
    }

    /// 有众数（出现≥2）取众数，否则取中位数
    private static func modeOrMedian(_ xs: [Int]) -> Int {
        let freq = Dictionary(grouping: xs, by: { $0 }).mapValues { $0.count }
        let max = freq.values.max() ?? 0
        if max >= 2 {
            let modes = freq.filter { $0.value == max }.map { $0.key }.sorted()
            return modes.count == 1 ? modes.first! : Int(median(modes.map { Double($0) }) ?? 0)
        }
        return Int(median(xs.map { Double($0) }) ?? 0)
    }
}
