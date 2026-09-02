import SwiftUI

/// 提醒行视图（列表中的每一行）
struct ReminderRowView: View {
    let reminder: Reminder
    /// 提醒中（active / snoozed / overdue）行内确认。等待中不传。
    var onConfirm: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 13) {
            // v2.1.0: 彩色圆角方块图标容器（44pt / 圆角 14），内放「提醒类型 SF Symbol」
            // （替代原 emoji——深浅色一致、与系统风格统一；对齐 Android 侧 Material 图标替换）
            ZStack {
                // v2.2.1: 彩色渐变底（同色系由深到浅），emoji 更有层次
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [kindBadgeColor.opacity(0.32), kindBadgeColor.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                // v2.2.1: 恢复 emoji 主图标（v2.1.0 换 SF Symbols 后视觉存在感骤降，
                // 用户反馈「图标没了」；emoji 彩色表情在浅底容器里辨识度更高）
                Text(reminder.typeEmoji)
                    .font(.system(size: 20))
            }
            .accessibilityLabel(Localized("提醒类型"))

            VStack(alignment: .leading, spacing: 4) {
                // 已完成：标题划线变灰（滴答清单风格）
                Text(reminder.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .strikethrough(isDone, color: .secondary)
                    .foregroundStyle(isDone ? .secondary : .primary)

                HStack(spacing: 6) {
                    // 日期类：公历/农历彩色标签；周期类用规则徽章
                    if reminder.kind == .date {
                        dateTypeBadge
                    } else {
                        RepeatRuleBadge(reminder: reminder)
                    }
                }

                if reminder.retryStage > 0 && !isDone {
                    Text("还没确认 · \(retryClock) 再响")
                        .font(.caption2)
                        .foregroundStyle(ThemeTokens.statusSnoozed)
                }

                if showsStatusChip {
                    Text(reminder.status.rawValue.localized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(0.12))
                        .clipShape(Capsule())
                }

                if reminder.note.isNotEmpty && reminder.retryStage == 0 {
                    Text(reminder.note)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 4) {
                    Text(timeText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isDone ? Color(.tertiaryLabel) : timeColor)
                        .multilineTextAlignment(.trailing)
                    if onConfirm == nil {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                if let onConfirm {
                    Button(action: onConfirm) {
                        Text("确认".localized)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(ThemeTokens.brandPrimary, in: Capsule())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("确认".localized)
                    .accessibilityIdentifier("row-confirm")
                }
            }
        }
        // v2.5.0: 粘土拟态行卡（替代液态玻璃）
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clayCard(radius: 18)
        .opacity(reminder.isEnabled ? 1 : 0.5)
    }

    private var isDone: Bool { reminder.status == .confirmed }

    /// 等待中由分组标题表达，提醒中改走行内确认，不再叠状态胶囊
    private var showsStatusChip: Bool {
        if onConfirm != nil { return false }
        if reminder.status == .pending { return false }
        return true
    }

    private var timeColor: Color {
        reminder.status == .pending ? ThemeTokens.brandPrimary : statusColor
    }

    // MARK: - 类型标签

    @ViewBuilder
    private var dateTypeBadge: some View {
        Text(dateBadgeText)
            .font(.caption)
            .foregroundStyle(kindBadgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(kindBadgeColor.opacity(0.12))
            .clipShape(Capsule())
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

    private var baseTitle: String { String(solar.title.dropLast("（公历）".count)) }
    private var nearest: Reminder { solar.nextTriggerAt <= lunar.nextTriggerAt ? solar : lunar }

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.pink.opacity(0.32), .purple.opacity(0.24)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                Text(nearest.typeEmoji)
                    .font(.system(size: 20))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(baseTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(Localized("公历 %@", solar.dateDisplayText))
                        .font(.caption)
                        .foregroundStyle(.pink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.pink.opacity(0.12))
                        .clipShape(Capsule())
                    Text(Localized("农历 %@", lunar.dateDisplayText))
                        .font(.caption)
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Text(timeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ThemeTokens.brandPrimary)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clayCard(radius: 18)
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
