import Foundation

/// 节假日服务：管理中国法定节假日数据，计算下一个节假日日期
struct HolidayService {

    /// 节假日定义
    struct Holiday: Identifiable {
        let id: String
        let name: String
        let emoji: String
        let isLunar: Bool       // 是否按农历计算
        let month: Int          // 公历月 / 农历月
        let day: Int            // 公历日 / 农历日
    }

    /// 内置中国节假日列表
    static let allHolidays: [Holiday] = [
        Holiday(id: "yuandan",     name: "元旦",     emoji: "🎉", isLunar: false, month: 1,  day: 1),
        Holiday(id: "chunjie",     name: "春节",     emoji: "🧧", isLunar: true,  month: 1,  day: 1),
        Holiday(id: "yuanxiao",    name: "元宵节",   emoji: "🏮", isLunar: true,  month: 1,  day: 15),
        Holiday(id: "qingming",    name: "清明节",   emoji: "🌿", isLunar: false, month: 4,  day: 5),
        Holiday(id: "duanwu",      name: "端午节",   emoji: "🐲", isLunar: true,  month: 5,  day: 5),
        Holiday(id: "qixi",        name: "七夕",     emoji: "💕", isLunar: true,  month: 7,  day: 7),
        Holiday(id: "zhongqiu",    name: "中秋节",   emoji: "🥮", isLunar: true,  month: 8,  day: 15),
        Holiday(id: "guoqing",     name: "国庆节",   emoji: "🇨🇳", isLunar: false, month: 10, day: 1),
        Holiday(id: "chongyang",   name: "重阳节",   emoji: "🌺", isLunar: true,  month: 9,  day: 9),
        Holiday(id: "dongzhi",     name: "冬至",     emoji: "❄️", isLunar: false, month: 12, day: 22),
        Holiday(id: "laba",        name: "腊八节",   emoji: "🥣", isLunar: true,  month: 12, day: 8),
        Holiday(id: "xiaonian",    name: "小年",     emoji: "🏠", isLunar: true,  month: 12, day: 23),
        Holiday(id: "chuxi",       name: "除夕",     emoji: "🧨", isLunar: true,  month: 12, day: 30),
    ]

    /// 根据 ID 查找节假日
    static func find(by id: String) -> Holiday? {
        allHolidays.first { $0.id == id }
    }

    /// 根据名称模糊搜索节假日（给 AI 用）
    static func search(by name: String) -> Holiday? {
        let lower = name.lowercased()
        return allHolidays.first { $0.name.lowercased().contains(lower) }
    }

    /// 计算指定节假日的下一个日期
    static func nextDate(for holiday: Holiday, from now: Date = Date()) -> Date? {
        if holiday.isLunar {
            // 除夕 = 农历正月初一的前一天（腊月最后一天）。
            // 2025–2029 连续无年三十，硬写 12/30 会得到错误日期，故取「春节 - 1 天」。
            if holiday.name == "除夕" {
                guard let spring = LunarCalendar.nextLunarBirthday(month: 1, day: 1, from: now) else { return nil }
                return spring.addingTimeInterval(-86400)
            }
            // 其它农历节假日→用农历转换
            return LunarCalendar.nextLunarBirthday(month: holiday.month, day: holiday.day, from: now)
        } else {
            // 公历节假日→直接计算
            return nextSolarDate(month: holiday.month, day: holiday.day, from: now)
        }
    }

    /// 公历固定日期的下一次出现
    private static func nextSolarDate(month: Int, day: Int, from now: Date) -> Date? {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: now)

        // 构造今年的日期
        var thisYearComponents = DateComponents()
        thisYearComponents.year = currentYear
        thisYearComponents.month = month
        thisYearComponents.day = day

        if let thisYearDate = calendar.date(from: thisYearComponents), thisYearDate > now {
            return thisYearDate
        }

        // 已过→明年
        var nextYearComponents = DateComponents()
        nextYearComponents.year = currentYear + 1
        nextYearComponents.month = month
        nextYearComponents.day = day

        return calendar.date(from: nextYearComponents)
    }
}
