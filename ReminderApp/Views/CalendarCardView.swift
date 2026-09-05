import SwiftUI
import SwiftData

/// 月历 elevated 卡。热力只在统计页，这里只有圆点 + 今天胶囊。
struct CalendarCardView: View {
    let reminders: [Reminder]
    @Binding var displayYear: Int
    @Binding var displayMonth: Int
    var onDateTap: (Date) -> Void = { _ in }

    private let calendar = Calendar.current
    private let weekdayHeader = ["一", "二", "三", "四", "五", "六", "日"]

    @State private var selectedDate: Date?
    @State private var showMonthPicker = false
    @Environment(\.soft) private var soft

    init(reminders: [Reminder],
         displayYear: Binding<Int>,
         displayMonth: Binding<Int>,
         onDateTap: @escaping (Date) -> Void = { _ in }) {
        self.reminders = reminders
        self._displayYear = displayYear
        self._displayMonth = displayMonth
        self.onDateTap = onDateTap
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

    /// 今天的节假日状态后缀，如「· 元旦(休)」「· 调休上班」；无数据显示空
    private var todayHolidaySuffix: String {
        let comps = calendar.dateComponents([.year, .month, .day], from: today)
        guard let y = comps.year, let m = comps.month, let d = comps.day,
              let st = HolidayRemoteService.status(year: y, month: m, day: d) else { return "" }
        return st.isHoliday ? " · \(st.name)休" : " · 调休上班"
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
        SoftShadowCard(kind: .elevated, radius: ThemeTokens.radiusElevated) {
            VStack(spacing: 8) {
                header
                weekdayRow
                dayGrid
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 6)
        }
        .sheet(isPresented: $showMonthPicker) {
            MonthYearPickerSheet(
                year: displayYear,
                month: displayMonth,
                onSelect: { y, m in
                    withAnimation { displayYear = y; displayMonth = m }
                    showMonthPicker = false
                },
                onClose: { showMonthPicker = false }
            )
            .presentationDetents([.height(360)])
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Button { showMonthPicker = true } label: {
                HStack(spacing: 4) {
                    Text(Localized("%d年 %d月", displayYear, displayMonth))
                        .font(SoftType.section)
                        .foregroundStyle(soft.text)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(soft.muted)
                }
            }
            .buttonStyle(.plain)

            if isCurrentMonth {
                Text(Localized("今天 · 农历%@ · %@%@", todayLunarText, todayWeekdayText, todayHolidaySuffix))
                    .font(SoftType.caption)
                    .foregroundStyle(soft.muted)
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { goToToday() }
                } label: {
                    Text("今天".localized)
                        .font(SoftType.caption)
                        .foregroundStyle(ThemeTokens.strong)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    /// 当前是否显示本月
    private var isCurrentMonth: Bool {
        let now = Date()
        return displayYear == calendar.component(.year, from: now)
            && displayMonth == calendar.component(.month, from: now)
    }

    private func goToToday() {
        let now = Date()
        displayYear = calendar.component(.year, from: now)
        displayMonth = calendar.component(.month, from: now)
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
        let firstWeekday = (calendar.component(.weekday, from: firstOfMonth) + 5) % 7 + 1
        let leadingBlanks = firstWeekday - 1
        let cells = paddedCells(leading: leadingBlanks, daysInMonth: daysInMonth)

        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
            spacing: 6
        ) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                dayCell(cell)
                    .id("\(cell.year)-\(cell.month)-\(cell.day)")
            }
        }
        .contentShape(Rectangle())
        .gesture(
            // v1.8.7 UI 优化: 左右滑动快速切月（滴答清单式交互）
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let dx = value.translation.width
                    if abs(dx) > 60 {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            changeMonth(by: dx > 0 ? -1 : 1)
                        }
                    }
                }
        )
        .padding(.horizontal, 6)
    }

    // MARK: - 日期格子

    private struct DayCellData {
        let year: Int
        let month: Int
        let day: Int
        let inMonth: Bool
    }

    private func paddedCells(leading: Int, daysInMonth: Int) -> [DayCellData] {
        var cells: [DayCellData] = []
        var prevY = displayYear
        var prevM = displayMonth - 1
        if prevM < 1 { prevM = 12; prevY -= 1 }
        let prevDays = calendar.range(of: .day, in: .month, for: dateYMD(prevY, prevM, 1) ?? today)?.count ?? 30
        if leading > 0 {
            for d in (prevDays - leading + 1)...prevDays {
                cells.append(DayCellData(year: prevY, month: prevM, day: d, inMonth: false))
            }
        }
        for d in 1...daysInMonth {
            cells.append(DayCellData(year: displayYear, month: displayMonth, day: d, inMonth: true))
        }
        var nextY = displayYear
        var nextM = displayMonth + 1
        if nextM > 12 { nextM = 1; nextY += 1 }
        var n = 1
        while cells.count % 7 != 0 {
            cells.append(DayCellData(year: nextY, month: nextM, day: n, inMonth: false))
            n += 1
        }
        return cells
    }

    private func dateYMD(_ y: Int, _ m: Int, _ d: Int) -> Date? {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d
        return calendar.date(from: c)
    }

    @MainActor private func dayCell(_ cell: DayCellData) -> some View {
        let isToday = cell.year == calendar.component(.year, from: today)
            && cell.month == calendar.component(.month, from: today)
            && cell.day == calendar.component(.day, from: today)
        let key = String(format: "%04d-%02d-%02d", cell.year, cell.month, cell.day)
        let taskCount = cell.inMonth ? (taskDates[key] ?? 0) : 0
        let date = dateYMD(cell.year, cell.month, cell.day) ?? Date()
        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        let holidayStatus = HolidayRemoteService.status(year: cell.year, month: cell.month, day: cell.day)
        let holidayMark = holidayStatus.map { $0.isHoliday ? "休" : "班" }
        let muted = !cell.inMonth

        return VStack(spacing: 2) {
            if isToday {
                VStack(spacing: 0) {
                    Text("🦊")
                        .font(.system(size: 11))
                    Text("\(cell.day)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ThemeTokens.onStrong)
                    Text(holidayMark ?? lunarText(year: cell.year, month: cell.month, day: cell.day))
                        .font(SoftType.calendarLunar)
                        .foregroundStyle(ThemeTokens.onStrong.opacity(0.9))
                }
                .frame(width: 32, height: 48)
                .background(ThemeTokens.strong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                Text("\(cell.day)")
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(muted ? soft.muted.opacity(0.45) : (isSelected ? ThemeTokens.strong : soft.text))
                if let mark = holidayMark {
                    Text(mark)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(holidayStatus?.isHoliday == true ? ThemeTokens.holidayRest : ThemeTokens.holidayWork)
                } else {
                    Text(lunarText(year: cell.year, month: cell.month, day: cell.day))
                        .font(SoftType.calendarLunar)
                        .foregroundStyle(soft.muted.opacity(muted ? 0.45 : 1))
                        .lineLimit(1)
                }
                Circle()
                    .fill(taskCount > 0 ? ThemeTokens.strong : Color.clear)
                    .frame(width: 5, height: 5)
            }
        }
        .frame(height: 56)
        .frame(maxWidth: .infinity)
        .onTapGesture {
            selectedDate = date
            onDateTap(date)
        }
    }

    private func dateFor(_ day: Int) -> Date? {
        dateYMD(displayYear, displayMonth, day)
    }

    // MARK: - 农历

    private func lunarText(year: Int, month: Int, day: Int) -> String {
        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = year
        comps.month = month
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
    CalendarCardView(
        reminders: [],
        displayYear: .constant(2026),
        displayMonth: .constant(9)
    )
    .padding()
}

// MARK: - 月份/年份选择器（v1.8.7 UI 优化）

/// 快速跳转月份：年份滚轮 + 12 个月网格，解决「切换月份很难用」
struct MonthYearPickerSheet: View {
    @State private var year: Int
    @State private var month: Int
    let onSelect: (Int, Int) -> Void
    let onClose: () -> Void

    private let monthNames = ["一月", "二月", "三月", "四月", "五月", "六月",
                              "七月", "八月", "九月", "十月", "十一月", "十二月"]

    init(year: Int, month: Int, onSelect: @escaping (Int, Int) -> Void, onClose: @escaping () -> Void) {
        _year = State(initialValue: year)
        _month = State(initialValue: month)
        self.onSelect = onSelect
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 年份滚轮
                HStack(spacing: 12) {
                    Button {
                        year -= 1
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)

                    Text(Localized("%@ 年", String(year)))
                        .font(.title3.weight(.bold))
                        .frame(minWidth: 90)

                    Button {
                        year += 1
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 14)

                Divider()

                // 月份网格
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(1...12, id: \.self) { m in
                        let isSelected = m == month
                        Button {
                            month = m
                        } label: {
                            Text(monthNames[m - 1])
                                .font(.subheadline.weight(isSelected ? .bold : .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(isSelected ? ThemeTokens.brandPrimary : Color(.secondarySystemGroupedBackground))
                                .foregroundStyle(isSelected ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)

                Spacer()

                // 确定 / 取消
                HStack(spacing: 12) {
                    Button("取消".localized) { onClose() }
                        .buttonStyle(.bordered)
                    Button {
                        onSelect(year, month)
                    } label: {
                        Text(Localized("跳到 %@ 年 %@", String(year), monthNames[month - 1]))
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ThemeTokens.brandPrimary)
                }
                .padding(.bottom, 12)
            }
            .navigationTitle("选择月份".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成".localized) { onSelect(year, month) }
                }
            }
        }
    }
}
