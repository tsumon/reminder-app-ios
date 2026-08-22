import SwiftUI

/// 提醒行视图（列表中的每一行）
struct ReminderRowView: View {
    let reminder: Reminder

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
                    // 类型标签
                    Image(systemName: reminder.kindIcon)
                        .font(.caption2)
                    Text(kindLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(kindBadgeColor.opacity(0.12))
                        .clipShape(Capsule())
                }

                // v1.9.8 状态胶囊（设计图独立 chip）
                HStack(spacing: 6) {
                    Text(reminder.status.rawValue.localized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(0.12))
                        .clipShape(Capsule())

                    if reminder.retryStage > 0 && !isDone {
                        Text(Localized("第%d次重试", reminder.retryStage))
                            .font(.caption2)
                            .foregroundStyle(ThemeTokens.statusSnoozed)
                    }
                }

                if reminder.note.isNotEmpty && reminder.retryStage == 0 {
                    Text(reminder.note)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // 下次触发时间：状态色（设计图）
            Text(timeText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isDone ? Color(.tertiaryLabel) : statusColor)
                .multilineTextAlignment(.trailing)
        }
        // 液态玻璃行：ultraThinMaterial + 高光描边 + 柔和阴影
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.35), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        .opacity(reminder.isEnabled ? 1 : 0.5)
    }

    private var isDone: Bool { reminder.status == .confirmed }

    // MARK: - 类型标签

    private var kindLabel: String {
        "\(reminder.priority.emoji) \(reminder.dateDisplayText)"
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

                HStack(spacing: 6) {
                    Text(nearest.status.rawValue.localized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            Spacer()

            Text(timeText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
                .multilineTextAlignment(.trailing)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.35), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        .opacity(nearest.isEnabled ? 1 : 0.5)
    }

    private var statusColor: Color {
        switch nearest.status {
        case .pending:   return ThemeTokens.statusWaiting
        case .active:    return ThemeTokens.statusReminding
        case .snoozed:   return ThemeTokens.statusSnoozed
        case .confirmed: return ThemeTokens.statusCompleted
        case .overdue:   return ThemeTokens.statusOverdue
        }
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
