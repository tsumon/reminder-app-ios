import SwiftUI
import SwiftData

/// 提醒详情页
struct ReminderDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let reminder: Reminder
    @State private var showDeleteAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: 状态大卡片
                statusCard
                    .padding(.horizontal)

                // MARK: 操作按钮
                actionButtons
                    .padding(.horizontal)

                // MARK: 信息卡片
                infoCard
                    .padding(.horizontal)

                // MARK: 操作记录
                if !reminder.records.isEmpty {
                    recordsCard
                        .padding(.horizontal)
                }

                // MARK: 删除
                deleteButton
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            .padding(.vertical, 16)
        }
        .navigationTitle(reminder.title)
        .navigationBarTitleDisplayMode(.large)
        .alert("确认删除", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { deleteReminder() }
        } message: {
            Text("将永久删除「\(reminder.title)」提醒，此操作不可撤销。")
        }
        .onAppear {
            ReminderEngine.shared.configure(with: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: .reminderConfirmed)) { notification in
            if let id = notification.userInfo?["reminderID"] as? UUID,
               id == reminder.id {
                ReminderEngine.shared.confirmReminder(reminder)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .reminderSnoozed)) { notification in
            if let id = notification.userInfo?["reminderID"] as? UUID,
               id == reminder.id {
                ReminderEngine.shared.snoozeReminder(reminder)
            }
        }
    }

    // MARK: - 状态卡片

    private var statusCard: some View {
        VStack(spacing: 12) {
            Image(systemName: statusIconName)
                .font(.system(size: 48))
                .foregroundStyle(statusColor)

            Text(reminder.status.rawValue)
                .font(.title3.weight(.semibold))
                .foregroundStyle(statusColor)

            Text(nextTriggerText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(statusColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 操作按钮

    @ViewBuilder
    private var actionButtons: some View {
        if reminder.status == .active || reminder.status == .snoozed || reminder.status == .overdue {
            HStack(spacing: 12) {
                Button {
                    ReminderEngine.shared.confirmReminder(reminder)
                } label: {
                    Label("确认完成", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    ReminderEngine.shared.snoozeReminder(reminder)
                } label: {
                    Label("稍后提醒", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
            .controlSize(.large)
        }
    }

    // MARK: - 信息卡片

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("信息", systemImage: "info.circle")
                .font(.headline)

            Divider()

            infoRow(label: "周期", value: reminder.dateDisplayText)
            if reminder.kind == .cycle && reminder.cycle == .custom && reminder.customDays > 0 {
                infoRow(label: "自定义天数", value: "\(reminder.customDays) 天")
            }
            if reminder.kind == .rule {
                infoRow(label: "频率", value: reminder.rulePeriod.rawValue)
                infoRow(label: "周次", value: reminder.ruleWeek.label)
                infoRow(label: "星期", value: reminder.ruleWeekday.label)
                infoRow(label: "提醒时间", value: String(format: "%02d:%02d", reminder.reminderHour, reminder.reminderMinute))
            }
            if reminder.kind == .date {
                infoRow(label: "提醒类型", value: reminder.dateType?.rawValue ?? "")
                infoRow(label: "提前提醒", value: "\(reminder.advanceDays) 天")
                infoRow(label: "提醒时间", value: String(format: "%02d:%02d", reminder.reminderHour, reminder.reminderMinute))
            }
            infoRow(label: "首次提醒", value: formattedDate(reminder.firstTriggerAt))
            infoRow(label: "下次提醒", value: formattedDate(reminder.nextTriggerAt))

            if reminder.retryStage > 0 {
                infoRow(label: "重试阶段", value: "第 \(reminder.retryStage) 次")
            }

            infoRow(label: "创建时间", value: formattedDate(reminder.createdAt))

            Toggle(isOn: Binding(
                get: { reminder.isEnabled },
                set: { newValue in
                    reminder.isEnabled = newValue
                    reminder.updatedAt = Date()
                    try? modelContext.save()

                    if newValue {
                        Task {
                            await NotificationManager.shared.scheduleNotification(for: reminder, badgeCount: ReminderEngine.shared.unconfirmedCount())
                        }
                    } else {
                        Task {
                            await NotificationManager.shared.removePendingNotification(for: reminder.id)
                        }
                    }
                }
            )) {
                Text("启用提醒")
                    .font(.subheadline)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 操作记录卡片

    private var recordsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("操作记录", systemImage: "list.bullet.rectangle")
                .font(.headline)

            Divider()

            ForEach(reminder.records.sorted(by: { $0.performedAt > $1.performedAt }).prefix(20), id: \.id) { record in
                HStack {
                    Image(systemName: record.type == "confirm" ? "checkmark.circle" : record.type == "snooze" ? "clock" : "bell")
                        .foregroundStyle(record.type == "confirm" ? .green : record.type == "snooze" ? .orange : .blue)
                        .frame(width: 24)

                    Text(record.type == "confirm" ? "确认完成" : record.type == "snooze" ? "稍后提醒" : "系统提醒")
                        .font(.subheadline)

                    Spacer()

                    Text(formattedDate(record.performedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 删除按钮

    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteAlert = true
        } label: {
            Label("删除此提醒", systemImage: "trash")
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .controlSize(.large)
    }

    // MARK: - 辅助

    private var statusIconName: String {
        switch reminder.status {
        case .pending:   return "clock"
        case .active:    return "bell.badge.fill"
        case .snoozed:   return "moon.zzz.fill"
        case .confirmed: return "checkmark.circle.fill"
        case .overdue:   return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch reminder.status {
        case .pending:   return .blue
        case .active:    return .red
        case .snoozed:   return .orange
        case .confirmed: return .green
        case .overdue:   return .red
        }
    }

    private var nextTriggerText: String {
        switch reminder.status {
        case .pending:
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            return "将在 \(formatter.localizedString(for: reminder.nextTriggerAt, relativeTo: Date())) 提醒"
        case .confirmed:
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            return "下次提醒 \(formatter.localizedString(for: reminder.nextTriggerAt, relativeTo: Date()))"
        case .active, .snoozed, .overdue:
            return "等待确认操作"
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private func deleteReminder() {
        Task {
            await NotificationManager.shared.removePendingNotification(for: reminder.id)
        }
        modelContext.delete(reminder)
        try? modelContext.save()
        SyncStore.touchLocalChange()
        dismiss()
    }
}

#Preview {
    NavigationStack {
        ReminderDetailView(reminder: Reminder(
            title: "每周打针",
            note: "胰岛素注射",
            cycle: .weekly,
            firstTriggerAt: Date(),
            nextTriggerAt: Date().addingTimeInterval(86400),
            status: .active,
            retryStage: 1
        ))
    }
    .modelContainer(for: [Reminder.self, ReminderRecord.self])
}
