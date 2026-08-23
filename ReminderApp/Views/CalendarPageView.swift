import SwiftUI
import SwiftData

/// 日历 Tab（v1.9.8 对齐设计图）：整页月历 + 点击日期展示「当天任务」列表
struct CalendarPageView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Reminder.nextTriggerAt) private var reminders: [Reminder]
    // v2.5.0: 打卡记录（吉祥物心情 / 连胜旗 / 本周跑道）
    @Query(sort: \ReminderRecord.performedAt) private var records: [ReminderRecord]
    @State private var selectedDate: Date = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                CalendarCardView(
                    reminders: reminders,
                    streak: StatsService.summarize(records: records).currentStreak,
                    weekDone: weekDoneDays(records: records)
                ) { date in
                    selectedDate = date
                }

                dayTasksSection
            }
            .padding(16)
        }
        .background(PastelPlaygroundBackground())
        .navigationTitle("日历".localized)
        // v1.9.8.1: iPad 大屏下大标题+玻璃背景形成大块空白，改 inline 更紧凑
        .navigationBarTitleDisplayMode(.inline)
        .glassNavigationBar()
    }

    // MARK: - 当天任务

    @ViewBuilder
    private var dayTasksSection: some View {
        let tasks = dayReminders

        // 分组标题：小色条 + 标题 + 数量（设计图风格）
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(ThemeTokens.statusReminding)
                .frame(width: 4, height: 14)
            Text(dayTitle)
                .font(.headline)
                .foregroundStyle(.primary)
            Text("· \(tasks.count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ThemeTokens.statusReminding)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)

        if tasks.isEmpty {
            Text("这一天没有提醒".localized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
        } else {
            VStack(spacing: 10) {
                ForEach(tasks) { r in
                    NavigationLink {
                        ReminderDetailView(reminder: r)
                    } label: {
                        ReminderRowView(reminder: r)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var dayTitle: String {
        let f = DateFormatter()
        f.dateFormat = "M月d日 · EEEE"
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: selectedDate) + " 的任务"
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
