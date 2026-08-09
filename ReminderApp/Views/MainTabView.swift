import SwiftUI

/// v1.9.8 底部导航 Tab（对齐 README 设计图）：首页 / 日历 / 统计 / 设置
///
/// 每个 Tab 内嵌独立 NavigationStack，push 页（详情/AI/同步设置等）在各自栈内跳转。
struct MainTabView: View {
    @State private var selectedTab: Int

    init() {
        var initial = 0
        #if DEBUG
        // v1.9.8: 截图验证用——simctl launch booted com.reminder.app -tab 1 可直接落到指定 Tab
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-tab"),
           args.indices.contains(idx + 1),
           let t = Int(args[idx + 1]) {
            initial = min(max(t, 0), 3)
        }
        #endif
        _selectedTab = State(initialValue: initial)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ReminderListView()
            }
            .tabItem { Label("首页".localized, systemImage: "house.fill") }
            .tag(0)

            NavigationStack {
                CalendarPageView()
            }
            .tabItem { Label("日历".localized, systemImage: "calendar") }
            .tag(1)

            NavigationStack {
                StatsView()
            }
            .tabItem { Label("统计".localized, systemImage: "chart.bar.fill") }
            .tag(2)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("设置".localized, systemImage: "gearshape.fill") }
            .tag(3)
        }
        .tint(ThemeTokens.brandPrimary)
    }
}

#Preview {
    MainTabView()
        .modelContainer(for: [Reminder.self, ReminderRecord.self], inMemory: true)
}
