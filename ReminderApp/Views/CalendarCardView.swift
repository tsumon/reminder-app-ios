import SwiftUI
import SwiftData

/// 主页日历卡片：公历 + 农历 + 星期几 + 任务缩略标记
struct CalendarCardView: View {
    let reminders: [Reminder]
    var onDateTap: (Date) -> Void = { _ in }

    private let calendar = Calendar.current
    private let weekdayHeader = ["一", "二", "三", "四", "五", "六", "日"]

    @State private var displayYear: Int
    @State private var displayMonth: Int // 1-12
    @State private var selectedDate: Date?

    init(reminders: [Reminder]) {
        self.reminders = reminders
        let now = Date()
        _displayYear = State(initialValue: Calendar.current.component(.year, from: now))
        _displayMonth = State(initialValue: Calendar.current.component(.month, from: now))
    }

    // MARK: - 今天信息

    private var today: Date { Date() }

    private var todayLunarText: String {
        let lunar = LunarCalendar.solarToLunar(today)
        return lunar.description
    }

    private var todayWeekdayText: String {
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return names[calendar.component(.weekday, from: today) - 1]
    }

    // MARK: - 任务日期映射

    @MainActor private var taskDates: [String: Int] {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        var map: [String: Int] = [:]
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfDisplayMonth())?.count ?? 30
        for day in 1...daysInMonth {
            let count = reminders.filter {
                $0.isEnabled && ReminderEngine.shared.occursOn(reminder: $0, year: displayYear, month: displayMonth, day: day)
            }.count
            if count > 0 {
                map[String(format: "%04d-%02d-%02d", displayYear, displayMonth, day)] = count
            }
        }
        return map
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 8) {
            header
            weekdayRow
            dayGrid
        }
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var header: some View {
        HStack {
            Button {
                withAnimation { changeMonth(by: -1) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 3) {
                Text("\(displayYear)年\(displayMonth)月")
                    .font(.headline)
                Text("农历\(todayLunarText) · \(todayWeekdayText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation { changeMonth(by: 1) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(weekdayHeader, id: \.self) { d in
                Text(d)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 6)
    }

    @MainActor private var dayGrid: some View {
        let firstOfMonth = firstOfDisplayMonth()
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30
        // Calendar.weekday: 1=周日...7=周六 → 周一=1...周日=7
        let firstWeekday = (calendar.component(.weekday, from: firstOfMonth) + 5) % 7 + 1
        let leadingBlanks = firstWeekday - 1

        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
            spacing: 4
        ) {
            ForEach(0..<leadingBlanks, id: \.self) { _ in
                Color.clear.frame(height: 46)
            }
            ForEach(1...daysInMonth, id: \.self) { day in
                dayCell(day)
            }
        }
        .padding(.horizontal, 6)
    }

    // MARK: - 日期格子

    @MainActor private func dayCell(_ day: Int) -> some View {
        let isToday = displayYear == calendar.component(.year, from: today)
            && displayMonth == calendar.component(.month, from: today)
            && day == calendar.component(.day, from: today)

        let key = String(format: "%04d-%02d-%02d", displayYear, displayMonth, day)
        let taskCount = taskDates[key] ?? 0
        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: dateFor(day) ?? Date()) } ?? false

        return VStack(spacing: 2) {
            Text("\(day)")
                .font(.subheadline)
                .fontWeight(isToday || isSelected ? .bold : .regular)
                .foregroundStyle(
                    isSelected
                        ? AnyShapeStyle(.tint)
                        : (isToday ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                )
                .frame(width: 28, height: 28)
                .background(
                    isToday
                        ? AnyShapeStyle(.tint)
                        : (isSelected ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(Color.clear))
                )
                .clipShape(Circle())
                .overlay(
                    isSelected && !isToday
                        ? Circle().stroke(.tint, lineWidth: 1.5)
                        : nil
                )

            Text(lunarText(day))
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Circle()
                .fill(taskCount > 0 ? Color.accentColor : Color.clear)
                .frame(width: 4, height: 4)
        }
        .frame(height: 46)
        .frame(maxWidth: .infinity)
        .onTapGesture {
            let d = dateFor(day) ?? Date()
            selectedDate = d
            onDateTap(d)
        }
    }

    private func dateFor(_ day: Int) -> Date? {
        var comps = DateComponents()
        comps.year = displayYear
        comps.month = displayMonth
        comps.day = day
        return calendar.date(from: comps)
    }

    // MARK: - 农历

    private func lunarText(_ day: Int) -> String {
        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = displayYear
        comps.month = displayMonth
        comps.day = day
        comps.hour = 12
        guard let date = cal.date(from: comps) else { return "" }
        let lunar = LunarCalendar.solarToLunar(date)
        let dayNames = [
            "", "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
            "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
            "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
        ]
        guard lunar.day >= 0, lunar.day < dayNames.count else { return "" }
        return dayNames[lunar.day]
    }

    // MARK: - 工具

    private func firstOfDisplayMonth() -> Date {
        var comps = DateComponents()
        comps.year = displayYear
        comps.month = displayMonth
        comps.day = 1
        return calendar.date(from: comps) ?? today
    }

    private func changeMonth(by delta: Int) {
        var newMonth = displayMonth + delta
        var newYear = displayYear
        if newMonth < 1 {
            newMonth = 12
            newYear -= 1
        } else if newMonth > 12 {
            newMonth = 1
            newYear += 1
        }
        displayMonth = newMonth
        displayYear = newYear
    }
}

#Preview {
    CalendarCardView(reminders: [])
        .padding()
}
