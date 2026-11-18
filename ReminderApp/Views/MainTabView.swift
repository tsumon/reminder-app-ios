import SwiftUI

/// Child screens (AI chat / AI settings) increment this so MainTabView can
/// hide the bottom dock without flashing when pushing deeper screens.
private struct HideTabDockCountKey: EnvironmentKey {
    static let defaultValue: Binding<Int> = .constant(0)
}

extension EnvironmentValues {
    var hideTabDockCount: Binding<Int> {
        get { self[HideTabDockCountKey.self] }
        set { self[HideTabDockCountKey.self] = newValue }
    }
}

private struct HidesSoftTabDock: ViewModifier {
    @Environment(\.hideTabDockCount) private var hideTabDockCount

    func body(content: Content) -> some View {
        content
            .onAppear { hideTabDockCount.wrappedValue += 1 }
            .onDisappear { hideTabDockCount.wrappedValue = max(0, hideTabDockCount.wrappedValue - 1) }
    }
}

extension View {
    func hidesSoftTabDock() -> some View {
        modifier(HidesSoftTabDock())
    }
}

/// 四 Tab 根容器 + 极简奶油漫风底栏（无碎框、实时响应纸张换肤）
struct MainTabView: View {
    @Binding var selectedTab: Int
    @State private var hideTabDockCount = 0
    @Environment(\.colorScheme) private var scheme
    @AppStorage(ThemeStore.key) private var themeMode = 0
    @AppStorage(ThemeStore.colorKey) private var themeColor = 0

    private var hideTabDock: Bool { hideTabDockCount > 0 }

    private var resolvedScheme: ColorScheme {
        switch themeMode {
        case 1: return .light
        case 2: return .dark
        default: return scheme
        }
    }

    private var activeComic: ComicPalette {
        ComicPalette.of(resolvedScheme, colorIndex: themeColor)
    }

    init(selectedTab: Binding<Int> = .constant(0)) {
        _selectedTab = selectedTab
    }

    private var dockItems: [ComicTabItem] {
        [
            ComicTabItem(id: 0, title: "首页", systemImage: "house.fill"),
            ComicTabItem(id: 1, title: "日历", systemImage: "calendar"),
            ComicTabItem(id: 2, title: "统计", systemImage: "chart.bar.fill"),
            ComicTabItem(id: 3, title: "设置", systemImage: "gearshape.fill")
        ]
    }

    var body: some View {
        let palette = activeComic
        Group {
            switch selectedTab {
            case 0: NavigationStack { ReminderListView() }
            case 1: NavigationStack { CalendarPageView() }
            case 2: NavigationStack { StatsView() }
            default: NavigationStack { SettingsView() }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !hideTabDock {
                ComicTabDock(
                    selection: $selectedTab,
                    items: dockItems,
                    bottomPad: 6
                )
                .environment(\.comic, palette)
            }
        }
        .tint(palette.accent)
        .environment(\.comic, palette)
        .environment(\.hideTabDockCount, $hideTabDockCount)
        .preferredColorScheme(themeMode == 1 ? .light : themeMode == 2 ? .dark : nil)
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
