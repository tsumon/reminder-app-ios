import SwiftUI
import SwiftData

/// 新建 / 编辑提醒页（无框顶栏 + 模板条 + 1 张留白主卡 + 折叠高级策略）
struct CreateReminderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.comic) private var comic

    var editing: Reminder? = nil
    var initialDate: Date? = nil
    var initialSentence: String = ""
    var onCreated: ((Reminder) -> Void)? = nil

    @State private var expectedToken = ""
    @State private var initialRuleStart: ReminderEdits.RuleStartInput?
    @State private var saving = false
    @State private var didSave = false

    @State private var recurrenceMode = "fixed"
    @State private var reminderStyle = "persistent"
    @State private var intervalsText = "60,240,720,1440"
    @State private var maxAttempts = 5
    @State private var useAlarmKit = false
    @State private var quietEnabled = false
    @State private var quietStart = 1320
    @State private var quietEnd = 480
    @State private var showAdvancedPolicy = false

    @State private var title = ""
    @State private var note = ""
    @State private var kind: ReminderKind = .cycle
    @State private var cycle: ReminderCycle = .weekly
    @State private var customDays = ""
    @State private var showCustomDaysField = false

    @State private var dateType: DateReminderType = .solarBirthday
    @State private var targetMonth = 1
    @State private var targetDay = 1
    @State private var advanceDays: Double = 3
    @State private var reminderHour = 9
    @State private var reminderMinute = 0
    @State private var selectedHolidayID = "chunjie"

    @State private var rulePeriod: RulePeriod = .quarterly
    @State private var ruleWeek: RuleWeek = .w2
    @State private var ruleWeekday: RuleWeekday = .tue

    @State private var priority: ReminderPriority = .normal
    @State private var holidayAware = false
    @State private var dualBirthdayDetected = false
    @State private var suggestionText: String?

    @State private var triggerDate = Date()
    @State private var triggerTime: Date = {
        let cal = Calendar.current
        let now = Date()
        let cur = cal.date(bySetting: .second, value: 0, of: now) ?? now
        return cal.date(byAdding: .minute, value: 1, to: cur) ?? now
    }()

    @State private var errorMessage: String?
    @State private var nlText = ""
    @State private var nlHint: String?
    @State private var nlError = false
    @State private var needsRuleReview = false
    @State private var reviewedRule = false

    private var saveDisabled: Bool {
        saving || (needsRuleReview && !reviewedRule) || title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            bareHeader
            ComicHairline(outer: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if needsRuleReview { complexRuleCard }
                    naturalLanguageStrip
                    templateStrip

                    EditorMainCard(
                        title: $title, note: $note, kind: $kind, cycle: $cycle,
                        customDays: $customDays, showCustomDaysField: $showCustomDaysField,
                        dateType: $dateType, targetMonth: $targetMonth, targetDay: $targetDay,
                        advanceDays: $advanceDays, reminderHour: $reminderHour, reminderMinute: $reminderMinute,
                        selectedHolidayID: $selectedHolidayID, rulePeriod: $rulePeriod,
                        ruleWeek: $ruleWeek, ruleWeekday: $ruleWeekday, priority: $priority,
                        holidayAware: $holidayAware, triggerDate: $triggerDate, triggerTime: $triggerTime,
                        suggestionText: $suggestionText
                    )

                    ComicCollapsibleLine(
                        title: "高级策略 · 持续重响 · 勿扰时段".localized,
                        trailing: reminderStyle == "gentle" ? "轻柔".localized : (reminderStyle == "important" ? "重要".localized : "持续".localized),
                        isExpanded: showAdvancedPolicy
                    ) {
                        withAnimation(.easeOut(duration: 0.18)) { showAdvancedPolicy.toggle() }
                    }

                    if showAdvancedPolicy {
                        PolicyFields(
                            recurrenceMode: $recurrenceMode, style: $reminderStyle, intervals: $intervalsText,
                            attempts: $maxAttempts, useAlarmKit: $useAlarmKit, quietEnabled: $quietEnabled,
                            quietStart: $quietStart, quietEnd: $quietEnd,
                            repeatingCycle: kind == .cycle && cycle != .once, previewReminder: previewReminder
                        )
                    }
                }
                .padding(.horizontal, ThemeTokens.gutter)
                .padding(.top, 14)
                .padding(.bottom, 32)
            }
        }
        .background(ComicCanvas())
        .onAppear(perform: loadDraft)
        .alert("无法保存".localized, isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好".localized, role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private var bareHeader: some View {
        HStack {
            Button("取消".localized) { dismiss() }
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(comic.muted)
                .buttonStyle(.plain)
            Spacer()
            ComicBrandTitle(text: editing == nil ? "新建提醒".localized : "编辑提醒".localized, size: 18)
            Spacer()
            Button("保存".localized) { saveReminder() }
                .buttonStyle(ComicButtonStyle(variant: .accent, horizontalPadding: 14, verticalPadding: 7))
                .disabled(saveDisabled)
        }
        .padding(.horizontal, ThemeTokens.gutter)
        .padding(.vertical, 10)
    }

    private var complexRuleCard: some View {
        ComicCard(cut: ThemeTokens.cardCut, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("请先选择下方类型、周期和时间，再确认规则。".localized)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(comic.warn)
                Toggle("我已检查并确认下方规则".localized, isOn: $reviewedRule)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(comic.ink)
                    .tint(comic.accent)
                    .accessibilityIdentifier("confirm-complex-rule")
            }
        }
    }

    private var naturalLanguageStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("✦").font(.system(size: 13, weight: .bold)).foregroundStyle(comic.accent)
                TextField("明天下午3点开会 / 每周一9点晨会 / 农历8月15 中秋".localized, text: $nlText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .foregroundStyle(comic.ink)
                Button("智能识别".localized) { applyNaturalLanguage() }
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(comic.hero)
                    .buttonStyle(.plain)
                    .disabled(nlText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ComicHairline(outer: true)
            if let hint = nlHint {
                Text(hint)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(nlError ? comic.danger : comic.muted)
            }
        }
    }

    private var templateStrip: some View {
        HStack(spacing: 12) {
            Text("常用模板".localized)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(comic.muted)
            ForEach(ReminderTemplate.all) { tpl in
                Button { applyTemplate(tpl) } label: {
                    Text("+ \(tpl.title)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(comic.hero)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("reminder-template-\(tpl.id)")
            }
            Spacer(minLength: 0)
        }
    }

    private func applyTemplate(_ tpl: ReminderTemplate) {
        title = tpl.title; note = tpl.note; holidayAware = tpl.holidayAware
        switch tpl.kind {
        case .cycle:
            kind = .cycle; cycle = tpl.cycle == .yearly ? .yearly : .monthly; showCustomDaysField = false
        case .date:
            kind = .date; dateType = tpl.dateType == .lunarBirthday ? .lunarBirthday : .solarBirthday
            advanceDays = Double(tpl.advanceDays)
        }
    }

    private func applyNaturalLanguage() {
        if EditorRuleBuilder.isComplexSentence(nlText) {
            needsRuleReview = true; reviewedRule = false
            nlError = true; nlHint = "复杂规则请在下面完整表单中确认，或返回首页使用 AI。未自动猜测日期。"
            if title.isEmpty { title = nlText }
            return
        }
        guard let p = NaturalDateParser.parse(nlText) else {
            nlError = true; nlHint = "没听懂，换个说法试试～"; return
        }
        nlError = false; needsRuleReview = false; reviewedRule = false
        if title.trimmingCharacters(in: .whitespaces).isEmpty { title = p.title }

        let cal = Calendar.current
        triggerDate = p.nextTriggerAt; triggerTime = p.nextTriggerAt
        reminderHour = cal.component(.hour, from: p.nextTriggerAt)
        reminderMinute = cal.component(.minute, from: p.nextTriggerAt)

        var cycleText = "仅一次"
        switch p.repeatMode {
        case "lunar":
            kind = .date; dateType = .lunarBirthday
            if let m = p.targetMonth { targetMonth = m }
            if let d = p.targetDay { targetDay = d }
            cycleText = "农历每年"
        case "yearly":
            if p.dateType == .solarBirthday {
                kind = .date; dateType = .solarBirthday
                if let m = p.targetMonth { targetMonth = m }
                if let d = p.targetDay { targetDay = d }
            } else { kind = .cycle; cycle = .yearly }
            cycleText = "每年"
        case "daily": kind = .cycle; cycle = .daily; cycleText = "每天"
        case "weekly": kind = .cycle; cycle = .weekly; cycleText = "每周"
        case "monthly": kind = .cycle; cycle = .monthly; cycleText = "每月"
        default: kind = .cycle; cycle = .once; cycleText = "仅一次"
        }
        showCustomDaysField = (cycle == .custom)
        holidayAware = p.holidayAware
        dualBirthdayDetected = EditorRuleBuilder.detectsDualBirthday(nlText)

        var hint = "「\(p.title)」· \(cycleText) · \(p.label)"
        if dualBirthdayDetected { hint += " · 检测到新旧历两个生日，将创建两条" }
        if p.holidayAware { hint += " · 已开启避开节假日/周末" }
        nlHint = hint
    }

    private var previewReminder: Reminder {
        let cal = Calendar.current
        let effHour = kind == .rule ? cal.component(.hour, from: triggerTime) : reminderHour
        let effMinute = kind == .rule ? cal.component(.minute, from: triggerTime) : reminderMinute
        let anchor = ReminderEdits.cycleAnchor(date: triggerDate, time: triggerTime, editing: editing != nil)
        let r = Reminder(title: title, kind: kind, cycle: cycle, customDays: Int(customDays) ?? 1, dateType: dateType,
                         targetMonth: targetMonth, targetDay: targetDay, advanceDays: Int(advanceDays),
                         reminderHour: effHour, reminderMinute: effMinute, holidayID: selectedHolidayID,
                         rulePeriod: rulePeriod, ruleWeek: ruleWeek, ruleWeekday: ruleWeekday,
                         firstTriggerAt: anchor, nextTriggerAt: anchor, holidayAware: holidayAware)
        r.recurrenceMode = recurrenceMode; r.reminderStyle = reminderStyle
        r.retryIntervalsMinutes = PolicyFields.parsed(intervalsText) ?? ReminderPolicy.legacyIntervals
        r.maxReminderAttempts = maxAttempts
        r.quietStartMinute = quietEnabled ? quietStart : nil; r.quietEndMinute = quietEnabled ? quietEnd : nil
        if kind == .rule {
            r.nextTriggerAt = ReminderEdits.ruleFirstTrigger(
                start: .init(date: triggerDate, time: triggerTime, calendar: cal),
                period: rulePeriod, week: ruleWeek, weekday: ruleWeekday, hour: effHour, minute: effMinute, calendar: cal
            )
        } else if kind == .date {
            r.nextTriggerAt = ReminderEngine.shared.calculateNextTrigger(after: Date(), reminder: r)
        }
        return r
    }

    private func loadDraft() {
        guard expectedToken.isEmpty else { return }
        if let r = editing {
            LegacyPolicyStore.migrate(r)
            expectedToken = r.actionToken
            title = r.title; note = r.note; kind = r.kind; cycle = r.cycle
            customDays = r.customDays > 0 ? String(r.customDays) : ""; showCustomDaysField = (r.cycle == .custom)
            dateType = r.dateType ?? .solarBirthday; targetMonth = r.targetMonth; targetDay = r.targetDay
            advanceDays = Double(r.advanceDays); reminderHour = r.reminderHour; reminderMinute = r.reminderMinute
            selectedHolidayID = r.holidayID ?? "chunjie"; rulePeriod = r.rulePeriod; ruleWeek = r.ruleWeek; ruleWeekday = r.ruleWeekday
            priority = r.priority; holidayAware = r.holidayAware
            triggerDate = r.firstTriggerAt; triggerTime = r.firstTriggerAt
            initialRuleStart = ReminderEdits.RuleStartInput(date: triggerDate, time: triggerTime)
            recurrenceMode = r.recurrenceMode; reminderStyle = r.reminderStyle
            intervalsText = r.policy.intervals.map(String.init).joined(separator: ","); maxAttempts = r.policy.attempts
            useAlarmKit = r.useAlarmKit; quietEnabled = r.quietStartMinute != nil
            quietStart = r.quietStartMinute ?? 1320; quietEnd = r.quietEndMinute ?? 480
        } else if !initialSentence.isEmpty {
            expectedToken = "new"; nlText = initialSentence; applyNaturalLanguage()
        } else {
            expectedToken = "new"; if let date = initialDate { triggerDate = date }
        }
    }

    private func saveReminder() {
        guard !saving && !didSave && (!needsRuleReview || reviewedRule) else { return }
        guard let intervals = PolicyFields.parsed(intervalsText) else {
            errorMessage = "请填写有效重试间隔：1–10080 分钟，最多 10 个"; return
        }
        saving = true
        defer { if !didSave { saving = false } }
        let calendar = Calendar.current
        let ruleStart = ReminderEdits.RuleStartInput(date: triggerDate, time: triggerTime, calendar: calendar)
        let cleanTitle = title.trimmingCharacters(in: .whitespaces)
        let cleanNote = note.trimmingCharacters(in: .whitespaces)
        let reminder: Reminder

        switch kind {
        case .cycle:
            let finalTrigger = ReminderEdits.cycleAnchor(date: triggerDate, time: triggerTime, editing: editing != nil)
            if cycle == .custom {
                guard let days = Int(customDays.trimmingCharacters(in: .whitespaces)), days >= 1 else {
                    errorMessage = Localized("自定义周期请输入至少 1 天"); return
                }
                reminder = Reminder(title: cleanTitle, note: cleanNote, kind: .cycle, cycle: cycle, customDays: days,
                                    firstTriggerAt: finalTrigger, nextTriggerAt: finalTrigger, priority: priority, holidayAware: holidayAware)
            } else {
                reminder = Reminder(title: cleanTitle, note: cleanNote, kind: .cycle, cycle: cycle, customDays: 0,
                                    firstTriggerAt: finalTrigger, nextTriggerAt: finalTrigger, priority: priority, holidayAware: holidayAware)
            }
        case .rule:
            let rH = calendar.component(.hour, from: triggerTime)
            let rM = calendar.component(.minute, from: triggerTime)
            let first = ReminderEdits.ruleFirstTrigger(start: ruleStart, period: rulePeriod, week: ruleWeek,
                                                       weekday: ruleWeekday, hour: rH, minute: rM, calendar: calendar)
            reminder = Reminder(title: cleanTitle, note: cleanNote, kind: .rule, reminderHour: rH, reminderMinute: rM,
                                rulePeriod: rulePeriod, ruleWeek: ruleWeek, ruleWeekday: ruleWeekday,
                                firstTriggerAt: first, nextTriggerAt: first, priority: priority, holidayAware: holidayAware)
        case .date:
            let nextDate = EditorRuleBuilder.computeDateNextTrigger(
                dateType: dateType, targetMonth: targetMonth, targetDay: targetDay,
                reminderHour: reminderHour, reminderMinute: reminderMinute, selectedHolidayID: selectedHolidayID, calendar: calendar
            )
            reminder = Reminder(title: cleanTitle, note: cleanNote, kind: .date, dateType: dateType,
                                targetMonth: targetMonth, targetDay: targetDay, advanceDays: Int(advanceDays),
                                reminderHour: reminderHour, reminderMinute: reminderMinute,
                                holidayID: dateType == .holiday ? selectedHolidayID : nil,
                                firstTriggerAt: nextDate, nextTriggerAt: nextDate, priority: priority, holidayAware: holidayAware)
        }

        reminder.recurrenceMode = recurrenceMode; reminder.reminderStyle = reminderStyle
        reminder.retryIntervalsMinutes = intervals; reminder.maxReminderAttempts = maxAttempts
        reminder.quietStartMinute = quietEnabled ? quietStart : nil; reminder.quietEndMinute = quietEnabled ? quietEnd : nil
        reminder.useAlarmKit = useAlarmKit; reminder.policyMigrated = true

        if let editing {
            guard ReminderEdits.apply(reminder, to: editing, expectedToken: expectedToken,
                                      scheduleChanged: ReminderEdits.scheduleChanged(reminder, from: editing, ruleStart: ruleStart, originalRuleStart: initialRuleStart),
                                      context: modelContext, calculate: ReminderEngine.shared.calculateNextTrigger) else {
                errorMessage = "提醒已被其他操作修改，请关闭后重新编辑"; return
            }
            Task {
                if #available(iOS 26.0, *), editing.useAlarmKit { _ = await ImportantAlarmService.shared.requestAuthorization() }
                await ReminderEngine.shared.scheduleAllNotifications(for: editing)
            }
            didSave = true; dismiss(); return
        }

        if reminder.holidayAware {
            reminder.nextTriggerAt = ReminderEngine.shared.calculateNextTrigger(after: reminder.firstTriggerAt.addingTimeInterval(-1), reminder: reminder)
        }
        var createdList: [Reminder] = [reminder]
        if dualBirthdayDetected, let dual = EditorRuleBuilder.makeDualBirthdayPair(
            nlText: nlText, base: reminder, advanceDays: Int(advanceDays),
            reminderHour: reminderHour, reminderMinute: reminderMinute, priority: priority
        ) {
            createdList = [dual.solar, dual.lunar]
        }

        createdList.forEach { modelContext.insert($0) }
        do { try modelContext.save() } catch {
            errorMessage = Localized("保存失败，请重试：%@", error.localizedDescription); return
        }
        didSave = true; SyncStore.touchLocalChange()
        onCreated?(createdList[0])
        Task {
            for item in createdList {
                if #available(iOS 26.0, *), item.useAlarmKit { _ = await ImportantAlarmService.shared.requestAuthorization() }
                await ReminderEngine.shared.scheduleAllNotifications(for: item)
            }
        }
        dismiss()
    }
}
