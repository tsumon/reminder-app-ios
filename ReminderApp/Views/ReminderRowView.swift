import SwiftUI

/// 提醒行视图（列表中的每一行）
struct ReminderRowView: View {
    let reminder: Reminder

    var body: some View {
        HStack(spacing: 14) {
            // 状态图标（带状态色底盘）
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.14))
                    .frame(width: 38, height: 38)
                statusIcon
                    .font(.title3)
            }
            .accessibilityLabel("状态：\(reminder.status.rawValue)")

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

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

                    // 状态文字
                    Text(reminder.status.rawValue)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }

                if reminder.note.isNotEmpty {
                    Text(reminder.note)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // 下次触发时间
            VStack(alignment: .trailing, spacing: 2) {
                Text(timeText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                if reminder.retryStage > 0 {
                    Text("第\(reminder.retryStage)次重试")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(reminder.isEnabled ? 1 : 0.5)
    }

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

    // MARK: - 状态图标

    @ViewBuilder
    private var statusIcon: some View {
        switch reminder.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.blue)
        case .active:
            Image(systemName: "bell.badge.fill")
                .foregroundStyle(.red)
        case .snoozed:
            Image(systemName: "moon.zzz.fill")
                .foregroundStyle(.orange)
        case .confirmed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .overdue:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private var statusColor: Color {
        switch reminder.status {
        case .pending:   return .blue
        case .active:    return .red
        case .snoozed:   return .orange
        case .confirmed: return .green
        case .overdue:   return .red
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
