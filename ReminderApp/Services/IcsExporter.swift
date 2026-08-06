import Foundation

/// .ics 日历导出（v1.8.7 任务④）
///
/// 把提醒导出为 iCalendar（RFC 5545）VEVENT，供系统日历/Outlook/Google 日历订阅。
/// RRULE 映射（双端一致）：
///   once → 无 RRULE；daily → FREQ=DAILY；weekly → FREQ=WEEKLY；
///   biweekly → FREQ=WEEKLY;INTERVAL=2；monthly → FREQ=MONTHLY；
///   quarterly → FREQ=MONTHLY;INTERVAL=3；yearly → FREQ=YEARLY；
///   custom → FREQ=DAILY;INTERVAL=N
///   rule 类(第N周周X) → FREQ=对应周期;BYDAY=周几;BYSETPOS=N
enum IcsExporter {

    static func generateICS(reminders: [Reminder]) -> String {
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//ReminderApp//循环提醒//CN",
            "CALSCALE:GREGORIAN"
        ]

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyyMMdd'T'HHmmss"
        df.timeZone = .current

        for r in reminders where r.isEnabled {
            lines.append("BEGIN:VEVENT")
            lines.append("UID:reminder-\(r.id.uuidString)@reminder.app")
            lines.append("DTSTAMP:\(df.string(from: Date()))")
            lines.append("DTSTART:\(df.string(from: r.nextTriggerAt))")
            lines.append("SUMMARY:\(escape(r.title))")
            if !r.note.isEmpty {
                lines.append("DESCRIPTION:\(escape(r.note))")
            }
            if let rrule = rrule(for: r) {
                lines.append("RRULE:\(rrule)")
            }
            lines.append("END:VEVENT")
        }

        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n")
    }

    // MARK: - RRULE

    static func rrule(for r: Reminder) -> String? {
        switch r.kind {
        case .cycle:
            switch r.cycle {
            case .once: return nil
            case .daily: return "FREQ=DAILY"
            case .weekly: return "FREQ=WEEKLY"
            case .biweekly: return "FREQ=WEEKLY;INTERVAL=2"
            case .monthly: return "FREQ=MONTHLY"
            case .quarterly: return "FREQ=MONTHLY;INTERVAL=3"
            case .yearly: return "FREQ=YEARLY"
            case .custom: return "FREQ=DAILY;INTERVAL=\(max(r.customDays, 1))"
            }
        case .rule:
            // 每月/每季度/每年 第N周周X → BYDAY + BYSETPOS
            let byday = weekdayCode(r.ruleWeekday)
            let interval: String
            switch r.rulePeriod {
            case .monthly: interval = "FREQ=MONTHLY"
            case .quarterly: interval = "FREQ=MONTHLY;INTERVAL=3"
            case .yearly: interval = "FREQ=YEARLY"
            }
            return "\(interval);BYDAY=\(byday);BYSETPOS=\(r.ruleWeek.rawValue)"
        case .date:
            // 固定日期（生日/节假日）：单次事件，无 RRULE
            return nil
        }
    }

    /// RuleWeekday(1=周一..7=周日) → iCal 周几代码
    private static func weekdayCode(_ wd: RuleWeekday) -> String {
        ["MO", "TU", "WE", "TH", "FR", "SA", "SU"][wd.rawValue - 1]
    }

    // MARK: - 转义（RFC 5545 文本转义）

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
