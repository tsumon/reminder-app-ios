import SwiftUI

/// 同人生日合并展示条目（底层仍为两条独立提醒）
enum HomeDisplayRow: Identifiable {
    case pair(solar: Reminder, lunar: Reminder)
    case single(Reminder)

    var id: UUID {
        switch self {
        case .pair(let s, _): return s.id
        case .single(let r): return r.id
        }
    }

    var sortTime: Date {
        switch self {
        case .pair(let s, let l): return min(s.nextTriggerAt, l.nextTriggerAt)
        case .single(let r): return r.nextTriggerAt
        }
    }

    var nearest: Reminder {
        switch self {
        case .pair(let s, let l): return s.nextTriggerAt <= l.nextTriggerAt ? s : l
        case .single(let r): return r
        }
    }
}

func pairHomeBirthdayRows(_ items: [Reminder]) -> [HomeDisplayRow] {
    var solar: [String: Reminder] = [:]
    var lunar: [String: Reminder] = [:]
    var rest: [Reminder] = []
    for r in items {
        if r.kind == .date, r.dateType == .solarBirthday, r.title.hasSuffix("（公历）") {
            solar[String(r.title.dropLast(4))] = r
        } else if r.kind == .date, r.dateType == .lunarBirthday, r.title.hasSuffix("（农历）") {
            lunar[String(r.title.dropLast(4))] = r
        } else {
            rest.append(r)
        }
    }
    var rows: [HomeDisplayRow] = []
    for (base, s) in solar {
        if let l = lunar.removeValue(forKey: base) {
            rows.append(.pair(solar: s, lunar: l))
        } else {
            rest.append(s)
        }
    }
    rest.append(contentsOf: lunar.values)
    rows.append(contentsOf: rest.map(HomeDisplayRow.single))
    return rows.sorted { $0.sortTime < $1.sortTime }
}

/// 卡片二：无横线呼吸感事件清单卡（1:1 复刻 IOTA MONITOR「最近事件」）
/// 零行间分割线、零嵌套小标签框，仅靠等宽时间与留白对齐
struct HomeEventListCard: View {
    let title: String
    let rows: [HomeDisplayRow]
    var onOpenDetail: (UUID) -> Void
    var onConfirm: (Reminder) -> Void
    var onSnooze: (Reminder) -> Void
    var onSkip: (Reminder) -> Void
    var onDelete: (Reminder) -> Void

    @Environment(\.comic) private var comic

    var body: some View {
        ComicCard(cut: ThemeTokens.cardCut, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(comic.ink)
                    Spacer()
                    Text(Localized("%d 项", rows.count))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(comic.muted)
                }

                if rows.isEmpty {
                    Text("当前筛选下没有待触发提醒".localized)
                        .font(.system(size: 13.5, weight: .medium, design: .rounded))
                        .foregroundStyle(comic.muted)
                        .padding(.vertical, 8)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(rows) { item in
                            eventRow(item)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func eventRow(_ item: HomeDisplayRow) -> some View {
        let r = item.nearest
        let isPair: Bool = {
            if case .pair = item { return true }
            return false
        }()
        let displayTitle: String = {
            switch item {
            case .pair(let s, _): return String(s.title.dropLast("（公历）".count))
            case .single(let single): return single.title
            }
        }()
        let pairSubtitle: String? = {
            if case .pair(let s, let l) = item {
                return Localized("公历 %@", s.dateDisplayText) + " · " + Localized("农历 %@", l.dateDisplayText)
            }
            return nil
        }()
        let summary: String = {
            switch item {
            case .pair:
                return ""
            case .single(let single):
                return single.dateDisplayText
            }
        }()
        let isDue = r.status == .active || r.status == .snoozed || r.status == .overdue

        HStack(alignment: .center, spacing: 10) {
            Text(tabularTime(r.nextTriggerAt))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isDue ? comic.accent : comic.muted)
                .frame(width: 68, alignment: .leading)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(comic.ink)
                    .lineLimit(1)
                if let pairSubtitle {
                    Text(pairSubtitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(comic.muted)
                        .lineLimit(1)
                } else if r.status == .overdue {
                    Text("已逾期".localized)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(comic.danger)
                } else if !r.note.isEmpty {
                    Text(r.note)
                        .font(.system(size: 11.5, weight: .regular, design: .rounded))
                        .foregroundStyle(comic.muted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                onOpenDetail(r.id)
            }

            if !isPair {
                Text(summary)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(comic.muted)
                    .lineLimit(1)
                    .layoutPriority(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Button {
                onConfirm(r)
            } label: {
                Image(systemName: isDue ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isDue ? comic.accent : comic.muted.opacity(0.75))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打卡".localized)
        }
        .opacity(r.isEnabled ? 1 : 0.5)
        .contextMenu {
            Button {
                onConfirm(r)
            } label: {
                Label("完成".localized, systemImage: "checkmark")
            }
            Button {
                onSnooze(r)
            } label: {
                Label("稍后".localized, systemImage: "clock")
            }
            if !(r.kind == .cycle && r.cycle == .once) {
                Button {
                    onSkip(r)
                } label: {
                    Label("跳过".localized, systemImage: "forward")
                }
            }
            Divider()
            Button(role: .destructive) {
                onDelete(r)
            } label: {
                Label("删除".localized, systemImage: "trash")
            }
        }
    }

    private func tabularTime(_ date: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        if cal.isDateInToday(date) {
            f.dateFormat = "HH:mm"
            return f.string(from: date)
        } else if cal.isDateInTomorrow(date) {
            return "明天".localized
        } else if cal.component(.year, from: date) == cal.component(.year, from: Date()) {
            f.dateFormat = "MM-dd"
            return f.string(from: date)
        } else {
            f.dateFormat = "yy/M/d"
            return f.string(from: date)
        }
    }
}

/// 展开后的已完成清单轻面板（默认收起在底纸纯文字行下）
struct HomeCompletedCard: View {
    let items: [Reminder]
    var onOpenDetail: (UUID) -> Void
    var onReopen: (Reminder) -> Void
    var onDelete: (Reminder) -> Void

    @Environment(\.comic) private var comic

    var body: some View {
        ComicCard(cut: ThemeTokens.cardCut, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(items) { r in
                    HStack(spacing: 10) {
                        Button {
                            onOpenDetail(r.id)
                        } label: {
                            Text(r.title)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(comic.muted)
                                .strikethrough(true, color: comic.muted)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        Button {
                            onReopen(r)
                        } label: {
                            Text("重开".localized)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(comic.hero)
                        }
                        .buttonStyle(.plain)
                    }
                    .contextMenu {
                        Button {
                            onReopen(r)
                        } label: {
                            Label("重开".localized, systemImage: "arrow.uturn.backward")
                        }
                        Button(role: .destructive) {
                            onDelete(r)
                        } label: {
                            Label("删除".localized, systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}
