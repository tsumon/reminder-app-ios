import SwiftUI
import SwiftData
import UserNotifications

/// v2.1.1: 提醒可靠性诊断页——自签环境权限/排期状态经常异常，一键查看问题在哪。
/// 显示：通知权限、已排期通知数量、数据规模、WebDAV 配置、最近触发时间。
struct DiagnosticsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var reminders: [Reminder]

    @State private var authStatus = "检查中…"
    @State private var pendingCount = -1
    @State private var checkedAt = Date()

    var body: some View {
        List {
            Section("通知".localized) {
                HStack {
                    Label("通知权限".localized, systemImage: "bell.badge")
                    Spacer()
                    Text(authStatus)
                        .foregroundStyle(authStatus == "已授权".localized ? ThemeTokens.statusCompleted : ThemeTokens.statusOverdue)
                }
                HStack {
                    Label("已排期通知".localized, systemImage: "clock.badge.checkmark")
                    Spacer()
                    Text(pendingCount >= 0 ? "\(pendingCount)" : "…")
                        .foregroundStyle(pendingCount > 64 ? ThemeTokens.statusSnoozed : .secondary)
                }
            }

            Section("数据".localized) {
                row("提醒总数".localized, "\(reminders.count)")
                row("未完成".localized, "\(reminders.filter { $0.status != .confirmed }.count)")
                row("已停用".localized, "\(reminders.filter { !$0.isEnabled }.count)")
                row("关键提醒".localized, "\(reminders.filter { ReminderEngine.CriticalStore.isCritical($0.id) }.count)")
            }

            Section("同步".localized) {
                HStack {
                    Label("WebDAV".localized, systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    Text(SyncStore.isConfigured ? "已配置".localized : "未配置".localized)
                        .foregroundStyle(SyncStore.isConfigured ? ThemeTokens.statusCompleted : .secondary)
                }
            }

            Section("最近触发".localized) {
                let upcoming = reminders
                    .filter { $0.isEnabled && $0.status != .confirmed }
                    .sorted { $0.nextTriggerAt < $1.nextTriggerAt }
                    .prefix(5)
                if upcoming.isEmpty {
                    Text("暂无待触发的提醒".localized)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(upcoming)) { r in
                    HStack {
                        Text(r.title)
                            .lineLimit(1)
                        Spacer()
                        Text(r.nextTriggerAt.formatted(date: .numeric, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // v2.2.0: 最近 AI 调用（可观测性）
            Section("最近 AI 调用".localized) {
                let logs = AILogStore.recent().prefix(5)
                if logs.isEmpty {
                    Text("暂无 AI 调用记录".localized)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(logs)) { e in
                    HStack {
                        Text(e.time.formatted(date: .omitted, time: .standard))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(e.model)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(logSummary(e))
                            .font(.caption2)
                            .foregroundStyle(e.ok ? .secondary : ThemeTokens.statusOverdue)
                    }
                }
            }

            Section {
                Button {
                    refresh()
                } label: {
                    Label("重新检查".localized, systemImage: "arrow.clockwise")
                }
            } footer: {
                Text(Localized("检查时间：%@", checkedAt.formatted(date: .numeric, time: .standard)))
                    .font(.caption2)
            }
        }
        .navigationTitle("诊断".localized)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
    }

    private func logSummary(_ e: AILogStore.Entry) -> String {
        if !e.ok { return "失败".localized }
        let providerTag = e.provider == "fallback" ? " · 降级".localized : ""
        return Localized("%d 轮 · %dms%@", e.turns, e.durationMs, providerTag)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func refresh() {
        checkedAt = Date()
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                authStatus = "已授权".localized
            case .denied:
                authStatus = "已拒绝".localized
            case .notDetermined:
                authStatus = "未请求".localized
            @unknown default:
                authStatus = "未知".localized
            }

            let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
            pendingCount = requests.count
        }
    }
}
