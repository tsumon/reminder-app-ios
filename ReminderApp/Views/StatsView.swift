import SwiftUI
import SwiftData

/// 统计洞察：三砖 + 厚描边 donut + GitHub 热力 + 城堡 + 忘记时段
struct StatsView: View {
    @Query private var reminders: [Reminder]
    @Environment(\.soft) private var soft
    @Environment(\.colorScheme) private var scheme

    @State private var range="week"
    @State private var rangeOffset=0
    private var interval: DateInterval? {
        guard range != "all" else { return nil }
        var cal=Calendar.current;cal.firstWeekday=2
        let unit: Calendar.Component = range == "week" ? .weekOfYear : .month
        let date=cal.date(byAdding:unit,value:rangeOffset,to:Date()) ?? Date()
        return cal.dateInterval(of:unit,for:date)
    }
    var body: some View {
        let selectedInterval=interval
        let records = reminders.flatMap { $0.records }.filter { record in
            guard let selectedInterval else { return true }
            return record.performedAt>=selectedInterval.start && record.performedAt<selectedInterval.end
        }
        let summary = StatsService.summarize(records: records)
        let rate = summary.completionRate ?? 0

        ScrollView {
            VStack(spacing: 14) {
                Picker("日期".localized,selection:$range) {
                    Text("本周".localized).tag("week");Text("本月".localized).tag("month");Text("全部".localized).tag("all")
                }.pickerStyle(.segmented).onChange(of:range) { _,_ in rangeOffset=0 }
                if let interval {
                    HStack {
                        Button { rangeOffset-=1 } label: { Image(systemName:"chevron.left").frame(width:44,height:44) }.accessibilityLabel("上一段时间".localized)
                        Spacer()
                        Text(interval.start.formatted(date:.abbreviated,time:.omitted)+" – "+interval.end.addingTimeInterval(-1).formatted(date:.abbreviated,time:.omitted)).font(.caption)
                        Spacer()
                        Button { rangeOffset+=1 } label: { Image(systemName:"chevron.right").frame(width:44,height:44) }.accessibilityLabel("下一段时间".localized)
                    }
                }
                VStack(alignment:.leading,spacing:12) {
                    Text("每次确认，都有记录".localized).font(.title2.bold())
                    Text("完成、跳过和漏掉分别统计".localized).foregroundStyle(.secondary)
                    HStack {
                        overviewCard(title:"已完成",value:"\(records.filter { $0.type == "confirm" }.count)",color:soft.ok)
                        overviewCard(title:"跳过",value:"\(records.filter { $0.type == "skipped" }.count)",color:soft.warn)
                        overviewCard(title:"漏掉",value:"\(summary.missedCount)",color:soft.danger)
                    }
                    Text("漏掉按出现重试的日期计数；完成与跳过按操作次数计数。".localized).font(.caption).foregroundStyle(.secondary)
                }
                overviewCards(summary)

                SoftShadowCard(kind: .card, radius: ThemeTokens.radiusCard) {
                    SoftDonutChart(rate: rate, confirm: summary.confirmCount, missed: summary.missedCount)
                }

                SoftShadowCard(kind: .card, radius: ThemeTokens.radiusCard) {
                    CheckInHeatmap(counts: summary.heatmap)
                }

                castleCard(summary)
                forgetHoursCard(summary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .background(PaperCanvas())
        .navigationTitle("统计洞察".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(soft.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("统计洞察".localized)
                    .font(SoftType.title)
                    .foregroundStyle(soft.text)
            }
        }
    }

    private func overviewCards(_ s: StatsSummary) -> some View {
        HStack(spacing: 10) {
            overviewCard(title: "完成天数", value: "\(s.confirmCount)", color: soft.ok)
            overviewCard(title: "连续天数", value: "\(s.currentStreak)", color: soft.warn)
            overviewCard(
                title: "完成率",
                value: s.completionRate.map { "\(Int($0 * 100))%" } ?? "0%",
                color: ThemeTokens.strong
            )
        }
    }

    private func overviewCard(title: String, value: String, color: Color) -> some View {
        SoftShadowCard(kind: .elevated, radius: ThemeTokens.radiusShallow) {
            VStack(spacing: 4) {
                Text(value)
                    .font(SoftType.meter)
                    .meterTracking()
                    .foregroundStyle(color)
                Text(title.localized)
                    .font(SoftType.caption)
                    .foregroundStyle(soft.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
    }

    private func castleCard(_ s: StatsSummary) -> some View {
        SoftShadowCard(kind: .card, radius: ThemeTokens.radiusCard) {
            HStack(spacing: 18) {
                StreakCastleView(streak: s.currentStreak)
                VStack(alignment: .leading, spacing: 5) {
                    Text(Localized("打卡城堡 Lv.%d", StreakCastleView.level(forStreak: s.currentStreak)))
                        .font(SoftType.section)
                        .foregroundStyle(soft.text)
                    Text(Localized("连续 %d 天，每 3 天加盖一层", s.currentStreak))
                        .font(SoftType.caption)
                        .foregroundStyle(soft.muted)
                    HStack(spacing: 4) {
                        Image(systemName: "trophy.fill")
                            .font(.caption)
                        Text(Localized("最长纪录 %d 天", s.longestStreak))
                            .font(SoftType.caption)
                    }
                    .foregroundStyle(ThemeTokens.strong)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }

    private func forgetHoursCard(_ s: StatsSummary) -> some View {
        SoftShadowCard(kind: .card, radius: ThemeTokens.radiusCard) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("最常忘记时段".localized)
                        .font(SoftType.section)
                        .foregroundStyle(soft.text)
                    Spacer()
                    if s.forgetHours.isEmpty {
                        Text("暂无数据".localized)
                            .font(SoftType.caption)
                            .foregroundStyle(soft.muted)
                    }
                }

                if !s.forgetHours.isEmpty {
                    ForEach(Array(s.forgetHours.enumerated()), id: \.offset) { idx, item in
                        HStack(spacing: 10) {
                            Text(["🥇", "🥈", "🥉"][idx])
                            Text(Localized("%d:00 前后", item.hour))
                                .font(SoftType.bodyMedium)
                                .foregroundStyle(soft.text)
                            Spacer()
                            Text(Localized("漏 %d 次", item.count))
                                .font(SoftType.body)
                                .foregroundStyle(soft.muted)
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    Text("坚持得很好，没有漏掉过提醒".localized)
                        .font(SoftType.body)
                        .foregroundStyle(soft.muted)
                        .padding(.vertical, 8)
                }
            }
            .padding(16)
        }
    }
}

#Preview {
    StatsView()
}
