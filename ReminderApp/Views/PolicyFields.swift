import SwiftUI

struct PolicyFields: View {
    @Binding var recurrenceMode: String
    @Binding var style: String
    @Binding var intervals: String
    @Binding var attempts: Int
    @Binding var useAlarmKit: Bool
    var repeatingCycle: Bool
    var body: some View {
        Section("提醒策略".localized) {
            if repeatingCycle {
                Picker("周期起点".localized, selection: $recurrenceMode) {
                    Text("按原计划固定循环".localized).tag("fixed")
                    Text("从实际完成时间重新计算".localized).tag("afterCompletion")
                }
            }
            Picker("提醒方式".localized, selection: $style) {
                Text("轻柔 · 提醒一次".localized).tag("gentle")
                Text("持续 · 逐次重试".localized).tag("persistent")
                Text("重要 · 可使用系统闹钟".localized).tag("important")
            }
            if style != "gentle" {
                ForEach(Array((Self.parsed(intervals) ?? ReminderPolicy.legacyIntervals).enumerated()), id: \.offset) { index, minutes in
                    Stepper(value: Binding(get: { let values=Self.parsed(intervals) ?? ReminderPolicy.legacyIntervals; return values.indices.contains(index) ? values[index] : 60 }, set: { new in
                        var values=Self.parsed(intervals) ?? ReminderPolicy.legacyIntervals
                        guard values.indices.contains(index) else { return }
                        values[index]=new; intervals=values.map(String.init).joined(separator:",")
                    }), in: 1...10080) {
                        Text(Localized("第 %d 次重试 · %d 分钟", index+1, minutes))
                    }
                    Button("移除此间隔".localized, role: .destructive) {
                        var values=Self.parsed(intervals) ?? ReminderPolicy.legacyIntervals
                        if values.count>1 && values.indices.contains(index) { values.remove(at:index); intervals=values.map(String.init).joined(separator:",") }
                    }.disabled((Self.parsed(intervals)?.count ?? 0)<=1)
                }
                Button("添加重试间隔".localized) {
                    var values=Self.parsed(intervals) ?? ReminderPolicy.legacyIntervals
                    if values.count<10 { values.append(values.last ?? 60); intervals=values.map(String.init).joined(separator:",") }
                }.disabled((Self.parsed(intervals)?.count ?? 0)>=10)
                Stepper("最多提醒 \(attempts) 次", value: $attempts, in: 1...10)
                Text("间隔 1–10080 分钟，最多 10 个；用完后重复最后一个。所有重试遵守勿扰时段。".localized)
                    .font(.caption).foregroundStyle(.secondary)
            }
            if style == "important" {
                Toggle("使用 AlarmKit 系统闹钟（iOS 26+）".localized, isOn: $useAlarmKit)
                Text("需单独授权。不可用或未允许时使用普通通知；普通通知受静音、专注模式和系统设置影响。".localized)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    static func parsed(_ text: String) -> [Int]? {
        let parts = text.replacingOccurrences(of: "，", with: ",").split(separator: ",", omittingEmptySubsequences: false)
        let values = parts.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return !values.isEmpty && values.count == parts.count && values.count <= 10 && values.allSatisfy { (1...10080).contains($0) } ? values : nil
    }
}
