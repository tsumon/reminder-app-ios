import Foundation

/// 编辑器规则构造器：抽离复杂规则判定、日期计算与新旧历双生日拆分
enum EditorRuleBuilder {

    static func isComplexSentence(_ text: String) -> Bool {
        text.range(
            of: "每季度|第[一二三四五1-5].*周|每隔|每[0-9]+[天周月]|(?:除了|排除|仅限|工作日|最后)",
            options: .regularExpression
        ) != nil
    }

    static func detectsDualBirthday(_ text: String) -> Bool {
        let solarRe = try? NSRegularExpression(pattern: "\\d{1,2}\\s*月\\s*\\d{1,2}\\s*[号日]")
        let lunarRe = try? NSRegularExpression(pattern: "(?:农历|旧历|阴历)\\s*(?:\\d{1,2}|正|冬|腊|十[一二]|[一二三四五六七八九十])\\s*月\\s*(?:\\d{1,2}|初?[一二三四五六七八九十]|十[一二三四五六七八九]|二[一二三四五六七八九十]?|廿[一二三四五六七八九]?|三十?)")
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return (solarRe?.firstMatch(in: text, range: range) != nil) && (lunarRe?.firstMatch(in: text, range: range) != nil)
    }

    static func computeDateNextTrigger(
        dateType: DateReminderType,
        targetMonth: Int,
        targetDay: Int,
        reminderHour: Int,
        reminderMinute: Int,
        selectedHolidayID: String,
        calendar: Calendar = .current
    ) -> Date {
        let now = Date()
        switch dateType {
        case .solarBirthday:
            var comps = calendar.dateComponents([.year], from: now)
            comps.month = targetMonth; comps.day = targetDay; comps.hour = reminderHour; comps.minute = reminderMinute
            if let d = calendar.date(from: comps), d > now { return d }
            comps.year = (comps.year ?? 2026) + 1
            return calendar.date(from: comps) ?? now
        case .lunarBirthday:
            if let solar = LunarCalendar.nextLunarBirthday(month: targetMonth, day: targetDay, from: now) {
                var comps = calendar.dateComponents([.year, .month, .day], from: solar)
                comps.hour = reminderHour; comps.minute = reminderMinute
                return calendar.date(from: comps) ?? solar
            }
            var fb = calendar.dateComponents([.year], from: now)
            fb.month = targetMonth; fb.day = targetDay; fb.hour = reminderHour; fb.minute = reminderMinute
            if let d = calendar.date(from: fb), d > now { return d }
            fb.year = (fb.year ?? 2026) + 1
            return calendar.date(from: fb) ?? now
        case .holiday:
            if let holiday = HolidayService.find(by: selectedHolidayID),
               let next = HolidayService.nextDate(for: holiday, from: now) {
                var comps = calendar.dateComponents([.year, .month, .day], from: next)
                comps.hour = reminderHour; comps.minute = reminderMinute
                return calendar.date(from: comps) ?? next
            }
            return now.addingTimeInterval(86400)
        }
    }

    static func makeDualBirthdayPair(
        nlText: String,
        base: Reminder,
        advanceDays: Int,
        reminderHour: Int,
        reminderMinute: Int,
        priority: ReminderPriority
    ) -> (solar: Reminder, lunar: Reminder)? {
        guard !nlText.isEmpty else { return nil }
        let cal = Calendar.current
        let now = Date()
        let solarRegex = try? NSRegularExpression(pattern: "(?<![\\d])([0-9]{1,2})\\s*月\\s*([0-9]{1,2})\\s*[号日]")
        let lunarParsed = NaturalDateParser.parse(nlText, now: now)
        let nsRange = NSRange(nlText.startIndex..<nlText.endIndex, in: nlText)
        guard let sm = solarRegex?.firstMatch(in: nlText, range: nsRange),
              let rM = Range(sm.range(at: 1), in: nlText),
              let rD = Range(sm.range(at: 2), in: nlText),
              let sMonth = Int(nlText[rM]), let sDay = Int(nlText[rD]),
              (1...12).contains(sMonth), (1...31).contains(sDay),
              let parsedLunar = lunarParsed,
              let lMonth = parsedLunar.targetMonth, let lDay = parsedLunar.targetDay else { return nil }

        var cleanTitle = base.title
        if cleanTitle.hasSuffix("（公历）") || cleanTitle.hasSuffix("（农历）") {
            cleanTitle = String(cleanTitle.dropLast(4))
        }

        var solarNext = now
        let startYear = cal.component(.year, from: now)
        for y in startYear...(startYear + 8) {
            let comps = DateComponents(year: y, month: sMonth, day: sDay, hour: reminderHour, minute: reminderMinute, second: 0)
            if let d = cal.date(from: comps), cal.component(.month, from: d) == sMonth, cal.component(.day, from: d) == sDay, d > now {
                solarNext = d; break
            }
        }
        let solar = Reminder(
            title: "\(cleanTitle)（公历）", note: base.note, kind: .date, dateType: .solarBirthday,
            targetMonth: sMonth, targetDay: sDay, advanceDays: advanceDays,
            reminderHour: reminderHour, reminderMinute: reminderMinute,
            firstTriggerAt: solarNext, nextTriggerAt: solarNext, priority: priority, holidayAware: false
        )
        let lunarDate = LunarCalendar.nextLunarBirthday(month: lMonth, day: lDay, hour: reminderHour, minute: reminderMinute, from: now) ?? now
        let lunar = Reminder(
            title: "\(cleanTitle)（农历）", note: base.note, kind: .date, dateType: .lunarBirthday,
            targetMonth: lMonth, targetDay: lDay, advanceDays: advanceDays,
            reminderHour: reminderHour, reminderMinute: reminderMinute,
            firstTriggerAt: lunarDate, nextTriggerAt: lunarDate, priority: priority, holidayAware: false
        )
        for item in [solar, lunar] {
            item.recurrenceMode = base.recurrenceMode; item.reminderStyle = base.reminderStyle
            item.retryIntervalsMinutes = base.retryIntervalsMinutes; item.maxReminderAttempts = base.maxReminderAttempts
            item.quietStartMinute = base.quietStartMinute; item.quietEndMinute = base.quietEndMinute
            item.useAlarmKit = base.useAlarmKit; item.policyMigrated = true
        }
        return (solar, lunar)
    }
}
