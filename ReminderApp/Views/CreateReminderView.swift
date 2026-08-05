import SwiftUI
import SwiftData

/// 创建新提醒
struct CreateReminderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // MARK: - 基本输入

    @State private var title = ""
    @State private var note = ""

    // MARK: - 提醒大类

    @State private var kind: ReminderKind = .cycle

    // MARK: - 周期提醒

    @State private var cycle: ReminderCycle = .weekly
    @State private var customDays = ""
    @State private var showCustomDaysField = false

    // MARK: - 日期提醒

    @State private var dateType: DateReminderType = .solarBirthday
    @State private var targetMonth = 1
    @State private var targetDay = 1
    @State private var advanceDays: Double = 3
    @State private var reminderHour = 9
    @State private var reminderMinute = 0
    @State private var selectedHolidayID = "chunjie"

    // MARK: - 规则提醒（每月/每季度/每年 第N周周X）

    @State private var rulePeriod: RulePeriod = .quarterly
    @State private var ruleWeek: RuleWeek = .w2
    @State private var ruleWeekday: RuleWeekday = .tue

    // MARK: - 优先级

    @State private var priority: ReminderPriority = .normal

    // MARK: - 首次触发时间（周期类用）

    @State private var triggerDate = Date()
    @State private var triggerTime = Date()

    let months = Array(1...12)
    let days = Array(1...31)
    let hours = Array(0...23)
    let minutes = [0, 15, 30, 45]

    var body: some View {
        NavigationStack {
            Form {
                // MARK: 基本信息
                Section("提醒内容") {
                    TextField("提醒标题", text: $title)
                    TextField("备注（可选）", text: $note)
                }

                // MARK: 提醒类型切换
                Section {
                    Picker("类型", selection: $kind) {
                        ForEach(ReminderKind.allCases, id: \.self) { k in
                            Text(k.rawValue).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("优先级", selection: $priority) {
                        ForEach(ReminderPriority.allCases, id: \.self) { p in
                            Text("\(p.emoji) \(p.rawValue)").tag(p)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // MARK: 周期提醒设置
                if kind == .cycle {
                    cycleSection
                }

                // MARK: 规则提醒设置
                if kind == .rule {
                    ruleSection
                }

                // MARK: 日期提醒设置
                if kind == .date {
                    dateSection
                }

                // MARK: 首次触发时间（周期类 + 规则类）
                if kind == .cycle || kind == .rule {
                    Section("首次提醒时间") {
                        DatePicker("日期", selection: $triggerDate, displayedComponents: .date)
                        DatePicker("时间", selection: $triggerTime, displayedComponents: .hourAndMinute)
                    }
                }
            }
            .navigationTitle("新建提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveReminder() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - 周期 Section

    private var cycleSection: some View {
        Section("提醒周期") {
            Picker("周期", selection: $cycle) {
                ForEach(ReminderCycle.allCases, id: \.self) { c in
                    Text(c.rawValue).tag(c)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: cycle) { _, newValue in
                showCustomDaysField = newValue == .custom
            }

            if showCustomDaysField {
                HStack {
                    Text("自定义天数")
                    TextField("例如 10", text: $customDays)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    // MARK: - 规则 Section

    private var ruleSection: some View {
        Section {
            Picker("频率", selection: $rulePeriod) {
                ForEach(RulePeriod.allCases, id: \.self) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.menu)

            Picker("第几周", selection: $ruleWeek) {
                ForEach(RuleWeek.allCases, id: \.self) { w in
                    Text(w.label).tag(w)
                }
            }
            .pickerStyle(.menu)

            Picker("星期几", selection: $ruleWeekday) {
                ForEach(RuleWeekday.allCases, id: \.self) { w in
                    Text(w.label).tag(w)
                }
            }
            .pickerStyle(.menu)

            // 示例预览
            HStack {
                Text("下次触发")
                Spacer()
                Text(rulePreview)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("规则设置（例如：每季度第2周周二）")
        } footer: {
            Text("按所选频率的第 N 周星期 X 触发提醒")
        }
    }

    /// 规则提醒预览文本
    private var rulePreview: String {
        let engine = ReminderEngine.shared
        let date = engine.nextRuleDate(
            period: rulePeriod,
            week: ruleWeek.rawValue,
            weekday: ruleWeekday.rawValue,
            hour: reminderHour,
            minute: reminderMinute
        )
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "yyyy年M月d日 E HH:mm"
        return df.string(from: date)
    }

    // MARK: - 日期 Section

    private var dateSection: some View {
        Group {
            // 日期子类型
            Section("日期类型") {
                Picker("类型", selection: $dateType) {
                    ForEach(DateReminderType.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.menu)
            }

            // 日期选择（新历生日 / 农历生日）
            if dateType != .holiday {
                Section("日期") {
                    HStack {
                        Text("月份")
                        Spacer()
                        Picker("", selection: $targetMonth) {
                            ForEach(months, id: \.self) { m in
                                Text("\(m)月").tag(m)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    HStack {
                        Text("日期")
                        Spacer()
                        Picker("", selection: $targetDay) {
                            ForEach(days, id: \.self) { d in
                                Text("\(d)日").tag(d)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    // 农历日期预览
                    if dateType == .lunarBirthday {
                        HStack {
                            Text("农历")
                            Spacer()
                            Text(lunarPreview)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // 节假日选择
            if dateType == .holiday {
                Section("选择节日") {
                    Picker("节日", selection: $selectedHolidayID) {
                        ForEach(HolidayService.allHolidays) { holiday in
                            Text("\(holiday.emoji) \(holiday.name)").tag(holiday.id)
                        }
                    }
                    .pickerStyle(.menu)

                    if let holiday = HolidayService.find(by: selectedHolidayID) {
                        HStack {
                            Text("日期类型")
                            Spacer()
                            Text(holiday.isLunar ? "农历" : "公历")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // 提前提醒天数
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("提前 \(Int(advanceDays)) 天开始提醒")
                        .font(.subheadline)
                    Slider(value: $advanceDays, in: 0...14, step: 1)
                    Text("到期前每天上午发送预告通知，到期当天转为正式提醒")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // 提醒时间
            Section("提醒时间") {
                HStack {
                    Text("小时")
                    Spacer()
                    Picker("", selection: $reminderHour) {
                        ForEach(hours, id: \.self) { h in
                            Text(String(format: "%02d:00", h)).tag(h)
                        }
                    }
                    .pickerStyle(.menu)
                }
                HStack {
                    Text("分钟")
                    Spacer()
                    Picker("", selection: $reminderMinute) {
                        ForEach(minutes, id: \.self) { m in
                            Text(String(format: "%02d分", m)).tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    // MARK: - 农历预览

    private var lunarPreview: String {
        let monthNames = ["", "正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]
        let dayNames = ["", "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
                        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
                        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"]
        let m = min(max(targetMonth, 1), 12)
        let d = min(max(targetDay, 1), 30)
        return monthNames[m] + dayNames[d]
    }

    // MARK: - 保存

    private func saveReminder() {
        let calendar = Calendar.current

        let reminder: Reminder

        switch kind {
        case .cycle:
            let dateComponents = calendar.dateComponents([.year, .month, .day], from: triggerDate)
            let timeComponents = calendar.dateComponents([.hour, .minute], from: triggerTime)

            var merged = DateComponents()
            merged.year = dateComponents.year
            merged.month = dateComponents.month
            merged.day = dateComponents.day
            merged.hour = timeComponents.hour
            merged.minute = timeComponents.minute

            let firstTrigger = calendar.date(from: merged) ?? triggerDate
            let days = cycle == .custom ? (Int(customDays) ?? 0) : 0

            reminder = Reminder(
                title: title.trimmingCharacters(in: .whitespaces),
                note: note.trimmingCharacters(in: .whitespaces),
                kind: .cycle,
                cycle: cycle,
                customDays: days,
                firstTriggerAt: firstTrigger,
                nextTriggerAt: firstTrigger,
                priority: priority
            )

        case .rule:
            // 用户选择的首次时间作为锚点，取锚点之后的下一个规则日
            let dateComponents = calendar.dateComponents([.year, .month, .day], from: triggerDate)
            let timeComponents = calendar.dateComponents([.hour, .minute], from: triggerTime)
            var merged = DateComponents()
            merged.year = dateComponents.year
            merged.month = dateComponents.month
            merged.day = dateComponents.day
            merged.hour = timeComponents.hour
            merged.minute = timeComponents.minute
            let anchor = calendar.date(from: merged) ?? triggerDate

            let engine = ReminderEngine.shared
            let firstTrigger = engine.nextRuleDate(
                period: rulePeriod,
                week: ruleWeek.rawValue,
                weekday: ruleWeekday.rawValue,
                hour: reminderHour,
                minute: reminderMinute,
                from: anchor
            )
            reminder = Reminder(
                title: title.trimmingCharacters(in: .whitespaces),
                note: note.trimmingCharacters(in: .whitespaces),
                kind: .rule,
                reminderHour: reminderHour,
                reminderMinute: reminderMinute,
                rulePeriod: rulePeriod,
                ruleWeek: ruleWeek,
                ruleWeekday: ruleWeekday,
                firstTriggerAt: firstTrigger,
                nextTriggerAt: firstTrigger,
                priority: priority
            )

        case .date:
            // 计算下一次触发日期
            let now = Date()
            let nextDate: Date = {
                switch dateType {
                case .solarBirthday:
                    var comps = calendar.dateComponents([.year], from: now)
                    comps.month = targetMonth
                    comps.day = targetDay
                    comps.hour = reminderHour
                    comps.minute = reminderMinute
                    if let d = calendar.date(from: comps), d > now { return d }
                    comps.year = (comps.year ?? 2026) + 1
                    return calendar.date(from: comps) ?? now

                case .lunarBirthday:
                    if let solar = LunarCalendar.nextLunarBirthday(month: targetMonth, day: targetDay, from: now) {
                        var comps = calendar.dateComponents([.year, .month, .day], from: solar)
                        comps.hour = reminderHour
                        comps.minute = reminderMinute
                        return calendar.date(from: comps) ?? solar
                    }
                    // fallback
                    var fb = calendar.dateComponents([.year], from: now)
                    fb.month = targetMonth; fb.day = targetDay
                    fb.hour = reminderHour; fb.minute = reminderMinute
                    if let d = calendar.date(from: fb), d > now { return d }
                    fb.year = (fb.year ?? 2026) + 1
                    return calendar.date(from: fb) ?? now

                case .holiday:
                    let hid = selectedHolidayID
                    if let holiday = HolidayService.find(by: hid),
                       let next = HolidayService.nextDate(for: holiday, from: now) {
                        var comps = calendar.dateComponents([.year, .month, .day], from: next)
                        comps.hour = reminderHour; comps.minute = reminderMinute
                        return calendar.date(from: comps) ?? next
                    }
                    // fallback: 用 holiday 内置数据
                    if let holiday = HolidayService.find(by: hid) {
                        if holiday.isLunar,
                           let solar = LunarCalendar.nextLunarBirthday(month: holiday.month, day: holiday.day, from: now) {
                            var comps = calendar.dateComponents([.year, .month, .day], from: solar)
                            comps.hour = reminderHour; comps.minute = reminderMinute
                            return calendar.date(from: comps) ?? solar
                        } else {
                            var comps = calendar.dateComponents([.year], from: now)
                            comps.month = holiday.month; comps.day = holiday.day
                            comps.hour = reminderHour; comps.minute = reminderMinute
                            if let d = calendar.date(from: comps), d > now { return d }
                            comps.year = (comps.year ?? 2026) + 1
                            return calendar.date(from: comps) ?? now
                        }
                    }
                    return now
                }
            }()

            reminder = Reminder(
                title: title.trimmingCharacters(in: .whitespaces),
                note: note.trimmingCharacters(in: .whitespaces),
                kind: .date,
                dateType: dateType,
                targetMonth: targetMonth,
                targetDay: targetDay,
                advanceDays: Int(advanceDays),
                reminderHour: reminderHour,
                reminderMinute: reminderMinute,
                holidayID: dateType == .holiday ? selectedHolidayID : nil,
                firstTriggerAt: nextDate,
                nextTriggerAt: nextDate,
                priority: priority
            )
        }

        modelContext.insert(reminder)
        try? modelContext.save()
        SyncStore.touchLocalChange()

        Task {
            await ReminderEngine.shared.scheduleAllNotifications(for: reminder)
        }

        dismiss()
    }
}

#Preview {
    CreateReminderView()
        .modelContainer(for: [Reminder.self, ReminderRecord.self])
}
