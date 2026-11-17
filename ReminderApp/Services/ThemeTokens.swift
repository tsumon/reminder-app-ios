import SwiftUI
import UIKit

/// 设计令牌 — soft-ui v2（Joe 2026-09-05）
/// 双端对齐：iOS 本文件 / Android Tokens.kt
enum ThemeTokens {

    // MARK: 品牌主色（六色皮肤 → `--strong`，默认青碧）

    struct BrandPalette {
        let primary: Color
        let primaryDark: Color
        let gradientStart: Color
        let container: Color
    }

    static let palettes: [BrandPalette] = [
        BrandPalette(primary: Color(hex: 0x0F766E), primaryDark: Color(hex: 0x115E59),
                     gradientStart: Color(hex: 0x2DD4BF), container: Color(hex: 0xCCFBF1)),
        BrandPalette(primary: Color(hex: 0x2563EB), primaryDark: Color(hex: 0x1D4ED8),
                     gradientStart: Color(hex: 0x60A5FA), container: Color(hex: 0xDBEAFE)),
        BrandPalette(primary: Color(hex: 0xD9467A), primaryDark: Color(hex: 0xBE185D),
                     gradientStart: Color(hex: 0xF472B6), container: Color(hex: 0xFCE7F3)),
        BrandPalette(primary: Color(hex: 0xEA580C), primaryDark: Color(hex: 0xC2410C),
                     gradientStart: Color(hex: 0xFB923C), container: Color(hex: 0xFFEDD5)),
        BrandPalette(primary: Color(hex: 0x16A34A), primaryDark: Color(hex: 0x15803D),
                     gradientStart: Color(hex: 0x4ADE80), container: Color(hex: 0xDCFCE7)),
        BrandPalette(primary: Color(hex: 0x6D28D9), primaryDark: Color(hex: 0x5B21B6),
                     gradientStart: Color(hex: 0xA78BFA), container: Color(hex: 0xEDE9FE))
    ]

    static var palette: BrandPalette {
        let i = UserDefaults.standard.integer(forKey: "theme_color_index")
        return palettes.indices.contains(i) ? palettes[i] : palettes[0]
    }

    static var brandPrimary: Color { strong }
    static var brandPrimaryDark: Color { palette.primaryDark }
    static var brandGradientStart: Color { palette.gradientStart }
    static var brandContainer: Color { palette.container }
    /// `--strong`
    static var strong: Color { Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(palette.gradientStart) : UIColor(palette.primary) }) }
    static var onStrong: Color { Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: 0x091917)) : .white }) }

    private static func adaptive(_ light: UInt32,_ dark: UInt32) -> Color {
        Color(uiColor:UIColor { trait in UIColor(Color(hex:trait.userInterfaceStyle == .dark ? dark : light)) })
    }

    // MARK: 状态色

    static let statusReminding = adaptive(0xBD4436, 0xFF8A80)
    static let statusWaiting = adaptive(0x25669A, 0x8DBEF0)
    static let statusCompleted = adaptive(0x237A49, 0x66D99E)
    static let statusOverdue = adaptive(0xC0392B, 0xFF8A80)
    static let statusSnoozed = adaptive(0x9A5D08, 0xF9B649)

    static let holidayRest = Color(hex: 0xD32F2F)
    static let holidayWork = Color(hex: 0xEF6C00)

    // MARK: 热力（仅统计页）

    static func heat(_ level: Int, scheme: ColorScheme) -> Color {
        let clamped = min(max(level, 0), 4)
        if scheme == .dark {
            let hex: [UInt32] = [0x22262B, 0x11423D, 0x0F6B62, 0x14B8A6, 0x2DD4BF]
            return Color(hex: hex[clamped])
        } else {
            let hex: [UInt32] = [0xEBE6DC, 0xCCFBF1, 0x5EEAD4, 0x0D9488, 0x0F766E]
            return Color(hex: hex[clamped])
        }
    }

    static let heatmap0 = Color.gray.opacity(0.12)
    static let heatmap1 = brandPrimary.opacity(0.25)
    static let heatmap2 = brandPrimary.opacity(0.55)
    static let heatmap3 = brandPrimary

    // MARK: 圆角 / 尺寸

    static let radiusShallow: CGFloat = 12
    static let radiusCard: CGFloat = 16
    static let radiusElevated: CGFloat = 18
    static let radiusChip: CGFloat = 16
    static let radiusFull: CGFloat = 999
    static let btnCircle: CGFloat = 44
    static let btnInner: CGFloat = 6
    static let chipH: CGFloat = 32
    static let rowBadge: CGFloat = 44
    static let gutter: CGFloat = 16
    static let cardPad: CGFloat = 14
    static let cardGap: CGFloat = 8
    static let dockH: CGFloat = 48
    static let dockSelected: CGFloat = 32
    static let dockPadTop: CGFloat = 3
    static let dockPadBottom: CGFloat = 4
    /// Home-indicator pill (~5) + inset from the physical bottom (~8).
    static let dockIndicator: CGFloat = 13
    static let dockBottomGap: CGFloat = 0
    static let settingsGroupPadX: CGFloat = 16
    static let settingsGroupPadY: CGFloat = 4
    static let settingsRowH: CGFloat = 52
    static let settingsRowH2: CGFloat = 64
    static let settingsRowPadX: CGFloat = 16
    static let settingsRowPadY: CGFloat = 14
    static let settingsRowPadY2: CGFloat = 12
    static let settingsGroupGap: CGFloat = 16
    static let settingsThemeDot: CGFloat = 28

    static let cardRadius: CGFloat = 16
    static let cellRadius: CGFloat = 6
    static let radiusSmall: CGFloat = 10
    static let radiusMedium: CGFloat = 12
    static let radiusLarge: CGFloat = 18
    static let radiusXLarge: CGFloat = 24

    static let fontTiny: CGFloat = 9
    static let fontMicro: CGFloat = 8

    static let titleSize: CGFloat = 22
    static let titleLine: CGFloat = 28
    static let sectionSize: CGFloat = 19
    static let sectionLine: CGFloat = 24
    static let bodySize: CGFloat = 14.5
    static let bodyLine: CGFloat = 18
}

// MARK: - Soft 语义色（浅纸 / 深抬升）

struct SoftPalette {
    let canvas: Color
    let surface: Color
    let elevated: Color
    let text: Color
    let muted: Color
    let border: Color
    let track: Color
    let warn: Color
    let ok: Color
    let danger: Color
    let isDark: Bool

    static func of(_ scheme: ColorScheme) -> SoftPalette {
        if scheme == .dark {
            return SoftPalette(
                canvas: Color(hex: 0x111315),
                surface: Color(hex: 0x1A1D20),
                elevated: Color(hex: 0x22262B),
                text: Color(hex: 0xF4F4F5),
                muted: Color(hex: 0x94A3B8),
                border: Color(hex: 0x2A2F35),
                track: Color.white.opacity(0.08),
                warn: Color(hex: 0xF59E0B),
                ok: Color(hex: 0x34D399),
                danger: Color(hex: 0xF87171),
                isDark: true
            )
        }
        return SoftPalette(
            canvas: Color(hex: 0xF6F4EF),
            surface: Color(hex: 0xFFFFFF),
            elevated: Color(hex: 0xFFFFFF),
            text: Color(hex: 0x18181B),
            muted: Color(hex: 0x64748B),
            border: Color(hex: 0xE7E2D8),
            track: Color(hex: 0x18181B).opacity(0.08),
            warn: Color(hex: 0xD97706),
            ok: Color(hex: 0x059669),
            danger: Color(hex: 0xDC2626),
            isDark: false
        )
    }
}

private struct SoftPaletteKey: EnvironmentKey {
    static let defaultValue = SoftPalette.of(.light)
}

extension EnvironmentValues {
    var soft: SoftPalette {
        get { self[SoftPaletteKey.self] }
        set { self[SoftPaletteKey.self] = newValue }
    }
}

// MARK: - 锁死字号

enum SoftType {
    static var title: Font { .title.bold() }
    static var section: Font { .headline }
    static var body: Font { .body }
    static var bodyMedium: Font { .body.weight(.medium) }
    static var chip: Font { .subheadline.weight(.medium) }
    static var caption: Font { .caption }
    static var retry: Font { .subheadline }
    static var tab: Font { .caption2.weight(.medium) }
    static var calendarLunar: Font { .caption2 }
    static var confirm: Font { .body.weight(.semibold) }
    static var meter: Font { .title2.bold() }
}

extension View {
    func titleTracking() -> some View { tracking(-0.7) }
    func sectionTracking() -> some View { tracking(0.6) }
    func bodyTracking() -> some View { tracking(0.3) }
    func meterTracking() -> some View { tracking(-0.7) }
}
