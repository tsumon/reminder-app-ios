import Foundation

/// 农历-公历转换器 — 基于 iOS 系统内置农历历法（Calendar(identifier: .chinese)）
///
/// 「系统时间为主」：不再维护手写 1900-2100 查表数据，直接使用系统历法引擎。
/// 好处：
///   - 闰月、大小月规则与系统日历完全一致，消除此前手写算法的偏移误差；
///   - 覆盖范围由系统保证，无查表边界问题；
///   - 纯本地计算，离线可用（联网获取仅作为后续节假日的可选增强）。
///
/// 对外接口与旧实现完全一致（solarToLunar / lunarToSolar / nextLunarBirthday / LunarDate），
/// 调用点零改动。
struct LunarCalendar {

    // MARK: - 农历日期结构

    struct LunarDate {
        let year: Int
        let month: Int
        let day: Int
        let isLeapMonth: Bool

        var description: String {
            let monthNames = ["正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊"]
            let dayNames = [
                "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
                "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
                "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
            ]
            let prefix = isLeapMonth ? "闰" : ""
            return "\(prefix)\(monthNames[month - 1])月\(dayNames[day - 1])"
        }
    }

    private static var chineseCalendar: Calendar {
        var cal = Calendar(identifier: .chinese)
        cal.locale = Locale(identifier: "zh_CN")
        return cal
    }

    // MARK: - 公历 → 农历

    /// 将公历日期转换为农历日期
    static func solarToLunar(_ date: Date) -> LunarDate {
        let cal = chineseCalendar
        let comps = cal.dateComponents([.year, .month, .day, .isLeapMonth], from: date)
        return LunarDate(
            year: comps.year ?? 0,
            month: comps.month ?? 0,
            day: comps.day ?? 0,
            isLeapMonth: comps.isLeapMonth ?? false
        )
    }

    // MARK: - 农历 → 公历

    /// 将农历日期转换为公历日期（返回该农历日对应的公历 Date，当天 00:00）
    /// 如果该农历日期不存在（如某年没有此闰月），返回 nil
    static func lunarToSolar(lunarYear: Int, lunarMonth: Int, lunarDay: Int, isLeapMonth: Bool = false) -> Date? {
        guard lunarMonth >= 1, lunarMonth <= 12 else { return nil }
        guard lunarDay >= 1, lunarDay <= 30 else { return nil }

        let cal = chineseCalendar
        var comps = DateComponents()
        comps.year = lunarYear // Calendar(identifier:.chinese) 的 year 为绝对农历年
        comps.month = lunarMonth
        comps.day = lunarDay
        comps.isLeapMonth = isLeapMonth
        comps.hour = 0
        comps.minute = 0
        comps.second = 0

        guard let date = cal.date(from: comps) else { return nil }

        // 往返校验：系统历法对不存在的日期（如该年没有要求的闰月）会自动进位，
        // 必须反查确认「我设的农历月日」确实落在该公历日，否则返回 nil。
        let back = solarToLunar(date)
        guard back.year == lunarYear, back.month == lunarMonth, back.day == lunarDay else { return nil }
        if isLeapMonth && !back.isLeapMonth { return nil }
        return date
    }

    // MARK: - 便捷方法：获取农历生日对应的下一个公历日期

    /// 计算农历生日（月日）在当前/下一个农历年对应的公历日期
    /// 返回从 now 开始最近的一个匹配日期（保持旧行为：普通月优先，其次闰月）
    static func nextLunarBirthday(month: Int, day: Int, from now: Date = Date()) -> Date? {
        guard (1...12).contains(month), (1...30).contains(day) else { return nil }

        let currentLunarYear = chineseCalendar.dateComponents([.year], from: now).year ?? 0

        // 普通月：今年与明年
        for tryYear in currentLunarYear...(currentLunarYear + 1) {
            if let d = lunarToSolar(lunarYear: tryYear, lunarMonth: month, lunarDay: day),
               d > now {
                return d
            }
        }

        // 闰月：今年与明年（若当年该月是闰月）
        for tryYear in currentLunarYear...(currentLunarYear + 1) {
            if let d = lunarToSolar(lunarYear: tryYear, lunarMonth: month, lunarDay: day, isLeapMonth: true),
               d > now {
                return d
            }
        }

        return nil
    }
}
