import Foundation

/// 手动主题（v2.1.1）：0=跟随系统 1=浅色 2=深色
/// 自签环境系统外观可能不可控，手动切换是最稳的兜底。
enum ThemeStore {
    static let key = "app_theme_mode"

    static var mode: Int {
        get { UserDefaults.standard.integer(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// v2.4.0: 主题色板索引（0=青碧默认；与 ThemeTokens.palettes 对齐）
    static let colorKey = "theme_color_index"

    static var colorIndex: Int {
        get { UserDefaults.standard.integer(forKey: colorKey) }
        set { UserDefaults.standard.set(newValue, forKey: colorKey) }
    }
}
