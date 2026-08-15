import SwiftUI
import SwiftData

// MARK: - SwiftData 迁移（v2.0.15: 显式声明 schema v1 + 空迁移计划）
// 之前容器用裸 `Schema([Reminder.self, ReminderRecord.self])`，无 VersionedSchema/MigrationPlan：
// 一旦未来模型改非可选字段/加关系，老用户升级时容器创建失败直接 fatalError（启动即崩）。
// 现在显式声明 v1 为唯一 schema、stages 为空 = 不触发任何迁移（同一 schema，老数据原样打开），
// 为未来的 v2 迁移铺路，是最便宜的保险。

/// Schema v1：当前模型（Reminder + ReminderRecord），字段与既有持久化数据完全一致
enum ReminderSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [Reminder.self, ReminderRecord.self] }
}

/// 迁移计划：v1 为唯一 schema，无迁移阶段
enum ReminderMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [ReminderSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

@main
struct ReminderApp: App {
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var reminderEngine = ReminderEngine.shared
    @Environment(\.scenePhase) private var scenePhase
    // v2.0.4: 手动语言切换 —— 变化时通过 .id() 强制整棵视图树重建，新语言生效
    @AppStorage(AppLanguageManager.key) private var appLanguage = AppLanguage.system.rawValue
    // v2.1.1: 手动主题（0=跟随系统 1=浅色 2=深色）
    @AppStorage(ThemeStore.key) private var themeMode = 0
    // v2.4.0: 主题色板索引（切换后整树重建，全局换肤即时生效）
    @AppStorage(ThemeStore.colorKey) private var themeColor = 0

    /// SwiftData 容器（v2.1.1: 提升为 static，供 AppIntents/快捷指令访问同一 store）
    static let sharedModelContainer: ModelContainer = {
        // Schema(versionedSchema:) 显式走 v1 版本化 schema（ReminderSchemaV1.schema 属性不存在，
        // 必须经 Schema 构造器；ModelConfiguration(for:) 亦可，此处用最显式写法）
        let config = ModelConfiguration(schema: Schema(versionedSchema: ReminderSchemaV1.self), isStoredInMemoryOnly: false)

        do {
            // for: 需传 Schema（经 Schema(versionedSchema:) 显式走 v1），migrationPlan: 传计划本身
            return try ModelContainer(
                for: Schema(versionedSchema: ReminderSchemaV1.self),
                migrationPlan: ReminderMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            fatalError("SwiftData 初始化失败: \(error.localizedDescription)。若为升级后首次打开导致，请备份数据后重装 App。")
        }
    }()

    var body: some Scene {
        WindowGroup {
            // v1.9.8: 底部导航 Tab（首页/日历/统计/设置），对齐 README 设计图
            // v2.0.4: .id("\(appLanguage)-\(themeColor)") —— 语言切换后整树重建刷新文案
            // v2.1.1: .preferredColorScheme —— 手动主题（0=跟随系统）
            MainTabView()
                .id("\(appLanguage)-\(themeColor)")
                .preferredColorScheme(themeMode == 1 ? .light : themeMode == 2 ? .dark : nil)
                .onAppear {
                    reminderEngine.configure(with: Self.sharedModelContainer.mainContext)
                    // v1.8.7 任务⑥: 崩溃监控 + 埋点（启动最先安装）
                    TelemetryService.install()
                }
                // v1.9.6 fix: 回前台时同步小组件完成标记 + 清零通知角标。
                // 原实现只在启动 .task 同步——App 驻留/后台时点小组件「完成」永不落库
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task {
                            await syncWidgetCompletedReminders()
                            // v2.0.16: 小组件「稍后」标记同步（snooze + 重排）
                            await syncWidgetSnoozedReminders()
                            // 冷启动后经通知按钮拉起：排空入队的通知动作（确认/稍后/消除）
                            reminderEngine.drainPendingNotificationActions()
                            // P1-2: 后台期间系统按预排时间发过的重试通知，回前台补齐库内阶段
                            let descriptor = FetchDescriptor<Reminder>()
                            if let reminders = try? Self.sharedModelContainer.mainContext.fetch(descriptor) {
                            await reminderEngine.checkMissedReminders(reminders: reminders)
                        }
                        await reminderEngine.ensureRetryChains()
                        // 批次2 功能3: 回前台刷新周报通知内容（本周至今统计）
                        await refreshWeeklyReport()
                        }
                        // 通知角标：进入前台即清零（原实现从不清零，误导性未读数）
                        UIApplication.shared.applicationIconBadgeNumber = 0
                    }
                }
                .task {
                    _ = await notificationManager.requestAuthorization()
                    _ = await VoiceRecognizer.shared.requestAuthorization()
                    let descriptor = FetchDescriptor<Reminder>()
                    if let reminders = try? Self.sharedModelContainer.mainContext.fetch(descriptor) {
                        await reminderEngine.checkMissedReminders(reminders: reminders)
                    }
                    // P1-2: 为进入 31 天窗口（及季/年周期）的提醒补排递增重试链（固定标识符，重复调用只覆盖）
                    await reminderEngine.ensureRetryChains()
                    // v1.8.7: 同步小组件「完成」标记 → confirm + 重排通知 → 清空
                    await syncWidgetCompletedReminders()
                    // v2.0.16: 同步小组件「稍后」标记 → snooze + 重排通知 → 清空
                    await syncWidgetSnoozedReminders()
                    // v1.8.7 任务②: 后台刷新联网节假日数据（当年 + 下一年，跨年预取）
                    let year = Calendar.current.component(.year, from: Date())
                    async let r1 = HolidayRemoteService.refresh(year: year)
                    async let r2 = HolidayRemoteService.refresh(year: year + 1)
                    _ = await (r1, r2)
                    // Item 2: 启动后预检——把落在 ~1 个月内、恰逢法定节假日的循环/规则提醒前移
                    await reminderEngine.runHolidayPreCheck()
                    // 冷启动排空：App 经通知按钮拉起时 didReceive 已入队动作，引擎就绪后在此统一处理
                    reminderEngine.drainPendingNotificationActions()
                    // 批次2 功能3: 启动时刷新周报通知内容（本周至今统计）
                    await refreshWeeklyReport()
                    #if DEBUG
                    // v1.9.8: 模拟器截图验证用演示数据（仅 Debug 构建）
                    seedDemoDataIfNeeded()
                    #endif
                }
        }
        .modelContainer(Self.sharedModelContainer)
    }

    /// 批次2 功能3: 统计周报 —— 计算「本周至今」统计并覆盖安排每周日 20:00 通知
    private func refreshWeeklyReport() async {
        let descriptor = FetchDescriptor<ReminderRecord>()
        let records = (try? Self.sharedModelContainer.mainContext.fetch(descriptor)) ?? []
        await WeeklyReportService.schedule(records: records)
    }

    /// 把用户在小组件上点「完成」的提醒同步到数据库
    /// （AppIntent 只写 App Group 标记，这里做真正的 confirm + 通知重排）
    private func syncWidgetCompletedReminders() async {        let ids = WidgetSnapshot.completedReminderIDs()
        guard !ids.isEmpty else { return }

        let context = Self.sharedModelContainer.mainContext
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

    /// 把用户在小组件上点「稍后」的提醒同步到数据库
    /// （v2.0.16：AppIntent 只写 App Group 标记，这里做真正的 snooze + 通知重排）
    private func syncWidgetSnoozedReminders() async {
        let ids = WidgetSnapshot.snoozedReminderIDs()
        guard !ids.isEmpty else { return }

        let context = Self.sharedModelContainer.mainContext
        for id in ids {
            guard let uuid = UUID(uuidString: id) else { continue }
            let descriptor = FetchDescriptor<Reminder>(predicate: #Predicate { $0.id == uuid })
            guard let reminder = try? context.fetch(descriptor).first else { continue }
            // .task 继承 MainActor 上下文，snoozeReminder（引擎方法）可直接调用
            reminderEngine.snoozeReminder(reminder, afterMinutes: 15)
            print("[WidgetSync] 小组件稍后已落库: \(reminder.title)")
        }

        // 全部处理完再清空标记，避免 App 启动后遗留脏数据
        WidgetSnapshot.clearSnoozedReminderIDs(ids)
    }

#if DEBUG
    /// v1.9.8: 模拟器截图验证用演示数据（仅 Debug 构建，首次启动插入，模拟 README 设计图示例）
    private func seedDemoDataIfNeeded() {
        let context = Self.sharedModelContainer.mainContext
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
