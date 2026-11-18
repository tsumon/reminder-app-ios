import SwiftUI
import SwiftData

/// 统计洞察：#Streak 漫风大字主卡 + 无黑框暖色圆润点阵热力卡 + 忘记时段轻卡
struct StatsView: View {
    @Query private var reminders: [Reminder]
    @Environment(\.comic) private var comic

    @State private var range = "week"
    @State private var rangeOffset = 0

    private var interval: DateInterval? {
        guard range != "all" else { return nil }
        var cal = Calendar.current
        cal.firstWeekday = 2
        let unit: Calendar.Component = range == "week" ? .weekOfYear : .month
        let date = cal.date(byAdding: unit, value: rangeOffset, to: Date()) ?? Date()
        return cal.dateInterval(of: unit, for: date)
    }

    var body: some View {
        let selectedInterval = interval
        let allRecords = reminders.flatMap { $0.records }
        let allSummary = StatsService.summarize(records: allRecords)
        let records = allRecords.filter { record in
            guard let selectedInterval else { return true }
            return record.performedAt >= selectedInterval.start && record.performedAt < selectedInterval.end
        }
        let summary = StatsService.summarize(records: records)
        let confirmTotal = records.filter { $0.type == ReminderRecordType.confirm.rawValue }.count
        let skipTotal = records.filter { $0.type == ReminderRecordType.skipped.rawValue }.count

        VStack(spacing: 0) {
            bareHeader(selectedInterval: selectedInterval)
            ComicHairline(outer: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    streakHeroCard(
                        allSummary: allSummary,
                        summary: summary,
                        confirmTotal: confirmTotal,
                        skipTotal: skipTotal
                    )

                    ComicHeatmapCard(counts: allSummary.heatmap)

                    forgetHoursCard(summary)
                }
                .padding(.horizontal, ThemeTokens.gutter)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
        }
        .background(ComicCanvas())
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func bareHeader(selectedInterval: DateInterval?) -> some View {
        VStack(spacing: 6) {
            HStack {
                ComicBrandTitle(text: "统计洞察".localized, size: 20, showShard: true)
                Spacer()
                HStack(spacing: 14) {
                    ForEach([("week", "本周"), ("month", "本月"), ("all", "全部")], id: \.0) { key, label in
                        let active = range == key
                        Button {
                            range = key
                            rangeOffset = 0
                        } label: {
                            VStack(spacing: 2) {
                                Text(label.localized)
                                    .font(.system(size: 13.5, weight: active ? .heavy : .medium, design: .rounded))
                                    .foregroundStyle(active ? comic.ink : comic.muted)
                                Rectangle()
                                    .fill(active ? comic.accent : Color.clear)
                                    .frame(width: 16, height: 2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let selectedInterval {
                HStack {
                    Button { rangeOffset -= 1 } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(comic.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("上一段时间".localized)

                    Spacer()

                    Text(
                        selectedInterval.start.formatted(date: .abbreviated, time: .omitted)
                        + " – "
                        + selectedInterval.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted)
                    )
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(comic.muted)

                    Spacer()

                    Button { rangeOffset += 1 } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(comic.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("下一段时间".localized)
                }
            }
        }
        .padding(.horizontal, ThemeTokens.gutter)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func streakHeroCard(
        allSummary: StatsSummary,
        summary: StatsSummary,
        confirmTotal: Int,
        skipTotal: Int
    ) -> some View {
        ComicCard(cut: ThemeTokens.cardCut, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("每次确认，都有记录".localized)
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundStyle(comic.muted)
                        ComicHeroNumber(text: String(format: "#%02d", allSummary.currentStreak), size: 50)
                        Text(Localized("连续打卡天数 · 最长 %d 天", allSummary.longestStreak))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(comic.muted)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(summary.completionRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(comic.ink)
                        Text("完成率".localized)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(comic.muted)

                        VStack(alignment: .trailing, spacing: 3) {
                            Text("已完成 \(confirmTotal) · 跳过 \(skipTotal)")
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(comic.ink)
                            Text("漏掉 \(summary.missedCount)")
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(summary.missedCount > 0 ? comic.danger : comic.muted)
                        }
                        .padding(.top, 2)
                    }
                }

                ComicHairline(outer: false)

                Text("漏掉按出现重试的日期计数；完成与跳过按操作次数计数。".localized)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(comic.muted)
            }
        }
    }

    private func forgetHoursCard(_ s: StatsSummary) -> some View {
        ComicCard(cut: ThemeTokens.cardCut, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("最常忘记时段".localized)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(comic.ink)
                    Spacer()
                    if s.forgetHours.isEmpty {
                        Text("暂无数据".localized)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(comic.muted)
                    }
                }

                if s.forgetHours.isEmpty {
                    Text("坚持得很好，没有漏掉过提醒".localized)
                        .font(.system(size: 13.5, weight: .medium, design: .rounded))
                        .foregroundStyle(comic.muted)
                        .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(s.forgetHours.enumerated()), id: \.offset) { idx, item in
                            HStack(spacing: 10) {
                                Text("#\(idx + 1)")
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(comic.hero)
                                    .frame(width: 28, alignment: .leading)
                                Text(Localized("%d:00 前后", item.hour))
                                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(comic.ink)
                                Spacer()
                                Text(Localized("漏 %d 次", item.count))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(comic.muted)
                            }
                        }
                    }
                }
            }
        }
    }
}
