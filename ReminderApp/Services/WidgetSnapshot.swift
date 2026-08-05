import Foundation

/// 小组件展示的数据（纯值类型，App 与 Widget 共享）
struct WidgetReminderData: Codable {
    var unhandledCount: Int
    var nextTitle: String
    var nextTime: Date?
    var updatedAt: Date
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
}
