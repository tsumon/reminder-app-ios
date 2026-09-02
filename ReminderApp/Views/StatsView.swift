import SwiftUI
import SwiftData

/// 统计洞察页（v1.8.7 任务③）：完成率 / 连续打卡 / 最常忘记时段
struct StatsView: View {
    @Query private var reminders: [Reminder]

    var body: some View {
        let records = reminders.flatMap { $0.records }
        let summary = StatsService.summarize(records: records)

        // v1.9.8: NavigationStack 由 MainTabView 的 Tab 提供
        ScrollView {
            VStack(spacing: 14) {
                overviewCards(summary)
                confirmMissLine(summary)
                // v2.5.0: 连续打卡城堡（替代两张 streak 小卡）
                castleCard(summary)
                // v2.5.0: 本周盆栽花园（打卡越多长得越高）
                gardenCard(records: records)
                forgetHoursCard(summary)
            }
            .padding(16)
        }
        .background(PastelPlaygroundBackground())
        .navigationTitle("统计洞察".localized)
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
                value: s.completionRate.map { "\(Int($0 * 100))%" } ?? "0%",
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

    // MARK: - 确认 / 漏掉（单行，无完成率环）

    private func confirmMissLine(_ s: StatsSummary) -> some View {
        HStack(spacing: 22) {
            Label(Localized("确认 %d", s.confirmCount), systemImage: "checkmark")
                .foregroundStyle(.primary)
            Label(Localized("漏掉 %d", s.missedCount), systemImage: "minus.circle")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.medium))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    // MARK: - 连续打卡城堡（v2.5.0）

    private func castleCard(_ s: StatsSummary) -> some View {
        HStack(spacing: 18) {
            StreakCastleView(streak: s.currentStreak)
            VStack(alignment: .leading, spacing: 5) {
                Text(Localized("打卡城堡 Lv.%d", StreakCastleView.level(forStreak: s.currentStreak)))
                    .font(.headline)
                Text(Localized("连续 %d 天，每 3 天加盖一层", s.currentStreak))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Localized("最长纪录 %d 天 🏆", s.longestStreak))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Playful.purple)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: - 本周盆栽花园（v2.5.0）

    /// 周一~周日七盆植物：当天打卡越多长得越高（🌰→🌱→🌿→🌳），代替柱状图
    private func gardenCard(records: [ReminderRecord]) -> some View {
        let cal = Calendar.current
        let confirms = records.filter { $0.type == ReminderRecordType.confirm.rawValue }
        let today = cal.startOfDay(for: Date())
        let weekdayIdx = (cal.component(.weekday, from: today) + 5) % 7
        let monday = cal.date(byAdding: .day, value: -weekdayIdx, to: today) ?? today
        let names = ["一", "二", "三", "四", "五", "六", "日"]

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("本周花园".localized)
                    .font(.headline)
                Spacer()
                Text("打卡越多长得越高".localized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<7, id: \.self) { offset in
                    gardenPot(
                        day: cal.date(byAdding: .day, value: offset, to: monday),
                        name: names[offset],
                        confirms: confirms,
                        cal: cal,
                        today: today
                    )
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private func gardenPot(day: Date?, name: String, confirms: [ReminderRecord], cal: Calendar, today: Date) -> some View {
        let count = day.map { d in confirms.filter { cal.isDate($0.performedAt, inSameDayAs: d) }.count } ?? 0
        let isFuture = (day ?? today) > today
        let isToday = day.map { cal.isDateInToday($0) } ?? false

        return VStack(spacing: 4) {
            Text(plantEmoji(count))
                .font(.system(size: count >= 5 ? 27 : (count >= 3 ? 23 : 18)))
                .grayscale(isFuture ? 1 : 0)
                .opacity(isFuture ? 0.35 : 1)
            Text(name)
                .font(.system(size: 10, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Playful.purple : .secondary)
            Text("\(count)")
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isToday ? Playful.gold.opacity(0.15) : Color.clear)
        )
    }

    private func plantEmoji(_ count: Int) -> String {
        switch count {
        case 0:     return "🌰"
        case 1...2: return "🌱"
        case 3...4: return "🌿"
        default:    return "🌳"
        }
    }

    // MARK: - 最常忘记时段

    private func forgetHoursCard(_ s: StatsSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("最常忘记时段".localized, systemImage: "clock.badge.exclamationmark")
                    .font(.headline)
                Spacer()
                if s.forgetHours.isEmpty {
                    Text("暂无数据".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !s.forgetHours.isEmpty {
                ForEach(Array(s.forgetHours.enumerated()), id: \.offset) { idx, item in
                    HStack(spacing: 10) {
                        Text(["🥇", "🥈", "🥉"][idx])
                        Text(Localized("%d:00 前后", item.hour))
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(Localized("漏 %d 次", item.count))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text("坚持得很好，没有漏掉过提醒".localized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    @Environment(\.colorScheme) private var scheme

    private var cardBackground: some View {
        // v2.5.0: 粘土拟态卡（暖白渐变 + 高光描边 + 柔和双层阴影）
        // v2.5.1: 补深色分支——原写死浅色，深色模式下浅卡+白字看不清
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                scheme == .dark
                    ? AnyShapeStyle(Color(hex: 0x2A2735))
                    : AnyShapeStyle(LinearGradient(
                        colors: [.white, Playful.cream],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: scheme == .dark
                                ? [.white.opacity(0.10), .white.opacity(0.03)]
                                : [.white.opacity(0.85), .white.opacity(0.25)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: scheme == .dark ? Color.clear : Playful.purple.opacity(0.10), radius: 14, y: 8)
            .shadow(color: .black.opacity(0.05), radius: 5, y: 3)
    }
}

#Preview {
    StatsView()
}
