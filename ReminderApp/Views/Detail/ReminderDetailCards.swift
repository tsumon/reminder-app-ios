import SwiftUI

/// 详情页主卡片组件：焦点状态与确认卡 + 纯文字规则与策略卡
struct DetailHeroStatusCard: View {
    let reminder: Reminder
    let highlightConfirm: Bool
    var onConfirm: () -> Void
    var onMakeUpConfirm: () -> Void
    var onSnooze15: () -> Void
    var onSnooze60: () -> Void
    var onSnoozeTomorrow: () -> Void
    var onCustomSnooze: () -> Void
    var onSkip: () -> Void
    var onUndoCompletion: () -> Void
    var onEdit: () -> Void

    @Environment(\.comic) private var comic

    private var isDue: Bool {
        reminder.status == .active || reminder.status == .snoozed || reminder.status == .overdue
    }

    var body: some View {
        ComicCard(cut: ThemeTokens.cardCut, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("当前状态".localized)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(comic.muted)
                        ComicHeroNumber(text: heroBadgeText, size: 44)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 5) {
                        Text(statusTitle)
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(reminder.status == .overdue ? comic.danger : comic.ink)
                            .multilineTextAlignment(.trailing)
                        Text(reminder.dateDisplayText)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(comic.muted)
                        Text(nextTriggerText)
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(comic.muted)
                    }
                }

                ComicHairline(outer: false)

                HStack(alignment: .center, spacing: 12) {
                    if isDue {
                        Menu {
                            Button("15 分钟".localized, action: onSnooze15)
                            Button("1 小时".localized, action: onSnooze60)
                            Button("明天".localized, action: onSnoozeTomorrow)
                            Button("自定义…".localized, action: onCustomSnooze)
                        } label: {
                            Text("稍后提醒".localized)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(comic.muted)
                        }
                    }

                    if !(reminder.kind == .cycle && reminder.cycle == .once) {
                        Button("跳过本次".localized, action: onSkip)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(comic.muted)
                            .buttonStyle(.plain)
                    }

                    if reminder.undoCompletion != nil {
                        Button("撤销完成".localized, action: onUndoCompletion)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(comic.hero)
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("undo-completion")
                    }

                    Button("编辑完整规则".localized, action: onEdit)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(comic.hero)
                        .buttonStyle(.plain)

                    Spacer(minLength: 4)

                    if isDue {
                        Button(action: onConfirm) {
                            Text("确认完成".localized)
                        }
                        .buttonStyle(ComicButtonStyle(variant: .accent))
                        .accessibilityIdentifier("detail-confirm")
                    }
                }

                if reminder.status == .overdue {
                    HStack {
                        Spacer()
                        Button(action: onMakeUpConfirm) {
                            Text("补打今天".localized)
                        }
                        .buttonStyle(ComicButtonStyle(variant: .surface))
                    }
                }
            }
        }
    }

    private var heroBadgeText: String {
        switch reminder.status {
        case .confirmed: return "#OK"
        case .overdue:   return "#!!"
        default:
            return reminder.retryStage > 0 ? "#R\(reminder.retryStage)" : "#01"
        }
    }

    private var statusTitle: String {
        var t = reminder.status.rawValue.localized
        if reminder.retryStage > 0 {
            t += " · " + Localized("第%d次重试", reminder.retryStage)
        }
        return t
    }

    private var nextTriggerText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy/M/d HH:mm"
        return Localized("下次：%@", f.string(from: reminder.nextTriggerAt))
    }
}

/// 详情页规则与开关卡片
struct DetailInfoCard: View {
    let reminder: Reminder
    let holidayAdjustNote: String?
    @Binding var quietHoursEnabled: Bool
    @Binding var quietStart: Date
    @Binding var quietEnd: Date
    var onToggleEnabled: (Bool) -> Void
    var onToggleImportant: (Bool) -> Void
    var onToggleQuiet: (Bool) -> Void
    var onPersistQuiet: () -> Void

    @Environment(\.comic) private var comic

    var body: some View {
        ComicCard(cut: ThemeTokens.cardCut, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("规则与提醒设置".localized)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(comic.ink)

                if let note = holidayAdjustNote {
                    Text("· \(note)")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(comic.warn)
                }

                if !reminder.note.isEmpty {
                    infoRow("备注".localized, reminder.note)
                }
                infoRow("周期".localized, reminder.dateDisplayText)
                if reminder.kind == .cycle && reminder.cycle == .custom && reminder.customDays > 0 {
                    infoRow("自定义天数".localized, Localized("%d 天", reminder.customDays))
                }
                if reminder.kind == .rule {
                    infoRow("频率".localized, reminder.rulePeriod.rawValue.localized)
                    infoRow("周次".localized, "\(reminder.ruleWeek.label.localized) · \(reminder.ruleWeekday.label.localized)")
                }
                if reminder.kind == .date {
                    infoRow("提前提醒".localized, Localized("%d 天", reminder.advanceDays))
                }
                infoRow("首次提醒".localized, formattedDate(reminder.firstTriggerAt))
                infoRow("下次提醒".localized, formattedDate(reminder.nextTriggerAt))
                infoRow("创建时间".localized, formattedDate(reminder.createdAt))

                ComicHairline(outer: false)

                Toggle("启用提醒".localized, isOn: Binding(get: { reminder.isEnabled }, set: onToggleEnabled))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(comic.ink)
                    .tint(comic.accent)

                Toggle(isOn: Binding(get: { reminder.reminderStyle == "important" }, set: onToggleImportant)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("关键提醒".localized)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(comic.ink)
                        Text("重要事项按所选间隔重试，达到上限后停止".localized)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(comic.muted)
                    }
                }
                .tint(comic.accent)

                Toggle(isOn: Binding(get: { quietHoursEnabled }, set: onToggleQuiet)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("勿扰时段".localized)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(comic.ink)
                        Text("该时段内到点的提醒顺延到时段结束".localized)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(comic.muted)
                    }
                }
                .tint(comic.accent)

                if quietHoursEnabled {
                    HStack {
                        DatePicker("开始".localized, selection: $quietStart, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .onChange(of: quietStart) { _, _ in onPersistQuiet() }
                        Text("—")
                            .foregroundStyle(comic.muted)
                        DatePicker("结束".localized, selection: $quietEnd, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .onChange(of: quietEnd) { _, _ in onPersistQuiet() }
                    }
                }
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                .foregroundStyle(comic.muted)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(comic.ink)
                .multilineTextAlignment(.trailing)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy/M/d HH:mm"
        return f.string(from: date)
    }
}
