import Foundation
import UserNotifications

/// 批次2 功能3: 统计周报推送（iOS）
///
/// iOS 本地通知是「预排内容、到点由系统发出」，触发时无法执行代码动态计算，
/// 因此策略为：App 每次启动/回前台时计算「本周至今」统计，覆盖式安排每周日 20:00
/// 的周报通知（固定 identifier，重复 add 即覆盖）。周日 20:00 用户收到的是
/// 「最近一次打开 App 时」的本周统计，已足够接近实时（本周数据变化有限）。
///
/// 无任何操作记录时跳过（不打扰用户），与 Android WeeklyReportWorker 对齐。
enum WeeklyReportService {

    static let identifier = "weekly-report"

    /// 计算并安排（覆盖）每周日 20:00 的周报通知。
    /// 在 App 启动 / 回前台时调用。
    @MainActor
    static func schedule(records: [ReminderRecord]) async {
        // v2.0.22: 无记录时不再直接 return——用户清空数据后，旧周报通知
        // （固定 identifier）仍然存在，会在周日继续弹出过期的「本周统计」。
        // 必须先取消旧通知，再跳过本轮安排。
        guard !records.isEmpty else {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }

        // 本周起点（周一到周日，与 Android 对齐）
        let weekStart = startOfWeek(Date())
        let weekRecords = records.filter { $0.performedAt >= weekStart }
        let weekSummary = StatsService.summarize(records: weekRecords)
        let fullSummary = StatsService.summarize(records: records)

        let rateText: String
        if let rate = weekSummary.completionRate {
            rateText = "\(Int((rate * 100).rounded()))%"
        } else {
            rateText = "暂无".localized
        }

        var bodyLines: [String] = []
        bodyLines.append(Localized("完成 %d 项 · 漏掉 %d 项", weekSummary.confirmCount, weekSummary.missedCount))
        bodyLines.append(Localized("完成率 %@", rateText))
        if fullSummary.currentStreak > 0 {
            bodyLines.append(Localized("连续打卡 %d 天", fullSummary.currentStreak))
        }
        // 批次3 功能3: AI 解读——把数字变成一句可执行的洞察（未配置 AI 或调用失败则不追加）
        if let insight = await aiInsight(week: weekSummary, full: fullSummary, rateText: rateText) {
            bodyLines.append("💡 " + insight)
        }
        let body = bodyLines.joined(separator: "\n")

        let content = UNMutableNotificationContent()
        content.title = "📊 本周统计周报".localized
        content.body = body
        content.sound = .default
        content.categoryIdentifier = NotificationManager.advanceCategoryID
        content.userInfo = ["type": "weekly_report"]

        // 每周日(weekday=1) 20:00 重复触发；固定 identifier 覆盖旧内容
        var comps = DateComponents()
        comps.weekday = 1 // 周日
        comps.hour = 20
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await UNUserNotificationCenter.current().add(request)
            print("[WeeklyReport] 周报通知已安排（本周完成 \(weekSummary.confirmCount) / 漏掉 \(weekSummary.missedCount)）")
        } catch {
            print("[WeeklyReport] 安排失败: \(error.localizedDescription)")
        }
    }

    /// 批次3 功能3: 周报 AI 解读。
    ///
    /// 把「完成/漏掉/连续/常忘时段」几个数字丢给已配置的 AI，换回一句可执行的短建议。
    /// 设计上是**纯增量**：未配置 API Key、超时（25s）或任何异常都返回 nil，
    /// 周报本身照常发出，绝不因为 AI 挂掉而丢通知。
    @MainActor
    private static func aiInsight(
        week: StatsSummary,
        full: StatsSummary,
        rateText: String
    ) async -> String? {
        let settings = AISettings.shared
        guard settings.isConfigured else { return nil }

        let forget = week.forgetHours.prefix(2)
            .map { Localized("%d 点(%d 次)", $0.hour, $0.count) }
            .joined(separator: "、")
        var facts = Localized("本周完成 %d 项，漏掉 %d 项，完成率 %@。", week.confirmCount, week.missedCount, rateText)
        facts += Localized("当前连续打卡 %d 天，历史最长 %d 天。", full.currentStreak, full.longestStreak)
        if !forget.isEmpty { facts += Localized("最常漏掉的时段：%@。", forget) }

        let systemPrompt = "你是一位简洁克制的习惯教练。根据用户本周的提醒完成数据，用中文写一句 40 字以内的解读：先点评趋势，再给一条具体可执行的建议。不要寒暄、不要分点、不要复述原始数字。".localized

        let model = settings.model
        let endpoint = settings.apiEndpoint
        let apiKey = settings.apiKey

        do {
            let text = try await withTimeout(seconds: 25) {
                try await AIService.shared.complete(
                    model: model,
                    messages: [
                        AIService.ChatMessage(role: "system", content: systemPrompt),
                        AIService.ChatMessage(role: "user", content: facts)
                    ],
                    endpoint: endpoint,
                    apiKey: apiKey
                )
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return String(trimmed.prefix(80))
        } catch {
            print("[WeeklyReport] AI 解读失败，跳过: \(error.localizedDescription)")
            return nil
        }
    }

    /// 给异步任务加超时：谁先完成用谁，超时抛错。
    private static func withTimeout<T: Sendable>(
        seconds: Double,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw AIInsightTimeout()
            }
            guard let result = try await group.next() else { throw AIInsightTimeout() }
            group.cancelAll()
            return result
        }
    }

    private struct AIInsightTimeout: Error {}

    /// 本周起点：周一 00:00（Calendar 默认周一为一周首日）
    private static func startOfWeek(_ date: Date) -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 2 // 周一
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        guard let monday = cal.date(from: comps) else { return Calendar.current.startOfDay(for: date) }
        return monday
    }
}
