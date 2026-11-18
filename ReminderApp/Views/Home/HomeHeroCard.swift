import SwiftUI

/// 卡片一：焦点雕塑感 `#Count` 大字卡（1:1 复刻 IOTA MONITOR `#221` 构图与呼吸感）
struct HomeHeroCard: View {
    let totalCount: Int
    let enabledCount: Int
    let doneTodayCount: Int
    let dueReminders: [Reminder]
    let nextUpcoming: Reminder?
    var onCreate: () -> Void
    var onOpenDetail: (UUID) -> Void
    var onConfirm: (Reminder) -> Void
    var onSnooze: (Reminder) -> Void
    var onSkip: (Reminder) -> Void

    @Environment(\.comic) private var comic

    var body: some View {
        ComicCard(cut: ThemeTokens.cardCut, padding: 20) {
            if totalCount == 0 {
                emptyHeroContent
            } else if let focus = dueReminders.first {
                dueHeroContent(focus: focus)
            } else {
                calmHeroContent
            }
        }
    }

    // MARK: - 空库状态（#00 + 单枚「+ 创建提醒」切角键）

    private var emptyHeroContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("待办提醒".localized)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(comic.muted)
                    ComicHeroNumber(text: "#00", size: 50)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 5) {
                    Text("今天想做什么呀？".localized)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(comic.ink)
                        .multilineTextAlignment(.trailing)
                    Text("暂无循环提醒 · 纸面通透".localized)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(comic.muted)
                    if let lunar = lunarTodayText {
                        Text(lunar)
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(comic.muted)
                    }
                }
            }

            ComicHairline(outer: false)

            HStack(alignment: .center, spacing: 12) {
                Text("创建第一条循环提醒，准时守候重要事项".localized)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(comic.muted)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Button(action: onCreate) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .heavy))
                        Text("创建提醒".localized)
                    }
                }
                .buttonStyle(ComicButtonStyle(variant: .accent))
            }
        }
    }

    // MARK: - 到点待确认状态（#02 + 右侧事项详情 + 单枚「确认完成」）

    private func dueHeroContent(focus: Reminder) -> some View {
        let canSkip = !(focus.kind == .cycle && focus.cycle == .once)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("待确认提醒".localized)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(comic.muted)
                    ComicHeroNumber(text: String(format: "#%02d", dueReminders.count), size: 50)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 5) {
                    Text(focus.title)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(comic.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)

                    Text("\(clockString(focus.nextTriggerAt)) · \(focus.dateDisplayText)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(comic.muted)

                    Text(dueStatusLabel(focus))
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(focus.status == .overdue ? comic.danger : comic.warn)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onOpenDetail(focus.id)
            }

            ComicHairline(outer: false)

            HStack(alignment: .center, spacing: 14) {
                Button {
                    onSnooze(focus)
                } label: {
                    Text("稍后 15m".localized)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(comic.muted)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)

                if canSkip {
                    Text("·")
                        .foregroundStyle(comic.muted)
                    Button {
                        onSkip(focus)
                    } label: {
                        Text("跳过".localized)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(comic.muted)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 8)

                Button {
                    onConfirm(focus)
                } label: {
                    Text("确认完成".localized)
                }
                .buttonStyle(ComicButtonStyle(variant: .accent))
                .accessibilityIdentifier("row-confirm")
            }
        }
    }

    // MARK: - 无紧急待确认时的通透概览状态

    private var calmHeroContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("待确认提醒".localized)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(comic.muted)
                    ComicHeroNumber(text: "#00", size: 50)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 5) {
                    Text(nextUpcoming == nil ? "今日全部完成".localized : "排期正常".localized)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(comic.ink)
                    if let lunar = lunarTodayText {
                        Text("\(todayDateText) · \(lunar)")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(comic.muted)
                    }
                    Text(Localized("启用中 %d 项 · 今日已打卡 %d 次", enabledCount, doneTodayCount))
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(comic.muted)
                }
            }

            ComicHairline(outer: false)

            HStack(alignment: .center) {
                if let next = nextUpcoming {
                    Text("下一提醒 · \(shortTriggerText(next.nextTriggerAt))")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(comic.muted)
                    Spacer()
                    Button {
                        onOpenDetail(next.id)
                    } label: {
                        Text("查看详情".localized)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(comic.hero)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("所有提醒均已妥善完成".localized)
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(comic.muted)
                    Spacer()
                }
            }
        }
    }

    // MARK: - 文案格式

    private func dueStatusLabel(_ r: Reminder) -> String {
        if r.status == .overdue {
            return "已达重响上限 · 等待处理".localized
        }
        if r.retryStage > 0 {
            return Localized("第 %d 次重响 · 等待确认", r.retryStage)
        }
        return "等待确认".localized
    }

    private func clockString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "M/d HH:mm"
        return f.string(from: date)
    }

    private func shortTriggerText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = Calendar.current.isDateInToday(date) ? "今天 HH:mm" : "M月d日 HH:mm"
        return f.string(from: date)
    }

    private var todayDateText: String {
        let f = DateFormatter()
        f.locale = AppLanguageManager.currentLocale
        f.dateFormat = "M月d日"
        return f.string(from: Date())
    }

    private var lunarTodayText: String? {
        let lunar = LunarCalendar.solarToLunar(Date())
        guard lunar.month > 0 else { return nil }
        return "农历" + lunar.description
    }
}
