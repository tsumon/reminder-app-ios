import SwiftUI
import SwiftData

/// 统计洞察页（v1.8.7 任务③）：完成率 / 连续打卡 / 最常忘记时段 / 月历热力图
struct StatsView: View {
    @Query private var reminders: [Reminder]
    @State private var displayMonth = Date() // 热力图月份

    private let calendar = Calendar.current

    var body: some View {
        let records = reminders.flatMap { $0.records }
        let summary = StatsService.summarize(records: records)

        // v1.9.8: NavigationStack 由 MainTabView 的 Tab 提供
        ScrollView {
            VStack(spacing: 14) {
                overviewCards(summary)
                completionCard(summary)
                HStack(spacing: 12) {
                    streakCard(title: "当前连续", value: summary.currentStreak, icon: "flame.fill", color: .orange)
                    streakCard(title: "最长连续", value: summary.longestStreak, icon: "trophy.fill", color: .purple)
                }
                forgetHoursCard(summary)
                heatmapCard(summary)
            }
            .padding(16)
        }
        .navigationTitle("统计洞察")
        // v1.9.8.1: iPad 大屏下大标题+玻璃背景形成大块空白，改 inline 更紧凑
        .navigationBarTitleDisplayMode(.inline)
        .glassNavigationBar()
    }

    // MARK: - v1.9.8 设计图风格：顶部 3 数字概览卡

    private func overviewCards(_ s: StatsSummary) -> some View {
        HStack(spacing: 10) {
            overviewCard(title: "本月完成", value: "\(s.confirmCount)", color: ThemeTokens.statusCompleted)
            overviewCard(title: "连续天数", value: "\(s.currentStreak)", color: .orange)
            overviewCard(
                title: "完成率",
                value: s.completionRate.map { "\(Int($0 * 100))%" } ?? "—",
                color: ThemeTokens.brandPrimary
            )
        }
    }

    private func overviewCard(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(cardBackground)
    }

    // MARK: - 完成率

    private func completionCard(_ s: StatsSummary) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.18), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: s.completionRate.map { max(0.02, min($0, 1)) } ?? 0)
                    .stroke(
                        LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    if let rate = s.completionRate {
                        Text("\(Int(rate * 100))%")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                    } else {
                        Text("—")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Text("完成率")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 150, height: 150)
            .padding(.top, 8)

            HStack(spacing: 24) {
                Label("确认 \(s.confirmCount)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Label("漏掉 \(s.missedCount)", systemImage: "bell.slash.fill")
                    .foregroundStyle(.red)
            }
            .font(.subheadline.weight(.medium))
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(cardBackground)
    }

    // MARK: - 连续打卡

    private func streakCard(title: String, value: Int, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text("\(value) 天")
                .font(.title2.weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(cardBackground)
    }

    // MARK: - 最常忘记时段

    private func forgetHoursCard(_ s: StatsSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("最常忘记时段", systemImage: "clock.badge.exclamationmark")
                    .font(.headline)
                Spacer()
                if s.forgetHours.isEmpty {
                    Text("暂无数据")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !s.forgetHours.isEmpty {
                ForEach(Array(s.forgetHours.enumerated()), id: \.offset) { idx, item in
                    HStack(spacing: 10) {
                        Text(["🥇", "🥈", "🥉"][idx])
                        Text("\(item.hour):00 前后")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("漏 \(item.count) 次")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text("坚持得很好，没有漏掉过提醒 🎉")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: - 月历热力图

    private func heatmapCard(_ s: StatsSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("月历热力图", systemImage: "calendar")
                    .font(.headline)
                Spacer()
                Button {
                    changeMonth(-1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                Text(monthTitle)
                    .font(.subheadline.weight(.semibold))
                Button {
                    changeMonth(1)
                } label: {
                    Image(systemName: "chevron.right")
                }
            }

            // 星期表头
            HStack(spacing: 0) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { d in
                    Text(d)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            heatmapGrid(s)

            // 图例
            HStack(spacing: 6) {
                Text("少")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(0..<4, id: \.self) { lv in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(heatColor(lv))
                        .frame(width: 14, height: 14)
                }
                Text("多")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(cardBackground)
    }

    @ViewBuilder
    private func heatmapGrid(_ s: StatsSummary) -> some View {
        let comps = calendar.dateComponents([.year, .month], from: displayMonth)
        let year = comps.year ?? 2026
        let month = comps.month ?? 1
        if let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
           let days = calendar.range(of: .day, in: .month, for: first)?.count {

            let firstWeekday = (calendar.component(.weekday, from: first) + 5) % 7 + 1
            let leading = firstWeekday - 1
            let total = ((leading + days + 6) / 7) * 7

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 5) {
                ForEach(0..<total, id: \.self) { idx in
                    let day = idx - leading + 1
                    if day >= 1 && day <= days {
                        let key = String(format: "%04d-%02d-%02d", year, month, day)
                        let count = s.heatmap[key] ?? 0
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(heatColor(heatLevel(count)))
                                .frame(height: 26)
                            Text("\(day)")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Color.clear.frame(height: 32)
                    }
                }
            }
        }
    }

    /// 0=无，1=1次，2=2-3次，3=4+次
    private func heatLevel(_ count: Int) -> Int {
        switch count {
        case 0: return 0
        case 1: return 1
        case 2...3: return 2
        default: return 3
        }
    }

    private func heatColor(_ level: Int) -> Color {
        switch level {
        case 0: return ThemeTokens.heatmap0
        case 1: return ThemeTokens.heatmap1
        case 2: return ThemeTokens.heatmap2
        default: return ThemeTokens.heatmap3
        }
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月"
        return f.string(from: displayMonth)
    }

    private func changeMonth(_ delta: Int) {
        if let d = calendar.date(byAdding: .month, value: delta, to: displayMonth) {
            displayMonth = d
        }
    }

    private var cardBackground: some View {
        // 液态玻璃卡片：材质 + 高光描边
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.55), .white.opacity(0.12)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: ThemeTokens.brandPrimary.opacity(0.08), radius: 12, y: 5)
    }
}

#Preview {
    StatsView()
}
