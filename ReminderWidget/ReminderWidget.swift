import WidgetKit
import SwiftUI

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
    var entry: ReminderEntry

    var body: some View {
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

            // 最近提醒
            Text("最近提醒")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text(entry.data.nextTitle)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)

            if let time = entry.data.nextTime {
                Text(time, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("暂无安排")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
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
        .description("显示未处理提醒数和距离最近的提醒")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Bundle

@main
struct ReminderWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReminderWidget()
    }
}
