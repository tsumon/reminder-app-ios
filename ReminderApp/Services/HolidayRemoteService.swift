import Foundation

/// 联网节假日数据服务（v1.8.7 任务②）
///
/// 拉取官方口径的法定节假日安排（放假 + 调休上班日），供首页/日历卡显示「休/班」。
/// - 数据源：holiday-cn（NateScarlet/holiday-cn，GitHub 官方口径 JSON，免 key 无反爬）
///   GET https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/{year}.json
///   结构：{ "days": [ { "name": "元旦", "date": "2026-01-01", "isOffDay": true }, ... ] }
/// - 缓存：按年缓存到 UserDefaults，启动后台刷新；离线/失败时保留旧缓存，UI 静默降级
/// - 与提醒无关：提醒功能继续走内置 HolidayService，本服务只是展示增强
struct HolidayRemoteService {

    /// 某天的节假日状态
    struct DayStatus {
        let isHoliday: Bool   // true = 放假；false = 调休上班
        let name: String      // 节假日名称（调休上班日也带名称）
    }

    private static let baseURL = "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master"
    private static let cacheKeyPrefix = "remote_holiday_cache_"

    // MARK: - 查询

    /// 查询某公历日期（yyyy-MM-dd）的节假日状态；无数据（普通工作日/未拉到）返回 nil
    static func status(year: Int, month: Int, day: Int) -> DayStatus? {
        let key = String(format: "%04d-%02d-%02d", year, month, day)
        guard let cached = UserDefaults.standard.dictionary(forKey: cacheKey(year)) else { return nil }
        guard let raw = cached[key] as? [String: Any] else { return nil }
        guard let isHoliday = raw["holiday"] as? Bool, let name = raw["name"] as? String else { return nil }
        return DayStatus(isHoliday: isHoliday, name: name)
    }

    // MARK: - 刷新（启动时后台调用）

    /// 拉取指定年份的节假日安排并缓存到本地；失败静默（保留旧缓存，UI 降级）
    static func refresh(year: Int) async {
        guard let url = URL(string: "\(baseURL)/\(year).json") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let days = json["days"] as? [[String: Any]] else { return }

            var map: [String: [String: Any]] = [:]
            for entry in days {
                guard let name = entry["name"] as? String,
                      let date = entry["date"] as? String,
                      let isOffDay = entry["isOffDay"] as? Bool else { continue }
                // date 为 "yyyy-MM-dd"，直接作为 key；只保留当年数据
                if date.hasPrefix("\(year)-") {
                    map[date] = ["holiday": isOffDay, "name": name]
                }
            }
            guard !map.isEmpty else { return }
            UserDefaults.standard.set(map, forKey: cacheKey(year))
            print("[HolidayRemote] \(year) 节假日数据已缓存 \(map.count) 条")
        } catch {
            // 离线/接口失败：保留旧缓存，不打扰用户
            print("[HolidayRemote] \(year) 刷新失败，使用缓存/降级: \(error.localizedDescription)")
        }
    }

    private static func cacheKey(_ year: Int) -> String {
        "\(cacheKeyPrefix)\(year)"
    }
}
