import AlarmKit
import AppIntents
import SwiftData
import SwiftUI

@available(iOS 26.0, *)
struct ReminderAlarmMetadata: AlarmMetadata { var reminderID: String }

/// Alert-only fixed alarms: no countdown/Live Activity extension is required.
@available(iOS 26.0, *)
@MainActor final class ImportantAlarmService: ObservableObject {
    static let shared = ImportantAlarmService()
    private let key = "reminder_alarm_entries_v1"
    @Published private(set) var alarmCount = 0
    private var observer: Task<Void, Never>?
    private lazy var reconciler: AlarmDeliveryReconciler = {
        let entries = UserDefaults.standard.data(forKey: key).flatMap {
            try? JSONDecoder().decode([AlarmDeliveryReconciler.Entry].self, from: $0)
        } ?? []
        return AlarmDeliveryReconciler(entries: entries, persist: { [key = self.key] entries in
            UserDefaults.standard.set(try? JSONEncoder().encode(entries), forKey: key)
        })
    }()
    private init() {
        observer = Task { [weak self] in
            for await alarms in AlarmManager.shared.alarmUpdates { self?.alarmCount = alarms.count }
        }
    }
    var authorized: Bool { AlarmManager.shared.authorizationState == .authorized }
    var authorizationLabel: String {
        switch AlarmManager.shared.authorizationState {
        case .authorized: return "已允许"
        case .denied: return "未允许，使用普通通知"
        case .notDetermined: return "尚未申请"
        @unknown default: return "不可用"
        }
    }
    func requestAuthorization() async -> Bool {
        if authorized { return true }
        return (try? await AlarmManager.shared.requestAuthorization()) == .authorized
    }
    func reconcile(desired: [ReminderPolicy.Delivery]) {
        reconciler.reconcile(desired: authorized ? desired : [], cancel: { id in
            try? AlarmManager.shared.cancel(id: id)
        })
    }
    func schedule(_ delivery: ReminderPolicy.Delivery) async -> Bool {
        guard authorized, delivery.kind != .advance else { return false }
        return await reconciler.schedule(delivery, exists: { id in
            (try? AlarmManager.shared.alarms.contains { $0.id == id }) == true
        }, install: { id, current in
            try await self.install(current, id: id)
        }, cancel: { id in
            try? AlarmManager.shared.cancel(id: id)
        })
    }
    private func install(_ delivery: ReminderPolicy.Delivery, id: UUID) async throws {
        let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: delivery.title),
            stopButton: AlarmButton(text: "完成", textColor: .white, systemImageName: "checkmark"),
            secondaryButton: AlarmButton(text: "稍后15分钟", textColor: .white, systemImageName: "clock"),
            secondaryButtonBehavior: .custom)
        let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert),
            metadata: ReminderAlarmMetadata(reminderID: delivery.reminderID.uuidString), tintColor: Color.accentColor)
        let config = AlarmManager.AlarmConfiguration(schedule: .fixed(delivery.date), attributes: attributes,
            stopIntent: CompleteImportantReminderIntent(reminderID: delivery.reminderID.uuidString, token: delivery.token),
            secondaryIntent: SnoozeImportantReminderIntent(reminderID: delivery.reminderID.uuidString, token: delivery.token))
        _ = try await AlarmManager.shared.schedule(id: id, configuration: config)
    }
    func cancel(reminderID: UUID) {
        reconciler.cancel(reminderID: reminderID, systemCancel: { id in
            try? AlarmManager.shared.cancel(id: id)
        })
    }
    func act(reminderID: String, token: String, snooze: Bool) async {
        guard let id = UUID(uuidString: reminderID) else { return }
        let context = ReminderApp.sharedModelContainer.mainContext
        ReminderEngine.shared.configure(with: context)
        let all = (try? context.fetch(FetchDescriptor<Reminder>())) ?? []
        guard let r = all.first(where: { $0.id == id }), ReminderActions.accepts(r, token: token) else { return }
        if snooze { ReminderEngine.shared.snoozeReminder(r, afterMinutes: 15, expectedToken: token) }
        else { ReminderEngine.shared.confirmReminder(r, source: "AlarmKit", expectedToken: token) }
        cancel(reminderID: id)
        await ReminderEngine.shared.ensureRetryChains()
    }
}

@available(iOS 26.0, *)
struct CompleteImportantReminderIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "完成重要提醒"
    @Parameter(title: "提醒") var reminderID: String
    @Parameter(title: "操作令牌") var token: String
    init() { reminderID = ""; token = "" }
    init(reminderID: String, token: String) { self.reminderID = reminderID; self.token = token }
    @MainActor func perform() async throws -> some IntentResult {
        await ImportantAlarmService.shared.act(reminderID: reminderID, token: token, snooze: false)
        return .result()
    }
}

@available(iOS 26.0, *)
struct SnoozeImportantReminderIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "稍后重要提醒"
    @Parameter(title: "提醒") var reminderID: String
    @Parameter(title: "操作令牌") var token: String
    init() { reminderID = ""; token = "" }
    init(reminderID: String, token: String) { self.reminderID = reminderID; self.token = token }
    @MainActor func perform() async throws -> some IntentResult {
        await ImportantAlarmService.shared.act(reminderID: reminderID, token: token, snooze: true)
        return .result()
    }
}
