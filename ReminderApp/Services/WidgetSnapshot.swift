import Foundation

/// 小组件展示的数据（纯值类型，App 与 Widget 共享）
struct WidgetReminderData: Codable {
    var unhandledCount: Int
    var nextTitle: String
    var nextTime: Date?
    var updatedAt: Date
    /// 下一次提醒的 ID（UUID 字符串），供小组件「完成」按钮定位（v1.8.7）
    var nextReminderID: String?
}

/// App 与 Widget 之间通过 App Group 共享数据
enum WidgetSnapshot {
    static let appGroupID = "group.com.reminder.app"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func save(_ data: WidgetReminderData) {
        if let encoded = try? JSONEncoder().encode(data) {
            defaults?.set(encoded, forKey: "widget_data")
        }
    }

    static func load() -> WidgetReminderData {
        guard let data = defaults?.data(forKey: "widget_data"),
              let decoded = try? JSONDecoder().decode(WidgetReminderData.self, from: data) else {
            return WidgetReminderData(
                unhandledCount: 0,
                nextTitle: "暂无提醒",
                nextTime: nil,
                updatedAt: Date()
            )
        }
        return decoded
    }

    // MARK: - 小组件「完成」标记（v1.8.7）
    // 点击小组件完成按钮 → AppIntent 把提醒 ID 记到 App Group；
    // App 下次启动时读取并同步到数据库（confirm + 重排），然后清空。

    private static let completedIDsKey = "widget_completed_ids"

    /// 标记一个提醒已在小组件上完成（幂等）
    static func markCompleted(reminderID: String) {
        var ids = completedReminderIDs()
        ids.insert(reminderID)
        defaults?.set(Array(ids), forKey: completedIDsKey)
    }

    /// 读取待同步的已完成提醒 ID 集合
    static func completedReminderIDs() -> Set<String> {
        guard let raw = defaults?.array(forKey: completedIDsKey) as? [String] else { return [] }
        return Set(raw)
    }

    /// 清空已完成标记（App 同步落库后调用）
    static func clearCompletedReminderIDs(_ ids: Set<String>) {
        guard let existing = defaults?.array(forKey: completedIDsKey) as? [String] else { return }
        let remaining = Set(existing).subtracting(ids)
        defaults?.set(Array(remaining), forKey: completedIDsKey)
    }
}

