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
    @State private var selectedTab: Int
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

    /// Home-indicator pill ~5pt, ~8pt from the physical bottom.
    private var contentBottomPad: CGFloat {
        ThemeTokens.dockPadBottom + ThemeTokens.dockIndicator
    }

    private var dockReserve: CGFloat {
        ThemeTokens.dockPadTop + ThemeTokens.dockH + contentBottomPad
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
        // ZStack to the physical bottom so the icon row can sit 4pt above the
        // indicator pill. TabView / safeAreaInset would park the row above the
        // whole 34pt safe area and leave icons hanging in the upper half of the fill.
        // AI chat hides the dock: skip overlay + reserve, and restore the
        // system bottom safe area so the input bar sits above the home indicator.
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case 0: NavigationStack { ReminderListView() }
                case 1: NavigationStack { CalendarPageView() }
                case 2: NavigationStack { StatsView() }
                default: NavigationStack { SettingsView() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if hideTabDock {
                    Color.clear.frame(height: 0)
                } else {
                    Color.clear.frame(height: dockReserve)
                }
            }

            if !hideTabDock {
                SoftTabDock(
                    selection: $selectedTab,
                    items: dockItems,
                    bottomPad: contentBottomPad
                )
                .padding(.bottom, ThemeTokens.dockBottomGap)
                .environment(\.soft, SoftPalette.of(resolvedScheme))
            }
        }
        .tint(ThemeTokens.brandPrimary)
        .environment(\.soft, SoftPalette.of(resolvedScheme))
        .environment(\.hideTabDockCount, $hideTabDockCount)
        .preferredColorScheme(themeMode == 1 ? .light : themeMode == 2 ? .dark : nil)
        .ignoresSafeArea(edges: hideTabDock ? [] : .bottom)
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
