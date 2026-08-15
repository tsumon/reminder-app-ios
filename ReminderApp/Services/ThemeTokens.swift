import SwiftUI

/// 设计令牌（v1.8.7 任务⑤）— 双端统一（iOS 本文件 / Android Tokens.kt）
///
/// 一份令牌，两端各映射一份；新 UI 一律引用令牌，不写硬编码颜色/圆角/字号。
/// 主色统一为 Material Design 3 紫色 #6750A4。
enum ThemeTokens {

    // MARK: 品牌主色（双端统一 #6750A4）

    /// 主色：青碧 Teal #159A9C（v2.3.0 从 M3 紫换肤——清爽高效感，双端统一）
    static let brandPrimary = Color(red: 0x15 / 255.0, green: 0x9A / 255.0, blue: 0x9C / 255.0)

    // MARK: 状态色（与 Android 一致）

    /// 品牌深色主色（渐变末端，与 Android BrandPrimaryDark 一致）
    static let brandPrimaryDark = Color(red: 0x0E / 255.0, green: 0x6E / 255.0, blue: 0x70 / 255.0)
    /// v2.3.0: 品牌渐变起点（薄荷亮青，对齐 Android 0xFF4DB6AC）
    static let brandGradientStart = Color(red: 0x4D / 255.0, green: 0xB6 / 255.0, blue: 0xAC / 255.0)
    static let statusReminding = Color(red: 0xE7 / 255.0, green: 0x4C / 255.0, blue: 0x3C / 255.0)
    static let statusWaiting = Color(red: 0x34 / 255.0, green: 0x98 / 255.0, blue: 0xDB / 255.0)
    static let statusCompleted = Color(red: 0x27 / 255.0, green: 0xAE / 255.0, blue: 0x60 / 255.0)
    /// v1.9.8: 逾期（递增重试到上限，比提醒中更深一档的红色，与 Android StatusOverdue 一致）
    static let statusOverdue = Color(red: 0xC0 / 255.0, green: 0x39 / 255.0, blue: 0x2B / 255.0)
    /// v2.1.0: 稍后/已推迟（原各 View 硬编码 .orange，统一令牌，与 Android StatusSnoozed #F39C12 一致）
    static let statusSnoozed = Color(red: 0xF3 / 255.0, green: 0x9C / 255.0, blue: 0x12 / 255.0)

    // MARK: 节假日「休/班」

    /// 休（放假）红
    static let holidayRest = Color(red: 0xD3 / 255.0, green: 0x2F / 255.0, blue: 0x2F / 255.0)
    /// 班（调休上班）橙
    static let holidayWork = Color(red: 0xEF / 255.0, green: 0x6C / 255.0, blue: 0x00 / 255.0)

    // MARK: 热力图色阶（统计页，与 Android 一致；v2.1.0 由冷蓝统一为品牌紫系）

    static let heatmap0 = Color.gray.opacity(0.12)
    static let heatmap1 = brandPrimary.opacity(0.25)
    static let heatmap2 = brandPrimary.opacity(0.55)
    static let heatmap3 = brandPrimary

    // MARK: 圆角

    static let cardRadius: CGFloat = 16
    static let cellRadius: CGFloat = 6
    /// v2.1.0: 圆角梯度（替换各 View 硬编码 10/12/20/24）
    static let radiusSmall: CGFloat = 10
    static let radiusMedium: CGFloat = 12
    static let radiusLarge: CGFloat = 20
    static let radiusXLarge: CGFloat = 24

    // MARK: 字号（pt，与 Android FontTiny 9sp / FontMicro 8sp 对齐）

    static let fontTiny: CGFloat = 9
    static let fontMicro: CGFloat = 8
}
