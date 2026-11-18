import SwiftUI

/// 右上 + 左下 45° 斜切六边形（1:1 复刻 IOTA MONITOR 漫风印张）
struct ChamferShape: Shape {
    var cut: CGFloat = ThemeTokens.cardCut

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let c = min(cut, min(w, h) * 0.45)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - c, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + c, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - c))
        p.closeSubpath()
        return p
    }
}

/// 顶栏左侧不规则橙色几何块（1:1 复刻 IOTA MONITOR 标题前小印记）
struct ComicShardMark: View {
    @Environment(\.comic) private var comic
    var size: CGFloat = 18

    var body: some View {
        Canvas { ctx, s in
            let w = s.width
            let h = s.height
            var shard = Path()
            shard.move(to: CGPoint(x: w * 0.16, y: h * 0.06))
            shard.addLine(to: CGPoint(x: w * 0.84, y: h * 0.22))
            shard.addLine(to: CGPoint(x: w * 0.94, y: h * 0.82))
            shard.addLine(to: CGPoint(x: w * 0.42, y: h * 0.96))
            shard.addLine(to: CGPoint(x: w * 0.08, y: h * 0.72))
            shard.closeSubpath()
            ctx.fill(shard, with: .color(comic.accent))
        }
        .frame(width: size * 0.82, height: size)
        .accessibilityHidden(true)
    }
}

/// 通透暖奶油底纸画布
struct ComicCanvas: View {
    @Environment(\.comic) private var comic

    var body: some View {
        comic.canvas.ignoresSafeArea()
    }
}

/// 1pt 漫风分割细线（`outer = true` 用 `rule` 通栏焦糖线，否则用卡片内 `innerRule`）
struct ComicHairline: View {
    var outer: Bool = false
    @Environment(\.comic) private var comic

    var body: some View {
        Rectangle()
            .fill(outer ? comic.rule : comic.innerRule)
            .frame(height: 1)
    }
}

/// 极简奶油漫风主面板：零模糊硬投影（+2.2pt）+ 1.5pt 浓咖墨线 + 右上左下斜切角
struct ComicCard<Content: View>: View {
    var cut: CGFloat = ThemeTokens.cardCut
    var padding: CGFloat = 18
    var fill: Color? = nil
    @ViewBuilder var content: Content

    @Environment(\.comic) private var comic

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    ChamferShape(cut: cut)
                        .fill(comic.shadow)
                        .offset(x: ThemeTokens.shadowOffset, y: ThemeTokens.shadowOffset)
                    ChamferShape(cut: cut)
                        .fill(fill ?? comic.surface)
                    ChamferShape(cut: cut)
                        .stroke(
                            comic.border,
                            style: StrokeStyle(lineWidth: ThemeTokens.strokeWidth, lineJoin: .round)
                        )
                }
            }
    }
}
