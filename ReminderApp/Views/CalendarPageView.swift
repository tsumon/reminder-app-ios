import SwiftUI
import SwiftData

/// 日历 Tab：无框顶栏 + 无网格线整月漫风卡 + 选中日无分割线日程卡
struct CalendarPageView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.comic) private var comic
    @Query(sort: \Reminder.nextTriggerAt) private var reminders: [Reminder]

    @State private var selectedDate: Date = Date()
    @State private var displayYear: Int = Calendar.current.component(.year, from: Date())
    @State private var displayMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var pendingDetailID: UUID?
    @State private var showCreate = false

    var body: some View {
        VStack(spacing: 0) {
            bareHeader
            ComicHairline(outer: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    CalendarCardView(
                        reminders: reminders,
                        displayYear: $displayYear,
                        displayMonth: $displayMonth
                    ) { date in
                        selectedDate = date
                    }

                    dayScheduleCard

                    Button {
                        showCreate = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .heavy))
                            Text("添加当天提醒".localized)
                        }
                    }
                    .buttonStyle(ComicButtonStyle(variant: .accent, expand: true))
                    .accessibilityLabel("添加当天提醒".localized)
                }
                .padding(.horizontal, ThemeTokens.gutter)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateReminderView(initialDate: selectedDate)
        }
        .background(ComicCanvas())
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $pendingDetailID) { id in
            if let reminder = reminders.first(where: { $0.id == id }) {
                ReminderDetailView(reminder: reminder)
            }
        }
    }

    private var bareHeader: some View {
        HStack {
            Button {
                changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(comic.ink)
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("上一月".localized)

            Spacer()

            ComicBrandTitle(text: "日历".localized, size: 20, showShard: true)

            Spacer()

            Button {
                changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(comic.ink)
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("下一月".localized)
        }
        .padding(.horizontal, ThemeTokens.gutter)
        .padding(.vertical, 8)
    }

    private var dayScheduleCard: some View {
        let tasks = dayReminders
        return ComicCard(cut: ThemeTokens.cardCut, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(dayTitle)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(comic.ink)
                    Spacer()
                    Text(Localized("%d 项", tasks.count))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(comic.muted)
                }

                if tasks.isEmpty {
                    Text("这一天没有提醒".localized)
                        .font(.system(size: 13.5, weight: .medium, design: .rounded))
                        .foregroundStyle(comic.muted)
                        .padding(.vertical, 8)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(tasks) { r in
                            dayTaskRow(r)
                        }
                    }
                }
            }
        }
    }

    private func dayTaskRow(_ r: Reminder) -> some View {
        let token = r.actionToken
        let due = r.status == .active || r.status == .snoozed || r.status == .overdue
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(clockText(r))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(due ? comic.accent : comic.muted)
                .frame(width: 48, alignment: .leading)

            Button {
                pendingDetailID = r.id
            } label: {
                Text(r.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(comic.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(r.dateDisplayText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(comic.muted)
                .lineLimit(1)

            if due {
                Button {
                    _ = ReminderEngine.shared.confirmReminder(r, expectedToken: token)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(comic.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打卡".localized)
            }
        }
    }

    private func clockText(_ r: Reminder) -> String {
        switch r.kind {
        case .date:
            return String(format: "%02d:%02d", r.reminderHour, r.reminderMinute)
        case .rule, .cycle:
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "HH:mm"
            return f.string(from: r.firstTriggerAt)
        }
    }

    private func changeMonth(by delta: Int) {
        var m = displayMonth + delta
        var y = displayYear
        if m < 1 { m = 12; y -= 1 }
        else if m > 12 { m = 1; y += 1 }
        withAnimation(.easeInOut(duration: 0.18)) {
            displayMonth = m
            displayYear = y
        }
    }

    private var dayTitle: String {
        let f = DateFormatter()
        f.dateFormat = "M月d日 · EEEE"
        f.locale = AppLanguageManager.currentLocale
        return f.string(from: selectedDate)
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
