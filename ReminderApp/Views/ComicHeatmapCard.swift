import SwiftUI

/// 无黑框暖色圆润点阵热力轨迹（16 周）
struct ComicHeatmapCard: View {
    let counts: [String: Int]
    var weeks: Int = 16

    @Environment(\.comic) private var comic
    private let cal = Calendar.current
    private let rowLabels = ["一", "", "三", "", "五", "", "日"]
    private let cellGap: CGFloat = 3.5
    private let labelWidth: CGFloat = 14

    var body: some View {
        let cells = gridCells()
        ComicCard(cut: ThemeTokens.cardCut, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("完成记录".localized)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(comic.ink)
                    Spacer()
                    Text("\(weeks) 周")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(comic.muted)
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
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(comic.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    ForEach(0..<7, id: \.self) { r in
                        GridRow {
                            Text(rowLabels[r])
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(comic.muted)
                                .frame(width: labelWidth, alignment: .leading)

                            ForEach(0..<weeks, id: \.self) { w in
                                let cell = cells[w * 7 + r]
                                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                    .fill(ThemeTokens.heat(min(cell.count, 4), comic: comic))
                                    .overlay {
                                        if cell.isToday {
                                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                                .strokeBorder(comic.ink, lineWidth: 1.2)
                                        }
                                    }
                                    .aspectRatio(1, contentMode: .fit)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }

                HStack {
                    Text("打卡密度点阵".localized)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(comic.muted)
                    Spacer()
                    HStack(spacing: 4) {
                        Text("少")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(comic.muted)
                        ForEach(0..<5, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(ThemeTokens.heat(i, comic: comic))
                                .frame(width: 10, height: 10)
                        }
                        Text("多")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(comic.muted)
                    }
                }
            }
        }
    }

    private struct Cell {
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
        return (0..<(weeks * 7)).map { i in
            let d = cal.date(byAdding: .day, value: i, to: start) ?? start
            return Cell(
                count: counts[df.string(from: d)] ?? 0,
                isToday: cal.isDate(d, inSameDayAs: today),
                month: cal.component(.month, from: d)
            )
        }
    }
}
