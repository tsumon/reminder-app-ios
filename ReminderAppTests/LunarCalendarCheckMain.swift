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

        // 2b. P0-2 农历整年平移回归（2025–2030 官方口径锚点）
        // 2026 春节官方=02-17 与 CLDR 一致，不平移；2027–2030 比 CLDR 早 1 天。
        let shiftedSprings: [(Int, Int, Int)] = [
            (2027, 2, 6), (2028, 1, 26), (2029, 2, 13), (2030, 2, 3)
        ]
        for (y, m, d) in shiftedSprings {
            check("修正后 \(y) 春节 = \(m)-\(d) (CLDR 早1天)",
                  LunarCalendar.lunarToSolar(lunarYear: y, lunarMonth: 1, lunarDay: 1) == date(y, m, d))
            assertLunar(date(y, m, d), y, 1, 1, false, "\(y) 春节正月初一")
        }
        // 2026 春节不平移（官方=02-17，与 CLDR 一致）
        check("2026 春节不平移 = 02-17",
              LunarCalendar.lunarToSolar(lunarYear: 2026, lunarMonth: 1, lunarDay: 1) == date(2026, 2, 17))
        // 无年三十年份（官方口径）腊月三十不存在
        // 注：2029 农历有腊月三十（公历 2030-02-02），2030 无；故集合以 2030 收尾。
        for y in [2025, 2026, 2027, 2028, 2030] {
            check("农历\(y) 无腊月三十 → nil",
                  LunarCalendar.lunarToSolar(lunarYear: y, lunarMonth: 12, lunarDay: 30) == nil)
        }
        // 除夕连续性：平移年份 除夕(腊月廿九)=春节-1，反向查表一致
        assertLunar(date(2028, 1, 25), 2027, 12, 29, false, "2028 除夕=腊月廿九")
        assertLunar(date(2028, 1, 26), 2028, 1, 1, false, "2028 春节=正月初一")
        assertLunar(date(2029, 2, 12), 2028, 12, 29, false, "2029 除夕=腊月廿九")
        // 农历2029年 腊月为大月(30天)，有年三十：除夕 = 2030-02-02 = 腊月三十（HKO 口径）
        assertLunar(date(2030, 2, 1), 2029, 12, 29, false, "2030-02-01 = 农历2029年腊月廿九")
        assertLunar(date(2030, 2, 2), 2029, 12, 30, false, "2030 除夕=腊月三十(2029有年三十)")
        check("农历2029 有腊月三十 = 2030-02-02",
              LunarCalendar.lunarToSolar(lunarYear: 2029, lunarMonth: 12, lunarDay: 30) == date(2030, 2, 2))
        let d20300202 = LunarCalendar.solarToLunar(date(2030, 2, 2))
        check("2030-02-02 反向查表 = 农历2029年腊月三十",
              d20300202.year == 2029 && d20300202.month == 12 && d20300202.day == 30)

        // 2c. P1-2 递增重试时间轴回归（与 Android retryIntervals / MAX_ESCALATION 对齐）
        // 单测 RetrySchedule 纯逻辑，避免「iOS 改了没法本地验证」盲区。
        check("RetrySchedule.maxStage == 5 (第5阶段标 overdue)", RetrySchedule.maxStage == 5)
        // delay(afterStage:) 序列（秒）：0/1→1h，2→4h，3→12h，4+→24h
        check("delay(0..1) == 3600", RetrySchedule.delay(afterStage: 0) == 3600)
        check("delay(1) == 3600", RetrySchedule.delay(afterStage: 1) == 3600)
        check("delay(2) == 14400", RetrySchedule.delay(afterStage: 2) == 14400)
        check("delay(3) == 43200", RetrySchedule.delay(afterStage: 3) == 43200)
        check("delay(4) == 86400", RetrySchedule.delay(afterStage: 4) == 86400)
        check("delay(5) == 86400 (封顶 24h)", RetrySchedule.delay(afterStage: 5) == 86400)
        check("delay(99) == 86400 (封顶 24h)", RetrySchedule.delay(afterStage: 99) == 86400)
        // cumulativeOffset：D-day 起累计时间轴
        check("cumulativeOffset(1) == 0 (D-day)", RetrySchedule.cumulativeOffset(toStage: 1) == 0)
        check("cumulativeOffset(2) == 3600 (T+1h)", RetrySchedule.cumulativeOffset(toStage: 2) == 3600)
        check("cumulativeOffset(3) == 18000 (T+5h)", RetrySchedule.cumulativeOffset(toStage: 3) == 18000)
        check("cumulativeOffset(4) == 61200 (T+17h)", RetrySchedule.cumulativeOffset(toStage: 4) == 61200)
        check("cumulativeOffset(5) == 147600 (T+41h)", RetrySchedule.cumulativeOffset(toStage: 5) == 147600)
        // catchUp：App 被杀一段时间后回来，按错过次数补齐阶段
        let baseT = date(2030, 1, 1)
        let now41h = baseT.addingTimeInterval(41 * 3600)
        let caughtA = RetrySchedule.catchUp(stage: 0, dueAt: baseT, now: now41h)
        check("catchUp(stage0, now=T+41h) → stage=5 overdue",
              caughtA.stage == 5 && caughtA.isOverdue)
        let now5h = baseT.addingTimeInterval(5 * 3600)
        let caughtB = RetrySchedule.catchUp(stage: 0, dueAt: baseT, now: now5h)
        check("catchUp(stage0, now=T+5h) → stage=3 due=T+17h 非逾期",
              caughtB.stage == 3
              && !caughtB.isOverdue
              && Int(caughtB.dueAt.timeIntervalSince(baseT)) == 17 * 3600)
        // catchUp 保证单调推进、不回退
        let caughtC = RetrySchedule.catchUp(stage: 3, dueAt: baseT.addingTimeInterval(17 * 3600), now: now41h)
        check("catchUp(stage3, now=T+41h) 从阶段3继续 → stage=5 overdue",
              caughtC.stage == 5 && caughtC.isOverdue)

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
