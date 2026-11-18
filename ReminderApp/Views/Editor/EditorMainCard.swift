import SwiftUI
import SwiftData

/// 新建 / 编辑提醒主卡片（单屏仅 1 张大留白主面板，零嵌套碎框）
struct EditorMainCard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.comic) private var comic

    @Binding var title: String
    @Binding var note: String
    @Binding var kind: ReminderKind
    @Binding var cycle: ReminderCycle
    @Binding var customDays: String
    @Binding var showCustomDaysField: Bool
    @Binding var dateType: DateReminderType
    @Binding var targetMonth: Int
    @Binding var targetDay: Int
    @Binding var advanceDays: Double
    @Binding var reminderHour: Int
    @Binding var reminderMinute: Int
    @Binding var selectedHolidayID: String
    @Binding var rulePeriod: RulePeriod
    @Binding var ruleWeek: RuleWeek
    @Binding var ruleWeekday: RuleWeekday
    @Binding var priority: ReminderPriority
    @Binding var holidayAware: Bool
    @Binding var triggerDate: Date
    @Binding var triggerTime: Date
    @Binding var suggestionText: String?

    var body: some View {
        ComicCard(cut: ThemeTokens.cardCut, padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                titleAndNoteBlock
                ComicHairline(outer: false)
                kindSelectorRow
                ComicHairline(outer: false)

                if kind == .cycle {
                    cycleBlock
                } else {
                    EditorRuleAndDateFields(
                        kind: kind,
                        dateType: $dateType,
                        targetMonth: $targetMonth,
                        targetDay: $targetDay,
                        advanceDays: $advanceDays,
                        reminderHour: $reminderHour,
                        reminderMinute: $reminderMinute,
                        selectedHolidayID: $selectedHolidayID,
                        rulePeriod: $rulePeriod,
                        ruleWeek: $ruleWeek,
                        ruleWeekday: $ruleWeekday,
                        triggerTime: triggerTime
                    )
                }

                if kind == .cycle || kind == .rule {
                    ComicHairline(outer: false)
                    firstTriggerBlock
                }

                ComicHairline(outer: false)
                priorityAndHolidayBlock
            }
        }
    }

    private var titleAndNoteBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("提醒标题".localized, text: $title)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(comic.ink)
                .textFieldStyle(.plain)

            TextField("备注（可选）".localized, text: $note)
                .font(.system(size: 14.5, weight: .medium, design: .rounded))
                .foregroundStyle(comic.ink)
                .textFieldStyle(.plain)
        }
    }

    private var kindSelectorRow: some View {
        HStack(spacing: 16) {
            Text("提醒类型".localized)
                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                .foregroundStyle(comic.muted)

            Spacer()

            ForEach(ReminderKind.allCases, id: \.self) { k in
                let selected = kind == k
                Button {
                    withAnimation(.easeOut(duration: 0.14)) { kind = k }
                } label: {
                    VStack(spacing: 3) {
                        Text(k.rawValue.localized)
                            .font(.system(size: 14, weight: selected ? .heavy : .medium, design: .rounded))
                            .foregroundStyle(selected ? comic.ink : comic.muted)
                        Rectangle()
                            .fill(selected ? comic.accent : Color.clear)
                            .frame(width: 18, height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var cycleBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("重复周期".localized)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(comic.muted)
                Spacer()
                Button { suggestFrequency() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 11, weight: .bold))
                        Text("智能建议频率".localized)
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(comic.hero)
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 12) {
                ForEach(ReminderCycle.allCases, id: \.self) { c in
                    let isSelected = cycle == c
                    Button {
                        cycle = c
                        showCustomDaysField = (c == .custom)
                    } label: {
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                if isSelected {
                                    Circle().fill(comic.accent).frame(width: 6, height: 6)
                                }
                                Text(c.rawValue.localized)
                                    .font(.system(size: 14, weight: isSelected ? .heavy : .medium, design: .rounded))
                                    .foregroundStyle(isSelected ? comic.ink : comic.muted)
                                    .lineLimit(1)
                            }
                            Rectangle()
                                .fill(isSelected ? comic.accent : Color.clear)
                                .frame(width: 22, height: 2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(c.rawValue.localized)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }

            if let tip = suggestionText {
                Text(tip)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(comic.muted)
            }

            if showCustomDaysField || cycle == .custom {
                HStack {
                    Text("自定义天数".localized)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(comic.ink)
                    Spacer()
                    TextField("例如 10".localized, text: $customDays)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(comic.ink)
                        .frame(width: 110)
                }
            }
        }
    }

    private var firstTriggerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker("首次日期".localized, selection: $triggerDate, displayedComponents: .date)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(comic.ink)
            DatePicker("触发时间".localized, selection: $triggerTime, displayedComponents: .hourAndMinute)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(comic.ink)
        }
    }

    private var priorityAndHolidayBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("优先级".localized)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(comic.muted)
                Spacer()
                HStack(spacing: 16) {
                    ForEach(ReminderPriority.allCases, id: \.self) { p in
                        let selected = priority == p
                        Button {
                            priority = p
                        } label: {
                            Text(p.rawValue.localized)
                                .font(.system(size: 14, weight: selected ? .heavy : .medium, design: .rounded))
                                .foregroundStyle(selected ? comic.accent : comic.muted)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Toggle(isOn: $holidayAware) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("避开节假日/周末".localized)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(comic.ink)
                    Text("遇周末或法定节假日顺延至下一工作日".localized)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(comic.muted)
                }
            }
            .tint(comic.accent)
        }
    }

    private func suggestFrequency() {
        Task {
            let all = (try? modelContext.fetch(FetchDescriptor<Reminder>())) ?? []
            let map: [UUID: [TimeInterval]] = Dictionary(
                uniqueKeysWithValues: all.map { r in
                    (r.id, r.records.filter { $0.type == ReminderRecordType.confirm.rawValue }.map { $0.performedAt.timeIntervalSince1970 })
                }
            )
            let s = FrequencySuggester.suggest(title: title, reminders: all, confirmTimestampsByReminder: map)
            cycle = s.cycle
            showCustomDaysField = s.cycle == .custom
            customDays = s.cycle == .custom ? String(s.customDays) : ""
            suggestionText = s.reason
        }
    }
}
