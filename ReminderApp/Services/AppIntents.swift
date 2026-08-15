import AppIntents
import SwiftData

/// v2.1.1: 快捷指令 / Siri 集成（自签环境可用的原生能力，无需开发者证书）。
/// 在「快捷指令」App 里搜索「循环提醒」即可添加：
/// - 「添加提醒」：标题 + 可选时间，立即在 App 内创建一条一次性提醒
/// - 「下次提醒」：查询最近一条未完成的提醒（返回对话文本）
struct ReminderShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddReminderIntent(),
            phrases: [
                "用\(.applicationName)添加提醒",
                "添加提醒到\(.applicationName)"
            ],
            shortTitle: "添加提醒",
            systemImageName: "bell.badge.fill"
        )
        AppShortcut(
            intent: NextReminderIntent(),
            phrases: [
                "\(.applicationName)下次提醒",
                "查看\(.applicationName)最近提醒"
            ],
            shortTitle: "下次提醒",
            systemImageName: "clock"
        )
    }
}

/// 添加提醒（一次性：标题 + 可选时间；不带时间则立即触发）
struct AddReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "添加提醒"
    static var description = IntentDescription("在循环提醒中添加一条提醒（默认一次性）")

    @Parameter(title: "标题")
    var title: String

    @Parameter(title: "时间", description: "留空则立即提醒")
    var when: Date?

    @MainActor
    func perform() async throws -> some IntentResult {
        let trigger = when ?? Date()
        let reminder = Reminder(
            title: title,
            kind: .cycle,
            cycle: .once,
            firstTriggerAt: trigger,
            nextTriggerAt: trigger
        )
        let context = ReminderApp.sharedModelContainer.mainContext
        context.insert(reminder)
        try context.save()
        SyncStore.touchLocalChange()

        // 立即排通知（含勿扰顺延/幽灵守卫）
        await ReminderEngine.shared.scheduleAllNotifications(for: reminder)
        return .result()
    }
}

/// 查询下次提醒（未完成的最近一条）
struct NextReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "下次提醒"
    static var description = IntentDescription("查询最近一条未完成的提醒")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ReminderApp.sharedModelContainer.mainContext
        let all = (try? context.fetch(FetchDescriptor<Reminder>())) ?? []
        let next = all
            .filter { $0.isEnabled && $0.status != .confirmed }
            .min { $0.nextTriggerAt < $1.nextTriggerAt }

        if let next {
            let time = next.nextTriggerAt.formatted(date: .numeric, time: .shortened)
            return .result(dialog: "\(next.title)（\(time)）")
        }
        return .result(dialog: "当前没有待提醒事项")
    }
}
