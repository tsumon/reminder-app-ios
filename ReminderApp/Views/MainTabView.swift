import SwiftUI

/// Child screens (AI chat / AI settings) increment this so MainTabView can
/// hide the overlay dock. Count, not Bool: pushing AI settings from chat
/// would otherwise `onDisappear` the chat page and flash the dock back.
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
    /// Hide the floating SoftTabDock while this screen is visible.
    func hidesSoftTabDock() -> some View {
        modifier(HidesSoftTabDock())
    }
}

/// 四 Tab + 悬浮 pill dock。iOS 无 FAB。
struct MainTabView: View {
    @Binding var selectedTab: Int
    @State private var hideTabDockCount = 0
    @Environment(\.colorScheme) private var scheme
    @AppStorage(ThemeStore.key) private var themeMode = 0

    private var hideTabDock: Bool { hideTabDockCount > 0 }

    private var resolvedScheme: ColorScheme {
        switch themeMode {
        case 1: return .light
        case 2: return .dark
        default: return scheme
        }
    }

    init(selectedTab: Binding<Int> = .constant(0)) {
        _selectedTab = selectedTab
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
                SoftTabDock(
                    selection: $selectedTab,
                    items: dockItems,
                    bottomPad: 6
                )
                .environment(\.soft, SoftPalette.of(resolvedScheme))
            }
        }
        .tint(ThemeTokens.brandPrimary)
        .environment(\.soft, SoftPalette.of(resolvedScheme))
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
