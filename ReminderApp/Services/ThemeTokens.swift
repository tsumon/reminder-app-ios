import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

/// 极简奶油漫风（Minimalist Cream Comic）纸张与强调色规格
struct ComicPaperSpec {
    let name: String
    let canvas: UInt32
    let surface: UInt32
    let ink: UInt32
    let muted: UInt32
    let rule: UInt32
    let innerRule: UInt32
    let accent: UInt32
    let onAccent: UInt32
    let hero: UInt32
    let heroShadow: UInt32
    let dotEmpty: UInt32
}

/// 运行时生效的漫风语义色板（通过 `@Environment(\.comic)` 注入全树）
struct ComicPalette {
    let paperName: String
    let canvas: Color
    let surface: Color
    let elevated: Color
    let ink: Color
    let border: Color
    let shadow: Color
    let muted: Color
    let rule: Color
    let innerRule: Color
    let accent: Color
    let onAccent: Color
    let hero: Color
    let heroShadow: Color
    let dotEmpty: Color
    let warn: Color
    let ok: Color
    let danger: Color
    let isDark: Bool

    static let specs: [ComicPaperSpec] = [
        // 0: 奶油橙（默认，1:1 取样自 IOTA MONITOR）
        ComicPaperSpec(
            name: "奶油橙",
            canvas: 0xF6E5C8, surface: 0xFFF5DF, ink: 0x472714, muted: 0x6D503B,
            rule: 0xCDA780, innerRule: 0xE5CCA9, accent: 0xF06A29, onAccent: 0x27140B,
            hero: 0x774501, heroShadow: 0xFCC5A2, dotEmpty: 0xECD9BC
        ),
        // 1: 抹茶奶纸
        ComicPaperSpec(
            name: "抹茶奶纸",
            canvas: 0xE5EFE0, surface: 0xFBFDF8, ink: 0x1F3524, muted: 0x536E58,
            rule: 0xB5CBB0, innerRule: 0xD5E4D1, accent: 0x58A973, onAccent: 0x132919,
            hero: 0x265938, heroShadow: 0xBCE0C6, dotEmpty: 0xD2E2CE
        ),
        // 2: 海盐汽水
        ComicPaperSpec(
            name: "海盐汽水",
            canvas: 0xE3EDF6, surface: 0xF9FCFF, ink: 0x1B2D42, muted: 0x526982,
            rule: 0xB4C8DC, innerRule: 0xD3E1EE, accent: 0x4A8FE7, onAccent: 0x102238,
            hero: 0x1E4C8A, heroShadow: 0xBDD6F7, dotEmpty: 0xCFE0EE
        ),
        // 3: 莓果奶昔
        ComicPaperSpec(
            name: "莓果奶昔",
            canvas: 0xF4E4EA, surface: 0xFFF8FA, ink: 0x3D1C28, muted: 0x734D5B,
            rule: 0xD9B6C3, innerRule: 0xEBD4DC, accent: 0xE05A8B, onAccent: 0x2B0E19,
            hero: 0x7A2444, heroShadow: 0xF5C2D4, dotEmpty: 0xE8CED7
        ),
        // 4: 黄油柠檬
        ComicPaperSpec(
            name: "黄油柠檬",
            canvas: 0xF6EECA, surface: 0xFFFDF0, ink: 0x3D2E10, muted: 0x6E5B35,
            rule: 0xD6C48E, innerRule: 0xE8DCB6, accent: 0xE59A24, onAccent: 0x291B05,
            hero: 0x734B08, heroShadow: 0xF5DC9B, dotEmpty: 0xE8DFB9
        ),
        // 5: 复古电紫
        ComicPaperSpec(
            name: "复古电紫",
            canvas: 0xEAE4F4, surface: 0xFAF8FF, ink: 0x2A1E3D, muted: 0x5E5075,
            rule: 0xC2B5D9, innerRule: 0xDAD1EA, accent: 0x8B6CE8, onAccent: 0x190E2E,
            hero: 0x482B85, heroShadow: 0xD4C4F7, dotEmpty: 0xD7CEE8
        )
    ]

    static func spec(at index: Int) -> ComicPaperSpec {
        specs.indices.contains(index) ? specs[index] : specs[0]
    }

    static func of(_ scheme: ColorScheme, colorIndex: Int = ThemeStore.colorIndex) -> ComicPalette {
        let p = spec(at: colorIndex)
        if scheme == .dark {
            // 暗夜暖琥珀（Nocturnal Ink）
            return ComicPalette(
                paperName: p.name,
                canvas: Color(hex: 0x1B1613),
                surface: Color(hex: 0x261F1B),
                elevated: Color(hex: 0x2E2520),
                ink: Color(hex: 0xF3E3CF),
                border: Color(hex: 0xC9AE92),
                shadow: Color(hex: 0x0B0807),
                muted: Color(hex: 0xA38D78),
                rule: Color(hex: 0x3E322A),
                innerRule: Color(hex: 0x382D26),
                accent: Color(hex: p.accent),
                onAccent: Color(hex: 0x1F0E05),
                hero: Color(hex: 0xF6A86E),
                heroShadow: Color(hex: 0x4A240B),
                dotEmpty: Color(hex: 0x342A24),
                warn: Color(hex: 0xF3A847),
                ok: Color(hex: 0x62C388),
                danger: Color(hex: 0xEE7762),
                isDark: true
            )
        }
        return ComicPalette(
            paperName: p.name,
            canvas: Color(hex: p.canvas),
            surface: Color(hex: p.surface),
            elevated: Color(hex: p.surface),
            ink: Color(hex: p.ink),
            border: Color(hex: p.ink),
            shadow: Color(hex: p.ink),
            muted: Color(hex: p.muted),
            rule: Color(hex: p.rule),
            innerRule: Color(hex: p.innerRule),
            accent: Color(hex: p.accent),
            onAccent: Color(hex: p.onAccent),
            hero: Color(hex: p.hero),
            heroShadow: Color(hex: p.heroShadow),
            dotEmpty: Color(hex: p.dotEmpty),
            warn: Color(hex: 0x9E550E),
            ok: Color(hex: 0x2F6F44),
            danger: Color(hex: 0xB83B28),
            isDark: false
        )
    }
}

private struct ComicPaletteKey: EnvironmentKey {
    static let defaultValue = ComicPalette.of(.light, colorIndex: 0)
}

extension EnvironmentValues {
    var comic: ComicPalette {
        get { self[ComicPaletteKey.self] }
        set { self[ComicPaletteKey.self] = newValue }
    }
}

/// 全局令牌与辅助色（双端极简奶油漫风对齐）
enum ThemeTokens {
    struct BrandPalette {
        let name: String
        let canvas: Color
        let surface: Color
        let primary: Color
        let onPrimary: Color
        let ink: Color
    }

    static var palettes: [BrandPalette] {
        ComicPalette.specs.map {
            BrandPalette(
                name: $0.name,
                canvas: Color(hex: $0.canvas),
                surface: Color(hex: $0.surface),
                primary: Color(hex: $0.accent),
                onPrimary: Color(hex: $0.onAccent),
                ink: Color(hex: $0.ink)
            )
        }
    }

    static var currentSpec: ComicPaperSpec {
        ComicPalette.spec(at: ThemeStore.colorIndex)
    }

    static var brandPrimary: Color { strong }
    static var strong: Color { Color(hex: currentSpec.accent) }
    static var onStrong: Color {
        Color(uiColor: UIColor { trait in
            UIColor(Color(hex: trait.userInterfaceStyle == .dark ? 0x1F0E05 : currentSpec.onAccent))
        })
    }

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            UIColor(Color(hex: trait.userInterfaceStyle == .dark ? dark : light))
        })
    }

    static let statusReminding = adaptive(0xC94E20, 0xF48B5F)
    static let statusWaiting = adaptive(0x6D503B, 0xA38D78)
    static let statusCompleted = adaptive(0x2F6F44, 0x62C388)
    static let statusOverdue = adaptive(0xB83B28, 0xEE7762)
    static let statusSnoozed = adaptive(0x9E550E, 0xF3A847)

    static let holidayRest = adaptive(0xB83B28, 0xEE7762)
    static let holidayWork = adaptive(0x9E550E, 0xF3A847)

    static func heat(_ level: Int, comic: ComicPalette) -> Color {
        let clamped = min(max(level, 0), 4)
        switch clamped {
        case 0: return comic.dotEmpty
        case 1: return comic.accent.opacity(comic.isDark ? 0.30 : 0.28)
        case 2: return comic.accent.opacity(comic.isDark ? 0.52 : 0.50)
        case 3: return comic.accent.opacity(comic.isDark ? 0.76 : 0.75)
        default: return comic.accent
        }
    }

    static let gutter: CGFloat = 16
    static let cardCut: CGFloat = 11
    static let buttonCut: CGFloat = 5.5
    static let strokeWidth: CGFloat = 1.5
    static let shadowOffset: CGFloat = 2.2
    static let dockH: CGFloat = 50
}
