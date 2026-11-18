import SwiftUI
import SwiftData

/// 无网格线 7 列月历漫风面板（仅选中/今日衬小巧奶油橙切角块）
struct CalendarCardView: View {
    let reminders: [Reminder]
    @Binding var displayYear: Int
    @Binding var displayMonth: Int
    var onDateTap: (Date) -> Void = { _ in }

    private let calendar = Calendar.current
    private let weekdayHeader = ["一", "二", "三", "四", "五", "六", "日"]

    @State private var selectedDate: Date?
    @State private var showMonthPicker = false
    @Environment(\.comic) private var comic

    init(
        reminders: [Reminder],
        displayYear: Binding<Int>,
        displayMonth: Binding<Int>,
        onDateTap: @escaping (Date) -> Void = { _ in }
    ) {
        self.reminders = reminders
        self._displayYear = displayYear
        self._displayMonth = displayMonth
        self.onDateTap = onDateTap
    }

    private var today: Date { Date() }

    private var todayLunarText: String {
        LunarCalendar.solarToLunar(today).description
    }

    private var todayWeekdayText: String {
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return names[calendar.component(.weekday, from: today) - 1]
    }

    private var todayHolidaySuffix: String {
        let comps = calendar.dateComponents([.year, .month, .day], from: today)
        guard let y = comps.year, let m = comps.month, let d = comps.day,
              let st = HolidayRemoteService.status(year: y, month: m, day: d) else { return "" }
        return st.isHoliday ? " · \(st.name)休" : " · 调休上班"
    }

    @MainActor private var taskDates: [String: Int] {
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

    var body: some View {
        ComicCard(cut: ThemeTokens.cardCut, padding: 14) {
            VStack(spacing: 10) {
                header
                weekdayRow
                dayGrid
            }
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
        HStack(alignment: .firstTextBaseline) {
            Button { showMonthPicker = true } label: {
                HStack(spacing: 4) {
                    Text(Localized("%d年 %d月", displayYear, displayMonth))
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(comic.ink)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(comic.muted)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if isCurrentMonth {
                Text(Localized("农历%@ · %@%@", todayLunarText, todayWeekdayText, todayHolidaySuffix))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(comic.muted)
                    .lineLimit(1)
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { goToToday() }
                } label: {
                    Text("回到今天".localized)
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(comic.hero)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }

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
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(comic.muted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @MainActor private var dayGrid: some View {
        let firstOfMonth = firstOfDisplayMonth()
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30
        let firstWeekday = (calendar.component(.weekday, from: firstOfMonth) + 5) % 7 + 1
        let cells = paddedCells(leading: firstWeekday - 1, daysInMonth: daysInMonth)

        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
            spacing: 4
        ) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                dayCell(cell)
                    .id("\(cell.year)-\(cell.month)-\(cell.day)")
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let dx = value.translation.width
                    if abs(dx) > 60 {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            changeMonth(by: dx > 0 ? -1 : 1)
                        }
                    }
                }
        )
    }

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
        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? isToday
        let holidayStatus = HolidayRemoteService.status(year: cell.year, month: cell.month, day: cell.day)
        let holidayMark = holidayStatus.map { $0.isHoliday ? "休" : "班" }
        let outMonth = !cell.inMonth
        let activeHighlight = isSelected || isToday

        return VStack(spacing: 2) {
            Text("\(cell.day)")
                .font(.system(size: 14.5, weight: activeHighlight ? .heavy : .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(
                    isSelected ? comic.onAccent
                    : (outMonth ? comic.muted.opacity(0.4) : (isToday ? comic.hero : comic.ink))
                )

            if let mark = holidayMark {
                Text(mark)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        isSelected ? comic.onAccent
                        : (holidayStatus?.isHoliday == true ? comic.danger : comic.warn)
                    )
            } else {
                Text(lunarText(year: cell.year, month: cell.month, day: cell.day))
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(isSelected ? comic.onAccent.opacity(0.9) : comic.muted.opacity(outMonth ? 0.4 : 1))
                    .lineLimit(1)
            }

            Circle()
                .fill(taskCount > 0 ? (isSelected ? comic.onAccent : comic.accent) : Color.clear)
                .frame(width: 4.5, height: 4.5)
        }
        .frame(height: 52)
        .frame(maxWidth: .infinity)
        .background {
            if isSelected {
                ZStack {
                    ChamferShape(cut: 5).fill(comic.shadow).offset(x: 1.5, y: 1.5)
                    ChamferShape(cut: 5).fill(comic.accent)
                    ChamferShape(cut: 5).stroke(comic.border, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
                }
                .padding(.horizontal, 3)
            } else if isToday {
                ChamferShape(cut: 5)
                    .stroke(comic.accent, style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
                    .padding(.horizontal, 3)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(.isButton)
        .onTapGesture {
            selectedDate = date
            onDateTap(date)
        }
    }

    private func lunarText(year: Int, month: Int, day: Int) -> String {
        var comps = DateComponents(); comps.year = year; comps.month = month; comps.day = day; comps.hour = 12
        guard let date = calendar.date(from: comps) else { return "" }
        let lunar = LunarCalendar.solarToLunar(date)
        let dayNames = [
            "", "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
            "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
            "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
        ]
        guard lunar.day >= 0, lunar.day < dayNames.count else { return "" }
        return dayNames[lunar.day]
    }

    private func firstOfDisplayMonth() -> Date {
        var comps = DateComponents(); comps.year = displayYear; comps.month = displayMonth; comps.day = 1
        return calendar.date(from: comps) ?? today
    }

    private func changeMonth(by delta: Int) {
        var m = displayMonth + delta
        var y = displayYear
        if m < 1 { m = 12; y -= 1 }
        else if m > 12 { m = 1; y += 1 }
        displayMonth = m; displayYear = y
    }
}
