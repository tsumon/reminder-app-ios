import SwiftUI

/// 规则周期与纪念日/节假日纯文字键值输入子视图（供 EditorMainCard 组合复用）
struct EditorRuleAndDateFields: View {
    let kind: ReminderKind
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
    let triggerTime: Date

    @Environment(\.comic) private var comic
    private let months = Array(1...12)
    private let days = Array(1...31)
    private let hours = Array(0...23)
    private let minutes = Array(0..<60)

    var body: some View {
        if kind == .rule {
            ruleBlock
        } else if kind == .date {
            dateBlock
        }
    }

    private var ruleBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("频率".localized)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(comic.muted)
                Spacer()
                Picker("频率".localized, selection: $rulePeriod) {
                    ForEach(RulePeriod.allCases, id: \.self) { p in
                        Text(p.rawValue.localized).tag(p)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack {
                Text("第几周".localized)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(comic.muted)
                Spacer()
                Picker("第几周".localized, selection: $ruleWeek) {
                    ForEach(RuleWeek.allCases, id: \.self) { w in
                        Text(w.label.localized).tag(w)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 4) {
                ForEach(RuleWeekday.allCases, id: \.self) { w in
                    let on = ruleWeekday == w
                    Button { ruleWeekday = w } label: {
                        VStack(spacing: 3) {
                            Text(w.label.localized)
                                .font(.system(size: 13, weight: on ? .heavy : .medium, design: .rounded))
                                .foregroundStyle(on ? comic.ink : comic.muted)
                            Rectangle()
                                .fill(on ? comic.accent : Color.clear)
                                .frame(width: 14, height: 2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }

            HStack {
                Text("下次触发".localized)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(comic.muted)
                Spacer()
                Text(rulePreview)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(comic.ink)
            }
        }
    }

    private var dateBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("日期类型".localized)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(comic.muted)
                Spacer()
                Picker("类型".localized, selection: $dateType) {
                    ForEach(DateReminderType.allCases, id: \.self) { t in
                        Text(t.rawValue.localized).tag(t)
                    }
                }
                .pickerStyle(.menu)
            }

            if dateType != .holiday {
                HStack {
                    Text("月份 / 日期".localized)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(comic.muted)
                    Spacer()
                    Picker("", selection: $targetMonth) {
                        ForEach(months, id: \.self) { m in Text(Localized("%d月", m)).tag(m) }
                    }
                    .pickerStyle(.menu)
                    Picker("", selection: $targetDay) {
                        ForEach(days, id: \.self) { d in Text(Localized("%d日", d)).tag(d) }
                    }
                    .pickerStyle(.menu)
                }

                if dateType == .lunarBirthday {
                    HStack {
                        Text("农历".localized)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(comic.muted)
                        Spacer()
                        Text(lunarPreview)
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundStyle(comic.ink)
                    }
                }
            } else {
                HStack {
                    Text("节日".localized)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(comic.muted)
                    Spacer()
                    Picker("节日".localized, selection: $selectedHolidayID) {
                        ForEach(HolidayService.allHolidays) { h in
                            Text("\(h.emoji) \(h.name)").tag(h.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(Localized("提前 %d 天开始提醒", Int(advanceDays)))
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(comic.ink)
                Slider(value: $advanceDays, in: 0...90, step: 1)
                    .tint(comic.accent)
            }

            HStack {
                Text("提醒时间".localized)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(comic.muted)
                Spacer()
                Picker("", selection: $reminderHour) {
                    ForEach(hours, id: \.self) { h in Text(String(format: "%02d时", h)).tag(h) }
                }
                .pickerStyle(.menu)
                Picker("", selection: $reminderMinute) {
                    ForEach(minutes, id: \.self) { m in Text(String(format: "%02d分", m)).tag(m) }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var rulePreview: String {
        let cal = Calendar.current
        let d = ReminderEngine.shared.nextRuleDate(
            period: rulePeriod, week: ruleWeek.rawValue, weekday: ruleWeekday.rawValue,
            hour: cal.component(.hour, from: triggerTime), minute: cal.component(.minute, from: triggerTime)
        )
        let df = DateFormatter()
        df.locale = AppLanguageManager.currentLocale
        df.dateFormat = "yyyy/M/d HH:mm"
        return df.string(from: d)
    }

    private var lunarPreview: String {
        let monthNames = ["", "正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]
        let dayNames = ["", "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
                        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
                        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"]
        return monthNames[min(max(targetMonth, 1), 12)] + dayNames[min(max(targetDay, 1), 30)]
    }
}
