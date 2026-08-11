import Foundation

/// .ics 日历导出（v1.8.7 任务④；v2.0.20 批次2 增强）
///
/// 把提醒导出为 iCalendar（RFC 5545）VEVENT，供系统日历/Outlook/Google 日历导入。
/// 批次2 增强：补 DTEND（30 分钟时长）、X-WR-CALNAME / X-WR-TIMEZONE（时区正确导入）、
/// RFC 5545 行折叠（>75 字符折行，续行空格前缀，长标题/备注不截断）。
/// RRULE 映射（双端一致）：
///   once → 无 RRULE；daily → FREQ=DAILY；weekly → FREQ=WEEKLY；
///   biweekly → FREQ=WEEKLY;INTERVAL=2；monthly → FREQ=MONTHLY；
///   quarterly → FREQ=MONTHLY;INTERVAL=3；yearly → FREQ=YEARLY；
///   custom → FREQ=DAILY;INTERVAL=N
///   rule 类(第N周周X) → FREQ=对应周期;BYDAY=周几;BYSETPOS=N
enum IcsExporter {

    private static let eventDuration: TimeInterval = 30 * 60

    static func generateICS(reminders: [Reminder]) -> String {
        let timeZone = TimeZone.current
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//ReminderApp//循环提醒//CN",
            "CALSCALE:GREGORIAN",
            "X-WR-CALNAME:循环提醒器",
            "X-WR-TIMEZONE:\(timeZone.identifier)"
        ]

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyyMMdd'T'HHmmss"
        df.timeZone = timeZone

        for r in reminders where r.isEnabled {
            lines.append("BEGIN:VEVENT")
            lines.append("UID:reminder-\(r.id.uuidString)@reminder.app")
            lines.append("DTSTAMP:\(df.string(from: Date()))")
            lines.append("DTSTART:\(df.string(from: r.nextTriggerAt))")
            lines.append("DTEND:\(df.string(from: r.nextTriggerAt.addingTimeInterval(eventDuration)))")
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

        // RFC 5545 §3.1：物理行最长 75 octets（不含 CRLF），超长需折行，续行以单个空格开头
        return lines.flatMap { foldLine($0) }.joined(separator: "\r\n")
    }

    /// RFC 5545 行折叠：按 UTF-8 字节数折到 ≤75（续行 ≤74，预留续行空格位）
    private static func foldLine(_ line: String) -> [String] {
        let bytes = Array(line.utf8)
        if bytes.count <= 75 { return [line] }

        var folded: [String] = []
        var start = 0
        var first = true
        while start < bytes.count {
            let limit = first ? 75 : 74
            var end = start + limit
            if end >= bytes.count {
                let tail = String(decoding: bytes[start...], as: UTF8.self)
                folded.append(first ? tail : " \(tail)")
                break
            }
            // 不能把 UTF-8 多字节字符截断：若断点落在续字节(10xxxxxx)，回退到完整字符前
            while end > start, end < bytes.count, bytes[end] & 0xC0 == 0x80 {
                end -= 1
            }
            if end <= start { end = start + 1 } // 防御：单字节字符占满 limit 的极端情况
            let part = String(decoding: bytes[start..<end], as: UTF8.self)
            folded.append(first ? part : " \(part)")
            start = end
            first = false
        }
        return folded
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
            // I3: 固定日期（生日/节假日）按年重复，日历订阅应每年出现一次，而非一次性事件
            return "FREQ=YEARLY"
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
