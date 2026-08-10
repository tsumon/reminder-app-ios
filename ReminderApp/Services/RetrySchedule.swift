import Foundation

/// 递增重试时间表（P1-2，v2.0.8）—— iOS 侧唯一事实来源
///
/// 双端约定（与 Android `ReminderEngine.retryIntervals` / `MAX_ESCALATION` 完全一致）：
///  - 到期未确认后依次重试：1h → 4h → 12h → 24h → 24h
///  - 从 D-day 起的累计时间轴：T、T+1h、T+5h、T+17h、T+41h（共 5 次触发）
///  - 第 5 次触发即标 `overdue`，停止轰炸，留在列表等用户手动确认 / 重新打开
///  - 重试期间【不推进周期】，周期只在「确认完成 / 重新打开」时前进
///
/// 纯 Foundation、无 UserNotifications / SwiftData 依赖，
/// 因此可以被 macOS 命令行回归检查（ReminderAppTests）直接编译并断言。
enum RetrySchedule {

    /// 重试上限：达到第 5 阶段即 overdue
    static let maxStage = 5

    /// 「刚完成第 stage 次触发」到「下一次触发」的等待时长（秒）。
    ///
    /// stage=0/1 → 1h，2 → 4h，3 → 12h，4 及以上 → 24h。
    /// 对应 Android `retryIntervals[oldRetryCount]`（oldRetryCount = stage - 1）。
    static func delay(afterStage stage: Int) -> TimeInterval {
        if stage <= 1 { return 3600 }      // 1 小时
        if stage == 2 { return 14400 }     // 4 小时
        if stage == 3 { return 43200 }     // 12 小时
        return 86400                       // 24 小时
    }

    /// 从 D-day 起、到达「第 stage 次触发」的累计偏移（秒）。
    /// stage=1 → 0（D-day 本身）、2 → 1h、3 → 5h、4 → 17h、5 → 41h。
    static func cumulativeOffset(toStage stage: Int) -> TimeInterval {
        guard stage > 1 else { return 0 }
        var total: TimeInterval = 0
        for s in 1..<stage { total += delay(afterStage: s) }
        return total
    }

    /// 启动追赶：App 被杀期间只有系统在按预排时间发通知，库里的阶段不会自己动。
    /// 回到 App 时按「错过了几次触发」把阶段一次性补齐。
    ///
    /// - Parameters:
    ///   - stage: 库里记录的当前阶段（0 表示还没触发过）
    ///   - dueAt: 库里记录的下次触发时间
    ///   - now: 当前时间
    /// - Returns: 补齐后的阶段、下次触发时间，以及是否已达上限（需标 overdue）
    static func catchUp(stage: Int, dueAt: Date, now: Date) -> (stage: Int, dueAt: Date, isOverdue: Bool) {
        var s = stage
        var due = dueAt
        // 用 due 自身累加而不是 now，保证与预排通知的时间轴严格一致
        while due <= now && s < maxStage {
            s += 1
            due = due.addingTimeInterval(delay(afterStage: s))
        }
        return (s, due, s >= maxStage)
    }
}
