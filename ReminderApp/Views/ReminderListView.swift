import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import WidgetKit

/// 导入/导出用的 JSON 文件文档
struct ReminderBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .plainText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// 首页：提醒列表
struct ReminderListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Reminder.nextTriggerAt) private var reminders: [Reminder]
    @State private var showCreateSheet = false

    // 智能清单筛选
    @State private var smartList: SmartList = .all

    // 导入/导出
    @State private var showExportExporter = false
    @State private var exportDocument: ReminderBackupDocument?
    @State private var showImportImporter = false

    // 同步提示
    @State private var syncMessage: String?
    // 点击日历某天 → 查看当日任务
    @State private var selectedDay: Date?
    @State private var showDaySheet = false

    var body: some View {
        NavigationStack {
            Group {
                if reminders.isEmpty {
                    emptyView
                } else {
                    listView
                }
            }
            .navigationTitle("提醒事项")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink {
                        AIChatView()
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.purple)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showCreateSheet = true
                        } label: {
                            Label("新建提醒", systemImage: "plus.circle")
                        }
                        Divider()
                        Button {
                            syncNow()
                        } label: {
                            Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                        }
                        NavigationLink {
                            SyncSettingsView()
                        } label: {
                            Label("同步设置", systemImage: "gearshape")
                        }
                        Divider()
                        Button {
                            exportBackup()
                        } label: {
                            Label("导出提醒", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            showImportImporter = true
                        } label: {
                            Label("导入提醒", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3.weight(.semibold))
                    }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateReminderView()
            }
            .fileExporter(
                isPresented: $showExportExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "reminder_backup_\(Int(Date().timeIntervalSince1970))"
            ) { result in
                if case .failure(let error) = result {
                    print("[导出] 失败: \(error)")
                }
            }
            .fileImporter(
                isPresented: $showImportImporter,
                allowedContentTypes: [.json, .plainText]
            ) { result in
                importBackup(result)
            }
            .onAppear {
                saveWidgetSnapshot(reminders)
                // 自动同步（限频 5 分钟）
                if SyncStore.autoSync && SyncStore.isConfigured &&
                    Date().timeIntervalSince1970 - SyncStore.lastSyncAt > 300 {
                    Task {
                        _ = await WebDavSync.syncNow(reminders: reminders, modelContext: modelContext)
                    }
                }
            }
            .onChange(of: reminders) { _, newValue in
                saveWidgetSnapshot(newValue)
            }
            .alert("同步", isPresented: Binding(
                get: { syncMessage != nil },
                set: { if !$0 { syncMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(syncMessage ?? "")
            }
            .sheet(isPresented: $showDaySheet) {
                if let day = selectedDay {
                    DayTasksSheet(day: day, reminders: reminders)
                }
            }
        }
    }

    // MARK: - 小组件数据快照

    private func saveWidgetSnapshot(_ reminders: [Reminder]) {
        let now = Date()
        let unhandled = reminders.filter {
            $0.isEnabled && ($0.status == .active || $0.status == .snoozed ||
                ($0.status == .pending && $0.nextTriggerAt <= now))
        }
        let next = reminders
            .filter { $0.isEnabled && $0.nextTriggerAt > now }
            .min { $0.nextTriggerAt < $1.nextTriggerAt }

        WidgetSnapshot.save(WidgetReminderData(
            unhandledCount: unhandled.count,
            nextTitle: next?.title ?? "暂无提醒",
            nextTime: next?.nextTriggerAt,
            updatedAt: now
        ))

        // 主动刷新已添加的小组件
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - 导入/导出

    private func exportBackup() {
        let json = BackupHelper.exportJSON(reminders)
        exportDocument = ReminderBackupDocument(text: json)
        showExportExporter = true
    }

    // MARK: - 同步

    private func syncNow() {
        Task {
            let result = await WebDavSync.syncNow(reminders: reminders, modelContext: modelContext)
            switch result {
            case .success:
                syncMessage = "同步完成"
            case .failure(let msg):
                syncMessage = msg
            }
        }
    }

    private func importBackup(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: url),
                  let json = String(data: data, encoding: .utf8),
                  let items = BackupHelper.importJSON(json) else {
                print("[导入] 解析失败")
                return
            }

            // 去重：同一份备份文件被导入两次（或用户先同步再导入）时，
            // 之前会无脑 insert 出一堆一模一样的提醒，通知也会重复响。
            // 用 id 做主键匹配，id 对不上时退化成「标题 + 触发时间」指纹。
            var existingIDs = Set(reminders.map(\.id))
            var existingFingerprints = Set(
                reminders.map { "\($0.title)|\(Int($0.nextTriggerAt.timeIntervalSince1970))" }
            )

            var importedCount = 0
            var skippedCount = 0
            for item in items {
                let reminder = BackupHelper.makeReminder(from: item)
                let fingerprint = "\(reminder.title)|\(Int(reminder.nextTriggerAt.timeIntervalSince1970))"

                if existingIDs.contains(reminder.id) || existingFingerprints.contains(fingerprint) {
                    skippedCount += 1
                    continue
                }

                existingIDs.insert(reminder.id)
                existingFingerprints.insert(fingerprint)
                modelContext.insert(reminder)
                importedCount += 1
            }
            try? modelContext.save()
            SyncStore.touchLocalChange()
            print("[导入] 新增 \(importedCount) 条，跳过重复 \(skippedCount) 条")

            // 重新调度通知
            Task {
                for reminder in reminders where reminder.isEnabled {
                    await ReminderEngine.shared.scheduleAllNotifications(for: reminder)
                }
            }
        case .failure(let error):
            print("[导入] 失败: \(error)")
        }
    }

    // MARK: - 空状态

    private var emptyView: some View {
        List {
            // 日历
            Section {
                CalendarCardView(reminders: reminders, onDateTap: { selectedDay = $0; showDaySheet = true })
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section {
                VStack(spacing: 20) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)

                    Text("暂无提醒")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text("点击右上角 + 创建你的第一个循环提醒")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)

                    Button {
                        showCreateSheet = true
                    } label: {
                        Label("创建提醒", systemImage: "plus.circle.fill")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - 提醒列表

    private var listView: some View {
        List {
            // 智能清单筛选条
            Section {
                smartListBar
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            // 概览（参考滴答清单：待处理数 + 最近提醒）
            let unhandled = reminders.filter { $0.isEnabled && $0.status != .confirmed }.count
            let next = reminders.filter { $0.isEnabled && $0.nextTriggerAt > Date() }.min { $0.nextTriggerAt < $1.nextTriggerAt }
            Section {
                OverviewCard(unhandledCount: unhandled, nextReminder: next)
            }

            // 日历卡片
            Section {
                CalendarCardView(reminders: reminders, onDateTap: { selectedDay = $0; showDaySheet = true })
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            // 应用智能清单筛选后的全集
            let filtered = reminders.filter { matchSmartList($0) }

            // 正在提醒中（active / snoozed / overdue）
            let activeReminders = filtered.filter {
                $0.status == .active || $0.status == .snoozed || $0.status == .overdue
            }
            if !activeReminders.isEmpty {
                Section("🔔 提醒中") {
                    ForEach(activeReminders) { reminder in
                        NavigationLink {
                            ReminderDetailView(reminder: reminder)
                        } label: {
                            ReminderRowView(reminder: reminder)
                        }
                        .swipeActions(edge: .leading) {
                            completeSwipe(for: reminder)
                        }
                        .swipeActions(edge: .trailing) {
                            deleteSwipe(for: reminder)
                        }
                    }
                }
            }

            // 等待中
            let pendingReminders = filtered.filter { $0.status == .pending }
            if !pendingReminders.isEmpty {
                Section("⏳ 等待中") {
                    ForEach(pendingReminders) { reminder in
                        NavigationLink {
                            ReminderDetailView(reminder: reminder)
                        } label: {
                            ReminderRowView(reminder: reminder)
                        }
                        .swipeActions(edge: .leading) {
                            completeSwipe(for: reminder)
                        }
                        .swipeActions(edge: .trailing) {
                            deleteSwipe(for: reminder)
                        }
                    }
                }
            }

            // 已完成
            let confirmedReminders = filtered.filter { $0.status == .confirmed }
            if !confirmedReminders.isEmpty {
                Section("✅ 已完成") {
                    ForEach(confirmedReminders) { reminder in
                        NavigationLink {
                            ReminderDetailView(reminder: reminder)
                        } label: {
                            ReminderRowView(reminder: reminder)
                        }
                        .swipeActions(edge: .leading) {
                            reopenSwipe(for: reminder)
                        }
                        .swipeActions(edge: .trailing) {
                            deleteSwipe(for: reminder)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await ReminderEngine.shared.checkMissedReminders(reminders: reminders)
        }
    }

    // MARK: - 智能清单筛选条

    private var smartListBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SmartList.allCases, id: \.self) { list in
                    Button {
                        smartList = list
                    } label: {
                        Text(list.label)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(smartList == list ? Color.accentColor : Color.gray.opacity(0.18))
                            .foregroundStyle(smartList == list ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    // MARK: - 滑动操作

    /// 右滑 → 完成
    @ViewBuilder
    private func completeSwipe(for reminder: Reminder) -> some View {
        Button {
            ReminderEngine.shared.confirmReminder(reminder)
        } label: {
            Label("完成", systemImage: "checkmark")
        }
        .tint(.green)
    }

    /// 右滑（已完成行）→ 重新打开
    @ViewBuilder
    private func reopenSwipe(for reminder: Reminder) -> some View {
        Button {
            ReminderEngine.shared.reopenReminder(reminder)
        } label: {
            Label("重开", systemImage: "arrow.uturn.backward")
        }
        .tint(.orange)
    }

    /// 左滑 → 删除
    @ViewBuilder
    private func deleteSwipe(for reminder: Reminder) -> some View {
        Button(role: .destructive) {
            deleteReminder(reminder)
        } label: {
            Label("删除", systemImage: "trash")
        }
    }

    // MARK: - 智能清单匹配

    private func matchSmartList(_ reminder: Reminder) -> Bool {
        switch smartList {
        case .all:      return true
        case .done:     return reminder.status == .confirmed
        case .high:     return reminder.priority == .high
        case .today:    return occursWithin(reminder: reminder, days: 0...0)
        case .tomorrow: return occursWithin(reminder: reminder, days: 1...1)
        case .week:     return occursWithin(reminder: reminder, days: 0...7)
        case .month:    return occursWithin(reminder: reminder, days: 0...daysLeftInMonth())
        }
    }

    private func occursWithin(reminder: Reminder, days: ClosedRange<Int>) -> Bool {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for d in days.lowerBound...days.upperBound {
            guard let date = cal.date(byAdding: .day, value: d, to: today) else { continue }
            let y = cal.component(.year, from: date)
            let m = cal.component(.month, from: date)
            let day = cal.component(.day, from: date)
            if ReminderEngine.shared.occursOn(reminder: reminder, year: y, month: m, day: day) {
                return true
            }
        }
        return false
    }

    private func daysLeftInMonth() -> Int {
        let cal = Calendar.current
        let now = Date()
        guard let range = cal.range(of: .day, in: .month, for: now),
              let lastDay = cal.date(bySetting: .day, value: range.count, of: now) else { return 30 }
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: lastDay)).day ?? 30
    }

    private func deleteReminders(_ offsets: IndexSet, from items: [Reminder]) {
        for index in offsets {
            guard index < items.count else { continue }
            let reminder = items[index]
            Task {
                await NotificationManager.shared.removePendingNotification(for: reminder.id)
            }
            modelContext.delete(reminder)
        }
        try? modelContext.save()
        SyncStore.touchLocalChange()
    }

    private func deleteReminder(_ reminder: Reminder) {
        Task {
            await NotificationManager.shared.removePendingNotification(for: reminder.id)
        }
        modelContext.delete(reminder)
        try? modelContext.save()
        SyncStore.touchLocalChange()
    }
}

// MARK: - 智能清单类型

enum SmartList: String, CaseIterable, Hashable {
    case all      = "全部"
    case today    = "今天"
    case tomorrow = "明天"
    case week     = "本周"
    case month    = "本月"
    case high     = "高优先级"
    case done     = "已完成"

    var label: String { rawValue }
}

// MARK: - 点击日历某天 → 当日任务弹窗

struct DayTasksSheet: View {
    let day: Date
    let reminders: [Reminder]

    @MainActor private var dateReminders: [Reminder] {
        let cal = Calendar.current
        let y = cal.component(.year, from: day)
        let m = cal.component(.month, from: day)
        let d = cal.component(.day, from: day)
        return reminders.filter {
            $0.isEnabled && ReminderEngine.shared.occursOn(reminder: $0, year: y, month: m, day: d)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if dateReminders.isEmpty {
                    Spacer()
                    Text("这一天没有提醒")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    List(dateReminders) { r in
                        NavigationLink {
                            ReminderDetailView(reminder: r)
                        } label: {
                            ReminderRowView(reminder: r)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var title: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: day) + " 的任务"
    }
}

// MARK: - 首页概览卡片（参考滴答清单：待处理数 + 最近提醒）

struct OverviewCard: View {
    let unhandledCount: Int
    let nextReminder: Reminder?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("待处理 \(unhandledCount) 项")
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let r = nextReminder {
                    Text("\(r.title) · \(r.nextTriggerAt.formatted(date: .numeric, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("暂无即将到来的提醒")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground(Color.clear)
    }
}
