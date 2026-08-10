import AppIntents
import WidgetKit

/// 小组件「⏸ 稍后」按钮（v2.0.16，iOS 17+ widget 交互）
///
/// 点击后把提醒 ID 记到 App Group（WidgetSnapshot.markSnoozed），
/// 并立即刷新小组件；App 下次启动时读取该标记并同步到数据库
/// （snooze 推迟 15 分钟 + 重排通知），见 ReminderApp.swift。
struct SnoozeReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "稍后提醒"
    static var description = IntentDescription(LocalizedStringResource("将该提醒推迟 15 分钟再提醒"))

    @Parameter(title: "提醒 ID")
    var reminderID: String

    init() {}

    init(reminderID: String) {
        self.reminderID = reminderID
    }

    func perform() async throws -> some IntentResult {
        WidgetSnapshot.markSnoozed(reminderID: reminderID)
        // 刷新小组件：推迟后的下次提醒立即可见
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
