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
    // v2.0.4: 手动语言切换（与 App 根视图共享同一 UserDefaults key，切换即全局重建）
    @AppStorage(AppLanguageManager.key) private var appLanguage = AppLanguage.system.rawValue
    // v2.1.1: 手动主题（0=跟随系统 1=浅色 2=深色；与 App 根视图共享 ThemeStore.key）
    @AppStorage(ThemeStore.key) private var themeMode = 0
    // v2.4.0: 主题色板索引（切换后根视图 .id() 重建即时生效）
    @AppStorage(ThemeStore.colorKey) private var themeColor = 0

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    @Environment(\.soft) private var soft

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                settingsGroup {
                    Picker("语言".localized, selection: $appLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang.rawValue)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                settingsGroup {
                    Picker("主题".localized, selection: $themeMode) {
                        Text("跟随系统".localized).tag(0)
                        Text("浅色".localized).tag(1)
                        Text("深色".localized).tag(2)
                    }
                    .pickerStyle(.navigationLink)
                    Divider().background(soft.track)
                    HStack(spacing: 10) {
                        Text("主题色".localized)
                            .font(SoftType.body)
                            .foregroundStyle(soft.text)
                        Spacer()
                        ForEach(Array(ThemeTokens.palettes.enumerated()), id: \.offset) { index, palette in
                            Button { themeColor = index } label: {
                                ZStack {
                                    Circle()
                                        .fill(palette.primary)
                                        .frame(width: 28, height: 28)
                                    if themeColor == index {
                                        Image(systemName: "checkmark")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                settingsGroup {
                    NavigationLink { SyncSettingsView() } label: {
                        settingsRow("WebDAV 同步", systemImage: "arrow.triangle.2.circlepath")
                    }
                }

                settingsGroup {
                    NavigationLink { DiagnosticsView() } label: {
                        settingsRow("提醒诊断", systemImage: "stethoscope")
                    }
                    Divider().background(soft.track)
                    NavigationLink { LocalBackupsView() } label: {
                        settingsRow("本地备份", systemImage: "externaldrive")
                    }
                }

                settingsGroup {
                    NavigationLink { AISettingsView() } label: {
                        settingsRow("AI 助手设置", systemImage: "sparkles")
                    }
                }

                settingsGroup {
                    HStack {
                        settingsRow("版本", systemImage: "app.badge")
                        Spacer()
                        Text(appVersion)
                            .font(SoftType.body)
                            .foregroundStyle(soft.muted)
                    }
                    Divider().background(soft.track)
                    Button { checkForUpdates() } label: {
                        HStack {
                            settingsRow("检查更新", systemImage: "arrow.clockwise")
                            Spacer()
                            if checking { ProgressView() }
                        }
                    }
                    .disabled(checking)
                    .buttonStyle(.plain)
                    Divider().background(soft.track)
                    NavigationLink { ChangelogView() } label: {
                        settingsRow("更新日志", systemImage: "doc.text")
                    }
                }

                Text("支持循环提醒 · 同步 · 在线升级".localized)
                    .font(SoftType.caption)
                    .foregroundStyle(soft.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .background(PaperCanvas())
        .navigationTitle("设置".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(soft.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("设置".localized)
                    .font(SoftType.title)
                    .foregroundStyle(soft.text)
            }
        }
            .alert(
                "检查更新",
                isPresented: Binding(
                    get: { resultMsg != nil },
                    set: { if !$0 { resultMsg = nil } }
                )
            ) {
                if let info = updateInfo {
                    Button("前往下载".localized) {
                        if let ipa = info.ipaURL {
                            // 自签：下载到本地文件 App
                            downloading(to: info)
                        } else {
                            UIApplication.shared.open(info.releaseURL)
                        }
                    }
                }
                Button("好".localized, role: .cancel) { resultMsg = nil }
            } message: {
                Text((resultMsg ?? "").localized)
            }
    }

    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        SoftShadowCard(kind: .card, radius: ThemeTokens.radiusCard) {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(soft.text)
        }
    }

    private func settingsRow(_ title: String, systemImage: String) -> some View {
        Label(title.localized, systemImage: systemImage)
            .font(SoftType.body)
            .foregroundStyle(soft.text)
            .padding(.vertical, 10)
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
                resultMsg = Localized("发现新版本 v%@，当前 v%@。", info.latestVersion, UpdateService.currentVersion)
            } else {
                isError = false
                updateInfo = nil
                resultMsg = Localized("当前已是最新版本 v%@", UpdateService.currentVersion)
            }
        }
    }

    private func downloading(to info: AppUpdateInfo) {
        resultMsg = "正在下载 .ipa… 完成后请到「文件」App-我的 iPhone-循环提醒 用自签工具安装。"
        Task {
            guard let ipa = info.ipaURL else { return }
            do {
                let url = try await UpdateService.downloadIpa(info: info)
                resultMsg = Localized("已下载：%@。打开「文件」App → 我的 iPhone → 循环提醒 → 用 AltStore/爱思等自签工具安装。", url.lastPathComponent)
            } catch {
                isError = true
                resultMsg = Localized("下载失败：%@", error.localizedDescription)
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
        .navigationTitle("更新日志".localized)
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
            "设计令牌统一（主色青碧 #159A9C）",
            "崩溃监控 + 埋点基础设施",
        ]),
    ]
}

#Preview {
    SettingsView()
        .modelContainer(for: [Reminder.self, ReminderRecord.self])
}
