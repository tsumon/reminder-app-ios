import SwiftUI
import SwiftData

/// 提醒详情页（极简奶油漫风两主卡 + 底纸纯文字折叠预览与操作记录）
struct ReminderDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.comic) private var comic

    let reminder: Reminder
    var highlightConfirm: Bool = false

    @State private var showEdit = false
    @State private var showDeleteAlert = false
    @State private var showShareSheet = false
    @State private var deleteErrorMessage: String?
    @State private var checkInText: String?
    @State private var checkInToken = 0

    @State private var showCustomSnooze = false
    @State private var customSnoozeToken = ""
    @State private var customSnoozeMinutes = "15"

    @State private var quietHoursEnabled = false
    @State private var quietStart = Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var quietEnd = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()

    @State private var showFuturePreview = false
    @State private var showHistoryRecords = false

    var body: some View {
        let token = reminder.actionToken
        let futures = ReminderEngine.shared.futureTriggers(for: reminder, count: 10)
        let sortedRecords = reminder.records.sorted { $0.performedAt > $1.performedAt }

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DetailHeroStatusCard(
                    reminder: reminder,
                    highlightConfirm: highlightConfirm,
                    onConfirm: { performCheckIn(expectedToken: token) },
                    onMakeUpConfirm: { performCheckIn(source: "补打卡", expectedToken: token) },
                    onSnooze15: { _ = ReminderEngine.shared.snoozeReminder(reminder, afterMinutes: 15, expectedToken: token) },
                    onSnooze60: { _ = ReminderEngine.shared.snoozeReminder(reminder, afterMinutes: 60, expectedToken: token) },
                    onSnoozeTomorrow: { ReminderEngine.shared.snoozeReminderTomorrow(reminder, expectedToken: token) },
                    onCustomSnooze: { customSnoozeToken = token; showCustomSnooze = true },
                    onSkip: { ReminderEngine.shared.skipReminder(reminder, expectedToken: token) },
                    onUndoCompletion: { ReminderEngine.shared.undoCompletion(reminder, expectedToken: token) },
                    onEdit: { showEdit = true }
                )

                DetailInfoCard(
                    reminder: reminder,
                    holidayAdjustNote: ReminderEngine.HolidayAdjustStore.note(for: reminder.id),
                    quietHoursEnabled: $quietHoursEnabled,
                    quietStart: $quietStart,
                    quietEnd: $quietEnd,
                    onToggleEnabled: toggleEnabled,
                    onToggleImportant: toggleImportant,
                    onToggleQuiet: toggleQuietHours,
                    onPersistQuiet: persistQuietHours
                )

                if !futures.isEmpty {
                    ComicCollapsibleLine(
                        title: "未来触发预览".localized,
                        trailing: Localized("%d 次", futures.count),
                        isExpanded: showFuturePreview
                    ) {
                        withAnimation(.easeOut(duration: 0.16)) { showFuturePreview.toggle() }
                    }

                    if showFuturePreview {
                        ComicCard(cut: ThemeTokens.cardCut, padding: 16) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(futures.enumerated()), id: \.offset) { idx, d in
                                    HStack {
                                        Text("#\(idx + 1)")
                                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                                            .monospacedDigit()
                                            .foregroundStyle(comic.hero)
                                            .frame(width: 28, alignment: .leading)
                                        Text(formattedDate(d))
                                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                                            .monospacedDigit()
                                            .foregroundStyle(comic.ink)
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                }

                if !sortedRecords.isEmpty {
                    ComicCollapsibleLine(
                        title: "操作记录".localized,
                        trailing: Localized("%d 条", sortedRecords.count),
                        isExpanded: showHistoryRecords
                    ) {
                        withAnimation(.easeOut(duration: 0.16)) { showHistoryRecords.toggle() }
                    }

                    if showHistoryRecords {
                        ComicCard(cut: ThemeTokens.cardCut, padding: 16) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(sortedRecords.prefix(20), id: \.id) { rec in
                                    HStack {
                                        Text(recordLabel(rec.type))
                                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                                            .foregroundStyle(comic.ink)
                                        Spacer()
                                        Text(formattedDate(rec.performedAt))
                                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                            .monospacedDigit()
                                            .foregroundStyle(comic.muted)
                                    }
                                }
                            }
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label("删除此提醒".localized, systemImage: "trash")
                    }
                    .buttonStyle(ComicButtonStyle(variant: .danger))
                    Spacer()
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, ThemeTokens.gutter)
            .padding(.vertical, 16)
        }
        .background(ComicCanvas())
        .navigationTitle(reminder.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(comic.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(comic.ink)
                }
                .accessibilityIdentifier("share-reminder")
            }
        }
        .sheet(isPresented: $showEdit) { CreateReminderView(editing: reminder) }
        .sheet(isPresented: $showShareSheet) { ActivityShareSheet(items: shareItems) }
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
        } message: { Text(deleteErrorMessage ?? "") }
        .alert("自定义稍后".localized, isPresented: $showCustomSnooze) {
            TextField("分钟数".localized, text: $customSnoozeMinutes)
                .keyboardType(.numberPad)
            Button("取消".localized, role: .cancel) {}
            Button("确定".localized) {
                let minutes = Int(customSnoozeMinutes) ?? 15
                _ = ReminderEngine.shared.snoozeReminder(reminder, afterMinutes: max(1, minutes), expectedToken: customSnoozeToken)
            }
        } message: {
            Text("多少分钟后再次提醒？".localized)
        }
        .onAppear {
            ReminderEngine.shared.configure(with: modelContext)
            if let start = reminder.quietStartMinute, let end = reminder.quietEndMinute {
                quietHoursEnabled = true
                quietStart = Calendar.current.date(bySettingHour: start / 60, minute: start % 60, second: 0, of: Date()) ?? quietStart
                quietEnd = Calendar.current.date(bySettingHour: end / 60, minute: end % 60, second: 0, of: Date()) ?? quietEnd
            }
        }
        .overlay { CheckInFeedbackBanner(text: checkInText) }
        .task(id: checkInToken) {
            guard checkInToken > 0, checkInText != nil else { return }
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if !Task.isCancelled { checkInText = nil }
        }
    }

    // MARK: - 交互动作

    private var shareItems: [Any] {
        let text = ReminderShare.plainText(
            title: reminder.title, cycleLabel: reminder.dateDisplayText,
            nextTrigger: reminder.nextTriggerAt, note: reminder.note
        )
        let ics = IcsExporter.generateICS(reminders: [reminder])
        return [text, ReminderShare.writeICSFile(named: reminder.title, contents: ics)]
    }

    private func performCheckIn(source: String = "手动确认", expectedToken: String) {
        guard ReminderEngine.shared.confirmReminder(reminder, source: source, expectedToken: expectedToken) else { return }
        let records = (try? modelContext.fetch(FetchDescriptor<ReminderRecord>())) ?? []
        let streak = StatsService.summarize(records: records).currentStreak
        let prefix = source == "补打卡" ? "补打卡成功".localized : "打卡成功".localized
        checkInText = streak > 1 ? Localized("%@，已连续 %d 天", prefix, streak) : prefix
        checkInToken += 1
    }

    private func toggleEnabled(_ newValue: Bool) {
        reminder.isEnabled = newValue
        reminder.updatedAt = Date()
        if newValue, reminder.nextTriggerAt <= Date() {
            reminder.nextTriggerAt = ReminderEngine.shared.calculateNextTrigger(after: Date(), reminder: reminder)
        }
        _ = ReminderActions.changed(reminder, context: modelContext)
        if newValue {
            Task { await ReminderEngine.shared.scheduleAllNotifications(for: reminder) }
        } else {
            Task { await NotificationManager.shared.removePendingNotification(for: reminder.id) }
        }
    }

    private func toggleImportant(_ newValue: Bool) {
        reminder.reminderStyle = newValue ? "important" : "persistent"
        _ = ReminderActions.changed(reminder, context: modelContext)
        if reminder.isEnabled {
            Task { await ReminderEngine.shared.scheduleAllNotifications(for: reminder) }
        }
    }

    private func toggleQuietHours(_ newValue: Bool) {
        quietHoursEnabled = newValue
        if newValue {
            persistQuietHours()
        } else {
            reminder.quietStartMinute = nil; reminder.quietEndMinute = nil
            _ = ReminderActions.changed(reminder, context: modelContext)
            if reminder.isEnabled {
                Task { await ReminderEngine.shared.scheduleAllNotifications(for: reminder) }
            }
        }
    }

    private func persistQuietHours() {
        let start = Calendar.current.component(.hour, from: quietStart) * 60 + Calendar.current.component(.minute, from: quietStart)
        let end = Calendar.current.component(.hour, from: quietEnd) * 60 + Calendar.current.component(.minute, from: quietEnd)
        reminder.quietStartMinute = start; reminder.quietEndMinute = end
        _ = ReminderActions.changed(reminder, context: modelContext)
        if reminder.isEnabled {
            Task { await ReminderEngine.shared.scheduleAllNotifications(for: reminder) }
        }
    }

    private func deleteReminder() {
        let id = reminder.id
        guard ReminderActions.delete(reminder, context: modelContext) else {
            deleteErrorMessage = "删除失败，请重试".localized; return
        }
        Task {
            await NotificationManager.shared.removePendingNotification(for: id)
            await ReminderEngine.shared.ensureRetryChains()
        }
        dismiss()
    }

    private func recordLabel(_ type: String) -> String {
        switch type {
        case ReminderRecordType.confirm.rawValue: return "确认完成".localized
        case ReminderRecordType.snooze.rawValue:  return "稍后提醒".localized
        case ReminderRecordType.skipped.rawValue: return "跳过本次".localized
        default: return "系统提醒".localized
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy/M/d HH:mm"
        return f.string(from: date)
    }
}
