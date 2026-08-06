import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Entry

struct ReminderEntry: TimelineEntry {
    let date: Date
    let data: WidgetReminderData
}

// MARK: - Provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> ReminderEntry {
        ReminderEntry(date: Date(), data: WidgetSnapshot.load())
    }

    func getSnapshot(in context: Context, completion: @escaping (ReminderEntry) -> Void) {
        completion(ReminderEntry(date: Date(), data: WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReminderEntry>) -> Void) {
        let entry = ReminderEntry(date: Date(), data: WidgetSnapshot.load())
        // 每小时刷新一次；App 更新数据后会通过 WidgetCenter 主动刷新
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

// MARK: - View

struct ReminderWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: ReminderEntry

    var body: some View {
        switch family {
        case .systemLarge:
            largeView
        default:
            compactView
        }
    }

    // MARK: 紧凑布局（small / medium）

    private var compactView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 未处理提醒
            HStack(spacing: 6) {
                Image(systemName: "bell.badge.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                Text("未处理提醒")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(entry.data.unhandledCount)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.red)
            }

            Divider()

            // 今天农历（v1.8.7）
            HStack(spacing: 4) {
                Image(systemName: "moon.stars.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text(lunarText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // 最近提醒
            Text(entry.data.nextTitle)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)

            if let time = entry.data.nextTime {
                Text(countdownText(from: entry.date, to: time))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("暂无安排")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            completeButton
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: 大尺寸布局（systemLarge，v1.8.7）

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 头部：未处理数 + 农历日期格
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("未处理提醒")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Image(systemName: "bell.badge.fill")
                            .font(.title3)
                            .foregroundStyle(.red)
                        Text("\(entry.data.unhandledCount)")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(.red)
                    }
                }
                Spacer()
                // 农历日期格：今天农历 + 干支年
                VStack(alignment: .trailing, spacing: 2) {
                    Text(lunarText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(ganzhiText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Divider()

            // 最近提醒
            Text("最近提醒")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Text(entry.data.nextTitle)
                .font(.title3.weight(.bold))
                .lineLimit(1)

            if let time = entry.data.nextTime {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.subheadline)
                        .foregroundStyle(.purple)
                    Text(countdownText(from: entry.date, to: time))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("暂无安排")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            completeButton
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: 完成按钮（v1.8.7，iOS 17 widget 交互）

    @ViewBuilder
    private var completeButton: some View {
        if let id = entry.data.nextReminderID, !id.isEmpty {
            if WidgetSnapshot.completedReminderIDs().contains(id) {
                // 已在小组件上标记完成，等 App 启动同步落库
                Label("已标记完成，打开 App 生效", systemImage: "checkmark.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Button(intent: CompleteReminderIntent(reminderID: id)) {
                    Label("完成", systemImage: "checkmark.circle")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(.green)
                }
            }
        }
    }

    // MARK: - 农历

    /// 今天农历，如「正月十五」
    private var lunarText: String {
        LunarCalendar.solarToLunar(entry.date).description
    }

    /// 干支年，如「丙午年」
    private var ganzhiText: String {
        let lunar = LunarCalendar.solarToLunar(entry.date)
        let stems = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
        let branches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
        // 干支以 1984 甲子年为基准：absoluteYear - 1984 取模 60
        let index = ((lunar.year - 1984) % 60 + 60) % 60
        return stems[index % 10] + branches[index % 12] + "年"
    }
}

// MARK: - 倒计时文案（v1.8.7：自定义「X小时Y分后」，优于系统 .relative 英文格式）

private func countdownText(from now: Date, to target: Date) -> String {
    let seconds = Int(target.timeIntervalSince(now))
    guard seconds > 0 else { return "已到时间" }
    let days = seconds / 86400
    let hours = (seconds % 86400) / 3600
    let minutes = (seconds % 3600) / 60
    if days > 0 {
        return "\(days) 天后"
    } else if hours > 0 {
        return minutes > 0 ? "\(hours) 小时 \(minutes) 分后" : "\(hours) 小时后"
    } else if minutes > 0 {
        return "\(minutes) 分钟后"
    } else {
        return "\(seconds) 秒后"
    }
}

// MARK: - Widget

struct ReminderWidget: Widget {
    let kind = "ReminderWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ReminderWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("循环提醒")
        .description("显示未处理提醒数、今天农历和最近的提醒，支持一键完成")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Bundle

@main
struct ReminderWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReminderWidget()
    }
}
