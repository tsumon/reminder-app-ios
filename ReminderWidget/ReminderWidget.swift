import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Entry & Provider

struct ReminderEntry: TimelineEntry {
    let date: Date
    let data: WidgetReminderData
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> ReminderEntry {
        ReminderEntry(date: Date(), data: WidgetSnapshot.load())
    }

    func getSnapshot(in context: Context, completion: @escaping (ReminderEntry) -> Void) {
        completion(ReminderEntry(date: Date(), data: WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReminderEntry>) -> Void) {
        let entry = ReminderEntry(date: Date(), data: WidgetSnapshot.load())
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

// MARK: - 小组件自包含极简奶油漫风原语（Target 独立编译，严禁依赖宿主 Views）

private struct WidgetChamferShape: Shape {
    var cut: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        let c = min(cut, min(rect.width, rect.height) * 0.45)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - c, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + c, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - c))
        p.closeSubpath()
        return p
    }
}

private struct WidgetComicColors {
    let canvas: Color
    let surface: Color
    let ink: Color
    let border: Color
    let shadow: Color
    let muted: Color
    let rule: Color
    let accent: Color
    let onAccent: Color
    let hero: Color
    let heroShadow: Color

    static func of(_ scheme: ColorScheme) -> WidgetComicColors {
        if scheme == .dark {
            return WidgetComicColors(
                canvas: Self.hex(0x1B1613),
                surface: Self.hex(0x261F1B),
                ink: Self.hex(0xF3E3CF),
                border: Self.hex(0xC9AE92),
                shadow: Self.hex(0x0B0807),
                muted: Self.hex(0xA38D78),
                rule: Self.hex(0x382D26),
                accent: Self.hex(0xF06A29),
                onAccent: Self.hex(0x1F0E05),
                hero: Self.hex(0xF6A86E),
                heroShadow: Self.hex(0x4A240B)
            )
        }
        return WidgetComicColors(
            canvas: Self.hex(0xF6E5C8),
            surface: Self.hex(0xFFF5DF),
            ink: Self.hex(0x472714),
            border: Self.hex(0x472714),
            shadow: Self.hex(0x472714),
            muted: Self.hex(0x6D503B),
            rule: Self.hex(0xE5CCA9),
            accent: Self.hex(0xF06A29),
            onAccent: Self.hex(0x27140B),
            hero: Self.hex(0x774501),
            heroShadow: Self.hex(0xFCC5A2)
        )
    }

    private static func hex(_ v: UInt32) -> Color {
        Color(
            red: Double((v >> 16) & 0xFF) / 255.0,
            green: Double((v >> 8) & 0xFF) / 255.0,
            blue: Double(v & 0xFF) / 255.0
        )
    }
}

// MARK: - 小组件视图

struct ReminderWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    var entry: ReminderEntry

    private var c: WidgetComicColors { WidgetComicColors.of(scheme) }

    var body: some View {
        Group {
            switch family {
            case .systemLarge:
                largeView
            default:
                compactView
            }
        }
        .padding(10)
        .background {
            ZStack {
                WidgetChamferShape(cut: 9)
                    .fill(c.shadow)
                    .offset(x: 1.8, y: 1.8)
                WidgetChamferShape(cut: 9)
                    .fill(c.surface)
                WidgetChamferShape(cut: 9)
                    .stroke(c.border, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
            }
        }
        .padding(4)
        .containerBackground(for: .widget) {
            c.canvas
        }
        .widgetURL(detailURL)
    }

    // MARK: - Small / Medium 紧凑印张

    private var compactView: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("待确认".localized)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(c.muted)
                Spacer()
                heroCount(size: 24)
            }

            Rectangle()
                .fill(c.rule)
                .frame(height: 1)

            Text(entry.data.nextTitle)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(c.ink)
                .lineLimit(1)

            HStack(spacing: 4) {
                if let time = entry.data.nextTime {
                    Text(countdownText(from: entry.date, to: time))
                        .monospacedDigit()
                } else {
                    Text("暂无安排".localized)
                }
                if family != .systemSmall {
                    Text("· 农历\(lunarText)")
                }
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(c.muted)
            .lineLimit(1)

            Spacer(minLength: 0)

            completeButton
        }
    }

    // MARK: - Large 通透大印张

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("未处理提醒".localized)
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(c.muted)
                    heroCount(size: 42)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("农历\(lunarText)")
                        .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(c.ink)
                    Text(ganzhiText)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(c.muted)
                }
            }

            Rectangle()
                .fill(c.rule)
                .frame(height: 1)

            Text("最近提醒".localized)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(c.muted)

            Text(entry.data.nextTitle)
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(c.ink)
                .lineLimit(2)

            if let time = entry.data.nextTime {
                Text(countdownText(from: entry.date, to: time))
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(c.muted)
            } else {
                Text("暂无安排".localized)
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .foregroundStyle(c.muted)
            }

            Spacer(minLength: 4)

            completeButton
        }
        .padding(4)
    }

    private func heroCount(size: CGFloat) -> some View {
        let label = String(format: "#%02d", entry.data.unhandledCount)
        return ZStack(alignment: .topLeading) {
            Text(label)
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(c.heroShadow)
                .offset(x: 1.6, y: 1.6)
                .accessibilityHidden(true)
            Text(label)
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(c.hero)
        }
    }

    // MARK: - 交互按钮（奶油橙底 + 深咖墨字 #27140B）

    @ViewBuilder
    private var completeButton: some View {
        if let id = entry.data.nextReminderID, !id.isEmpty {
            if WidgetSnapshot.completedReminderIDs().contains(id) {
                Text("✓ " + "已标记完成，打开 App 生效".localized)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(c.hero)
            } else if WidgetSnapshot.snoozedReminderIDs().contains(id) {
                Text("› " + "已推迟 15 分钟，打开 App 生效".localized)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(c.muted)
            } else {
                let canSnooze = (entry.data.nextTime ?? .distantFuture) <= entry.date
                HStack(spacing: 8) {
                    Button(intent: CompleteReminderIntent(reminderID: id, token: entry.data.nextActionToken ?? "")) {
                        Text("完成".localized)
                            .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(c.onAccent)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background {
                                WidgetChamferShape(cut: 4.5)
                                    .fill(c.accent)
                                WidgetChamferShape(cut: 4.5)
                                    .stroke(c.border, lineWidth: 1.2)
                            }
                    }
                    .buttonStyle(.plain)

                    if canSnooze {
                        Button(intent: SnoozeReminderIntent(reminderID: id, token: entry.data.nextActionToken ?? "")) {
                            Text("稍后".localized)
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .foregroundStyle(c.muted)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var detailURL: URL? {
        guard let id = entry.data.nextReminderID, !id.isEmpty else { return nil }
        return URL(string: "reminder://detail/\(id)")
    }

    private var lunarText: String {
        LunarCalendar.solarToLunar(entry.date).description
    }

    private var ganzhiText: String {
        let lunar = LunarCalendar.solarToLunar(entry.date)
        let stems = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
        let branches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
        let index = ((lunar.year - 1984) % 60 + 60) % 60
        return stems[index % 10] + branches[index % 12] + "年"
    }
}

private func countdownText(from now: Date, to target: Date) -> String {
    let seconds = Int(target.timeIntervalSince(now))
    guard seconds > 0 else { return "已到时间".localized }
    let days = seconds / 86400
    let hours = (seconds % 86400) / 3600
    let minutes = (seconds % 3600) / 60
    if days > 0 {
        return Localized("%d 天后", days)
    } else if hours > 0 {
        return minutes > 0 ? Localized("%d 小时 %d 分后", hours, minutes) : Localized("%d 小时后", hours)
    } else if minutes > 0 {
        return Localized("%d 分钟后", minutes)
    } else {
        return Localized("%d 秒后", seconds)
    }
}

struct ReminderWidget: Widget {
    let kind = "ReminderWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ReminderWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("循环提醒".localized)
        .description("显示未处理提醒数、今天农历和最近的提醒，支持一键完成".localized)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct ReminderWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReminderWidget()
    }
}
