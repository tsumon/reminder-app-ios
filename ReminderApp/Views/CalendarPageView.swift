import SwiftUI
import SwiftData

/// 日历 Tab（v1.9.8 对齐设计图）：整页月历 + 点击日期展示「当天任务」列表
struct CalendarPageView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Reminder.nextTriggerAt) private var reminders: [Reminder]
    @State private var selectedDate: Date = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                CalendarCardView(reminders: reminders) { date in
                    selectedDate = date
                }

                dayTasksSection
            }
            .padding(16)
        }
        .navigationTitle("日历")
        .navigationBarTitleDisplayMode(.large)
        .glassPageBackground()
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
            Text("这一天没有提醒")
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
