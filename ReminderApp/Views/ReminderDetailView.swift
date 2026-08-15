import SwiftUI
import SwiftData

/// 提醒详情页
struct ReminderDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let reminder: Reminder
    @State private var showDeleteAlert = false
    @State private var appeared = false
    // v2.0.22: 删除保存失败提示（不直接关页面）
    @State private var deleteErrorMessage: String?
    // 批次2 功能2: 打卡成功 → 正向反馈卡片文案（非空即展示）
    @State private var checkInText: String?
    // v2.0.21 G3: 每次打卡自增，作为自动消失计时器的 id（换值即取消上一条的计时，防提前清空）
    @State private var checkInToken = 0

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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // 批次3 功能6: 单条提醒分享卡片（导出为 JSON 经系统分享面板发出）
                ShareLink(item: BackupHelper.exportSingle(reminder)) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .alert("确认删除".localized, isPresented: $showDeleteAlert) {
            Button("取消".localized, role: .cancel) {}
            Button("删除".localized, role: .destructive) { deleteReminder() }
        } message: {
            Text(Localized("将永久删除「%@」提醒，此操作不可撤销。", reminder.title))
        }
        .alert("删除失败".localized, isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )) {
            Button("好".localized, role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
        .onAppear {
            ReminderEngine.shared.configure(with: modelContext)
            appeared = true
        }
        // 批次2 功能2: 打卡成功卡片（顶部浮层，不拦截点击）
        .overlay {
            CheckInFeedbackBanner(text: checkInText)
        }
        // v2.0.21 G3: 自动消失改用可取消的 task（原 asyncAfter 无法撤销，连续确认会提前清掉后一条）
        .task(id: checkInToken) {
            guard checkInToken > 0, checkInText != nil else { return }
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard !Task.isCancelled else { return }
            checkInText = nil
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
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        performCheckIn()
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

                // 已逾期：给一个明确的「补打今天」入口——按今天完成、推进周期、计入统计
                if reminder.status == .overdue {
                    Button {
                        performCheckIn(source: "补打卡")
                    } label: {
                        Label("补打今天".localized, systemImage: "checkmark.circle.badge.questionmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(ThemeTokens.statusOverdue)
                    .accessibilityHint("把这条逾期提醒按今天完成，并推进到下一个周期".localized)
                }
            }
            .controlSize(.large)
        }
    }

    /// 打卡（确认完成 / 补打今天共用）：确认 + 弹正向反馈卡片
    private func performCheckIn(source: String = "手动确认") {
        ReminderEngine.shared.confirmReminder(reminder, source: source)
        // 批次2 功能2: 打卡成功卡片（计算当前连续天数）
        let descriptor = FetchDescriptor<ReminderRecord>()
        let records = (try? modelContext.fetch(descriptor)) ?? []
        let streak = StatsService.summarize(records: records).currentStreak
        let prefix = source == "补打卡" ? "补打卡成功".localized : "打卡成功".localized
        checkInText = streak > 1
            ? Localized("%@，已连续 %d 天 🎉", prefix, streak)
            : "\(prefix) 🎉"
        checkInToken += 1
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
                            // Bug 2: 开关重开必须走 scheduleAllNotifications，
                            // 否则缺幽灵守卫 / 日期类提前预告 / 递增重试链
                            // （scheduleNotification 只排 D-day 单条）。
                            await ReminderEngine.shared.scheduleAllNotifications(for: reminder)
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

            // 批次3 功能5: 关键提醒开关（触发更激进的重复 alert 脉冲）
            Toggle(isOn: Binding(
                get: { ReminderEngine.CriticalStore.isCritical(reminder.id) },
                set: { newValue in
                    ReminderEngine.CriticalStore.setCritical(newValue, for: reminder.id)
                    if reminder.isEnabled {
                        Task {
                            await ReminderEngine.shared.scheduleAllNotifications(for: reminder)
                        }
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("关键提醒".localized)
                        .font(.subheadline)
                    Text("重要事项，错过会重复提醒直到确认".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                    Image(systemName: record.type == ReminderRecordType.confirm.rawValue ? "checkmark.circle" : record.type == ReminderRecordType.snooze.rawValue ? "clock" : "bell")
                        .foregroundStyle(record.type == ReminderRecordType.confirm.rawValue ? .green : record.type == ReminderRecordType.snooze.rawValue ? .orange : .blue)
                        .frame(width: 24)

                    Text(record.type == ReminderRecordType.confirm.rawValue ? "确认完成" : record.type == ReminderRecordType.snooze.rawValue ? "稍后提醒" : "系统提醒")
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
        // v2.0.22: 保存失败不再吞掉后直接关页面——UI 已消失但数据还在，
        // 用户会以为删掉了；失败时保留页面并提示
        do {
            try modelContext.save()
        } catch {
            deleteErrorMessage = Localized("删除失败，请重试：%@", error.localizedDescription)
            return
        }
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
