import SwiftUI

// MARK: - 治愈游戏色板（v2.5.0）

/// 治愈游戏化设计令牌（粘土拟态 Claymorphism）。
/// 装饰/奖励色固定不随主题色板切换；主强调色仍走 ThemeTokens.brandPrimary。
enum Playful {
    static let cream    = Color(hex: 0xFFF5E6)   // 暖白基底
    static let purple   = Color(hex: 0x6C5CE7)   // 紫（打卡按钮/数据高亮）
    static let coral    = Color(hex: 0xFF6B6B)   // 珊瑚粉
    static let gold     = Color(hex: 0xFECA57)   // 星星金（奖励反馈）
    static let mint     = Color(hex: 0x55EFC4)   // 薄荷绿（奖励反馈）
    static let ink      = Color(hex: 0x2D3436)   // 深灰（周期规则徽章，形成对比）
    static let peach    = Color(hex: 0xFFE1C4)   // 背景·桃
    static let lavender = Color(hex: 0xE4DCF7)   // 背景·薰衣草
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

// MARK: - 粘土卡样式

/// 粘土拟态卡片：大圆角 + 暖白渐变底 + 顶部内高光 + 双层柔和阴影（外彩内灰）
struct ClayCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(scheme == .dark
                          ? AnyShapeStyle(Color(hex: 0x2A2735))
                          : AnyShapeStyle(LinearGradient(
                              colors: [.white, Playful.cream],
                              startPoint: .topLeading,
                              endPoint: .bottomTrailing)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: scheme == .dark
                                ? [.white.opacity(0.10), .white.opacity(0.03)]
                                : [.white.opacity(0.85), .white.opacity(0.25)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: Playful.purple.opacity(scheme == .dark ? 0.0 : 0.10), radius: 14, y: 8)
            .shadow(color: .black.opacity(0.06), radius: 5, y: 3)
    }
}

extension View {
    func clayCard(radius: CGFloat = 24) -> some View {
        modifier(ClayCardModifier(radius: radius))
    }
}

// MARK: - 桃粉薰衣草渐变背景 + 漂浮装饰

/// 页面背景：桃 + 薰衣草软渐变，散布缓慢漂浮的星星/云朵（深色模式回落深紫灰）
struct PastelPlaygroundBackground: View {
    @Environment(\.colorScheme) private var scheme
    @State private var floatUp = false

    private struct Decor: Identifiable {
        let id: Int
        let emoji: String
        let x: CGFloat   // 0-1 水平相对位置
        let y: CGFloat   // 0-1 垂直相对位置
        let size: CGFloat
        let opacity: CGFloat
        let duration: Double
    }

    private let decors: [Decor] = [
        Decor(id: 0, emoji: "☁️", x: 0.12, y: 0.10, size: 30, opacity: 0.9, duration: 5.2),
        Decor(id: 1, emoji: "⭐️", x: 0.88, y: 0.16, size: 16, opacity: 0.9, duration: 4.1),
        Decor(id: 2, emoji: "✨", x: 0.76, y: 0.62, size: 14, opacity: 0.8, duration: 4.8),
        Decor(id: 3, emoji: "☁️", x: 0.80, y: 0.86, size: 24, opacity: 0.7, duration: 5.6),
        Decor(id: 4, emoji: "⭐️", x: 0.08, y: 0.72, size: 13, opacity: 0.8, duration: 4.4),
        Decor(id: 5, emoji: "✨", x: 0.30, y: 0.40, size: 12, opacity: 0.6, duration: 5.0)
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: scheme == .dark
                        ? [Color(hex: 0x272333), Color(hex: 0x1C1A26)]
                        : [Playful.peach, Playful.lavender],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                ForEach(decors) { d in
                    Text(d.emoji)
                        .font(.system(size: d.size))
                        .opacity(scheme == .dark ? d.opacity * 0.45 : d.opacity)
                        .position(
                            x: geo.size.width * d.x,
                            y: geo.size.height * d.y + (floatUp ? -7 : 7)
                        )
                        .animation(
                            .easeInOut(duration: d.duration).repeatForever(autoreverses: true),
                            value: floatUp
                        )
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear { floatUp = true }
    }
}

// MARK: - 3D 吉祥物

/// 吉祥物（小狐狸）：表情随完成率变化，庆祝时戴派对帽
struct MascotView: View {
    enum Mood {
        case cheer   // 全部完成/高完成率
        case happy   // 有进展
        case idle    // 待办中
        case sleepy  // 无任务/低完成

        var emoji: String { "🦊" }
        var accessory: String? {
            switch self {
            case .cheer: return "🎉"
            case .happy: return "✨"
            case .idle:  return nil
            case .sleepy: return "💤"
            }
        }
    }

    let mood: Mood
    var size: CGFloat = 44
    @State private var floatUp = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Text(mood.emoji)
                .font(.system(size: size * 0.55))
                .offset(y: floatUp ? -1.5 : 1.5)
                .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: floatUp)

            if let acc = mood.accessory {
                Text(acc)
                    .font(.system(size: size * 0.26))
                    .offset(x: size * 0.18, y: -size * 0.04)
            }
        }
        .frame(width: size, height: size)
        .background(
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.95), Playful.cream],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5))
        .clipShape(Circle())
        .shadow(color: Playful.purple.opacity(0.14), radius: 6, y: 3)
        .onAppear { floatUp = true }
    }
}

/// 吉祥物手里的连胜小旗：「🔥 第 N 天」
struct StreakFlag: View {
    let days: Int
    var body: some View {
        Text("🔥 \(Localized("第 %d 天", days))")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(
                    LinearGradient(colors: [Playful.coral, Playful.gold],
                                   startPoint: .leading, endPoint: .trailing)
                )
            )
            .overlay(Capsule().strokeBorder(.white.opacity(0.7), lineWidth: 1))
            .shadow(color: Playful.coral.opacity(0.35), radius: 4, y: 2)
    }
}

// MARK: - 连续打卡城堡

/// 连续打卡城堡：连续天数越长楼层越高（每 3 天一层，封顶 7 层 + 金冠）
struct StreakCastleView: View {
    let streak: Int
    var compact = false

    /// 楼层数：0 天=空地小旗，每 3 天 +1 层，最多 7 层
    private var floors: Int { StreakCastleView.level(forStreak: streak) }

    /// 城堡等级（=楼层数），供统计页文案等处复用
    static func level(forStreak streak: Int) -> Int {
        guard streak > 0 else { return 0 }
        return min(7, 1 + (streak - 1) / 3)
    }

    private var floorHeight: CGFloat { compact ? 11 : 16 }
    private var towerWidth: CGFloat { compact ? 46 : 64 }

    var body: some View {
        VStack(spacing: 3) {
            if streak > 0 {
                StreakFlag(days: streak)
            } else {
                Text("🌱")
                    .font(.system(size: compact ? 14 : 18))
            }

            castle
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: floors)
    }

    private var castle: some View {
        VStack(spacing: 1) {
            // 塔顶：金冠（满级）/ 小旗
            if floors >= 7 {
                Text("👑").font(.system(size: compact ? 13 : 17))
            } else {
                Text("🚩").font(.system(size: compact ? 11 : 13))
            }

            // 层层堆叠的塔身（自上而下渐宽），每层一扇小窗
            VStack(spacing: 1) {
                ForEach(1...max(floors, 1), id: \.self) { floor in
                    let isTop = floor == 1
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: floorColors(floor),
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(width: towerWidth * (isTop ? 0.72 : 1.0),
                               height: floorHeight)
                        .overlay(alignment: .center) {
                            Circle()
                                .fill(Playful.ink.opacity(0.55))
                                .frame(width: 5, height: 5)
                                .offset(y: 1)
                        }
                }
            }

            // 城堡底座 + 城门
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: [Playful.gold, Playful.coral.opacity(0.85)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: towerWidth + 14, height: floorHeight + 4)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Playful.ink)
                    .frame(width: 12, height: floorHeight - 1)
                    .offset(y: -1)
            }
        }
        .opacity(floors == 0 ? 0.55 : 1)
    }

    /// 楼层配色：低层薄荷 → 高层星星金
    private func floorColors(_ floor: Int) -> [Color] {
        let ratio = floors > 1 ? Double(floor - 1) / Double(floors - 1) : 0
        let top = interpolate(from: Playful.mint, to: Playful.gold, t: ratio)
        return [top.opacity(0.95), top.opacity(0.7)]
    }

    private func interpolate(from a: Color, to b: Color, t: Double) -> Color {
        let clamped = min(max(t, 0), 1)
        let f = { (c: Color) in
            UIColor(c).rgba
        }
        let (r1, g1, b1, _) = f(a)
        let (r2, g2, b2, _) = f(b)
        return Color(red: r1 + (r2 - r1) * clamped,
                     green: g1 + (g2 - g1) * clamped,
                     blue: b1 + (b2 - b1) * clamped)
    }
}

extension UIColor {
    var rgba: (CGFloat, CGFloat, CGFloat, CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }
}

// MARK: - 彩带粒子（打卡庆祝）

/// 打卡成功彩带：粉彩纸屑 + 星星从顶部爆开，约 1.4s 后自然消散。
/// trigger 变化即重放一次；放在 overlay 全屏位置，不拦截点击。
struct ConfettiBurst: View {
    let trigger: Int
    @State private var startedAt: Date?
    // 空闲时暂停时间线，避免 TimelineView(.animation) 常年 60fps 空转耗电
    @State private var active = false

    private struct Particle {
        let angle: Double     // 弧度
        let speed: Double
        let spin: Double
        let size: Double
        let emoji: String?    // nil = 粉彩纸屑矩形
        let color: Color
        let delay: Double
    }

    private let particles: [Particle] = {
        var seed: UInt64 = 20260823
        func rand() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
        }
        let palette: [Color] = [Playful.gold, Playful.coral, Playful.mint, Playful.purple, Color(hex: 0xFFD9E8)]
        let emojis = ["⭐️", "✨", "🎉", "💫", nil]
        return (0..<46).map { i in
            Particle(
                angle: Double.pi / 2 + (rand() - 0.5) * Double.pi * 1.3,
                speed: 320 + rand() * 360,
                spin: (rand() - 0.5) * 12,
                size: 6 + rand() * 8,
                emoji: i % 3 == 0 ? emojis[Int(rand() * 4.99)] : nil,
                color: palette[Int(rand() * 4.99)],
                delay: rand() * 0.12
            )
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !active)) { timeline in
            Canvas { context, size in
                guard let start = startedAt else { return }
                let t = timeline.date.timeIntervalSince(start)
                guard t >= 0, t < 1.5 else { return }

                let origin = CGPoint(x: size.width / 2, y: size.height * 0.3)
                let gravity = 640.0

                for p in particles {
                    let pt = t - p.delay
                    guard pt >= 0 else { continue }
                    let x = origin.x + cos(p.angle) * p.speed * pt
                    let y = origin.y + sin(p.angle) * p.speed * pt + 0.5 * gravity * pt * pt
                    guard y < size.height + 30 else { continue }
                    let alpha = max(0, 1.3 - t) / 1.3
                    var ctx = context
                    ctx.opacity = alpha
                    let point = CGPoint(x: x, y: y)
                    if let emoji = p.emoji {
                        ctx.drawLayer { layer in
                            layer.translateBy(x: point.x, y: point.y)
                            layer.rotate(by: .radians(p.spin * pt))
                            layer.draw(Text(emoji).font(.system(size: p.size + 4)), at: .zero)
                        }
                    } else {
                        ctx.drawLayer { layer in
                            layer.translateBy(x: point.x, y: point.y)
                            layer.rotate(by: .radians(p.spin * pt))
                            let rect = CGRect(x: -p.size / 2, y: -p.size / 3, width: p.size, height: p.size * 0.66)
                            layer.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(p.color))
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            startedAt = Date()
            active = true
            // 粒子寿命 1.5s（含 delay），1.7s 后停表暂停时间线
            Task {
                try? await Task.sleep(nanoseconds: 1_700_000_000)
                active = false
            }
        }
    }
}

// MARK: - 发光球打卡按钮

/// 魔法光球打卡按钮：未完成=暖白球+虚线环；完成=薄荷→金渐变填充+光晕
struct OrbCheckButton: View {
    let done: Bool
    let action: () -> Void
    @State private var bounce = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(done
                          ? AnyShapeStyle(LinearGradient(colors: [Playful.mint, Playful.gold],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(LinearGradient(colors: [.white, Playful.cream.opacity(0.9)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing)))
                Circle()
                    .strokeBorder(done ? Color.clear : Playful.purple.opacity(0.35),
                                  style: StrokeStyle(lineWidth: 1.6, dash: [4, 3]))
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("✨")
                        .font(.system(size: 10))
                }
            }
            .frame(width: 34, height: 34)
            .shadow(color: done ? Playful.gold.opacity(0.75) : Playful.purple.opacity(0.12),
                    radius: done ? 9 : 4, y: 2)
            .scaleEffect(bounce ? 1.18 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: bounce)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: done)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(done ? "已完成".localized : "打卡".localized)
    }
}

// MARK: - 本周彩虹跑道进度条

/// 本周进度彩虹跑道：「本周 5/7 🎯」，跑道头挂一颗星星
struct WeeklyProgressTrack: View {
    let done: Int
    let total: Int

    private var progress: CGFloat {
        guard total > 0 else { return 0 }
        return min(1, CGFloat(done) / CGFloat(total))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("本周进度".localized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(done)/\(total) 🎯")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Playful.purple)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Playful.purple.opacity(0.10))
                    Capsule()
                        .fill(
                            LinearGradient(colors: [Playful.mint, Playful.gold, Playful.coral],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: max(geo.size.width * 0.04, geo.size.width * progress))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                    if progress > 0.02 {
                        Text("⭐️")
                            .font(.system(size: 13))
                            .offset(x: geo.size.width * progress - 9, y: 0)
                            .shadow(color: Playful.gold.opacity(0.6), radius: 4)
                    }
                }
            }
            .frame(height: 14)
            .animation(.spring(response: 0.6, dampingFraction: 0.85), value: progress)
        }
    }
}

// MARK: - 智能重复规则徽章

/// 周期规则徽章：`--strong` 浅容器洗色，圆角 8，无外描边。
struct RepeatRuleBadge: View {
    let reminder: Reminder
    @Environment(\.soft) private var soft

    private var ruleText: String {
        let time: String
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        switch reminder.kind {
        case .date:
            time = ""
        case .rule, .cycle:
            time = f.string(from: reminder.firstTriggerAt)
        }
        let base = reminder.dateDisplayText
        return time.isEmpty ? base : "\(base) · \(time)"
    }

    var body: some View {
        Text(ruleText)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(soft.isDark ? ThemeTokens.brandGradientStart : ThemeTokens.brandPrimaryDark)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(soft.isDark
                          ? ThemeTokens.strong.opacity(0.22)
                          : ThemeTokens.brandContainer.opacity(0.62))
            )
    }
}

// MARK: - 里程碑宝箱

/// 时间线底部里程碑宝箱：完成今日全部任务即可开启
struct MilestoneChest: View {
    let doneToday: Int
    let totalToday: Int

    private var unlocked: Bool { totalToday > 0 && doneToday >= totalToday }

    var body: some View {
        HStack(spacing: 10) {
            Text(unlocked ? "🎊" : "🎁")
                .font(.system(size: 26))
                .grayscale(unlocked ? 0 : 0.35)
                .saturation(unlocked ? 1.2 : 0.8)
            VStack(alignment: .leading, spacing: 2) {
                Text(unlocked ? "宝箱已开启！".localized : "完成全部任务开启宝箱".localized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(unlocked ? Playful.purple : .primary)
                if !unlocked {
                    Text(Localized("还差 %d 项 · 今日 %d/%d",
                                   max(totalToday - doneToday, 0), doneToday, totalToday))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if unlocked {
                Text("+1 🏆")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Playful.coral)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Playful.gold.opacity(0.25)))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clayCard(radius: 18)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: unlocked)
    }
}

// MARK: - 打卡数据辅助

/// 本周（周一起）有确认打卡记录的天数（0-7），用于彩虹跑道与宝箱
func weekDoneDays(records: [ReminderRecord]) -> Int {
    let cal = Calendar.current
    let confirms = records.filter { $0.type == ReminderRecordType.confirm.rawValue }
    let today = cal.startOfDay(for: Date())
    let weekday = (cal.component(.weekday, from: today) + 5) % 7 // 0=周一
    guard let monday = cal.date(byAdding: .day, value: -weekday, to: today) else { return 0 }
    var done = 0
    for offset in 0...6 {
        guard let day = cal.date(byAdding: .day, value: offset, to: monday) else { continue }
        if confirms.contains(where: { cal.isDate($0.performedAt, inSameDayAs: day) }) {
            done += 1
        }
    }
    return done
}

/// 今日已确认打卡次数（宝箱 doneToday 口径）
func todayDoneCount(records: [ReminderRecord]) -> Int {
    let cal = Calendar.current
    return records.filter {
        $0.type == ReminderRecordType.confirm.rawValue && cal.isDateInToday($0.performedAt)
    }.count
}

// MARK: - 空状态挥手小动物

/// 空状态：小狐狸挥手「今天想做什么呀？」
struct WavingEmptyMascot: View {
    var onCreate: () -> Void

    @State private var wave = false
    @State private var floatUp = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .topTrailing) {
                MascotView(mood: .sleepy, size: 92)
                Text("👋")
                    .font(.system(size: 30))
                    .rotationEffect(.degrees(wave ? 18 : -12))
                    .offset(x: 16, y: wave ? -4 : 4)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: wave)
            }
            .offset(y: floatUp ? -3 : 3)
            .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: floatUp)

            Text("今天想做什么呀？".localized)
                .font(.title3.weight(.bold))

            Text("创建你的第一个循环提醒，小狐狸帮你记住".localized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: onCreate) {
                HStack(spacing: 8) {
                    Text("✨")
                    Text("创建提醒".localized)
                        .font(.headline)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 26)
                .padding(.vertical, 13)
                .background(
                    Capsule().fill(
                        LinearGradient(colors: [Playful.purple, Playful.coral],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                )
                .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1.5))
                .shadow(color: Playful.purple.opacity(0.35), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .onAppear {
            wave = true
            floatUp = true
        }
    }
}
