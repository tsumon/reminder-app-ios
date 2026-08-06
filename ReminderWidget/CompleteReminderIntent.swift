import AppIntents
import WidgetKit

/// 小组件「✓ 完成」按钮（v1.8.7，iOS 17+ widget 交互）
///
/// 点击后把提醒 ID 记到 App Group（WidgetSnapshot.markCompleted），
/// 并立即刷新小组件；App 下次启动时读取该标记并同步到数据库
/// （confirm + 重排通知），见 ReminderApp.swift。
struct CompleteReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "完成提醒"
    static var description = IntentDescription("将该提醒标记为已完成并安排下一次")

    @Parameter(title: "提醒 ID")
    var reminderID: String

    init() {}

    init(reminderID: String) {
        self.reminderID = reminderID
    }

    func perform() async throws -> some IntentResult {
        WidgetSnapshot.markCompleted(reminderID: reminderID)
        // 刷新小组件：完成后的下一次提醒立即可见
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
