import Foundation
import UserNotifications
import SwiftData

/// 通知管理器：负责权限请求、通知注册、分类（带操作按钮）
@MainActor
final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    @Published var isAuthorized = false

    /// 通知分类 ID（注册到 iOS 系统，关联确认/稍后按钮）
    static let categoryIdentifier = NotificationActionIDs.category

    /// 预告通知分类（无操作按钮，仅信息展示）
    static let advanceCategoryID = "REMINDER_ADVANCE"

    /// Action 标识符
    static let confirmActionID = NotificationActionIDs.confirm
    static let snoozeActionID = NotificationActionIDs.snooze

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
            title: "确认",
            options: [.foreground]  // 点击后打开 App 处理
        )

        // 「稍后提醒」按钮
        // v2.0.22: 去掉 .authenticationRequired —— 代码注释明确「不需要解锁也能操作」，
        // 但该选项实际要求认证，锁屏上点稍后会被系统拦下，与产品预期相反
        let snoozeAction = UNNotificationAction(
            identifier: Self.snoozeActionID,
            title: "稍后",
            options: []
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
        await ReminderEngine.shared.scheduleAllNotifications(for: reminder)
    }

    /// 真正添加 D-day 通知（不含移除逻辑，供 scheduleAllNotifications 在统一移除后调用）
    /// 排 D-day 通知；at 缺省用 reminder.nextTriggerAt（v2.1.1: 勿扰时段顺延后的触发时间）
    private var reservedUnmanaged = Set<String>()
    func reserveUnmanaged(identifier: String) async {
        reservedUnmanaged.insert(identifier)
        await ReminderEngine.shared.ensureRetryChains()
    }
    func releaseUnmanagedReservation(identifier: String) { reservedUnmanaged.remove(identifier) }
    func unmanagedPendingCount() async -> Int {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return Set(requests.filter { $0.content.userInfo["reminderID"] == nil }.map(\.identifier)).union(reservedUnmanaged).count
    }
    func pendingNotificationCount() async -> Int { await UNUserNotificationCenter.current().pendingNotificationRequests().count }
    func removeManagedRequests() async {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers:
            requests.filter { $0.content.userInfo["reminderID"] != nil }.map(\.identifier))
    }
    func addDelivery(_ delivery: ReminderPolicy.Delivery, badgeCount: Int) async {
        let content = UNMutableNotificationContent()
        content.title = delivery.title; content.body = delivery.body; content.sound = .default
        content.badge = NSNumber(value: badgeCount)
        content.categoryIdentifier = delivery.kind == .advance ? Self.advanceCategoryID : Self.categoryIdentifier
        content.threadIdentifier = delivery.reminderID.uuidString
        content.userInfo = ["reminderID": delivery.reminderID.uuidString, "token": delivery.token,
                            "type": delivery.kind == .advance ? "advance" : "reminder"]
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: delivery.date)
        let request = UNNotificationRequest(identifier: delivery.identifier, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        do { try await UNUserNotificationCenter.current().add(request) }
        catch { print("[Notifications] \(error)") }
    }

    /// 取消该提醒的所有待发送通知（异步：先等查询返回，再移除，保证调用方 await 后已生效）
    func removePendingNotification(for reminderID: UUID) async {
        if #available(iOS 26.0, *) { ImportantAlarmService.shared.cancel(reminderID: reminderID) }
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers:
            delivered.filter { $0.request.content.userInfo["reminderID"] as? String == reminderID.uuidString }.map { $0.request.identifier })
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
        let token: String?
    }

    private static let pendingActionsKey = "pendingNotificationActions"

    /// 调试 / 测试：模拟通知动作（与 didReceive 同一入队 + 排空路径）。
    func simulateNotificationAction(_ action: NotificationActionType, reminderID: UUID) {
        enqueueNotificationAction(action, reminderID)
        if ReminderEngine.shared.isConfigured {
            ReminderEngine.shared.drainPendingNotificationActions()
        }
    }

    /// 入队一条通知动作（持久化到 UserDefaults，App 启动后排空）
    func enqueueNotificationAction(_ action: NotificationActionType, _ reminderID: UUID, token: String? = nil) {
        var list = Self.loadPendingActions()
        list.append(PendingNotificationAction(action: action, reminderID: reminderID.uuidString, enqueuedAt: Date(), token: token ?? ReminderEngine.shared.token(for: reminderID)))
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

    // MARK: - 通知点击直达确认面板（批次2 功能1，冷启动兜底）

    private static let pendingDetailKey = "pendingDetailReminderID"

    /// 记录「点击通知本体要直达的提醒 id」——post 通知可能早于视图订阅而丢失，
    /// 落 UserDefaults 由列表页 onAppear 兜底消费，与 pendingActions 同一模式。
    static func savePendingDetailID(_ idString: String) {
        UserDefaults.standard.set(idString, forKey: pendingDetailKey)
    }

    /// 取出并清空待直达的提醒 id（只消费一次）
    static func takePendingDetailID() -> String? {
        let v = UserDefaults.standard.string(forKey: pendingDetailKey)
        if v != nil { UserDefaults.standard.removeObject(forKey: pendingDetailKey) }
        return v
    }

    private static let pendingHighlightKey = "pendingHighlightConfirm"

    static func savePendingHighlightConfirm(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: pendingHighlightKey)
    }

    static func takePendingHighlightConfirm() -> Bool {
        let v = UserDefaults.standard.bool(forKey: pendingHighlightKey)
        UserDefaults.standard.removeObject(forKey: pendingHighlightKey)
        return v
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
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uitest_isolate_notifications") {
            completionHandler([])
            return
        }
        #endif
        completionHandler([.banner, .sound, .badge])
    }

    /// 用户点击通知操作按钮（确认/稍后）
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        // 批次2 功能3: 统计周报 → 打开统计 Tab（无 reminderID，type 标记）
        if userInfo["type"] as? String == "weekly_report" {
            NotificationCenter.default.post(name: .openStatsTab, object: nil)
            completionHandler()
            return
        }

        guard let reminderIDString = userInfo["reminderID"] as? String,
              let reminderID = UUID(uuidString: reminderIDString) else {
            completionHandler()
            return
        }

        guard let token = userInfo["token"] as? String else { completionHandler(); return }
        _ = token
        switch response.actionIdentifier {
        case Self.confirmActionID:
            enqueueNotificationAction(.confirm, reminderID, token: userInfo["token"] as? String)
        case Self.snoozeActionID:
            enqueueNotificationAction(.snooze, reminderID, token: userInfo["token"] as? String)
        case UNNotificationDismissActionIdentifier:
            // 用户滑动消除 → 进入递增重试（1h→4h→12h→24h），并写入 trigger 记录供统计
            enqueueNotificationAction(.dismiss, reminderID, token: userInfo["token"] as? String)
        default:
            // 批次2 功能1: 点击通知本体（非操作按钮）→ 直达该提醒的确认面板
            // （ReminderListView 监听后程序化 push ReminderDetailView）
            // 双通道：post 热启动即时响应 + UserDefaults 冷启动兜底（视图未就绪时事件不丢）
            NotificationManager.savePendingDetailID(reminderIDString)
            NotificationCenter.default.post(name: .openReminderDetail, object: reminderIDString)
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
    // 批次2 功能1: 点击通知本体 → 直达确认面板（object 为 reminderID 的 uuidString）
    static let openReminderDetail = Notification.Name("openReminderDetail")
    // 批次2 功能3: 点击统计周报通知 → 打开统计 Tab
    static let openStatsTab = Notification.Name("openStatsTab")
}
