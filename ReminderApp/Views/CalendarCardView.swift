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
    // v1.8.7 UI 优化: 月份选择器 / 是否显示「回到今天」
    @State private var showMonthPicker = false

    init(reminders: [Reminder], onDateTap: @escaping (Date) -> Void = { _ in }) {
        self.reminders = reminders
        self.onDateTap = onDateTap
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
        VStack(spacing: 8) {
            header
            weekdayRow
            dayGrid
        }
        .padding(.vertical, 12)
        // 液态玻璃：材质 + 高光描边 + 大圆角柔和阴影
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.55), .white.opacity(0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: ThemeTokens.brandPrimary.opacity(0.10), radius: 14, y: 6)
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
        HStack(spacing: 4) {
            // 上一月（加大热区）
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { changeMonth(by: -1) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            // 月份标题：点击弹出月份选择器（v1.8.7 UI 优化）
            Button {
                showMonthPicker = true
            } label: {
                VStack(spacing: 3) {
                    HStack(spacing: 4) {
                        Text(Localized("%d年%d月", displayYear, displayMonth))
                            .font(.headline)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(Localized("农历%@ · %@%@", todayLunarText, todayWeekdayText, todayHolidaySuffix))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // 回到今天（非当月时显示）
            if !isCurrentMonth {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        goToToday()
                    }
                } label: {
                    Text("今天".localized)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(ThemeTokens.brandPrimary.opacity(0.12))
                        .foregroundStyle(ThemeTokens.brandPrimary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            // 下一月（加大热区）
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { changeMonth(by: 1) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
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
        // Calendar.weekday: 1=周日...7=周六 → 周一=1...周日=7
        let firstWeekday = (calendar.component(.weekday, from: firstOfMonth) + 5) % 7 + 1
        let leadingBlanks = firstWeekday - 1

        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
            spacing: 4
        ) {
            // ⚠️ 两个 ForEach 的 id 必须加前缀区分：空格 id 0..<N 与日期 id 1..N 重叠时
            // SwiftUI 会丢弃重复元素 → 8 月(leadingBlanks=5)的 1-4 日不显示
            ForEach(0..<leadingBlanks, id: \.self) { i in
                Color.clear
                    .frame(height: 50)
                    .id("blank-\(i)")
            }
            ForEach(1...daysInMonth, id: \.self) { day in
                dayCell(day)
                    .id("day-\(day)")
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

    @MainActor private func dayCell(_ day: Int) -> some View {
        let isToday = displayYear == calendar.component(.year, from: today)
            && displayMonth == calendar.component(.month, from: today)
            && day == calendar.component(.day, from: today)

        let key = String(format: "%04d-%02d-%02d", displayYear, displayMonth, day)
        let taskCount = taskDates[key] ?? 0
        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: dateFor(day) ?? Date()) } ?? false
        // v1.8.7 任务②：联网节假日的「休/班」状态（无数据返回 nil）
        let holidayStatus = HolidayRemoteService.status(year: displayYear, month: displayMonth, day: day)

        return VStack(spacing: 1) {
            Text("\(day)")
                .font(.subheadline)
                .fontWeight(isToday || isSelected ? .bold : .regular)
                .foregroundStyle(
                    isSelected
                        ? AnyShapeStyle(.tint)
                        : (isToday ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                )
                .frame(width: 26, height: 26)
                .background(
                    isToday
                        ? AnyShapeStyle(.tint)
                        : (isSelected ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(Color.clear))
                )
                .clipShape(Circle())
                .overlay(alignment: .topTrailing) {
                    // 任务角标：右上小圆点
                    Circle()
                        .fill(taskCount > 0 ? Color.accentColor : Color.clear)
                        .frame(width: 5, height: 5)
                        .padding(2)
                }
                .overlay(
                    isSelected && !isToday
                        ? Circle().stroke(.tint, lineWidth: 1.5)
                        : nil
                )

            Text(lunarText(day))
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // 休/班角标：放假红「休」、调休上班橙「班」；普通日占位保持对齐
            Text(holidayStatus.map { $0.isHoliday ? "休" : "班" } ?? "")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(holidayStatus?.isHoliday == true ? ThemeTokens.holidayRest : ThemeTokens.holidayWork)
                .lineLimit(1)
        }
        .frame(height: 50)
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
