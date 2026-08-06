import SwiftUI
import SwiftData

/// 设置页：同步/AI/关于（版本号 + 检查更新 + 更新日志）
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var reminders: [Reminder]

    @State private var updateInfo: AppUpdateInfo?
    @State private var checking = false
    @State private var resultMsg: String?
    @State private var isError = false

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        // v1.9.8: NavigationStack 由 MainTabView 的 Tab 提供
        Form {
                // MARK: 同步
                Section("同步") {
                    NavigationLink {
                        SyncSettingsView()
                    } label: {
                        Label("WebDAV 同步", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                // MARK: AI
                Section("AI") {
                    NavigationLink {
                        AISettingsView()
                    } label: {
                        Label("AI 助手设置", systemImage: "sparkles")
                    }
                }

                // MARK: 关于
                Section {
                    // 版本号
                    HStack {
                        Label("版本", systemImage: "app.badge")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }

                    // 检查更新
                    Button {
                        checkForUpdates()
                    } label: {
                        HStack {
                            Label("检查更新", systemImage: "arrow.clockwise")
                            Spacer()
                            if checking {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(checking)

                    // 更新日志
                    NavigationLink {
                        ChangelogView()
                    } label: {
                        Label("更新日志", systemImage: "doc.text")
                    }
                } header: {
                    Text("关于")
                } footer: {
                    Text("支持循环提醒 · 同步 · 在线升级")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .glassPageBackground()
            .glassNavigationBar()
            .scrollContentBackground(.hidden)
            .alert(
                "检查更新",
                isPresented: Binding(
                    get: { resultMsg != nil },
                    set: { if !$0 { resultMsg = nil } }
                )
            ) {
                if let info = updateInfo {
                    Button("前往下载") {
                        if let ipa = info.ipaURL {
                            // 自签：下载到本地文件 App
                            downloading(to: info)
                        } else {
                            UIApplication.shared.open(info.releaseURL)
                        }
                    }
                }
                Button("好", role: .cancel) { resultMsg = nil }
            } message: {
                Text(resultMsg ?? "")
            }
    }

    private func checkForUpdates() {
        checking = true
        Task {
            guard let info = await UpdateService.checkLatest() else {
                checking = false
                isError = true
                resultMsg = "检查更新失败，请检查网络后重试"
                return
            }
            checking = false
            if info.isNewer {
                updateInfo = info
                resultMsg = "发现新版本 v\(info.latestVersion)，当前 v\(UpdateService.currentVersion)。"
            } else {
                isError = false
                updateInfo = nil
                resultMsg = "当前已是最新版本 v\(UpdateService.currentVersion)"
            }
        }
    }

    private func downloading(to info: AppUpdateInfo) {
        resultMsg = "正在下载 .ipa… 完成后请到「文件」App-我的 iPhone-循环提醒 用自签工具安装。"
        Task {
            guard let ipa = info.ipaURL else { return }
            do {
                let url = try await UpdateService.downloadIpa(from: ipa, version: info.latestVersion)
                resultMsg = "已下载：\(url.lastPathComponent)。打开「文件」App → 我的 iPhone → 循环提醒 → 用 AltStore/爱思等自签工具安装。"
            } catch {
                isError = true
                resultMsg = "下载失败：\(error.localizedDescription)"
            }
        }
    }
}

// MARK: - 更新日志

struct ChangelogView: View {
    var body: some View {
        List {
            ForEach(changelog, id: \.version) { entry in
                Section(header: Text(entry.version)) {
                    ForEach(entry.items, id: \.self) { item in
                        Text("· \(item)")
                            .font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle("更新日志")
        .navigationBarTitleDisplayMode(.inline)
    }

    private struct ChangelogEntry {
        let version: String
        let items: [String]
    }

    private let changelog: [ChangelogEntry] = [
        ChangelogEntry(version: "v1.9.2", items: [
            "修复安卓端收不到更新提示（GitHub API 国内超时）",
            "WebDAV 坚果云友好错误提示 + 「测试连接」按钮",
        ]),
        ChangelogEntry(version: "v1.9.1", items: [
            "AI 支持创建规则提醒（每季度/每月/每年 第N周周X，如 1/4/7/10 月第一周周四报税）",
            "首页菜单新增「检查更新」入口",
        ]),
        ChangelogEntry(version: "v1.9.0", items: [
            "UI 优化：滴答清单风格（渐变概览卡、已完成划线、卡片圆角阴影）",
            "日历：滑动切月 + 月份选择器 + 回到今天",
            "在线升级：自动检查 GitHub 最新版本，下载到本地安装",
            "新增 App 图标（品牌紫 + 铃铛）",
        ]),
        ChangelogEntry(version: "v1.8.7", items: [
            "小组件增强：农历日期格、倒计时、完成按钮、大尺寸",
            "节假日联网补全：日历显示「休/班」",
            "统计洞察：完成率、连续打卡、忘记时段、月历热力图",
            ".ics 日历导出",
            "设计令牌统一（主色 M3 紫 #6750A4）",
            "崩溃监控 + 埋点基础设施",
        ]),
    ]
}

#Preview {
    SettingsView()
        .modelContainer(for: [Reminder.self, ReminderRecord.self])
}
