import Foundation

/// 历法引擎回归检查（v1.8.5 换系统历法后必跑）
///
/// 以 macOS 命令行工具形式运行（无需 iOS 模拟器 / host app），
/// 直接把产品代码 ReminderApp/Services/LunarCalendar.swift 编译进来断言权威农历事实。
/// 覆盖：近 10 年春节、2027 官方口径修正、2020 闰四月、2023 闰二月、
/// 除夕/正月初一边界、农历生日跨年、不存在日期拦截。
@main
struct LunarCalendarCheck {

    static var failures = 0

    static func check(_ name: String, _ cond: Bool) {
        print((cond ? "PASS " : "FAIL ") + name)
        if !cond { failures += 1 }
    }

    static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 0, minute: 0, second: 0))!
    }

    static func assertLunar(_ date: Date, _ y: Int, _ m: Int, _ d: Int, _ leap: Bool = false,
                            _ label: String) {
        let l = LunarCalendar.solarToLunar(date)
        check("\(label) → 农历\(y)年\(leap ? "闰" : "")\(m)月\(d)日 (得 \(l.year)/\(l.month)/\(l.day)/\(l.isLeapMonth))",
              l.year == y && l.month == m && l.day == d && l.isLeapMonth == leap)
    }

    static func main() {
        // 1. 近 10 年春节
        let springs: [(Int, Int, Int)] = [
            (2017, 1, 28), (2018, 2, 16), (2019, 2, 5), (2020, 1, 25), (2021, 2, 12),
            (2022, 2, 1), (2023, 1, 22), (2024, 2, 10), (2025, 1, 29), (2026, 2, 17)
        ]
        for (y, m, d) in springs {
            assertLunar(date(y, m, d), y, 1, 1, false, "春节 \(y)")
            check("农历\(y)正月初一 → 公历 \(m)-\(d)",
                  LunarCalendar.lunarToSolar(lunarYear: y, lunarMonth: 1, lunarDay: 1) == date(y, m, d))
        }

        // 2. 2027 春节官方口径修正（CLDR 差 1 天）
        check("修正后 2027 春节 = 02-06 (CLDR 裸数据给 02-07)",
              LunarCalendar.lunarToSolar(lunarYear: 2027, lunarMonth: 1, lunarDay: 1) == date(2027, 2, 6))
        check("官方口径 2026 年无腊月三十 → nil",
              LunarCalendar.lunarToSolar(lunarYear: 2026, lunarMonth: 12, lunarDay: 30) == nil)
        assertLunar(date(2027, 2, 6), 2027, 1, 1, false, "02-06 应为正月初一")
        assertLunar(date(2027, 2, 5), 2026, 12, 29, false, "02-05 应为除夕(腊月廿九)")

        // 3. 2020 闰四月
        assertLunar(date(2020, 6, 6), 2020, 4, 15, true, "2020 闰四月十五")
        check("lunarToSolar(2020 闰四月十五) = 06-06",
              LunarCalendar.lunarToSolar(lunarYear: 2020, lunarMonth: 4, lunarDay: 15, isLeapMonth: true) == date(2020, 6, 6))
        check("2020 闰四月三十不存在 → nil",
              LunarCalendar.lunarToSolar(lunarYear: 2020, lunarMonth: 4, lunarDay: 30, isLeapMonth: true) == nil)

        // 4. 2023 闰二月
        assertLunar(date(2023, 3, 22), 2023, 2, 1, true, "2023 闰二月初一")
        check("lunarToSolar(2023 闰二月初一) = 03-22",
              LunarCalendar.lunarToSolar(lunarYear: 2023, lunarMonth: 2, lunarDay: 1, isLeapMonth: true) == date(2023, 3, 22))
        check("2023 普通二月三十 = 03-21 (普通二月是大月)",
              LunarCalendar.lunarToSolar(lunarYear: 2023, lunarMonth: 2, lunarDay: 30) == date(2023, 3, 21))
        check("2023 闰二月三十不存在 → nil",
              LunarCalendar.lunarToSolar(lunarYear: 2023, lunarMonth: 2, lunarDay: 30, isLeapMonth: true) == nil)

        // 5. 农历生日跨年
        let thisYear = LunarCalendar.lunarToSolar(lunarYear: 2026, lunarMonth: 1, lunarDay: 1)!
        check("今年(2026)正月初一已过 (\(thisYear))", thisYear <= date(2026, 8, 6))
        check("明年正月初一 = 2027-02-06",
              LunarCalendar.lunarToSolar(lunarYear: 2027, lunarMonth: 1, lunarDay: 1) == date(2027, 2, 6))
        check("nextLunarBirthday(正月初一, from 2026-08-06) = 2027-02-06",
              LunarCalendar.nextLunarBirthday(month: 1, day: 1, from: date(2026, 8, 6)) == date(2027, 2, 6))

        print(failures == 0 ? "== ALL LUNAR REGRESSION PASS ==" : "== \(failures) FAILURES ==")
        exit(Int32(failures))
    }
}
