import Foundation

/// 自然语言日期/时间解析（本地、无需 API）
///
/// 支持示例：
///  - 今天 / 明天 / 后天 / 大后天
///  - 周一 / 下周一（周X / 星期X / 礼拜X）
///  - 每月15号 / 每月5日
///  - 9月5号 / 1月14日（公历生日）
///  - 农历八月初五 → 需数字形式「农历8月5」
///  - 每天 / 每周 / 每月 / 每年
///  - 明早9点 / 下午3点 / 晚上8点半 / 09:30
///  - 3天后 / 2小时后 / 30分钟后 / 2周后
///
/// 实现说明：使用 NSRegularExpression（而非 Swift 正则字面量），
/// 以兼容 Swift 5 语言模式（裸斜杠字面量默认关闭）。
struct NaturalDateParser {

    struct ParsedSchedule {
        let nextTriggerAt: Date
        let repeatMode: String      // once | daily | weekly | monthly | yearly | lunar
        let dateType: DateReminderType?
        let targetMonth: Int?
        let targetDay: Int?
        let title: String
        let label: String
        /// v2.4.11: 手动创建对齐 AI——周几（1=周一..7=周日，weekly 用）与避开节假日/周末
        let weekday: Int?
        let holidayAware: Bool
    }

    // MARK: - 正则工具

    /// 返回第一个匹配的各捕获组字符串（索引 0 为整体匹配）
    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let m = regex.firstMatch(in: text, range: range) else { return nil }
        var groups: [String] = []
        for i in 0..<m.numberOfRanges {
            if let r = Range(m.range(at: i), in: text) {
                groups.append(String(text[r]))
            } else {
                groups.append("")
            }
        }
        return groups
    }

    private static func matches(_ pattern: String, in text: String) -> Bool {
        firstMatch(pattern, in: text) != nil
    }

    private static func replacing(_ pattern: String, in text: String, with replacement: String = " ") -> String {
        text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }

    private static func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int {
        min(max(v, lo), hi)
    }

    // MARK: - 主解析

    static func parse(_ input: String, now: Date = Date()) -> ParsedSchedule? {
        let text = input.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return nil }

        var hour = 9
        var minute = 0
        var repeatMode = "once"
        var weekday: Int? = nil
        var dateType: DateReminderType?
        var targetMonth: Int?
        var targetDay: Int?

        let cal = Calendar.current
        var base = now

        // ---------- 重复模式 ----------
        if text.contains("农历") || text.contains("旧历") || text.contains("阴历") {
            repeatMode = "lunar"; dateType = .lunarBirthday
        } else if text.contains("每天") || text.contains("每日") || text.contains("天天") {
            repeatMode = "daily"
        } else if text.contains("每年") || text.contains("年年") {
            repeatMode = "yearly"
        } else if text.contains("每月") || text.contains("每个月") {
            repeatMode = "monthly"
        } else if text.contains("每周") || text.contains("每星期") || text.contains("每礼拜") {
            repeatMode = "weekly"
        }

        // ---------- 时间 ----------
        if let g = firstMatch("([0-9]{1,2})[:：]([0-9]{2})", in: text) {
            hour = clamp(Int(g[1]) ?? 9, 0, 23)
            minute = clamp(Int(g[2]) ?? 0, 0, 59)
        } else if let g = firstMatch("([0-9]{1,2})\\s*点\\s*(?:([0-9]{1,2})\\s*分?)?", in: text) {
            var h = clamp(Int(g[1]) ?? 9, 0, 23)
            let mm = g[2].isEmpty ? 0 : clamp(Int(g[2]) ?? 0, 0, 59)
            if (text.contains("下午") || text.contains("晚上") || text.contains("傍晚")) && h < 12 { h += 12 }
            if text.contains("中午") && h <= 12 { h = 12 }
            hour = h; minute = mm
        } else {
            if text.contains("中午") { hour = 12 }
            else if text.contains("下午") || text.contains("晚上") || text.contains("傍晚") { hour = 15 }
            else if text.contains("凌晨") { hour = 5 }
            else if text.contains("早上") || text.contains("上午") { hour = 9 }
        }
        // 「X点半」
        if text.contains("半"), matches("[0-9]{1,2}\\s*点", in: text), minute == 0 { minute = 30 }

        // ---------- 日期锚点 ----------
        var isRelativeTime = false
        if let g = firstMatch("([0-9]{1,2})\\s*天[后以後]", in: text) {
            base = cal.date(byAdding: .day, value: Int(g[1]) ?? 1, to: base) ?? base
        } else if let g = firstMatch("([0-9]{1,2})\\s*周[后以後]", in: text) {
            base = cal.date(byAdding: .day, value: (Int(g[1]) ?? 1) * 7, to: base) ?? base
        } else if let g = firstMatch("([0-9]{1,2})\\s*小时[后以後]", in: text) {
            base = cal.date(byAdding: .hour, value: Int(g[1]) ?? 1, to: base) ?? base
            isRelativeTime = true
        } else if let g = firstMatch("([0-9]{1,3})\\s*分钟[后以後]", in: text) {
            base = cal.date(byAdding: .minute, value: Int(g[1]) ?? 30, to: base) ?? base
            isRelativeTime = true
        } else if text.contains("大后天") {
            base = cal.date(byAdding: .day, value: 3, to: base) ?? base
        } else if text.contains("后天") {
            base = cal.date(byAdding: .day, value: 2, to: base) ?? base
        } else if text.contains("明天") || text.contains("明日") || text.contains("明早") || text.contains("明晚") {
            base = cal.date(byAdding: .day, value: 1, to: base) ?? base
        } else if text.contains("昨天") || text.contains("昨日") {
            base = cal.date(byAdding: .day, value: -1, to: base) ?? base
        }

        // 周X / 星期X / 礼拜X（可带「下」）
        if let g = firstMatch("(下|上)?(?:周|星期|礼拜)([一二三四五六日天1-7])", in: text) {
            let map: [String: Int] = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "日": 7, "天": 7,
                                      "1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7]
            let target = map[g[2]] ?? 1
            let prefix = g[1] ?? ""
            var curDow = cal.component(.weekday, from: base) // 1=Sun
            curDow = curDow == 1 ? 7 : curDow - 1
            var diff = (target - curDow + 7) % 7
            // v1.9.6 fix: 支持「上周」——原实现只处理「下」，把「上」静默当本周处理
            if prefix == "下" {
                diff += 7
            } else if prefix == "上" {
                diff -= 7
                if diff == 0 { diff = -7 } // 今天就是目标周几 → 上周同日
            } else if diff == 0 {
                diff = 7 // 本周且已过 → 下同
            }
            base = cal.date(byAdding: .day, value: diff, to: base) ?? base
            if repeatMode == "once" { repeatMode = "weekly" }
            weekday = target
        }

        // 每月X号
        if let g = firstMatch("每月\\s*([0-9]{1,2})\\s*[号日]", in: text) {
            let parsedDay = clamp(Int(g[1]) ?? 1, 1, 31)
            targetDay = parsedDay
            repeatMode = "monthly"
            // 锚点必须落在「未来最近一个 X 号」所在月份：
            // ① date(bySetting:) 在短月返回 nil（2/28 设 31 号）→ 逐月找有 X 号的月份；
            // ② 若 X 号已过（1/31 说每月30号）→ 找后续月份；
            // 否则 firstTriggerAt 会被钳到短月末，引擎锚点日丢失（永久漂移 28 号），
            // 或 nextTriggerAt 落在过去 → 创建瞬间弹通知。
            var candidate: Date? = cal.date(bySetting: .day, value: parsedDay, of: base)
            if candidate == nil || candidate! <= base {
                // 从下月起的 12 个月内找第一个有 parsedDay 的月份
                candidate = nil
                for months in 1...12 {
                    if let next = cal.date(byAdding: .month, value: months, to: base),
                       let day = cal.date(bySetting: .day, value: parsedDay, of: next) {
                        candidate = day
                        break
                    }
                }
            }
            if let c = candidate {
                base = c
            }
        }

        // 公历 X月X日 / X月X号
        if repeatMode != "lunar", let g = firstMatch("([0-9]{1,2})\\s*月\\s*([0-9]{1,2})\\s*[号日]", in: text) {
            let tm = clamp(Int(g[1]) ?? 1, 1, 12)
            let td = clamp(Int(g[2]) ?? 1, 1, 31)
            targetMonth = tm; targetDay = td
            repeatMode = "yearly"; dateType = .solarBirthday
            var c = cal.dateComponents([.year], from: base)
            c.month = tm; c.day = td; c.hour = hour; c.minute = minute; c.second = 0
            if let d = cal.date(from: c) { base = d }
        }

        // 公历数字简写 2.10 / 2-10 / 2/10。紧凑无分隔格式（211）歧义太大
        // （2/11 还是 21/1 无从判断），不在此处理——AI 入口会反问确认
        if repeatMode != "lunar", let g = firstMatch("(?<![0-9.])([0-9]{1,2})[.\\-/]([0-9]{1,2})(?![0-9.\\-/])", in: text) {
            let tm = clamp(Int(g[1]) ?? 1, 1, 12)
            let td = clamp(Int(g[2]) ?? 1, 1, 31)
            targetMonth = tm; targetDay = td
            repeatMode = "yearly"; dateType = .solarBirthday
            var c = cal.dateComponents([.year], from: base)
            c.month = tm; c.day = td; c.hour = hour; c.minute = minute; c.second = 0
            if let d = cal.date(from: c) { base = d }
        }

        // 农历 X月X
        if let g = firstMatch("(?:农历|旧历|阴历)\\s*([0-9]{1,2})\\s*月\\s*([0-9]{1,2})", in: text) {
            let lm = clamp(Int(g[1]) ?? 1, 1, 12)
            let ld = clamp(Int(g[2]) ?? 1, 1, 30)
            let year = cal.component(.year, from: base)
            if let solar = LunarCalendar.lunarToSolar(lunarYear: year, lunarMonth: lm, lunarDay: ld) {
                base = solar
                targetMonth = lm; targetDay = ld
                repeatMode = "lunar"; dateType = .lunarBirthday
            }
        }

        // ---------- 应用时分 ----------
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: base)
        if !isRelativeTime {
            comps.hour = hour
            comps.minute = minute
        }
        comps.second = 0
        var next = cal.date(from: comps) ?? base

        // 一次性且已过去 → 顺延一天，避免立即触发
        if repeatMode == "once" && next <= now {
            next = cal.date(byAdding: .day, value: 1, to: next) ?? next
        }

        let title = extractTitle(text)
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "yyyy-MM-dd HH:mm"

        // v2.4.11: 避开节假日/周末——显式关键词优先，其次事务类关键词自动开启
        let holidayAware: Bool
        if text.contains("避开节假日") || text.contains("顺延") || text.contains("工作日") {
            holidayAware = true
        } else if text.contains("报税") || text.contains("缴费") || text.contains("还款")
            || text.contains("办证") || text.contains("开会") || text.contains("取件")
            || text.contains("办事") || text.contains("银行") || text.contains("上班") {
            holidayAware = true
        } else {
            holidayAware = false
        }

        return ParsedSchedule(
            nextTriggerAt: next,
            repeatMode: repeatMode,
            dateType: dateType,
            targetMonth: targetMonth,
            targetDay: targetDay,
            title: title,
            label: fmt.string(from: next),
            weekday: weekday,
            holidayAware: holidayAware
        )
    }

    // MARK: - 标题提取（剥离时间/日期词）

    private static func extractTitle(_ text: String) -> String {
        var t = text
        // 日期/时间片段
        t = replacing("([0-9]{1,2})\\s*[:：]\\s*[0-9]{2}", in: t)
        t = replacing("([0-9]{1,2})\\s*点\\s*[0-9]{0,2}\\s*分?半?", in: t)
        t = replacing("(今天|今日|明天|明日|明早|明晚|后天|大后天|昨天|昨日)", in: t)
        t = replacing("(每)?(下|上)?(周|星期|礼拜)[一二三四五六日天1-7]", in: t)
        t = replacing("每月\\s*[0-9]{1,2}\\s*[号日]", in: t)
        t = replacing("[0-9]{1,2}\\s*月\\s*[0-9]{1,2}\\s*[号日]", in: t)
        t = replacing("(?<![0-9.])[0-9]{1,2}[.\\-/][0-9]{1,2}(?![0-9.\\-/])", in: t)
        t = replacing("(农历|旧历|阴历)\\s*[0-9]{1,2}\\s*月\\s*[0-9]{1,2}", in: t)
        t = replacing("(早上|上午|中午|下午|晚上|凌晨|傍晚)", in: t)
        t = replacing("[0-9]{1,3}\\s*(天|周|小时|分钟)\\s*[后以後]", in: t)
        t = replacing("(每天|每日|天天|每年|年年|每周|每星期|每礼拜|每月|每个月)", in: t)
        // 常见口语前缀
        t = replacing("(提醒我|提醒|帮我|记得|设置|设定|闹钟|我想|让我|请)", in: t)
        t = replacing("\\s+", in: t)
        let trimmed = t.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "提醒" : trimmed
    }
}
