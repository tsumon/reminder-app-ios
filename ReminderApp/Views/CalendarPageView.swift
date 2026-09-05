import SwiftUI
import SwiftData

/// 日历 Tab：整月 elevated 卡 + 当天任务。无本周进度、无热力月格。
struct CalendarPageView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Reminder.nextTriggerAt) private var reminders: [Reminder]
    @Query(sort: \ReminderRecord.performedAt) private var records: [ReminderRecord]
    @State private var selectedDate: Date = Date()
    @State private var displayYear: Int = Calendar.current.component(.year, from: Date())
    @State private var displayMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var pendingDetailID: UUID?
    @Environment(\.soft) private var soft

    var body: some View {
        VStack(spacing: 0) {
            SoftScreenHeader(title: "日历") {
                SoftCircleButton(size: 40, action: { changeMonth(by: -1) }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ThemeTokens.strong)
                }
                .accessibilityLabel("上一月".localized)
            } trailing: {
                SoftCircleButton(size: 40, action: { changeMonth(by: 1) }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ThemeTokens.strong)
                }
                .accessibilityLabel("下一月".localized)
            }
            .background(soft.canvas)

            ScrollView {
                VStack(spacing: 14) {
                    CalendarCardView(
                        reminders: reminders,
                        displayYear: $displayYear,
                        displayMonth: $displayMonth
                    ) { date in
                        selectedDate = date
                    }

                    dayTasksSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
        .background(PaperCanvas())
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $pendingDetailID) { id in
            if let reminder = reminders.first(where: { $0.id == id }) {
                ReminderDetailView(reminder: reminder)
            }
        }
    }

    private func changeMonth(by delta: Int) {
        var m = displayMonth + delta
        var y = displayYear
        if m < 1 { m = 12; y -= 1 }
        else if m > 12 { m = 1; y += 1 }
        withAnimation(.easeInOut(duration: 0.2)) {
            displayMonth = m
            displayYear = y
        }
    }

    @ViewBuilder
    private var dayTasksSection: some View {
        let tasks = dayReminders
        SoftSectionHeader(title: dayTitle, color: ThemeTokens.statusReminding, count: tasks.count)

        if tasks.isEmpty {
            Text("这一天没有提醒".localized)
                .font(SoftType.body)
                .foregroundStyle(soft.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
        } else {
            VStack(spacing: 10) {
                ForEach(tasks) { r in
                    dayTaskRow(r)
                }
            }
        }
    }

    @ViewBuilder
    private func dayTaskRow(_ r: Reminder) -> some View {
        let due = r.status == .active || r.status == .snoozed || r.status == .overdue
        Button {
            pendingDetailID = r.id
        } label: {
            ReminderRowView(reminder: r, onConfirm: due ? {
                ReminderEngine.shared.confirmReminder(r)
            } : nil)
        }
        .buttonStyle(.plain)
    }

    private var dayTitle: String {
        let f = DateFormatter()
        f.dateFormat = "M月d日 · EEEE"
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: selectedDate) + "的任务"
    }

    @MainActor private var dayReminders: [Reminder] {
        let cal = Calendar.current
        let y = cal.component(.year, from: selectedDate)
        let m = cal.component(.month, from: selectedDate)
        let d = cal.component(.day, from: selectedDate)
        return reminders.filter {
            $0.isEnabled && ReminderEngine.shared.occursOn(reminder: $0, year: y, month: m, day: d)
        }
    }
}

#Preview {
    CalendarPageView()
        .modelContainer(for: [Reminder.self, ReminderRecord.self], inMemory: true)
}
