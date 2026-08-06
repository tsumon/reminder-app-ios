import Foundation
import UserNotifications
import SwiftData

/// 通知管理器：负责权限请求、通知注册、分类（带操作按钮）
@MainActor
final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    @Published var isAuthorized = false

    /// 通知分类 ID（注册到 iOS 系统，关联确认/稍后按钮）
    static let categoryIdentifier = "REMINDER_CATEGORY"

    /// 预告通知分类（无操作按钮，仅信息展示）
    static let advanceCategoryID = "REMINDER_ADVANCE"

    /// Action 标识符
    static let confirmActionID = "CONFIRM_ACTION"
    static let snoozeActionID = "SNOOZE_ACTION"

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - 权限请求

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            isAuthorized = granted
            if granted {
                registerCategories()
            }
            return granted
        } catch {
            print("[NotificationManager] 授权失败: \(error.localizedDescription)")
            return false
        }
    }

    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
        if isAuthorized {
            registerCategories()
        }
    }

    // MARK: - 注册通知分类和操作按钮

    private func registerCategories() {
        // 「确认完成」按钮
        let confirmAction = UNNotificationAction(
            identifier: Self.confirmActionID,
            title: "确认完成",
            options: [.foreground]  // 点击后打开 App 处理
        )

        // 「稍后提醒」按钮
        let snoozeAction = UNNotificationAction(
            identifier: Self.snoozeActionID,
            title: "稍后提醒",
            options: [.authenticationRequired]  // 不需要解锁也能操作
        )

        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [confirmAction, snoozeAction],
            intentIdentifiers: [],
            options: [.customDismissAction]  // 滑动消除也会触发回调
        )

        // 预告通知分类（无操作按钮）
        let advanceCategory = UNNotificationCategory(
            identifier: Self.advanceCategoryID,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([category, advanceCategory])
        print("[NotificationManager] 通知分类已注册")
    }

    // MARK: - 发送本地通知

    /// 为指定提醒安排本地通知（会先移除旧通知，避免竞态把刚加的也删掉）
    func scheduleNotification(for reminder: Reminder, badgeCount: Int = 1) async {
        // 等待旧通知移除完成后再添加，避免「异步删除晚于添加」把新通知也删掉
        await removePendingNotification(for: reminder.id)
        try? await addDdayNotification(for: reminder, badgeCount: badgeCount)
    }

    /// 真正添加 D-day 通知（不含移除逻辑，供 scheduleAllNotifications 在统一移除后调用）
    func addDdayNotification(for reminder: Reminder, badgeCount: Int = 1) async throws {
        let content = UNMutableNotificationContent()
        content.title = "⏰ \(reminder.title)"
        content.body = reminder.note.isEmpty
            ? "该完成了，点击确认或稍后提醒"
            : reminder.note
        content.sound = .default
        content.badge = NSNumber(value: badgeCount)
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [
            "reminderID": reminder.id.uuidString,
            "reminderTitle": reminder.title
        ]

        // 计算触发时间
        let triggerDate = reminder.nextTriggerAt
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "reminder-\(reminder.id.uuidString)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            print("[NotificationManager] 通知已安排: \(reminder.title) @ \(triggerDate)")
        } catch {
            print("[NotificationManager] 安排通知失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 预告通知（无操作按钮）

    func scheduleAdvanceNotification(for reminder: Reminder, at date: Date, daysBefore: Int, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = "📅 \(reminder.title)"
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.advanceCategoryID
        content.userInfo = [
            "reminderID": reminder.id.uuidString,
            "type": "advance",
            "daysBefore": daysBefore
        ]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: "reminder-\(reminder.id.uuidString)-advance-\(daysBefore)",
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("[NotificationManager] 预告通知安排失败: \(error.localizedDescription)")
        }
    }

    /// 取消该提醒的所有待发送通知（异步：先等查询返回，再移除，保证调用方 await 后已生效）
    func removePendingNotification(for reminderID: UUID) async {
        let requests = await withCheckedContinuation { (cont: CheckedContinuation<[UNNotificationRequest], Never>) in
            UNUserNotificationCenter.current().getPendingNotificationRequests { cont.resume(returning: $0) }
        }
        let toRemove = requests
            .filter { $0.content.userInfo["reminderID"] as? String == reminderID.uuidString }
            .map { $0.identifier }

        if !toRemove.isEmpty {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: toRemove)
            print("[NotificationManager] 移除 \(toRemove.count) 条旧通知")
        }
    }

    /// 移除所有待发送通知
    func removeAllPendingNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// 前台收到通知时仍然展示
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// 用户点击通知操作按钮（确认/稍后）
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        guard let reminderIDString = userInfo["reminderID"] as? String,
              let reminderID = UUID(uuidString: reminderIDString) else {
            completionHandler()
            return
        }

        switch response.actionIdentifier {
        case Self.confirmActionID:
            // 用户确认完成——通过通知中心广播
            NotificationCenter.default.post(
                name: .reminderConfirmed,
                object: nil,
                userInfo: ["reminderID": reminderID]
            )
            print("[NotificationManager] 用户确认完成: \(reminderIDString)")

        case Self.snoozeActionID:
            // 用户稍后提醒
            NotificationCenter.default.post(
                name: .reminderSnoozed,
                object: nil,
                userInfo: ["reminderID": reminderID]
            )
            print("[NotificationManager] 用户稍后提醒: \(reminderIDString)")

        case UNNotificationDismissActionIdentifier:
            // 用户滑动消除——不做任何操作，等递增重试
            print("[NotificationManager] 用户消除通知（将进入递增重试）")

        default:
            break
        }

        completionHandler()
    }
}

// MARK: - 通知名称扩展

extension Notification.Name {
    static let reminderConfirmed = Notification.Name("reminderConfirmed")
    static let reminderSnoozed = Notification.Name("reminderSnoozed")
}
