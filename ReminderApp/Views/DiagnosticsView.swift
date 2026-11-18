import SwiftUI
import SwiftData
import UserNotifications

/// 提醒可靠性诊断页（漫风印张化，保留权限自检与 10 秒测试提醒）
struct DiagnosticsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.comic) private var comic
    @Query private var reminders: [Reminder]

    @State private var authStatus = "检查中…"
    @State private var pendingCount = -1
    @State private var alarmStatus = "iOS 26+ 可用"
    @State private var testResult = ""
    @State private var coverage = ""
    @State private var checkedAt = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                permissionAndCheckCard
                dataAndSyncCard
                upcomingAndLogsCard
                if ProcessInfo.processInfo.arguments.contains("-uitest") {
                    debugSimulationCard
                }
            }
            .padding(ThemeTokens.gutter)
        }
        .background(ComicCanvas())
        .navigationTitle("诊断".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(comic.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear(perform: refresh)
    }

    // MARK: - 卡片一：通知权限与一键测试

    private var permissionAndCheckCard: some View {
        ComicCard(cut: ThemeTokens.cardCut, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("权限与提醒自检".localized)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(comic.ink)

                row("通知权限".localized, authStatus, highlight: authStatus == "已授权".localized ? comic.ok : comic.danger)
                row("已排期通知".localized, pendingCount >= 0 ? "\(pendingCount)" : "…")
                row("AlarmKit", alarmStatus)

                if !coverage.isEmpty {
                    Text(coverage)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(comic.muted)
                }

                HStack(spacing: 10) {
                    Button("申请通知权限".localized) {
                        Task { _ = await NotificationManager.shared.requestAuthorization(); refresh() }
                    }
                    .buttonStyle(ComicButtonStyle(variant: .surface, expand: true))

                    Button("发送10秒测试提醒".localized) {
                        sendTenSecondTest()
                    }
                    .buttonStyle(ComicButtonStyle(variant: .accent, expand: true))
                }

                Button("允许重要提醒使用 AlarmKit".localized) {
                    Task {
                        if #available(iOS 26.0, *) {
                            _ = await ImportantAlarmService.shared.requestAuthorization()
                            await ReminderEngine.shared.ensureRetryChains()
                        }
                        refresh()
                    }
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(comic.hero)
                .buttonStyle(.plain)

                if !testResult.isEmpty {
                    Text(testResult)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(comic.ok)
                }
            }
        }
    }

    // MARK: - 卡片二：数据与同步概览

    private var dataAndSyncCard: some View {
        ComicCard(cut: ThemeTokens.cardCut, padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("数据与隐私".localized)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(comic.ink)

                row("提醒总数".localized, "\(reminders.count)")
                row("未完成".localized, "\(reminders.filter { $0.status != .confirmed }.count)")
                row("已停用".localized, "\(reminders.filter { !$0.isEnabled }.count)")
                row("关键提醒".localized, "\(reminders.filter { $0.reminderStyle == "important" }.count)")
                row("WebDAV".localized, SyncStore.isConfigured ? "已配置".localized : "未配置".localized)

                ComicHairline(outer: false)

                Text("提醒和历史保存在本设备；API 密钥与 WebDAV 密码保存在 Keychain。".localized)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(comic.muted)

                Button {
                    refresh()
                } label: {
                    Text(Localized("重新检查 · %@", checkedAt.formatted(date: .omitted, time: .standard)))
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(comic.hero)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 卡片三：最近触发与 AI 日志

    private var upcomingAndLogsCard: some View {
        let upcoming = reminders.filter { $0.isEnabled && $0.status != .confirmed }.sorted { $0.nextTriggerAt < $1.nextTriggerAt }.prefix(5)
        let logs = AILogStore.recent().prefix(5)
        return ComicCard(cut: ThemeTokens.cardCut, padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("最近触发".localized)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(comic.ink)

                if upcoming.isEmpty {
                    Text("暂无待触发的提醒".localized)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(comic.muted)
                } else {
                    ForEach(Array(upcoming)) { r in
                        row(r.title, r.nextTriggerAt.formatted(date: .numeric, time: .shortened))
                    }
                }

                ComicHairline(outer: false)

                Text("最近 AI 调用".localized)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(comic.ink)

                if logs.isEmpty {
                    Text("暂无 AI 调用记录".localized)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(comic.muted)
                } else {
                    ForEach(Array(logs)) { e in
                        row(e.model, e.ok ? "\(e.turns) 轮 · \(e.durationMs)ms" : "失败".localized)
                    }
                }
            }
        }
    }

    private var debugSimulationCard: some View {
        let target = reminders.filter { $0.isEnabled && $0.status != .confirmed }.sorted { $0.nextTriggerAt < $1.nextTriggerAt }.first
        return ComicCard(cut: ThemeTokens.cardCut, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("调试：模拟通知动作".localized)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(comic.ink)
                if let r = target {
                    Button(Localized("模拟确认：%@", r.title)) {
                        NotificationManager.shared.simulateNotificationAction(.confirm, reminderID: r.id)
                    }
                    .accessibilityIdentifier("debug-sim-confirm")
                    Button(Localized("模拟稍后：%@", r.title)) {
                        NotificationManager.shared.simulateNotificationAction(.snooze, reminderID: r.id)
                    }
                    .accessibilityIdentifier("debug-sim-snooze")
                }
            }
        }
    }

    private func row(_ label: String, _ value: String, highlight: Color? = nil) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                .foregroundStyle(comic.ink)
                .lineLimit(1)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(highlight ?? comic.muted)
        }
    }

    private func sendTenSecondTest() {
        Task {
            guard await NotificationManager.shared.requestAuthorization() else {
                testResult = "请在系统设置中允许通知"; return
            }
            let content = UNMutableNotificationContent()
            content.title = "提醒自检"
            content.body = "测试通知已送达"
            content.sound = .default
            await NotificationManager.shared.reserveUnmanaged(identifier: "permission-test")
            defer { NotificationManager.shared.releaseUnmanagedReservation(identifier: "permission-test") }
            do {
                try await UNUserNotificationCenter.current().add(
                    UNNotificationRequest(
                        identifier: "permission-test",
                        content: content,
                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
                    )
                )
                testResult = "已安排，锁屏等待10秒检查声音和横幅"
            } catch {
                testResult = error.localizedDescription
            }
        }
    }

    private func refresh() {
        checkedAt = Date()
        Task {
            ReminderEngine.shared.configure(with: modelContext)
            await ReminderEngine.shared.ensureRetryChains()
            let engine = ReminderEngine.shared
            coverage = "已覆盖下次提醒 \(engine.scheduledPrimaryCount)/\(engine.eligiblePrimaryCount)（系统上限 64 条待发通知）。"
            if #available(iOS 26.0, *) { alarmStatus = ImportantAlarmService.shared.authorizationLabel }
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: authStatus = "已授权".localized
            case .denied: authStatus = "已拒绝".localized
            case .notDetermined: authStatus = "未请求".localized
            @unknown default: authStatus = "未知".localized
            }
            pendingCount = await UNUserNotificationCenter.current().pendingNotificationRequests().count
        }
    }
}

/// 首页底纸纯文字排期自检行（零外框，1:1 对标参考图 `› 网络与图表`）
struct NotificationHealthCard: View {
    var onOpen: (() -> Void)? = nil

    @Environment(\.scenePhase) private var phase
    @Environment(\.comic) private var comic
    @State private var status = "检查中…".localized
    @State private var isHealthy = true
    @State private var count = 0

    var body: some View {
        Group {
            if let onOpen {
                ComicCollapsibleLine(
                    title: "\(status) · 通知与排期自检",
                    trailing: Localized("%d 条待发", count),
                    warn: !isHealthy,
                    action: onOpen
                )
            } else {
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                        Text("\(status) · 通知与排期自检")
                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        Spacer()
                        Text(Localized("%d 条待发", count))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(isHealthy ? comic.muted : comic.warn)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityIdentifier("notification-health")
        .task { await refresh() }
        .onChange(of: phase) { _, value in
            if value == .active { Task { await refresh() } }
        }
    }

    private func refresh() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let ok = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        isHealthy = ok
        status = ok ? "通知已授权".localized : "通知需要设置".localized
        count = await center.pendingNotificationRequests().count
    }
}
