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
        BrandPalette(primary: Color(hex: 0x087F7A), primaryDark: Color(hex: 0x08635F),
                     gradientStart: Color(hex: 0x53B9AD), container: Color(hex: 0xDDEEE8)),
        BrandPalette(primary: Color(hex: 0x3B82F6), primaryDark: Color(hex: 0x1E5BC4),
                     gradientStart: Color(hex: 0x7FB5FF), container: Color(hex: 0xC9E0FF)),
        BrandPalette(primary: Color(hex: 0xE0457B), primaryDark: Color(hex: 0xB02E5C),
                     gradientStart: Color(hex: 0xF58FB0), container: Color(hex: 0xFCD3E1)),
        BrandPalette(primary: Color(hex: 0xF07B2F), primaryDark: Color(hex: 0xC05A16),
                     gradientStart: Color(hex: 0xF7B27D), container: Color(hex: 0xFDE3CC)),
        BrandPalette(primary: Color(hex: 0x2E9E5B), primaryDark: Color(hex: 0x1D7A42),
                     gradientStart: Color(hex: 0x74C99B), container: Color(hex: 0xD1F0DE)),
        BrandPalette(primary: Color(hex: 0x6C5CE7), primaryDark: Color(hex: 0x4A3FB8),
                     gradientStart: Color(hex: 0xA69CF5), container: Color(hex: 0xE1DDFC))
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
    static var onStrong: Color { Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red:16/255,green:29/255,blue:32/255,alpha:1) : .white }) }

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
            let hex: [UInt32] = [0x252422, 0x0E3D28, 0x0A6B38, 0x22A34A, 0x3DD15F]
            return Color(hex: hex[clamped])
        } else {
            let hex: [UInt32] = [0xE8E4DC, 0xC8EBD4, 0x86D4A4, 0x3AAD72, 0x1B7A4C]
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
    let track: Color
    let warn: Color
    let ok: Color
    let danger: Color
    let isDark: Bool

    static func of(_ scheme: ColorScheme) -> SoftPalette {
        if scheme == .dark {
            return SoftPalette(
                canvas: Color(hex: 0x101D20),
                surface: Color(hex: 0x192A2D),
                elevated: Color(hex: 0x22373B),
                text: Color(hex: 0xEDEDF0),
                muted: Color(hex: 0xA7BABD),
                track: Color.white.opacity(0.08),
                warn: Color(hex: 0xF39C12),
                ok: Color(hex: 0x27AE60),
                danger: Color(hex: 0xE74C3C),
                isDark: true
            )
        }
        return SoftPalette(
            canvas: Color(hex: 0xF6F7F2),
            surface: Color(hex: 0xFFFFFF),
            elevated: Color.white,
            text: Color(hex: 0x142D30),
            muted: Color(hex: 0x596D70),
            track: Color(red: 26/255, green: 26/255, blue: 28/255).opacity(0.08),
            warn: Color(hex: 0x9A5D08),
            ok: Color(hex: 0x237A49),
            danger: Color(hex: 0xC0392B),
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
