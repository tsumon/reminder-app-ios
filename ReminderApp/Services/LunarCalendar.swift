import Foundation

/// 农历-公历转换器 — 基于 iOS 系统内置农历历法（Calendar(identifier: .chinese)）
///
/// 「系统时间为主」：不再维护手写 1900-2100 查表数据，直接使用系统历法引擎。
/// 好处：闰月/大小月与系统日历一致、覆盖范围由系统保证、纯本地计算离线可用。
///
/// ⚠️ 中国官方口径修正：系统历法（CLDR 数据）在个别年份与中国大陆官方口径
/// （紫金山天文台，新华社发布口径）有 1 天差异。例如农历 2026 年腊月，
/// CLDR 认为有三十（→ 2027 春节 02-07），官方口径无年三十（2027 春节 02-06）。
/// 提醒 App 面向中国用户，春节等关键日期必须与官方一致，故用 [lunarOverrides]
/// 做定向修正。新差异由回归测试（LunarCalendarTests）持续发现并补充。
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

    /// 缓存系统农历历法对象（创建开销不小，每次转换重建没必要）
    private static let chineseCalendar: Calendar = {
        var cal = Calendar(identifier: .chinese)
        cal.locale = Locale(identifier: "zh_CN")
        return cal
    }()

    // MARK: - 官方口径修正表

    /// 农历 → 公历修正：key = "农历年:月:日"（普通月），value = 官方公历 (y,m,d)；
    /// 不在表里的普通月但 value 为 nil 表示官方不存在该日。
    /// 目前 1 处：CLDR 认为农历 2026 年腊月有三十、2027 春节 02-07；
    /// 官方口径（新华社/紫金山天文台）2025-2029 连续 5 年无年三十，2027 春节 = 02-06。
    private static let lunarOverrides: [String: (Int, Int, Int)?] = [
        "2027:1:1": (2027, 2, 6),
        "2026:12:30": nil
    ]

    /// 公历 → 农历修正（由 lunarOverrides 反推）：key = "yyyyMMdd"
    private static let solarOverrides: [String: String] = {
        var map: [String: String] = [:]
        for (lunarKey, solar) in lunarOverrides {
            if let s = solar {
                map[String(format: "%04d%02d%02d", s.0, s.1, s.2)] = lunarKey
            }
        }
        return map
    }()

    // MARK: - 农历年份换算

    /// ⚠️ 关键语义（回归测试实测确认）：
    /// Calendar(identifier:.chinese) 的 DateComponents.year 是 **60 年干支循环内的年份
    /// （1-60）**，必须配 era 使用；直接传绝对农历年（如 2026）给 date(from:) 会返回 nil。
    /// 换算基准与 ICU ChineseCalendar 一致：绝对农历年 + 2637 = extendedYear，
    /// extendedYear = (era - 1) * 60 + eraYear。
    private static func eraYear(forAbsoluteYear year: Int) -> (era: Int, year: Int) {
        let extended = year + 2637
        let era = (extended - 1) / 60 + 1
        return (era, extended - (era - 1) * 60)
    }

    private static func absoluteYear(era: Int, eraYear: Int) -> Int {
        (era - 1) * 60 + eraYear - 2637
    }

    // MARK: - 公历 → 农历

    /// 将公历日期转换为农历日期（year 为绝对农历年，与旧查表实现一致）
    static func solarToLunar(_ date: Date) -> LunarDate {
        let cal = chineseCalendar

        // 官方口径修正：CLDR 把 2027-02-06 判为农历 2026 腊月三十，官方为正月初一
        let comps0 = Calendar.current.dateComponents([.year, .month, .day], from: date)
        if let y = comps0.year, let m = comps0.month, let d = comps0.day {
            let key = String(format: "%04d%02d%02d", y, m, d)
            if let lunarKey = solarOverrides[key] {
                let parts = lunarKey.split(separator: ":")
                if parts.count == 3 {
                    return LunarDate(
                        year: Int(parts[0]) ?? 0,
                        month: Int(parts[1]) ?? 0,
                        day: Int(parts[2]) ?? 0,
                        isLeapMonth: false
                    )
                }
            }
        }

        let comps = cal.dateComponents([.era, .year, .month, .day, .isLeapMonth], from: date)
        return LunarDate(
            year: absoluteYear(era: comps.era ?? 1, eraYear: comps.year ?? 0),
            month: comps.month ?? 0,
            day: comps.day ?? 0,
            isLeapMonth: comps.isLeapMonth ?? false
        )
    }

    // MARK: - 农历 → 公历

    /// 将农历日期转换为公历日期（返回该农历日对应的公历 Date，当天 00:00）
    /// [isLeapMonth] 指定闰月；如果该农历日期不存在（如该年无此闰月/无此普通月），返回 nil
    static func lunarToSolar(lunarYear: Int, lunarMonth: Int, lunarDay: Int, isLeapMonth: Bool = false) -> Date? {
        guard lunarMonth >= 1, lunarMonth <= 12 else { return nil }
        guard lunarDay >= 1, lunarDay <= 30 else { return nil }

        // 官方口径修正优先（仅普通月；闰月不存在于官方差异表中）
        if !isLeapMonth {
            let lunarKey = "\(lunarYear):\(lunarMonth):\(lunarDay)"
            if let override = lunarOverrides[lunarKey] {
                guard let s = override else { return nil }
                return Calendar.current.date(from: DateComponents(
                    year: s.0, month: s.1, day: s.2, hour: 0, minute: 0, second: 0
                ))
            }
        }

        let cal = chineseCalendar
        let (era, eraY) = eraYear(forAbsoluteYear: lunarYear)
        var comps = DateComponents()
        comps.era = era
        comps.year = eraY // era 内的干支年份（1-60），不是绝对年
        comps.month = lunarMonth
        comps.day = lunarDay
        comps.isLeapMonth = isLeapMonth
        comps.hour = 0
        comps.minute = 0
        comps.second = 0

        guard let date = cal.date(from: comps) else { return nil }

        // 往返校验：系统历法对不存在的日期会自动进位，反查确认后再返回
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

        let currentLunarYear = solarToLunar(now).year // 绝对农历年

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
