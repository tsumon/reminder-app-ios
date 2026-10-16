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
    struct Entry: Codable { let id: UUID; let reminderID: String; let token: String; let date: Date }
    private let key = "reminder_alarm_entries_v1"
    @Published private(set) var alarmCount = 0
    private var observer: Task<Void, Never>?
    private var entries: [Entry] {
        get { (UserDefaults.standard.data(forKey: key)).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }
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
    func schedule(_ delivery: ReminderPolicy.Delivery) async -> Bool {
        guard authorized, delivery.kind != .advance else { return false }
        if let entry = entries.first(where: { $0.reminderID == delivery.reminderID.uuidString && $0.token == delivery.token && $0.date == delivery.date }),
           (try? AlarmManager.shared.alarms.contains { $0.id == entry.id }) == true { return true }
        let id = UUID()
        let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: delivery.title),
            stopButton: AlarmButton(text: "完成", textColor: .white, systemImageName: "checkmark"),
            secondaryButton: AlarmButton(text: "稍后15分钟", textColor: .white, systemImageName: "clock"),
            secondaryButtonBehavior: .custom)
        let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert),
            metadata: ReminderAlarmMetadata(reminderID: delivery.reminderID.uuidString), tintColor: Color.accentColor)
        let config = AlarmManager.AlarmConfiguration(schedule: .fixed(delivery.date), attributes: attributes,
            stopIntent: CompleteImportantReminderIntent(reminderID: delivery.reminderID.uuidString, token: delivery.token),
            secondaryIntent: SnoozeImportantReminderIntent(reminderID: delivery.reminderID.uuidString, token: delivery.token))
        do {
            _ = try await AlarmManager.shared.schedule(id: id, configuration: config)
            entries.append(Entry(id: id, reminderID: delivery.reminderID.uuidString, token: delivery.token, date: delivery.date))
            return true
        } catch { print("[AlarmKit] fallback: \(error)"); return false }
    }
    func cancel(reminderID: UUID) {
        for entry in entries where entry.reminderID == reminderID.uuidString { try? AlarmManager.shared.cancel(id: entry.id) }
        entries.removeAll { $0.reminderID == reminderID.uuidString }
    }
    func removeStale(validTokens: [String: String]) async {
        let stale = entries.filter { validTokens[$0.reminderID] != $0.token || !authorized }
        for entry in stale { try? AlarmManager.shared.cancel(id: entry.id) }
        let ids = Set(stale.map(\.id)); entries.removeAll { ids.contains($0.id) }
    }
    func act(reminderID: String, token: String, snooze: Bool) async {
        guard let id = UUID(uuidString: reminderID) else { return }
        let context = ReminderApp.sharedModelContainer.mainContext
        ReminderEngine.shared.configure(with: context)
        let all = (try? context.fetch(FetchDescriptor<Reminder>())) ?? []
        guard let r = all.first(where: { $0.id == id }), ReminderActions.accepts(r, token: token) else { return }
        if snooze { ReminderEngine.shared.snoozeReminder(r, afterMinutes: 15) }
        else { ReminderEngine.shared.confirmReminder(r, source: "AlarmKit") }
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
