import SwiftUI

/// 圆润立体美漫标题字（双层硬投影 + SF Pro Rounded Heavy）
struct ComicBrandTitle: View {
    let text: String
    var size: CGFloat = 20
    var showShard: Bool = false
    @Environment(\.comic) private var comic

    var body: some View {
        HStack(spacing: 8) {
            if showShard {
                ComicShardMark(size: size)
            }
            ZStack(alignment: .topLeading) {
                Text(text)
                    .font(.system(size: size, weight: .heavy, design: .rounded))
                    .foregroundStyle(comic.heroShadow)
                    .offset(x: 1.6, y: 1.6)
                    .lineLimit(1)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.system(size: size, weight: .heavy, design: .rounded))
                    .foregroundStyle(comic.ink)
                    .lineLimit(1)
            }
        }
    }
}

/// 焦点大数字（1:1 复刻 `#221` 暖琥珀立体圆体大字 + 浅橘投影）
struct ComicHeroNumber: View {
    let text: String
    var size: CGFloat = 50
    @Environment(\.comic) private var comic

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(text)
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(comic.heroShadow)
                .offset(x: 2.2, y: 2.2)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(comic.hero)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

/// 漫风切角实体按键（按压 +1.5pt 下沉反馈，严禁橘底印白字）
struct ComicButtonStyle: ButtonStyle {
    enum Variant {
        case accent
        case surface
        case danger
    }

    var variant: Variant = .accent
    var cut: CGFloat = ThemeTokens.buttonCut
    var horizontalPadding: CGFloat = 14
    var verticalPadding: CGFloat = 8
    var expand: Bool = false

    @Environment(\.comic) private var comic
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && isEnabled
        let fill: Color = {
            switch variant {
            case .accent: return comic.accent
            case .surface: return comic.surface
            case .danger: return comic.danger
            }
        }()
        let fg: Color = {
            switch variant {
            case .accent: return comic.onAccent
            case .surface: return comic.ink
            case .danger: return Color(hex: 0xFFF5DF)
            }
        }()

        configuration.label
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(fg)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: expand ? .infinity : nil, minHeight: 36)
            .background {
                ZStack {
                    ChamferShape(cut: cut)
                        .fill(comic.shadow)
                        .offset(x: pressed ? 0.5 : 2.0, y: pressed ? 0.5 : 2.0)
                    ChamferShape(cut: cut)
                        .fill(fill)
                    ChamferShape(cut: cut)
                        .stroke(
                            comic.border,
                            style: StrokeStyle(lineWidth: ThemeTokens.strokeWidth, lineJoin: .round)
                        )
                }
            }
            .offset(x: pressed ? 1.5 : 0, y: pressed ? 1.5 : 0)
            .opacity(isEnabled ? 1.0 : 0.45)
            .animation(.easeOut(duration: 0.1), value: pressed)
    }
}

/// 底纸无框折叠/引导纯文字行（1:1 对标参考图 `› 网络与图表`）
struct ComicCollapsibleLine: View {
    let title: String
    var trailing: String? = nil
    var isExpanded: Bool? = nil
    var warn: Bool = false
    let action: () -> Void

    @Environment(\.comic) private var comic

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: (isExpanded == true) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(warn ? comic.warn : comic.muted)
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(warn ? comic.warn : comic.muted)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(comic.muted)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 底栏导航（未选中零边框，仅选中项衬奶油橙切角底块）

struct ComicTabItem: Identifiable {
    let id: Int
    let title: String
    let systemImage: String
}

struct ComicTabDock: View {
    @Binding var selection: Int
    let items: [ComicTabItem]
    var bottomPad: CGFloat = 6

    @Environment(\.comic) private var comic

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items) { item in
                let isSelected = selection == item.id
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        selection = item.id
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 14, weight: .bold))
                        Text(item.title.localized)
                            .font(.system(size: 13.5, weight: isSelected ? .heavy : .semibold, design: .rounded))
                            .lineLimit(1)
                    }
                    .foregroundStyle(isSelected ? comic.onAccent : comic.muted)
                    .padding(.horizontal, isSelected ? 12 : 8)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background {
                        if isSelected {
                            ZStack {
                                ChamferShape(cut: ThemeTokens.buttonCut)
                                    .fill(comic.shadow)
                                    .offset(x: 1.8, y: 1.8)
                                ChamferShape(cut: ThemeTokens.buttonCut)
                                    .fill(comic.accent)
                                ChamferShape(cut: ThemeTokens.buttonCut)
                                    .stroke(
                                        comic.border,
                                        style: StrokeStyle(lineWidth: ThemeTokens.strokeWidth, lineJoin: .round)
                                    )
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title.localized)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 9)
        .padding(.bottom, bottomPad)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("soft-tab-dock")
        .background {
            comic.canvas
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    ComicHairline(outer: true)
                }
        }
    }
}
