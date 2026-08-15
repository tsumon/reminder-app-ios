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

    // MARK: - 关键提醒（批次3 功能5）

    @State private var isCritical = false

    // MARK: - 功能8 智能频率建议

    @State private var suggestionText: String? = nil

    // MARK: - 首次触发时间（周期类用）

    @State private var triggerDate = Date()
    // v2.0.22: 默认时间向上取整到下一分钟——原默认值是当前时刻，用户立即保存时
    // firstTrigger 是当前分钟的 xx:xx:00（已过去），首个通知会被系统丢弃或误判为遗漏
    @State private var triggerTime: Date = {
        let calendar = Calendar.current
        let now = Date()
        let currentMinute = calendar.date(bySetting: .second, value: 0, of: now) ?? now
        return calendar.date(byAdding: .minute, value: 1, to: currentMinute) ?? now
    }()

    // v2.0.22: 保存失败/校验失败提示（原来 try? save() 吞错后直接关页面）
    @State private var errorMessage: String?

    // MARK: - 自然语言快速创建

    @State private var nlText = ""
    @State private var nlHint: String?
    @State private var nlError = false

    let months = Array(1...12)
    let days = Array(1...31)
    let hours = Array(0...23)
    let minutes = [0, 15, 30, 45]

    var body: some View {
        NavigationStack {
            Form {
                // MARK: 自然语言快速创建
                naturalLanguageSection

                // MARK: 基本信息
                Section("提醒内容".localized) {
                    TextField("提醒标题".localized, text: $title)
                    TextField("备注（可选）".localized, text: $note)
                }

                // MARK: 提醒类型切换
                Section {
                    Picker("类型".localized, selection: $kind) {
                        ForEach(ReminderKind.allCases, id: \.self) { k in
                            Text(k.rawValue.localized).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("优先级".localized, selection: $priority) {
                        ForEach(ReminderPriority.allCases, id: \.self) { p in
                            Text("\(p.emoji) \(p.rawValue.localized)").tag(p)
                        }
                    }
                    .pickerStyle(.menu)

                    // 批次3 功能5: 关键提醒开关（触发更激进的重复 alert 脉冲）
                    Toggle(isOn: $isCritical) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("关键提醒".localized)
                            Text("重要事项，错过会重复提醒直到确认".localized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
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
                    Section("首次提醒时间".localized) {
                        DatePicker("日期".localized, selection: $triggerDate, displayedComponents: .date)
                        DatePicker("时间".localized, selection: $triggerTime, displayedComponents: .hourAndMinute)
                    }
                }
            }
            .navigationTitle("新建提醒".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消".localized) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存".localized) { saveReminder() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("无法保存".localized, isPresented: errorAlertBinding) {
                Button("好".localized, role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - 自然语言 Section

    private var naturalLanguageSection: some View {
        Section {
            TextField("明天下午3点开会 / 每周一9点晨会 / 农历8月15 中秋".localized, text: $nlText, axis: .vertical)
                .lineLimit(1...2)

            Button {
                applyNaturalLanguage()
            } label: {
                Label("智能识别".localized, systemImage: "sparkles")
            }
            .disabled(nlText.trimmingCharacters(in: .whitespaces).isEmpty)

            if let hint = nlHint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(nlError ? Color.red : Color.secondary)
            }
        } header: {
            Text("✨ 一句话创建".localized)
        } footer: {
            Text("识别后会自动填好下面的表单，可再手动微调".localized)
        }
    }

    private func applyNaturalLanguage() {
        guard let p = NaturalDateParser.parse(nlText) else {
            nlError = true
            nlHint = "没听懂，换个说法试试～"
            return
        }
        nlError = false

        // 标题
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            title = p.title
        }

        let cal = Calendar.current
        triggerDate = p.nextTriggerAt
        triggerTime = p.nextTriggerAt
        reminderHour = cal.component(.hour, from: p.nextTriggerAt)
        reminderMinute = cal.component(.minute, from: p.nextTriggerAt)

        var cycleText = "仅一次"
        switch p.repeatMode {
        case "lunar":
            kind = .date
            dateType = .lunarBirthday
            if let m = p.targetMonth { targetMonth = m }
            if let d = p.targetDay { targetDay = d }
            cycleText = "农历每年"
        case "yearly":
            if p.dateType == .solarBirthday {
                kind = .date
                dateType = .solarBirthday
                if let m = p.targetMonth { targetMonth = m }
                if let d = p.targetDay { targetDay = d }
            } else {
                kind = .cycle
                cycle = .yearly
            }
            cycleText = "每年"
        case "daily":
            kind = .cycle; cycle = .daily; cycleText = "每天"
        case "weekly":
            kind = .cycle; cycle = .weekly; cycleText = "每周"
        case "monthly":
            kind = .cycle; cycle = .monthly; cycleText = "每月"
        default:
            kind = .cycle; cycle = .once; cycleText = "仅一次"
        }
        showCustomDaysField = (cycle == .custom)

        nlHint = "「\(p.title)」· \(cycleText) · \(p.label)"
    }

    // MARK: - 周期 Section

    private var cycleSection: some View {
        Section("提醒周期".localized) {
            Picker("周期".localized, selection: $cycle) {
                ForEach(ReminderCycle.allCases, id: \.self) { c in
                    Text(c.rawValue.localized).tag(c)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: cycle) { _, newValue in
                showCustomDaysField = newValue == .custom
            }

            // 功能8 智能频率建议入口
            Button {
                Task {
                    let all = (try? modelContext.fetch(FetchDescriptor<Reminder>())) ?? []
                    // I18: 显式预取 confirm 记录（强制 SwiftData 惰性关系在当前 context 解析），
                    //     对齐 Android 显式传入 confirmMillisByReminder，避免 iOS 静默看到 0 条间隔
                    let confirmTimestampsByReminder: [UUID: [TimeInterval]] = Dictionary(
                        uniqueKeysWithValues: all.map { r in
                            (r.id, r.records
                                .filter { $0.type == ReminderRecordType.confirm.rawValue }
                                .map { $0.performedAt.timeIntervalSince1970 })
                        }
                    )
                    let s = FrequencySuggester.suggest(title: title, reminders: all,
                                                       confirmTimestampsByReminder: confirmTimestampsByReminder)
                    cycle = s.cycle
                    customDays = s.cycle == .custom ? String(s.customDays) : ""
                    suggestionText = s.reason
                }
            } label: {
                Label("智能建议频率", systemImage: "wand.and.stars")
            }

            if let tip = suggestionText {
                Text(tip)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if showCustomDaysField {
                HStack {
                    Text("自定义天数".localized)
                    TextField("例如 10".localized, text: $customDays)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    // MARK: - 规则 Section

    private var ruleSection: some View {
        Section {
            Picker("频率".localized, selection: $rulePeriod) {
                ForEach(RulePeriod.allCases, id: \.self) { p in
                    Text(p.rawValue.localized).tag(p)
                }
            }
            .pickerStyle(.menu)

            Picker("第几周".localized, selection: $ruleWeek) {
                ForEach(RuleWeek.allCases, id: \.self) { w in
                    Text(w.label.localized).tag(w)
                }
            }
            .pickerStyle(.menu)

            Picker("星期几".localized, selection: $ruleWeekday) {
                ForEach(RuleWeekday.allCases, id: \.self) { w in
                    Text(w.label.localized).tag(w)
                }
            }
            .pickerStyle(.menu)

            // 示例预览
            HStack {
                Text("下次触发".localized)
                Spacer()
                Text(rulePreview)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("规则设置（例如：每季度第2周周二）".localized)
        } footer: {
            Text("按所选频率的第 N 周星期 X 触发提醒".localized)
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
            Section("日期类型".localized) {
                Picker("类型".localized, selection: $dateType) {
                    ForEach(DateReminderType.allCases, id: \.self) { t in
                        Text(t.rawValue.localized).tag(t)
                    }
                }
                .pickerStyle(.menu)
            }

            // 日期选择（新历生日 / 农历生日）
            if dateType != .holiday {
                Section("日期".localized) {
                    HStack {
                        Text("月份".localized)
                        Spacer()
                        Picker("", selection: $targetMonth) {
                            ForEach(months, id: \.self) { m in
                                Text(Localized("%d月", m)).tag(m)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    HStack {
                        Text("日期".localized)
                        Spacer()
                        Picker("", selection: $targetDay) {
                            ForEach(days, id: \.self) { d in
                                Text(Localized("%d日", d)).tag(d)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    // 农历日期预览
                    if dateType == .lunarBirthday {
                        HStack {
                            Text("农历".localized)
                            Spacer()
                            Text(lunarPreview)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // 节假日选择
            if dateType == .holiday {
                Section("选择节日".localized) {
                    Picker("节日".localized, selection: $selectedHolidayID) {
                        ForEach(HolidayService.allHolidays) { holiday in
                            Text("\(holiday.emoji) \(holiday.name)").tag(holiday.id)
                        }
                    }
                    .pickerStyle(.menu)

                    if let holiday = HolidayService.find(by: selectedHolidayID) {
                        HStack {
                            Text("日期类型".localized)
                            Spacer()
                            Text(holiday.isLunar ? "农历".localized : "公历".localized)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // 提前提醒天数
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Localized("提前 %d 天开始提醒", Int(advanceDays)))
                        .font(.subheadline)
                    Slider(value: $advanceDays, in: 0...14, step: 1)
                    Text("到期前每天上午发送预告通知，到期当天转为正式提醒".localized)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // 提醒时间
            Section("提醒时间".localized) {
                HStack {
                    Text("小时".localized)
                    Spacer()
                    Picker("", selection: $reminderHour) {
                        ForEach(hours, id: \.self) { h in
                            Text(String(format: "%02d:00", h)).tag(h)
                        }
                    }
                    .pickerStyle(.menu)
                }
                HStack {
                    Text("分钟".localized)
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
            // v2.0.22: 保存前兜底——合并时间可能仍是过去（跨午夜/秒差），
            // 统一顺延到下一分钟，避免「立即创建立即过期」的首个通知丢失
            let finalTrigger = firstTrigger > Date()
                ? firstTrigger
                : (calendar.date(byAdding: .minute, value: 1, to: firstTrigger) ?? firstTrigger)
            // v2.0.22: 自定义周期留空/非法时禁止保存（原实现静默兜底成每天一次，
            // 用户没输入也会被高频打扰）；改成保存按钮直接拦截
            if cycle == .custom {
                guard let days = Int(customDays.trimmingCharacters(in: .whitespaces)), days >= 1 else {
                    errorMessage = Localized("自定义周期请输入至少 1 天")
                    return
                }
                reminder = Reminder(
                    title: title.trimmingCharacters(in: .whitespaces),
                    note: note.trimmingCharacters(in: .whitespaces),
                    kind: .cycle,
                    cycle: cycle,
                    customDays: days,
                    firstTriggerAt: finalTrigger,
                    nextTriggerAt: finalTrigger,
                    priority: priority
                )
            } else {
                reminder = Reminder(
                    title: title.trimmingCharacters(in: .whitespaces),
                    note: note.trimmingCharacters(in: .whitespaces),
                    kind: .cycle,
                    cycle: cycle,
                    customDays: 0,
                    firstTriggerAt: finalTrigger,
                    nextTriggerAt: finalTrigger,
                    priority: priority
                )
            }

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
        // v2.0.22: 保存失败不再吞掉——保存成功后才推进同步版本、排通知、关页面；
        // 否则 UI 显示已创建但数据没落盘，同步还会上传不完整数据
        do {
            try modelContext.save()
        } catch {
            errorMessage = Localized("保存失败，请重试：%@", error.localizedDescription)
            return
        }
        SyncStore.touchLocalChange()

        // 批次3 功能5: 关键提醒标记落 UserDefaults 侧存（避免改 SwiftData schema）
        ReminderEngine.CriticalStore.setCritical(isCritical, for: reminder.id)

        Task {
            await ReminderEngine.shared.scheduleAllNotifications(for: reminder)
        }

        dismiss()
    }

    /// v2.0.22: 保存校验/失败提示（自定义周期、保存错误等）
    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

#Preview {
    CreateReminderView()
        .modelContainer(for: [Reminder.self, ReminderRecord.self])
}
