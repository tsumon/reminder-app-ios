import SwiftUI
import SwiftData

/// 设置页：实时 6 款奶油漫风纸张色板切换 + 外观模式 + 同步/诊断/备份/更新
struct SettingsView: View {
    @Environment(\.comic) private var comic

    @State private var updateInfo: AppUpdateInfo?
    @State private var checking = false
    @State private var resultMsg: String?
    @State private var isError = false

    @AppStorage(AppLanguageManager.key) private var appLanguage = AppLanguage.system.rawValue
    @AppStorage(ThemeStore.key) private var themeMode = 0
    @AppStorage(ThemeStore.colorKey) private var themeColor = 0

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ComicBrandTitle(text: "设置".localized, size: 20, showShard: true)
                Spacer()
                Text(comic.paperName)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(comic.muted)
            }
            .padding(.horizontal, ThemeTokens.gutter)
            .padding(.vertical, 10)

            ComicHairline(outer: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    appearanceAndPaletteCard
                    featureLinksCard
                    aboutCard

                    Text("支持循环提醒 · 同步 · 在线升级".localized)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(comic.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding(.horizontal, ThemeTokens.gutter)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
        }
        .background(ComicCanvas())
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .navigationBar)
        .alert(
            "检查更新",
            isPresented: Binding(
                get: { resultMsg != nil },
                set: { if !$0 { resultMsg = nil } }
            )
        ) {
            if let info = updateInfo {
                Button("前往下载".localized) {
                    if info.ipaURL != nil { downloading(to: info) }
                    else { UIApplication.shared.open(info.releaseURL) }
                }
            }
            Button("好".localized, role: .cancel) { resultMsg = nil }
        } message: {
            Text((resultMsg ?? "").localized)
        }
    }

    private var appearanceAndPaletteCard: some View {
        ComicCard(cut: ThemeTokens.cardCut, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("外观模式".localized)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(comic.muted)
                    Spacer()
                    HStack(spacing: 14) {
                        ForEach([(0, "跟随系统"), (1, "浅色"), (2, "深色")], id: \.0) { mode, label in
                            let active = themeMode == mode
                            Button { themeMode = mode } label: {
                                VStack(spacing: 2) {
                                    Text(label.localized)
                                        .font(.system(size: 13.5, weight: active ? .heavy : .medium, design: .rounded))
                                        .foregroundStyle(active ? comic.ink : comic.muted)
                                    Rectangle()
                                        .fill(active ? comic.accent : Color.clear)
                                        .frame(width: 18, height: 2)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                ComicHairline(outer: false)

                HStack {
                    Text("界面语言".localized)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(comic.muted)
                    Spacer()
                    Picker("语言".localized, selection: $appLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }

                ComicHairline(outer: false)

                VStack(alignment: .leading, spacing: 10) {
                    Text("主题纸色".localized)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(comic.muted)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 12) {
                        ForEach(Array(ComicPalette.specs.enumerated()), id: \.offset) { index, spec in
                            let selected = themeColor == index
                            Button { themeColor = index } label: {
                                HStack(spacing: 7) {
                                    ZStack {
                                        Circle()
                                            .fill(Color(hex: spec.accent))
                                            .frame(width: 15, height: 15)
                                        if selected {
                                            Circle()
                                                .fill(Color(hex: spec.onAccent))
                                                .frame(width: 5.5, height: 5.5)
                                        }
                                    }
                                    Text(spec.name.localized)
                                        .font(.system(size: 13.5, weight: selected ? .heavy : .medium, design: .rounded))
                                        .foregroundStyle(selected ? comic.ink : comic.muted)
                                        .lineLimit(1)
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(spec.name.localized)
                        }
                    }
                }
            }
        }
    }

    private var featureLinksCard: some View {
        ComicCard(cut: ThemeTokens.cardCut, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                NavigationLink { SyncSettingsView() } label: { navRow("WebDAV 同步".localized, icon: "arrow.triangle.2.circlepath") }.buttonStyle(.plain)
                ComicHairline(outer: false)
                NavigationLink { AISettingsView() } label: { navRow("AI 助手设置".localized, icon: "sparkles") }.buttonStyle(.plain)
                ComicHairline(outer: false)
                NavigationLink { DiagnosticsView() } label: { navRow("提醒诊断".localized, icon: "stethoscope") }.buttonStyle(.plain)
                ComicHairline(outer: false)
                NavigationLink { LocalBackupsView() } label: { navRow("本地备份".localized, icon: "externaldrive") }.buttonStyle(.plain)
            }
        }
    }

    private var aboutCard: some View {
        ComicCard(cut: ThemeTokens.cardCut, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("版本".localized, systemImage: "app.badge")
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                        .foregroundStyle(comic.ink)
                    Spacer()
                    Text(appVersion)
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(comic.muted)
                }

                ComicHairline(outer: false)

                Button { checkForUpdates() } label: {
                    HStack {
                        Label("检查更新".localized, systemImage: "arrow.clockwise")
                            .font(.system(size: 14.5, weight: .bold, design: .rounded))
                            .foregroundStyle(comic.ink)
                        Spacer()
                        if checking { ProgressView().controlSize(.small) }
                        else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(comic.muted)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(checking)

                ComicHairline(outer: false)

                NavigationLink { ChangelogView() } label: { navRow("更新日志".localized, icon: "doc.text") }.buttonStyle(.plain)
            }
        }
    }

    private func navRow(_ title: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.system(size: 14.5, weight: .bold, design: .rounded))
                .foregroundStyle(comic.ink)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(comic.muted)
        }
        .contentShape(Rectangle())
    }

    private func checkForUpdates() {
        checking = true
        Task {
            guard let info = await UpdateService.checkLatest() else {
                checking = false; isError = true
                resultMsg = "检查更新失败，请检查网络后重试"; return
            }
            checking = false
            if info.isNewer {
                updateInfo = info
                resultMsg = Localized("发现新版本 v%@，当前 v%@。", info.latestVersion, UpdateService.currentVersion)
            } else {
                isError = false; updateInfo = nil
                resultMsg = Localized("当前已是最新版本 v%@", UpdateService.currentVersion)
            }
        }
    }

    private func downloading(to info: AppUpdateInfo) {
        resultMsg = "正在下载 .ipa… 完成后请到「文件」App 用自签工具安装。"
        Task {
            guard info.ipaURL != nil else { return }
            do {
                let url = try await UpdateService.downloadIpa(info: info)
                resultMsg = Localized("已下载：%@。打开「文件」App → 我的 iPhone → 循环提醒安装。", url.lastPathComponent)
            } catch {
                isError = true
                resultMsg = Localized("下载失败：%@", error.localizedDescription)
            }
        }
    }
}
