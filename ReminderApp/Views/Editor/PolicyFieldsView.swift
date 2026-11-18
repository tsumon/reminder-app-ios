import SwiftUI

/// 高级重试策略 + 勿扰时段 + 触发时间预览（默认收起在底纸纯文字行下）
struct PolicyFields: View {
    @Binding var recurrenceMode: String
    @Binding var style: String
    @Binding var intervals: String
    @Binding var attempts: Int
    @Binding var useAlarmKit: Bool
    @Binding var quietEnabled: Bool
    @Binding var quietStart: Int
    @Binding var quietEnd: Int
    var repeatingCycle: Bool
    var previewReminder: Reminder

    @Environment(\.comic) private var comic

    var body: some View {
        ComicCard(cut: ThemeTokens.cardCut, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                if repeatingCycle {
                    HStack {
                        Text("周期起点".localized)
                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(comic.muted)
                        Spacer()
                        Picker("周期起点".localized, selection: $recurrenceMode) {
                            Text("按原计划固定循环".localized).tag("fixed")
                            Text("从实际完成时间重新计算".localized).tag("afterCompletion")
                        }
                        .pickerStyle(.menu)
                    }
                }

                HStack {
                    Text("提醒方式".localized)
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(comic.muted)
                    Spacer()
                    Picker("提醒方式".localized, selection: $style) {
                        Text("轻柔 · 提醒一次".localized).tag("gentle")
                        Text("持续 · 逐次重试".localized).tag("persistent")
                        Text("重要 · 可使用系统闹钟".localized).tag("important")
                    }
                    .pickerStyle(.menu)
                }

                if style != "gentle" {
                    let parsedList = Self.parsed(intervals) ?? ReminderPolicy.legacyIntervals
                    ForEach(Array(parsedList.enumerated()), id: \.offset) { index, minutes in
                        VStack(alignment: .leading, spacing: 4) {
                            Stepper(value: Binding(
                                get: {
                                    let values = Self.parsed(intervals) ?? ReminderPolicy.legacyIntervals
                                    return values.indices.contains(index) ? values[index] : 60
                                },
                                set: { new in
                                    var values = Self.parsed(intervals) ?? ReminderPolicy.legacyIntervals
                                    guard values.indices.contains(index) else { return }
                                    values[index] = new
                                    intervals = values.map(String.init).joined(separator: ",")
                                }
                            ), in: 1...10080) {
                                Text(Localized("第 %d 次重试 · %d 分钟", index + 1, minutes))
                                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(comic.ink)
                            }
                            if parsedList.count > 1 {
                                Button("移除此间隔".localized) {
                                    var values = Self.parsed(intervals) ?? ReminderPolicy.legacyIntervals
                                    if values.count > 1 && values.indices.contains(index) {
                                        values.remove(at: index)
                                        intervals = values.map(String.init).joined(separator: ",")
                                    }
                                }
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(comic.danger)
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button("添加重试间隔".localized) {
                        var values = Self.parsed(intervals) ?? ReminderPolicy.legacyIntervals
                        if values.count < 10 {
                            values.append(values.last ?? 60)
                            intervals = values.map(String.init).joined(separator: ",")
                        }
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(comic.hero)
                    .buttonStyle(.plain)
                    .disabled((Self.parsed(intervals)?.count ?? 0) >= 10)

                    Stepper(value: $attempts, in: 1...10) {
                        Text("最多提醒 \(attempts) 次")
                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(comic.ink)
                    }

                    Text("间隔 1–10080 分钟，最多 10 个；所有重试遵守勿扰时段。".localized)
                        .font(.system(size: 11.5, weight: .regular, design: .rounded))
                        .foregroundStyle(comic.muted)
                }

                if style == "important" {
                    Toggle("使用 AlarmKit 系统闹钟（iOS 26+）".localized, isOn: $useAlarmKit)
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .tint(comic.accent)
                }

                ComicHairline(outer: false)

                Toggle("启用每日勿扰".localized, isOn: $quietEnabled)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(comic.ink)
                    .tint(comic.accent)

                if quietEnabled {
                    Stepper(
                        "开始：\(String(format: "%02d:%02d", quietStart / 60, quietStart % 60))",
                        value: $quietStart,
                        in: 0...1439,
                        step: 15
                    )
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .monospacedDigit()

                    Stepper(
                        "结束：\(String(format: "%02d:%02d", quietEnd / 60, quietEnd % 60))",
                        value: $quietEnd,
                        in: 0...1439,
                        step: 15
                    )
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .monospacedDigit()
                }

                ComicHairline(outer: false)

                schedulePreviewBlock
            }
        }
    }

    private var schedulePreviewBlock: some View {
        let dates = ReminderEngine.shared.futureTriggers(for: previewReminder, count: 3)
        return VStack(alignment: .leading, spacing: 6) {
            Text("提醒预览".localized)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(comic.ink)
            ForEach(Array(dates.enumerated()), id: \.offset) { idx, date in
                HStack {
                    Text(Localized("第 %d 次周期", idx + 1))
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(comic.muted)
                    Spacer()
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(comic.ink)
                }
            }
            if style != "gentle", let first = dates.first {
                let retries = ReminderPolicy.deliveryDates(for: previewReminder, now: first.addingTimeInterval(-1))
                ForEach(Array(retries.dropFirst().prefix(3).enumerated()), id: \.offset) { idx, date in
                    Text(Localized("重试 %d · %@", idx + 1, date.formatted(date: .abbreviated, time: .shortened)))
                        .font(.system(size: 11.5, weight: .regular, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(comic.muted)
                }
            }
        }
    }

    static func parsed(_ text: String) -> [Int]? {
        let parts = text.replacingOccurrences(of: "，", with: ",").split(separator: ",", omittingEmptySubsequences: false)
        let values = parts.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return !values.isEmpty && values.count == parts.count && values.count <= 10 && values.allSatisfy { (1...10080).contains($0) } ? values : nil
    }
}
