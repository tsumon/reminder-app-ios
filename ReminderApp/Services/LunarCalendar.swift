import Foundation

/// 农历-公历转换器（支持 1900–2100 年）
/// 基于查表法实现，数据来源于香港天文台农历数据
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

    // MARK: - 农历数据表（1900–2100，每年一个 UInt32）

    /// 每个 UInt32 编码：前 4 位=闰月月份（0=无闰月），后 12 位=每月大小月（1=30天，0=29天）
    /// 从高位到低位依次为正月初一到腊月（如有闰月则插在对应月份之后）
    private static let lunarInfo: [UInt32] = [
        0x04bd8, 0x04ae0, 0x0a570, 0x054d5, 0x0d260, 0x0d950, 0x16554, 0x056a0, 0x09ad0, 0x055d2, // 1900-1909
        0x04ae0, 0x0a5b6, 0x0a4d0, 0x0d250, 0x1d255, 0x0b540, 0x0d6a0, 0x0ada2, 0x095b0, 0x14977, // 1910-1919
        0x04970, 0x0a4b0, 0x0b4b5, 0x06a50, 0x06d40, 0x1ab54, 0x02b60, 0x09570, 0x052f2, 0x04970, // 1920-1929
        0x06566, 0x0d4a0, 0x0ea50, 0x16a95, 0x05ad0, 0x02b60, 0x186e3, 0x092e0, 0x1c8d7, 0x0c950, // 1930-1939
        0x0d4a0, 0x1d8a6, 0x0b550, 0x056a0, 0x1a5b4, 0x025d0, 0x092d0, 0x0d2b2, 0x0a950, 0x0b557, // 1940-1949
        0x06ca0, 0x0b550, 0x15355, 0x04da0, 0x0a5b0, 0x14573, 0x052b0, 0x0a9a8, 0x0e950, 0x06aa0, // 1950-1959
        0x0aea6, 0x0ab50, 0x04b60, 0x0aae4, 0x0a570, 0x05260, 0x0f263, 0x0d950, 0x05b57, 0x056a0, // 1960-1969
        0x096d0, 0x04dd5, 0x04ad0, 0x0a4d0, 0x0d4d4, 0x0d250, 0x0d558, 0x0b540, 0x0b6a0, 0x195a6, // 1970-1979
        0x095b0, 0x049b0, 0x0a974, 0x0a4b0, 0x0b27a, 0x06a50, 0x06d40, 0x0af46, 0x0ab60, 0x09570, // 1980-1989
        0x04af5, 0x04970, 0x064b0, 0x074a3, 0x0ea50, 0x06b58, 0x05ac0, 0x0ab60, 0x096d5, 0x092e0, // 1990-1999
        0x0c960, 0x0d954, 0x0d4a0, 0x0da50, 0x07552, 0x056a0, 0x0abb7, 0x025d0, 0x092d0, 0x0cab5, // 2000-2009
        0x0a950, 0x0b4a0, 0x0baa4, 0x0ad50, 0x055d9, 0x04ba0, 0x0a5b0, 0x15176, 0x052b0, 0x0a930, // 2010-2019
        0x07954, 0x06aa0, 0x0ad50, 0x05b52, 0x04b60, 0x0a6e6, 0x0a4e0, 0x0d260, 0x0ea65, 0x0d530, // 2020-2029
        0x05aa0, 0x076a3, 0x096d0, 0x04afb, 0x04ad0, 0x0a4d0, 0x1d0b6, 0x0d250, 0x0d520, 0x0dd45, // 2030-2039
        0x0b5a0, 0x056d0, 0x055b2, 0x049b0, 0x0a577, 0x0a4b0, 0x0aa50, 0x1b255, 0x06d20, 0x0ada0, // 2040-2049
        0x14b63, 0x09370, 0x049f8, 0x04970, 0x064b0, 0x168a6, 0x0ea50, 0x06b20, 0x1a6c4, 0x0aae0, // 2050-2059
        0x092e0, 0x0d2e3, 0x0c960, 0x0d557, 0x0d4a0, 0x0da50, 0x05d55, 0x056a0, 0x0a6d0, 0x055d4, // 2060-2069
        0x052d0, 0x0a9b8, 0x0a950, 0x0b4a0, 0x0b6a6, 0x0ad50, 0x055a0, 0x0aba4, 0x0a5b0, 0x052b0, // 2070-2079
        0x0b273, 0x06930, 0x07337, 0x06aa0, 0x0ad50, 0x14b55, 0x04b60, 0x0a570, 0x054e4, 0x0d160, // 2080-2089
        0x0e968, 0x0d520, 0x0daa0, 0x16aa6, 0x056d0, 0x04ae0, 0x0a9d4, 0x0a4d0, 0x0d150, 0x0f252, // 2090-2099
        0x0d520                                                                    // 2100
    ]

    // MARK: - 公历每月天数

    private static let solarMonthDays: [Int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

    private static func isSolarLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    // MARK: - 农历年信息

    /// 获取农历年的天数
    private static func lunarYearDays(_ year: Int) -> Int {
        let info = lunarInfo[year - 1900]
        var sum = 0
        for i in (0..<12).reversed() {
            sum += ((info >> i) & 1) == 1 ? 30 : 29
        }
        // 加上闰月天数
        let leapMonth = Int(info >> 12) & 0xF
        if leapMonth > 0 {
            let leapDays = ((info >> (12 - leapMonth)) & 1) == 1 ? 30 : 29
            sum += leapDays
        }
        return sum
    }

    /// 获取农历年闰月（0=无闰月）
    static func leapMonth(of year: Int) -> Int {
        Int(lunarInfo[year - 1900] >> 12) & 0xF
    }

    // MARK: - 公历 → 农历

    /// 将公历日期转换为农历日期
    static func solarToLunar(_ date: Date) -> LunarDate {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year!
        let month = components.month!
        let day = components.day!

        // 计算 date 距离 1900-01-31（农历庚子年正月初一）的天数
        let baseComponents = DateComponents(year: 1900, month: 1, day: 31)
        let baseDate = calendar.date(from: baseComponents)!
        let offset = calendar.dateComponents([.day], from: baseDate, to: date).day!

        // 在农历年表中查找
        var lunarYear = 1900
        var daysRemaining = offset

        while lunarYear < 2101 {
            let yearDays = lunarYearDays(lunarYear)
            if daysRemaining < yearDays { break }
            daysRemaining -= yearDays
            lunarYear += 1
        }

        // 在农历年中确定月份和日期
        let leap = leapMonth(of: lunarYear)
        let info = lunarInfo[lunarYear - 1900]
        var lunarMonth = 1
        var isLeap = false

        for m in 1...12 {
            let isLeapMonth = (leap > 0 && m == leap + 1 && !isLeap)
            let monthDays = ((info >> (16 - m)) & 1) == 1 ? 30 : 29

            if daysRemaining < monthDays {
                break
            }
            daysRemaining -= monthDays

            if isLeapMonth {
                let leapDays = ((info >> (16 - leap)) & 1) == 1 ? 30 : 29
                if daysRemaining < leapDays {
                    isLeap = true
                    lunarMonth = leap
                    break
                }
                daysRemaining -= leapDays
                isLeap = false
            }
            lunarMonth = m
        }

        return LunarDate(year: lunarYear, month: lunarMonth, day: daysRemaining + 1, isLeapMonth: isLeap)
    }

    // MARK: - 农历 → 公历

    /// 将农历日期转换为公历日期（返回该农历日对应的公历 Date）
    /// 如果该农历日不存在（如闰月只在闰年有），返回 nil
    static func lunarToSolar(lunarYear: Int, lunarMonth: Int, lunarDay: Int, isLeapMonth: Bool = false) -> Date? {
        guard lunarYear >= 1900, lunarYear <= 2100 else { return nil }
        guard lunarMonth >= 1, lunarMonth <= 12 else { return nil }
        guard lunarDay >= 1, lunarDay <= 30 else { return nil }

        let leap = leapMonth(of: lunarYear)

        // 如果要找闰月但该年没有闰月，返回 nil
        if isLeapMonth && leap != lunarMonth { return nil }

        let info = lunarInfo[lunarYear - 1900]

        // 计算从 1900-01-31 到目标农历日期的天数
        var totalDays = 0

        // 累加之前年份的天数
        for y in 1900..<lunarYear {
            totalDays += lunarYearDays(y)
        }

        // 累加当年之前月份的天数
        for m in 1..<lunarMonth {
            let monthDays = ((info >> (16 - m)) & 1) == 1 ? 30 : 29
            totalDays += monthDays

            // 如果当前月是闰月之后的月份，加上闰月天数
            if leap > 0 && m == leap {
                let leapDays = ((info >> (16 - leap)) & 1) == 1 ? 30 : 29
                totalDays += leapDays
            }
        }

        // 如果是闰月，加普通月的天数
        if isLeapMonth && leap == lunarMonth {
            let normalMonthDays = ((info >> (16 - lunarMonth)) & 1) == 1 ? 30 : 29
            totalDays += normalMonthDays
        }

        // 加上日期
        totalDays += lunarDay - 1

        // 基准日期 1900-01-31
        let calendar = Calendar.current
        let baseComponents = DateComponents(year: 1900, month: 1, day: 31)
        let baseDate = calendar.date(from: baseComponents)!

        return calendar.date(byAdding: .day, value: totalDays, to: baseDate)
    }

    // MARK: - 便捷方法：获取农历生日对应的下一个公历日期

    /// 计算农历生日（月日）在当前/下一个农历年对应的公历日期
    /// 返回从 now 开始最近的一个匹配日期
    static func nextLunarBirthday(month: Int, day: Int, from now: Date = Date()) -> Date? {
        let currentLunar = solarToLunar(now)
        var targetYear = currentLunar.year

        // 今年的农历生日是否已过？
        if currentLunar.month > month || (currentLunar.month == month && currentLunar.day > day) {
            targetYear += 1
        }

        // 尝试今年和明年的农历日期
        for offset in 0...1 {
            let tryYear = targetYear + offset
            let leapMonth = leapMonth(of: tryYear)

            // 先尝试非闰月
            if let result = lunarToSolar(lunarYear: tryYear, lunarMonth: month, lunarDay: day, isLeapMonth: false) {
                if result > now { return result }
            }

            // 如果当年闰月匹配，尝试闰月
            if leapMonth == month {
                if let result = lunarToSolar(lunarYear: tryYear, lunarMonth: month, lunarDay: day, isLeapMonth: true) {
                    if result > now { return result }
                }
            }
        }

        return nil
    }
}
