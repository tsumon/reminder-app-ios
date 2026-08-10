import SwiftUI
import SwiftData

@main
struct ReminderApp: App {
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var reminderEngine = ReminderEngine.shared
    @Environment(\.scenePhase) private var scenePhase
    // v2.0.4: 手动语言切换 —— 变化时通过 .id() 强制整棵视图树重建，新语言生效
    @AppStorage(AppLanguageManager.key) private var appLanguage = AppLanguage.system.rawValue

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
            // v1.9.8: 底部导航 Tab（首页/日历/统计/设置），对齐 README 设计图
            // v2.0.4: .id(appLanguage) —— 语言切换后整树重建刷新文案
            MainTabView()
                .id(appLanguage)
                .onAppear {
                    reminderEngine.configure(with: sharedModelContainer.mainContext)
                    // v1.8.7 任务⑥: 崩溃监控 + 埋点（启动最先安装）
                    TelemetryService.install()
                }
                // v1.9.6 fix: 回前台时同步小组件完成标记 + 清零通知角标。
                // 原实现只在启动 .task 同步——App 驻留/后台时点小组件「完成」永不落库
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task {
                            await syncWidgetCompletedReminders()
                        }
                        // 通知角标：进入前台即清零（原实现从不清零，误导性未读数）
                        UIApplication.shared.applicationIconBadgeNumber = 0
                    }
                }
                .task {
                    _ = await notificationManager.requestAuthorization()
                    _ = await VoiceRecognizer.shared.requestAuthorization()
                    let descriptor = FetchDescriptor<Reminder>()
                    if let reminders = try? sharedModelContainer.mainContext.fetch(descriptor) {
                        await reminderEngine.checkMissedReminders(reminders: reminders)
                    }
                    // v1.8.7: 同步小组件「完成」标记 → confirm + 重排通知 → 清空
                    await syncWidgetCompletedReminders()
                    // v1.8.7 任务②: 后台刷新联网节假日数据（当年 + 下一年，跨年预取）
                    let year = Calendar.current.component(.year, from: Date())
                    async let r1 = HolidayRemoteService.refresh(year: year)
                    async let r2 = HolidayRemoteService.refresh(year: year + 1)
                    _ = await (r1, r2)
                    // Item 2: 启动后预检——把落在 ~1 个月内、恰逢法定节假日的循环/规则提醒前移
                    await reminderEngine.runHolidayPreCheck()
                    #if DEBUG
                    // v1.9.8: 模拟器截图验证用演示数据（仅 Debug 构建）
                    seedDemoDataIfNeeded()
                    #endif
                }
        }
        .modelContainer(sharedModelContainer)
    }

    /// 把用户在小组件上点「完成」的提醒同步到数据库
    /// （AppIntent 只写 App Group 标记，这里做真正的 confirm + 通知重排）
    private func syncWidgetCompletedReminders() async {        let ids = WidgetSnapshot.completedReminderIDs()
        guard !ids.isEmpty else { return }

        let context = sharedModelContainer.mainContext
        for id in ids {
            guard let uuid = UUID(uuidString: id) else { continue }
            let descriptor = FetchDescriptor<Reminder>(predicate: #Predicate { $0.id == uuid })
            guard let reminder = try? context.fetch(descriptor).first else { continue }
            // .task 继承 MainActor 上下文，confirmReminder（@MainActor）可直接调用
            reminderEngine.confirmReminder(reminder)
            print("[WidgetSync] 小组件完成已落库: \(reminder.title)")
        }

        // 全部处理完再清空标记，避免 App 启动后遗留脏数据
        WidgetSnapshot.clearCompletedReminderIDs(ids)
    }

#if DEBUG
    /// v1.9.8: 模拟器截图验证用演示数据（仅 Debug 构建，首次启动插入，模拟 README 设计图示例）
    private func seedDemoDataIfNeeded() {
        let context = sharedModelContainer.mainContext
        let count = (try? context.fetchCount(FetchDescriptor<Reminder>())) ?? 0
        guard count == 0 else { return }
        let now = Date()
        let h = 3600.0
        let demos: [Reminder] = [
            Reminder(title: "吃降压药", note: "每天早饭后", kind: .cycle, cycle: .daily,
                     firstTriggerAt: now, nextTriggerAt: now.addingTimeInterval(h), status: .active, retryStage: 2),
            Reminder(title: "提交季度报表", note: "每季度一次", kind: .cycle, cycle: .quarterly,
                     firstTriggerAt: now, nextTriggerAt: now.addingTimeInterval(-h), status: .overdue),
            Reminder(title: "遛狗", note: "晚饭后", kind: .cycle, cycle: .daily,
                     firstTriggerAt: now, nextTriggerAt: now.addingTimeInterval(h * 20), status: .pending),
            Reminder(title: "交房租", kind: .cycle, cycle: .monthly,
                     firstTriggerAt: now, nextTriggerAt: now.addingTimeInterval(h * 24 * 25), status: .pending),
            Reminder(title: "妈妈的生日", kind: .date, dateType: .lunarBirthday, targetMonth: 8, targetDay: 15, advanceDays: 3,
                     firstTriggerAt: now, nextTriggerAt: now.addingTimeInterval(h * 24 * 21), status: .pending),
            Reminder(title: "体检预约", note: "提前一周提醒", kind: .date, dateType: .solarBirthday, targetMonth: 8, targetDay: 27, advanceDays: 7,
                     firstTriggerAt: now, nextTriggerAt: now.addingTimeInterval(h * 24 * 21), status: .pending),
        ]
        demos.forEach { context.insert($0) }
        try? context.save()
        print("[Debug] 已插入 \(demos.count) 条演示提醒")
    }
#endif
}
