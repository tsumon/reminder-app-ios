import SwiftUI
import SwiftData

/// 首页：提醒列表
struct ReminderListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Reminder.nextTriggerAt) private var reminders: [Reminder]
    @State private var showCreateSheet = false

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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                    }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateReminderView()
            }
        }
    }

    // MARK: - 空状态

    private var emptyView: some View {
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
        .padding(40)
    }

    // MARK: - 提醒列表

    private var listView: some View {
        List {
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
                    .onDelete(perform: deleteReminders)
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
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await ReminderEngine.shared.checkMissedReminders(reminders: reminders)
        }
    }

    private func deleteReminders(at offsets: IndexSet) {
        let pendingReminders = reminders.filter { $0.status == .pending }
        for index in offsets {
            let reminder = pendingReminders[index]
            Task {
                await NotificationManager.shared.removePendingNotification(for: reminder.id)
            }
            modelContext.delete(reminder)
        }
        try? modelContext.save()
    }
}
