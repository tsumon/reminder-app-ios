import SwiftUI

// MARK: - 纸面画布

struct PaperCanvas: View {
    @Environment(\.soft) private var soft
    var body: some View {
        soft.canvas.ignoresSafeArea()
    }
}

// MARK: - Soft shadow card（锤子纸面光影；无 BorderStroke）

enum SoftShadowKind {
    case sm, card, elevated
}

struct SoftShadowCard<Content: View>: View {
    var kind: SoftShadowKind = .card
    var radius: CGFloat = ThemeTokens.radiusCard
    var fill: Color? = nil
    var padding: CGFloat? = nil
    @ViewBuilder var content: Content

    @Environment(\.soft) private var soft

    var body: some View {
        content
            .padding(padding ?? 0)
            .modifier(SoftElevation(kind: kind, radius: radius, fill: cardFill))
    }

    private var cardFill: Color {
        fill ?? (kind == .elevated ? soft.elevated : soft.surface)
    }
}

/// DESIGN Shadow：多层 `.shadow` + overlay 模拟 inset；暗色 hairline 是 1pt spread，不是 `.stroke()`。
private struct SoftElevation: ViewModifier {
    var kind: SoftShadowKind
    var radius: CGFloat
    var fill: Color
    /// Bottom corners; `nil` matches `radius`. Dock uses 0 so fill can square off at the physical bottom.
    var bottomRadius: CGFloat? = nil
    @Environment(\.soft) private var soft

    func body(content: Content) -> some View {
        let br = bottomRadius ?? radius
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: radius,
            bottomLeadingRadius: br,
            bottomTrailingRadius: br,
            topTrailingRadius: radius,
            style: .continuous
        )
        content
            .background {
                ZStack {
                    if soft.isDark {
                        shape.fill(Color.white.opacity(hairlineOpacity))
                            .padding(-1)
                    }
                    shape.fill(fill)
                }
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(insetOpacity), location: 0),
                        .init(color: Color.white.opacity(insetOpacity * 0.35), location: 0.035),
                        .init(color: Color.clear, location: 0.12)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(shape)
                .allowsHitTesting(false)
            }
            .shadow(color: drop1.color, radius: drop1.blur, x: 0, y: drop1.y)
            .shadow(color: drop2.color, radius: drop2.blur, x: 0, y: drop2.y)
            .shadow(color: drop3.color, radius: drop3.blur, x: 0, y: drop3.y)
    }

    private var hairlineOpacity: Double {
        switch kind {
        case .sm: return 0.05
        case .card: return 0.08
        case .elevated: return 0.10
        }
    }

    private var insetOpacity: Double {
        if soft.isDark {
            switch kind {
            case .sm: return 0
            case .card: return 0.10
            case .elevated: return 0.14
            }
        }
        switch kind {
        case .sm: return 0
        case .card: return 0.85
        case .elevated: return 0.95
        }
    }

    private var drop1: (color: Color, blur: CGFloat, y: CGFloat) {
        if soft.isDark {
            switch kind {
            case .sm: return (Color.black.opacity(0.40), 2, 1)
            case .card: return (Color.black.opacity(0.45), 8, 4)
            case .elevated: return (Color.black.opacity(0.50), 12, 6)
            }
        }
        let ink = Color(hex: 0x111111)
        switch kind {
        case .sm: return (ink.opacity(0.05), 1, 1)
        case .card: return (ink.opacity(0.06), 2, 1)
        case .elevated: return (ink.opacity(0.06), 4, 2)
        }
    }

    private var drop2: (color: Color, blur: CGFloat, y: CGFloat) {
        if soft.isDark {
            switch kind {
            case .sm: return (.clear, 0, 0)
            case .card: return (Color.black.opacity(0.50), 32, 12)
            case .elevated: return (Color.black.opacity(0.55), 40, 16)
            }
        }
        let ink = Color(hex: 0x111111)
        switch kind {
        case .sm: return (ink.opacity(0.05), 4, 2)
        case .card: return (ink.opacity(0.06), 12, 6)
        case .elevated: return (ink.opacity(0.07), 16, 8)
        }
    }

    private var drop3: (color: Color, blur: CGFloat, y: CGFloat) {
        if soft.isDark { return (.clear, 0, 0) }
        let ink = Color(hex: 0x111111)
        switch kind {
        case .sm: return (.clear, 0, 0)
        case .card: return (ink.opacity(0.08), 32, 14)
        case .elevated: return (ink.opacity(0.08), 40, 16)
        }
    }
}

extension View {
    func softShadowCard(kind: SoftShadowKind = .card, radius: CGFloat = ThemeTokens.radiusCard) -> some View {
        SoftShadowCard(kind: kind, radius: radius, padding: 0) { self }
    }
}

// MARK: - 38–46 软圆钮

struct SoftCircleChrome<Content: View>: View {
    var size: CGFloat = ThemeTokens.btnCircle
    var fill: Color? = nil
    @ViewBuilder var content: Content
    @Environment(\.soft) private var soft

    var body: some View {
        ZStack {
            Circle().fill(fill ?? soft.surface)
            Circle()
                .fill(
                    LinearGradient(
                        stops: soft.isDark
                            ? [
                                .init(color: Color.white.opacity(0.16), location: 0),
                                .init(color: Color.white.opacity(0.06), location: 0.22),
                                .init(color: Color.clear, location: 0.62)
                            ]
                            : [
                                .init(color: Color.white.opacity(0.95), location: 0),
                                .init(color: Color.white.opacity(0.50), location: 0.28),
                                .init(color: Color.clear, location: 0.62)
                            ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            content
        }
        .frame(width: size, height: size)
        .background {
            if soft.isDark {
                Circle().fill(Color.white.opacity(0.10)).padding(-1)
            }
        }
        .shadow(
            color: soft.isDark ? Color.black.opacity(0.50) : Color(hex: 0x111111).opacity(0.06),
            radius: soft.isDark ? 20 : 2,
            y: soft.isDark ? 8 : 1
        )
        .shadow(
            color: soft.isDark ? .clear : Color(hex: 0x111111).opacity(0.10),
            radius: 16,
            y: 6
        )
    }
}

struct SoftCircleButton<Label: View>: View {
    var size: CGFloat = ThemeTokens.btnCircle
    var fill: Color? = nil
    var action: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        Button(action: action) {
            SoftCircleChrome(size: size, fill: fill) { label }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 凹陷搜索

struct SoftInsetSearch: View {
    @Binding var text: String
    var placeholder: String = "搜索提醒、日期..."
    var focused: FocusState<Bool>.Binding? = nil

    @Environment(\.soft) private var soft

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(soft.muted)
            Group {
                if let focused {
                    TextField("", text: $text, prompt: Text(placeholder.localized).foregroundStyle(soft.muted.opacity(0.85)))
                        .focused(focused)
                } else {
                    TextField("", text: $text, prompt: Text(placeholder.localized).foregroundStyle(soft.muted.opacity(0.85)))
                }
            }
            .font(SoftType.body)
            .foregroundStyle(soft.text)
            .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(soft.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空搜索".localized)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(soft.isDark ? Color.black.opacity(0.35) : Color(hex: 0xE8E8E4))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.black.opacity(soft.isDark ? 0.45 : 0.06), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(soft.isDark ? 0.35 : 0.06), radius: 2, y: 1)
        .accessibilityIdentifier("home-search")
    }
}

// MARK: - Chip

struct SoftChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    @Environment(\.soft) private var soft

    var body: some View {
        Button(action: action) {
            Text(title.localized)
                .font(SoftType.chip)
                .foregroundStyle(selected ? ThemeTokens.onStrong : soft.muted)
                .padding(.horizontal, 14)
                .frame(height: ThemeTokens.chipH)
                .background {
                    ZStack {
                        if soft.isDark && !selected {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.05))
                                .padding(-1)
                        }
                        Capsule(style: .continuous)
                            .fill(selected ? ThemeTokens.strong : soft.surface)
                    }
                }
                .shadow(
                    color: selected ? .clear : (soft.isDark ? Color.black.opacity(0.40) : Color(hex: 0x111111).opacity(0.05)),
                    radius: selected ? 0 : (soft.isDark ? 2 : 1),
                    y: selected ? 0 : 1
                )
                .shadow(
                    color: selected || soft.isDark ? .clear : Color(hex: 0x111111).opacity(0.05),
                    radius: 4,
                    y: 2
                )
        }
        .buttonStyle(.plain)
        .animation(.timingCurve(0.25, 1, 0.5, 1, duration: 0.18), value: selected)
    }
}

// MARK: - 分组标题 3×12 色条

struct SoftSectionHeader: View {
    let title: String
    let color: Color
    let count: Int

    @Environment(\.soft) private var soft

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(color)
                .frame(width: 3, height: 12)
            Text("\(title.localized) · \(count)")
                .font(SoftType.section)
                .foregroundStyle(soft.text)
            Spacer()
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
        .padding(.horizontal, 4)
    }
}

// MARK: - 待处理 soft 环

struct PendingCountRing: View {
    let count: Int
    var progress: Double = 0

    @Environment(\.soft) private var soft

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(soft.track.opacity(soft.isDark ? 1 : 1.6), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                    .stroke(ThemeTokens.strong,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(count)")
                    .font(SoftType.meter)
                    .meterTracking()
                    .foregroundStyle(ThemeTokens.strong)
            }
            .frame(width: 52, height: 52)
            Text("待处理".localized)
                .font(SoftType.caption)
                .foregroundStyle(soft.muted)
        }
    }
}

// MARK: - 厚描边 soft donut

struct SoftDonutChart: View {
    let rate: Double
    let confirm: Int
    let missed: Int

    @Environment(\.soft) private var soft

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                ring(radius: 54, stroke: 12, progress: rate, color: ThemeTokens.strong)
                ring(radius: 38, stroke: 12, progress: confirmShare, color: soft.ok)
                ring(radius: 22, stroke: 11, progress: missedShare, color: soft.danger)
            }
            .frame(width: 124, height: 124)

            VStack(alignment: .leading, spacing: 12) {
                legend(color: ThemeTokens.strong, label: "完成率",
                       value: "\(Int((rate * 100).rounded()))%")
                legend(color: soft.ok, label: "确认", value: "\(confirm)")
                legend(color: soft.danger, label: "漏掉", value: "\(missed)")
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var confirmShare: Double {
        let t = confirm + missed
        guard t > 0 else { return 0 }
        return Double(confirm) / Double(t)
    }

    private var missedShare: Double {
        let t = confirm + missed
        guard t > 0 else { return 0 }
        return Double(missed) / Double(t)
    }

    private func ring(radius: CGFloat, stroke: CGFloat, progress: Double, color: Color) -> some View {
        let gap: Double = 0.08
        let p = min(max(progress, 0), 1)
        let diameter = radius * 2
        return ZStack {
            Circle()
                .stroke(soft.isDark ? Color.white.opacity(0.06) : Color(hex: 0x111111).opacity(0.06),
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .frame(width: diameter, height: diameter)
                .shadow(color: Color.black.opacity(soft.isDark ? 0.35 : 0.06), radius: 4, y: 2)
            if p > 0.002 {
                Circle()
                    .trim(from: 0, to: CGFloat(max(0, p - gap)))
                    .stroke(
                        AngularGradient(
                            colors: [color.opacity(0.75), color, color.opacity(0.9)],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                    )
                    .frame(width: diameter, height: diameter)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.28), radius: 3, y: 1)
                Circle()
                    .trim(from: 0, to: CGFloat(max(0, p - gap)))
                    .stroke(
                        Color.white.opacity(soft.isDark ? 0.28 : 0.40),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                    )
                    .frame(width: diameter - stroke * 0.55, height: diameter - stroke * 0.55)
                    .rotationEffect(.degrees(-90))
            }
        }
        // stroke 画在 path 中线，外半圈会被 frame 裁掉而变细 flat；垫半个线宽对齐 Android Canvas
        .padding(stroke / 2)
    }

    private func legend(color: Color, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label.localized)
                .font(SoftType.caption)
                .foregroundStyle(soft.muted)
            Spacer()
            Text(value)
                .font(SoftType.section)
                .foregroundStyle(soft.text)
        }
    }
}

// MARK: - 44×44 emoji 井（radius 12，柔和色，不是 SF Symbol 方块）

struct SoftEmojiWell: View {
    let emoji: String
    var tint: Color = ThemeTokens.brandContainer
    @Environment(\.soft) private var soft

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ThemeTokens.radiusShallow, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(soft.isDark ? 0.38 : 0.72),
                            tint.opacity(soft.isDark ? 0.16 : 0.38)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(emoji)
                .font(.system(size: 22))
        }
        .frame(width: ThemeTokens.rowBadge, height: ThemeTokens.rowBadge)
        .accessibilityHidden(true)
    }
}

// MARK: - GitHub 圆角热力格子（仅统计）

struct CheckInHeatmap: View {
    let counts: [String: Int]
    var weeks: Int = 16

    @Environment(\.soft) private var soft
    @Environment(\.colorScheme) private var scheme

    private let cal = Calendar.current
    private let rowLabels = ["一", "", "三", "", "五", "", "日"]
    private let cellGap: CGFloat = 3
    private let labelWidth: CGFloat = 14

    var body: some View {
        let cells = gridCells()
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("本月打卡".localized)
                    .font(SoftType.section)
                    .foregroundStyle(soft.text)
                Spacer()
                Text("\(weeks) 周")
                    .font(SoftType.caption)
                    .foregroundStyle(soft.muted)
            }

            Grid(alignment: .leading, horizontalSpacing: cellGap, verticalSpacing: cellGap) {
                GridRow {
                    Color.clear.frame(width: labelWidth, height: 10)
                    ForEach(0..<weeks, id: \.self) { w in
                        let weekMonths = Set((0..<7).map { cells[w * 7 + $0].month })
                        let seen = Set((0..<(w * 7)).map { cells[$0].month })
                        let fresh = weekMonths.subtracting(seen)
                        let month = fresh.min() ?? cells[w * 7].month
                        Text(w == 0 || !fresh.isEmpty ? "\(month)月" : "")
                            .font(.system(size: 9))
                            .foregroundStyle(soft.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                ForEach(0..<7, id: \.self) { r in
                    GridRow {
                        Text(rowLabels[r])
                            .font(.system(size: 9, weight: .regular))
                            .foregroundStyle(soft.muted)
                            .frame(width: labelWidth, alignment: .leading)
                        ForEach(0..<weeks, id: \.self) { w in
                            let cell = cells[w * 7 + r]
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(ThemeTokens.heat(level(cell.count), scheme: scheme))
                                .overlay {
                                    if cell.isToday {
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .strokeBorder(ThemeTokens.strong, lineWidth: 1.4)
                                    }
                                }
                                .aspectRatio(1, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            HStack {
                Text("本周花园 · 打卡越多格子越深".localized)
                    .font(SoftType.caption)
                    .foregroundStyle(soft.muted)
                Spacer()
                HStack(spacing: 3) {
                    Text("少")
                        .font(.system(size: 9))
                        .foregroundStyle(soft.muted)
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(ThemeTokens.heat(i, scheme: scheme))
                            .frame(width: 10, height: 10)
                    }
                    Text("多")
                        .font(.system(size: 9))
                        .foregroundStyle(soft.muted)
                }
            }
        }
        .padding(16)
    }

    private struct Cell {
        let date: Date
        let count: Int
        let isToday: Bool
        let month: Int
    }

    private func gridCells() -> [Cell] {
        let today = cal.startOfDay(for: Date())
        let weekday = (cal.component(.weekday, from: today) + 5) % 7
        let thisMonday = cal.date(byAdding: .day, value: -weekday, to: today) ?? today
        let start = cal.date(byAdding: .day, value: -(weeks - 1) * 7, to: thisMonday) ?? thisMonday
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        var out: [Cell] = []
        for i in 0..<(weeks * 7) {
            let d = cal.date(byAdding: .day, value: i, to: start) ?? start
            let key = df.string(from: d)
            out.append(Cell(
                date: d,
                count: counts[key] ?? 0,
                isToday: cal.isDate(d, inSameDayAs: today),
                month: cal.component(.month, from: d)
            ))
        }
        return out
    }

    private func level(_ count: Int) -> Int {
        min(count, 4)
    }
}

// MARK: - 悬浮 pill dock

struct SoftTabItem: Identifiable {
    let id: Int
    let title: String
    let systemImage: String
}

struct SoftTabDock: View {
    @Binding var selection: Int
    let items: [SoftTabItem]
    var bottomPad: CGFloat = ThemeTokens.dockPadBottom

    @Environment(\.soft) private var soft

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    withAnimation(.timingCurve(0.25, 1, 0.5, 1, duration: 0.18)) {
                        selection = item.id
                    }
                } label: {
                    VStack(spacing: 2) {
                        ZStack {
                            if selection == item.id {
                                Circle()
                                    .fill(ThemeTokens.strong)
                                    .frame(width: ThemeTokens.dockSelected, height: ThemeTokens.dockSelected)
                            }
                            Image(systemName: item.systemImage)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(selection == item.id ? ThemeTokens.onStrong : soft.muted)
                        }
                        .frame(width: ThemeTokens.dockSelected, height: ThemeTokens.dockSelected)
                        Text(item.title.localized)
                            .font(SoftType.tab)
                            .foregroundStyle(selection == item.id ? ThemeTokens.strong : soft.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: ThemeTokens.dockH, alignment: .top)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title.localized)
            }
        }
        .padding(.horizontal, ThemeTokens.gutter)
        .padding(.top, ThemeTokens.dockPadTop)
        .padding(.bottom, bottomPad)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            // Full-width elevated fill to the physical bottom (home-indicator sits on --elevated).
            // Icon row uses a small top pad — not vertically centered in this skirt.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: ThemeTokens.dockPadTop + ThemeTokens.dockH + bottomPad + 80)
                .modifier(SoftElevation(
                    kind: .elevated,
                    radius: ThemeTokens.radiusElevated,
                    fill: soft.elevated,
                    bottomRadius: 0
                ))
        }
    }
}

// MARK: - 自定义顶栏

/// 隐藏 List/NavigationLink 系统 `>`。确认行必须无箭头；等待中行用自定义 chevron。
/// 不调用 iOS 26 才有的 NavLink 指示器 API：CI 的 Xcode 16 SDK 没有该符号。
struct HideNavLinkChevron: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

struct SoftScreenHeader<Leading: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    @Environment(\.soft) private var soft

    var body: some View {
        ZStack {
            Text(title.localized)
                .font(SoftType.title)
                .foregroundStyle(soft.text)
                .lineLimit(1)
            HStack(spacing: 0) {
                leading
                Spacer(minLength: 8)
                trailing
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(minHeight: 52)
    }
}
