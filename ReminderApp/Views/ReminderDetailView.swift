import SwiftUI
import SwiftData

/// 提醒详情页
struct ReminderDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let reminder: Reminder
    @State private var showDeleteAlert = false
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: 状态大卡片
                statusCard
                    .padding(.horizontal)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .animation(.spring(response: 0.45, dampingFraction: 0.8), value: appeared)

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
        .alert("确认删除".localized, isPresented: $showDeleteAlert) {
            Button("取消".localized, role: .cancel) {}
            Button("删除".localized, role: .destructive) { deleteReminder() }
        } message: {
            Text(Localized("将永久删除「%@」提醒，此操作不可撤销。", reminder.title))
        }
        .onAppear {
            ReminderEngine.shared.configure(with: modelContext)
            appeared = true
        }
    }

    // MARK: - 状态卡片

    /// v1.9.8 设计图风格：状态色渐变大卡 + 玻璃图标容器 + 阴影
    private var statusCard: some View {
        HStack(spacing: 16) {
            // 玻璃大图标容器
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.22))
                    .frame(width: 58, height: 58)
                Image(systemName: statusIconName)
                    .font(.system(size: 27))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("当前状态".localized)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                Text(statusTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text(Localized("下次：%@", nextTriggerText))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [statusColor, statusColor.opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: statusColor.opacity(0.35), radius: 14, y: 6)
    }

    /// 状态卡标题：状态 + 重试阶段（对齐设计图）
    private var statusTitle: String {
        var t = reminder.status.rawValue.localized
        if reminder.retryStage > 0 {
            t += " · " + Localized("第%d次重试", reminder.retryStage)
        }
        return t
    }

    // MARK: - 操作按钮

    @ViewBuilder
    private var actionButtons: some View {
        if reminder.status == .active || reminder.status == .snoozed || reminder.status == .overdue {
            HStack(spacing: 12) {
                Button {
                    ReminderEngine.shared.confirmReminder(reminder)
                } label: {
                    Label("确认完成".localized, systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    ReminderEngine.shared.snoozeReminder(reminder)
                } label: {
                    Label("稍后提醒".localized, systemImage: "clock.arrow.circlepath")
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
            Label("信息".localized, systemImage: "info.circle")
                .font(.headline)

            Divider()

            // Item 2: 本次触发因节假日前移的说明
            if let note = holidayAdjustNote {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .foregroundStyle(.orange)
                        .frame(width: 22)
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            infoRow(label: "周期".localized, value: reminder.dateDisplayText)
            if reminder.kind == .cycle && reminder.cycle == .custom && reminder.customDays > 0 {
                infoRow(label: "自定义天数".localized, value: Localized("%d 天", reminder.customDays))
            }
            if reminder.kind == .rule {
                infoRow(label: "频率".localized, value: reminder.rulePeriod.rawValue.localized)
                infoRow(label: "周次".localized, value: reminder.ruleWeek.label.localized)
                infoRow(label: "星期".localized, value: reminder.ruleWeekday.label.localized)
                infoRow(label: "提醒时间".localized, value: String(format: "%02d:%02d", reminder.reminderHour, reminder.reminderMinute))
            }
            if reminder.kind == .date {
                infoRow(label: "提醒类型".localized, value: reminder.dateType?.rawValue.localized ?? "")
                infoRow(label: "提前提醒".localized, value: Localized("%d 天", reminder.advanceDays))
                infoRow(label: "提醒时间".localized, value: String(format: "%02d:%02d", reminder.reminderHour, reminder.reminderMinute))
            }
            infoRow(label: "首次提醒".localized, value: formattedDate(reminder.firstTriggerAt))
            infoRow(label: "下次提醒".localized, value: formattedDate(reminder.nextTriggerAt))

            if reminder.retryStage > 0 {
                infoRow(label: "重试阶段".localized, value: Localized("第 %d 次", reminder.retryStage))
            }

            infoRow(label: "创建时间".localized, value: formattedDate(reminder.createdAt))

            Toggle(isOn: Binding(
                get: { reminder.isEnabled },
                set: { newValue in
                    reminder.isEnabled = newValue
                    reminder.updatedAt = Date()

                    // 关闭期间时间会流逝，重新开启时 nextTriggerAt 往往已经过期。
                    // 不重算的话通知要么立刻炸出来，要么因为是过去时间被系统直接丢弃，
                    // 结果就是「开关重开后再也不提醒了」。这里必须先把下次时间推到未来。
                    if newValue, reminder.nextTriggerAt <= Date() {
                        reminder.nextTriggerAt = ReminderEngine.shared.calculateNextTrigger(
                            after: Date(),
                            reminder: reminder
                        )
                    }
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
                Text("启用提醒".localized)
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
            Label("操作记录".localized, systemImage: "list.bullet.rectangle")
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
            Label("删除此提醒".localized, systemImage: "trash")
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .controlSize(.large)
    }

    // MARK: - 辅助

    /// Item 2: 读取本次触发被前移的说明（来自 UserDefaults 侧存）
    private var holidayAdjustNote: String? {
        ReminderEngine.HolidayAdjustStore.note(for: reminder.id)
    }

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
        case .pending:   return ThemeTokens.statusWaiting
        case .active:    return ThemeTokens.statusReminding
        case .snoozed:   return .orange
        case .confirmed: return ThemeTokens.statusCompleted
        case .overdue:   return ThemeTokens.statusOverdue
        }
    }

    private var nextTriggerText: String {
        switch reminder.status {
        case .pending:
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            return Localized("将在 %@ 提醒", formatter.localizedString(for: reminder.nextTriggerAt, relativeTo: Date()))
        case .confirmed:
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            return Localized("下次提醒 %@", formatter.localizedString(for: reminder.nextTriggerAt, relativeTo: Date()))
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
