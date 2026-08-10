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

    // MARK: - 递增重试链（P1-2：对齐 Android WorkManager 自动重试）

    /// 预排「递增重试」通知链。
    ///
    /// iOS 没有 WorkManager —— App 被杀后无法在到期那一刻动态排下一次重试，
    /// 因此排 D-day 通知时就把后续几次重试一次性交给系统持有。
    /// 重试通知使用固定标识符 `reminder-<id>-retry-<stage>`，重复调用只会覆盖、不会堆积。
    ///
    /// - Parameters:
    ///   - anchor: 下一次通知（即第 `currentStage + 1` 次触发）的时间
    ///   - currentStage: 当前已完成的重试阶段（0 表示还没触发过）
    func addRetryNotifications(for reminder: Reminder, anchor: Date, currentStage: Int, badgeCount: Int) async {
        guard currentStage < RetrySchedule.maxStage else { return }

        // 配额保护：iOS 单 App pending 通知上限 64 条，超出后新通知会被系统静默丢弃。
        // 留出余量给 D-day / 预告通知，避免重试链把正主挤掉。
        let pending = await withCheckedContinuation { (cont: CheckedContinuation<[UNNotificationRequest], Never>) in
            UNUserNotificationCenter.current().getPendingNotificationRequests { cont.resume(returning: $0) }
        }
        guard pending.count < 50 else {
            print("[NotificationManager] pending 已达 \(pending.count) 条，跳过重试链预排")
            return
        }

        let now = Date()
        var offset: TimeInterval = 0
        // anchor 处触发的是第 currentStage+1 次，所以重试链从第 currentStage+2 次开始预排
        var previousStage = currentStage + 1
        var stage = currentStage + 2

        while stage <= RetrySchedule.maxStage {
            offset += RetrySchedule.delay(afterStage: previousStage)
            let fireAt = anchor.addingTimeInterval(offset)
            if fireAt > now {
                await addRetryNotification(for: reminder, at: fireAt, stage: stage, badgeCount: badgeCount)
            }
            previousStage += 1
            stage += 1
        }
    }

    /// 单条重试通知（带确认/稍后按钮，与 D-day 通知同一分类）
    private func addRetryNotification(for reminder: Reminder, at date: Date, stage: Int, badgeCount: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "⏰ \(reminder.title)"
        content.body = reminder.note.isEmpty
            ? Localized("还没确认哦，这是第 %d 次提醒", stage)
            : Localized("还没确认哦（第 %d 次提醒）：%@", stage, reminder.note)
        content.sound = .default
        content.badge = NSNumber(value: badgeCount)
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [
            "reminderID": reminder.id.uuidString,
            "reminderTitle": reminder.title,
            "type": "retry",
            "retryStage": stage
        ]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        // 固定标识符：同一提醒同一阶段重复排期时覆盖旧的，避免重复轰炸
        let request = UNNotificationRequest(
            identifier: "reminder-\(reminder.id.uuidString)-retry-\(stage)",
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            print("[NotificationManager] 重试通知已安排: \(reminder.title) 阶段 \(stage) @ \(date)")
        } catch {
            print("[NotificationManager] 重试通知安排失败: \(error.localizedDescription)")
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

    // MARK: - 通知动作持久化队列（冷启动兜底）

    /// 通知动作类型（与 ReminderEngine.drainPendingNotificationActions 对应）
    enum NotificationActionType: String, Codable {
        case confirm
        case snooze
        case dismiss
    }

    /// 一条待处理通知动作（持久化，避免冷启动视图未订阅时事件丢失）
    struct PendingNotificationAction: Codable {
        let action: NotificationActionType
        let reminderID: String
        let enqueuedAt: Date
    }

    private static let pendingActionsKey = "pendingNotificationActions"

    /// 入队一条通知动作（持久化到 UserDefaults，App 启动后排空）
    private func enqueueNotificationAction(_ action: NotificationActionType, _ reminderID: UUID) {
        var list = Self.loadPendingActions()
        list.append(PendingNotificationAction(action: action, reminderID: reminderID.uuidString, enqueuedAt: Date()))
        Self.savePendingActions(list)
        print("[NotificationManager] 入队通知动作: \(action.rawValue) \(reminderID.uuidString)")
    }

    /// 取出并清空所有待处理动作（由 ReminderEngine 排空时调用）
    func dequeueAllPendingActions() -> [PendingNotificationAction] {
        let list = Self.loadPendingActions()
        if !list.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.pendingActionsKey)
        }
        return list
    }

    private static func loadPendingActions() -> [PendingNotificationAction] {
        guard let data = UserDefaults.standard.data(forKey: pendingActionsKey) else { return [] }
        return (try? JSONDecoder().decode([PendingNotificationAction].self, from: data)) ?? []
    }

    private static func savePendingActions(_ list: [PendingNotificationAction]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: pendingActionsKey)
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
            enqueueNotificationAction(.confirm, reminderID)
        case Self.snoozeActionID:
            enqueueNotificationAction(.snooze, reminderID)
        case UNNotificationDismissActionIdentifier:
            // 用户滑动消除 → 进入递增重试（1h→4h→12h→24h），并写入 trigger 记录供统计
            enqueueNotificationAction(.dismiss, reminderID)
        default:
            break
        }

        // 冷启动兜底：didReceive 可能早于视图订阅/引擎就绪，仅持久化入队；
        // 引擎就绪后由 ReminderApp.task / scenePhase.active 统一排空。
        // 若此刻引擎已就绪（热启动前台），直接排空，避免动作丢失。
        if ReminderEngine.shared.isConfigured {
            ReminderEngine.shared.drainPendingNotificationActions()
        }

        completionHandler()
    }
}

// MARK: - 通知名称扩展

extension Notification.Name {
    static let reminderConfirmed = Notification.Name("reminderConfirmed")
    static let reminderSnoozed = Notification.Name("reminderSnoozed")
    static let reminderDismissed = Notification.Name("reminderDismissed")
}
