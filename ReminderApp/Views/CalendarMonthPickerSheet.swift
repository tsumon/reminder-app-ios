import SwiftUI

/// 快速跳转月份弹窗（漫风化）
struct MonthYearPickerSheet: View {
    @State private var year: Int
    @State private var month: Int
    let onSelect: (Int, Int) -> Void
    let onClose: () -> Void

    @Environment(\.comic) private var comic
    private let monthNames = ["一月", "二月", "三月", "四月", "五月", "六月",
                              "七月", "八月", "九月", "十月", "十一月", "十二月"]

    init(year: Int, month: Int, onSelect: @escaping (Int, Int) -> Void, onClose: @escaping () -> Void) {
        _year = State(initialValue: year)
        _month = State(initialValue: month)
        self.onSelect = onSelect
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                HStack(spacing: 16) {
                    Button { year -= 1 } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(comic.ink)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)

                    Text(Localized("%@ 年", String(year)))
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(comic.ink)

                    Button { year += 1 } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(comic.ink)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 10)

                ComicHairline(outer: true)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(1...12, id: \.self) { m in
                        let isSelected = m == month
                        Button { month = m } label: {
                            Text(monthNames[m - 1])
                                .font(.system(size: 14, weight: isSelected ? .heavy : .semibold, design: .rounded))
                                .foregroundStyle(isSelected ? comic.onAccent : comic.ink)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background {
                                    ChamferShape(cut: 5)
                                        .fill(isSelected ? comic.accent : comic.surface)
                                    ChamferShape(cut: 5)
                                        .stroke(comic.border, lineWidth: 1.3)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, ThemeTokens.gutter)

                Spacer()

                HStack(spacing: 12) {
                    Button("取消".localized) { onClose() }
                        .buttonStyle(ComicButtonStyle(variant: .surface))
                    Button {
                        onSelect(year, month)
                    } label: {
                        Text(Localized("跳到 %@ 年 %@", String(year), monthNames[month - 1]))
                    }
                    .buttonStyle(ComicButtonStyle(variant: .accent, expand: true))
                }
                .padding(.horizontal, ThemeTokens.gutter)
                .padding(.bottom, 12)
            }
            .background(ComicCanvas())
            .navigationTitle("选择月份".localized)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
