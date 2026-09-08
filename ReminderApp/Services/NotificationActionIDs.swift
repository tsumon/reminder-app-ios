import Foundation

/// 通知动作标识（与 UNNotificationCategory / didReceive 对照；Android 对端见 NotificationManager.ACTION_*）。
enum NotificationActionIDs {
    static let category = "REMINDER_CATEGORY"
    static let confirm = "CONFIRM_ACTION"
    static let snooze = "SNOOZE_ACTION"
}
