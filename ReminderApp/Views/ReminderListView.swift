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

    // 导入/导出
    @State private var showExportExporter = false
    @State private var exportDocument: ReminderBackupDocument?
    @State private var showImportImporter = false

    // 同步提示
    @State private var syncMessage: String?

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

            for item in items {
                let reminder = BackupHelper.makeReminder(from: item)
                modelContext.insert(reminder)
            }
            try? modelContext.save()
            SyncStore.touchLocalChange()

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
                CalendarCardView(reminders: reminders)
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
            // 日历卡片
            Section {
                CalendarCardView(reminders: reminders)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            // 正在提醒中（active / snoozed / overdue）
            let activeReminders = reminders.filter {
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
                    }
                    .onDelete { offsets in
                        deleteReminders(offsets, from: activeReminders)
                    }
                }
            }

            // 等待中
            let pendingReminders = reminders.filter { $0.status == .pending }
            if !pendingReminders.isEmpty {
                Section("⏳ 等待中") {
                    ForEach(pendingReminders) { reminder in
                        NavigationLink {
                            ReminderDetailView(reminder: reminder)
                        } label: {
                            ReminderRowView(reminder: reminder)
                        }
                    }
                    .onDelete { offsets in
                        deleteReminders(offsets, from: pendingReminders)
                    }
                }
            }

            // 已完成
            let confirmedReminders = reminders.filter { $0.status == .confirmed }
            if !confirmedReminders.isEmpty {
                Section("✅ 已完成") {
                    ForEach(confirmedReminders) { reminder in
                        NavigationLink {
                            ReminderDetailView(reminder: reminder)
                        } label: {
                            ReminderRowView(reminder: reminder)
                        }
                    }
                    .onDelete { offsets in
                        deleteReminders(offsets, from: confirmedReminders)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await ReminderEngine.shared.checkMissedReminders(reminders: reminders)
        }
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
}
