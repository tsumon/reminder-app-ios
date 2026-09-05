import SwiftUI

/// 四 Tab + 悬浮 pill dock。iOS 无 FAB。
struct MainTabView: View {
    @State private var selectedTab: Int
    @Environment(\.colorScheme) private var scheme
    @AppStorage(ThemeStore.key) private var themeMode = 0

    private var resolvedScheme: ColorScheme {
        switch themeMode {
        case 1: return .light
        case 2: return .dark
        default: return scheme
        }
    }

    init() {
        var initial = 0
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-tab"),
           args.indices.contains(idx + 1),
           let t = Int(args[idx + 1]) {
            initial = min(max(t, 0), 3)
        }
        #endif
        _selectedTab = State(initialValue: initial)
    }

    private var dockItems: [SoftTabItem] {
        [
            SoftTabItem(id: 0, title: "首页", systemImage: "house.fill"),
            SoftTabItem(id: 1, title: "日历", systemImage: "calendar"),
            SoftTabItem(id: 2, title: "统计", systemImage: "chart.bar.fill"),
            SoftTabItem(id: 3, title: "设置", systemImage: "gearshape.fill")
        ]
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { ReminderListView() }
                .tag(0)
                .toolbar(.hidden, for: .tabBar)

            NavigationStack { CalendarPageView() }
                .tag(1)
                .toolbar(.hidden, for: .tabBar)

            NavigationStack { StatsView() }
                .tag(2)
                .toolbar(.hidden, for: .tabBar)

            NavigationStack { SettingsView() }
                .tag(3)
                .toolbar(.hidden, for: .tabBar)
        }
        .tint(ThemeTokens.brandPrimary)
        .environment(\.soft, SoftPalette.of(resolvedScheme))
        .preferredColorScheme(themeMode == 1 ? .light : themeMode == 2 ? .dark : nil)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SoftTabDock(selection: $selectedTab, items: dockItems)
                .environment(\.soft, SoftPalette.of(resolvedScheme))
        }
        .onReceive(NotificationCenter.default.publisher(for: .openReminderDetail)) { _ in
            selectedTab = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .openStatsTab)) { _ in
            selectedTab = 2
        }
    }
}

#Preview {
    MainTabView()
        .modelContainer(for: [Reminder.self, ReminderRecord.self], inMemory: true)
}
