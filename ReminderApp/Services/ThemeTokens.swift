import SwiftUI

/// 设计令牌（v1.8.7 任务⑤）— 双端统一（iOS 本文件 / Android Tokens.kt）
///
/// 一份令牌，两端各映射一份；新 UI 一律引用令牌，不写硬编码颜色/圆角/字号。
/// 主色统一为 Material Design 3 紫色 #6750A4。
enum ThemeTokens {

    // MARK: 品牌主色（双端统一 #6750A4）

    /// 主色：M3 紫 #6750A4
    static let brandPrimary = Color(red: 0x67 / 255.0, green: 0x50 / 255.0, blue: 0xA4 / 255.0)

    // MARK: 状态色（与 Android 一致）

    static let statusReminding = Color(red: 0xE7 / 255.0, green: 0x4C / 255.0, blue: 0x3C / 255.0)
    static let statusWaiting = Color(red: 0x34 / 255.0, green: 0x98 / 255.0, blue: 0xDB / 255.0)
    static let statusCompleted = Color(red: 0x27 / 255.0, green: 0xAE / 255.0, blue: 0x60 / 255.0)

    // MARK: 节假日「休/班」

    /// 休（放假）红
    static let holidayRest = Color(red: 0xD3 / 255.0, green: 0x2F / 255.0, blue: 0x2F / 255.0)
    /// 班（调休上班）橙
    static let holidayWork = Color(red: 0xEF / 255.0, green: 0x6C / 255.0, blue: 0x00 / 255.0)

    // MARK: 热力图色阶（统计页，与 Android 一致）

    static let heatmap0 = Color.gray.opacity(0.12)
    static let heatmap1 = Color(red: 0x2B / 255.0, green: 0x66 / 255.0, blue: 0xC4 / 255.0).opacity(0.25)
    static let heatmap2 = Color(red: 0x2B / 255.0, green: 0x66 / 255.0, blue: 0xC4 / 255.0).opacity(0.55)
    static let heatmap3 = Color(red: 0x2B / 255.0, green: 0x66 / 255.0, blue: 0xC4 / 255.0)

    // MARK: 圆角

    static let cardRadius: CGFloat = 16
    static let cellRadius: CGFloat = 6

    // MARK: 字号（pt）

    static let fontTiny: CGFloat = 8
    static let fontMicro: CGFloat = 8
}
