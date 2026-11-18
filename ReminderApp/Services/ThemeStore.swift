import Foundation

/// 手动主题与奶油漫风纸张色板存储
/// - `mode`: 0=跟随系统, 1=浅色, 2=深色
/// - `colorIndex`: 0=奶油橙(默认, 1:1 IOTA MONITOR), 1=抹茶奶纸, 2=海盐汽水, 3=莓果奶昔, 4=黄油柠檬, 5=复古电紫
enum ThemeStore {
    static let key = "app_theme_mode"

    static var mode: Int {
        get { UserDefaults.standard.integer(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static let colorKey = "theme_color_index"

    static var colorIndex: Int {
        get { UserDefaults.standard.integer(forKey: colorKey) }
        set { UserDefaults.standard.set(newValue, forKey: colorKey) }
    }

    static let paperNames: [String] = [
        "奶油橙",
        "抹茶奶纸",
        "海盐汽水",
        "莓果奶昔",
        "黄油柠檬",
        "复古电紫"
    ]
}
