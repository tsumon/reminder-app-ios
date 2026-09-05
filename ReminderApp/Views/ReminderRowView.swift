import SwiftUI

/// 提醒行视图（列表中的每一行）
struct ReminderRowView: View {
    let reminder: Reminder
    /// 提醒中（active / snoozed / overdue）行内确认。等待中不传。
    var onConfirm: (() -> Void)? = nil
    @Environment(\.soft) private var soft

    var body: some View {
        SoftShadowCard(kind: .card, radius: ThemeTokens.radiusCard) {
            HStack(spacing: 13) {
                SoftEmojiWell(emoji: reminder.typeEmoji, tint: wellTint)
                    .accessibilityLabel(Localized("提醒类型"))

                VStack(alignment: .leading, spacing: 4) {
                    Text(reminder.title)
                        .font(SoftType.bodyMedium)
                        .lineLimit(1)
                        .strikethrough(isDone, color: soft.muted)
                        .foregroundStyle(isDone ? soft.muted : soft.text)

                    HStack(spacing: 6) {
                        if reminder.kind == .date {
                            dateTypeBadge
                        } else {
                            RepeatRuleBadge(reminder: reminder)
                        }
                    }

                    if reminder.retryStage > 0 && !isDone {
                        Text("还没确认 · \(retryClock) 再响")
                            .font(SoftType.retry)
                            .foregroundStyle(soft.warn)
                    }

                    if reminder.note.isNotEmpty && reminder.retryStage == 0 {
                        Text(reminder.note)
                            .font(SoftType.caption)
                            .foregroundStyle(soft.muted)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 4) {
                        Text(timeText)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(isDone ? soft.muted : timeColor)
                            .multilineTextAlignment(.trailing)
                        if onConfirm == nil {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(soft.muted)
                        }
                    }
                    if let onConfirm {
                        Button(action: onConfirm) {
                            Text("确认".localized)
                                .font(SoftType.confirm)
                                .foregroundStyle(ThemeTokens.onStrong)
                                .padding(.horizontal, 14)
                                .frame(height: 32)
                                .background(ThemeTokens.strong, in: Capsule())
                                .overlay(alignment: .top) {
                                    Capsule()
                                        .fill(Color.white.opacity(0.28))
                                        .frame(height: 1)
                                        .padding(.horizontal, 8)
                                        .offset(y: 1)
                                }
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("确认".localized)
                        .accessibilityIdentifier("row-confirm")
                    }
                }
            }
            .padding(ThemeTokens.cardPad)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(reminder.isEnabled ? 1 : 0.5)
    }

    private var isDone: Bool { reminder.status == .confirmed }

    private var timeColor: Color {
        reminder.status == .pending ? ThemeTokens.brandPrimary : statusColor
    }

    // MARK: - 类型标签

    @ViewBuilder
    private var dateTypeBadge: some View {
        Text(dateBadgeText)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(kindBadgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(kindBadgeColor.opacity(soft.isDark ? 0.22 : 0.14))
            )
    }

    private var wellTint: Color {
        switch reminder.kind {
        case .cycle: return ThemeTokens.brandContainer
        case .rule:  return Color(hex: 0xB8E0D6)
        case .date:
            switch reminder.dateType {
            case .solarBirthday: return Color(hex: 0xFCD3E1)
            case .lunarBirthday: return Color(hex: 0xE1DDFC)
            case .holiday:       return Color(hex: 0xFDE3CC)
            case .none:          return Color(hex: 0xE4E4E0)
            }
        }
    }

    private var dateBadgeText: String {
        switch reminder.dateType {
        case .solarBirthday:
            return Localized("公历 %@", reminder.dateDisplayText)
        case .lunarBirthday:
            return Localized("农历 %@", reminder.dateDisplayText)
        default:
            return reminder.dateDisplayText
        }
    }

    private var kindBadgeColor: Color {
        switch reminder.kind {
        case .cycle: return .blue
        case .rule:  return .teal
        case .date:
            switch reminder.dateType {
            case .solarBirthday: return .pink
            case .lunarBirthday: return .purple
            case .holiday:       return .orange
            case .none:          return .gray
            }
        }
    }

    private var statusColor: Color {
        switch reminder.status {
        case .pending:   return ThemeTokens.statusWaiting
        case .active:    return ThemeTokens.statusReminding
        case .snoozed:   return ThemeTokens.statusSnoozed
        case .confirmed: return ThemeTokens.statusCompleted
        case .overdue:   return ThemeTokens.statusOverdue
        }
    }

    private var retryClock: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f.string(from: reminder.nextTriggerAt)
    }

    private var timeText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.localizedString(for: reminder.nextTriggerAt, relativeTo: Date())
    }
}

extension String {
    var isNotEmpty: Bool { !isEmpty }
}

/// v2.4.14: 同一人公历+农历生日合并行——「爸爸生日（公历）」+「爸爸生日（农历）」
/// 拆两条存储（各自独立触发），列表层合成一行显示。点击进入「下次先到」那条的详情。
struct MergedBirthdayRow: View {
    let solar: Reminder
    let lunar: Reminder
    @Environment(\.soft) private var soft

    private var baseTitle: String { String(solar.title.dropLast("（公历）".count)) }
    private var nearest: Reminder { solar.nextTriggerAt <= lunar.nextTriggerAt ? solar : lunar }

    var body: some View {
        SoftShadowCard(kind: .card, radius: ThemeTokens.radiusCard) {
            HStack(spacing: 13) {
                SoftEmojiWell(emoji: nearest.typeEmoji, tint: Color(hex: 0xFCD3E1))

                VStack(alignment: .leading, spacing: 4) {
                    Text(baseTitle)
                        .font(SoftType.bodyMedium)
                        .foregroundStyle(soft.text)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(Localized("公历 %@", solar.dateDisplayText))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.pink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.pink.opacity(soft.isDark ? 0.22 : 0.14))
                            )
                        Text(Localized("农历 %@", lunar.dateDisplayText))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.purple.opacity(soft.isDark ? 0.22 : 0.14))
                            )
                    }
                }

                Spacer()

                HStack(spacing: 4) {
                    Text(timeText)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(ThemeTokens.strong)
                        .multilineTextAlignment(.trailing)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(soft.muted)
                }
            }
            .padding(ThemeTokens.cardPad)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(nearest.isEnabled ? 1 : 0.5)
    }

    private var timeText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.localizedString(for: nearest.nextTriggerAt, relativeTo: Date())
    }
}

#Preview {
    List {
        ReminderRowView(reminder: Reminder(
            title: "每周打针",
            note: "胰岛素注射",
            kind: .cycle,
            cycle: .weekly,
            firstTriggerAt: Date(),
            nextTriggerAt: Date().addingTimeInterval(3600),
            status: .pending
        ))
        ReminderRowView(reminder: Reminder(
            title: "妈妈生日",
            note: "记得买礼物",
            kind: .date,
            dateType: .lunarBirthday,
            targetMonth: 8,
            targetDay: 15,
            advanceDays: 3,
            firstTriggerAt: Date().addingTimeInterval(86400 * 45),
            nextTriggerAt: Date().addingTimeInterval(86400 * 45),
            status: .pending
        ))
        ReminderRowView(reminder: Reminder(
            title: "春节",
            kind: .date,
            dateType: .holiday,
            advanceDays: 7,
            holidayID: "chunjie",
            firstTriggerAt: Date().addingTimeInterval(86400 * 180),
            nextTriggerAt: Date().addingTimeInterval(86400 * 180),
            status: .pending
        ))
    }
    .listStyle(.insetGrouped)
}
