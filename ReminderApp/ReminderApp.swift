import SwiftUI
import SwiftData

@main
struct ReminderApp: App {
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var reminderEngine = ReminderEngine.shared

    /// SwiftData 容器
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Reminder.self, ReminderRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("SwiftData 初始化失败: \(error.localizedDescription)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ReminderListView()
        }
        .modelContainer(sharedModelContainer)
        .onAppear {
            // 注入 SwiftData 上下文到引擎
            reminderEngine.configure(with: sharedModelContainer.mainContext)
        }
        .task {
            // 1. 请求通知权限
            _ = await notificationManager.requestAuthorization()

            // 2. 检查遗漏的提醒
            let descriptor = FetchDescriptor<Reminder>()
            if let reminders = try? sharedModelContainer.mainContext.fetch(descriptor) {
                await reminderEngine.checkMissedReminders(reminders: reminders)
            }
        }
    }
}
