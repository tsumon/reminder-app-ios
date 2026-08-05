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
                .onAppear {
                    reminderEngine.configure(with: sharedModelContainer.mainContext)
                }
                .task {
                    _ = await notificationManager.requestAuthorization()
                    _ = await VoiceRecognizer.shared.requestAuthorization()
                    let descriptor = FetchDescriptor<Reminder>()
                    if let reminders = try? sharedModelContainer.mainContext.fetch(descriptor) {
                        await reminderEngine.checkMissedReminders(reminders: reminders)
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
