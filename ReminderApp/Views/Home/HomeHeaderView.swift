import SwiftUI

enum SmartList: String, CaseIterable, Hashable {
    case all      = "全部"
    case today    = "今天"
    case tomorrow = "明天"
    case week     = "本周"
    case month    = "本月"
    case high     = "高优先级"
    case done     = "已完成"

    var label: String { rawValue }
}

/// 首页无框顶栏 + 副栏 + 纸面速记输入（1:1 对标 IOTA MONITOR 呼吸感留白）
struct HomeHeaderSection: View {
    @Binding var smartList: SmartList
    @Binding var kindFilter: String
    @Binding var sortOrder: String
    @Binding var quickSentence: String
    var quickFocused: FocusState<Bool>.Binding
    @Binding var searchText: String
    @Binding var isSearchPresented: Bool
    var searchFocused: FocusState<Bool>.Binding
    var hasUndoCreate: Bool
    var onUndoCreate: () -> Void
    var onCreateNew: () -> Void
    var onCheckRule: () -> Void
    var onSyncNow: () -> Void
    var onExportBackup: () -> Void
    var onExportICS: () -> Void
    var onShowNearbyShare: () -> Void
    var onCheckUpdates: () -> Void
    var onShowImport: () -> Void
    var onShowCardImport: () -> Void

    @AppStorage(ThemeStore.colorKey) private var themeColor = 0
    @Environment(\.comic) private var comic

    var body: some View {
        VStack(spacing: 0) {
            topBar
            subBar
            ComicHairline(outer: true)
            quickInputRow
            ComicHairline(outer: true)
                .opacity(0.55)
            if hasUndoCreate {
                undoCreateStrip
            }
            if isSearchPresented {
                searchStrip
            }
        }
        .background(comic.canvas)
    }

    // MARK: - 无框顶栏

    private var topBar: some View {
        HStack(spacing: 10) {
            ComicBrandTitle(text: "循环提醒".localized, size: 21, showShard: true)

            NavigationLink {
                AIChatView()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                    Text("AI")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(comic.hero)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("AI")
            .accessibilityIdentifier("ai-entry")

            Spacer(minLength: 4)

            Menu {
                overflowMenuContent
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(comic.ink)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("more-menu")

            Button(action: onCreateNew) {
                Text("+ " + "新建".localized)
            }
            .buttonStyle(ComicButtonStyle(variant: .accent, horizontalPadding: 12, verticalPadding: 7))
            .accessibilityLabel("新建提醒".localized)
        }
        .padding(.horizontal, ThemeTokens.gutter)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: - 无框副栏（纯文字筛选 + 纸张主题切换）

    private var subBar: some View {
        HStack(spacing: 14) {
            ForEach([SmartList.all, .today, .week], id: \.self) { item in
                let active = smartList == item
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        smartList = item
                    }
                } label: {
                    VStack(spacing: 3) {
                        Text(item.label.localized)
                            .font(.system(size: 13.5, weight: active ? .heavy : .medium, design: .rounded))
                            .foregroundStyle(active ? comic.ink : comic.muted)
                        Rectangle()
                            .fill(active ? comic.accent : Color.clear)
                            .frame(width: 16, height: 2)
                    }
                    .padding(.top, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    isSearchPresented.toggle()
                    if !isSearchPresented { searchText = "" }
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSearchPresented ? comic.accent : comic.muted)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("搜索".localized)

            Spacer(minLength: 4)

            Menu {
                Section("按类型筛选".localized) {
                    Button("全部类型".localized) { kindFilter = "all" }
                    ForEach(ReminderKind.allCases, id: \.self) { k in
                        Button(k.rawValue.localized) { kindFilter = k.rawValue }
                    }
                }
                Section("排序方式".localized) {
                    Button("时间".localized) { sortOrder = "time" }
                    Button("优先级".localized) { sortOrder = "priority" }
                    Button("提醒标题".localized) { sortOrder = "title" }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(sortOrder == "time" ? "按时间".localized : (sortOrder == "priority" ? "按优先级".localized : "按标题".localized))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(comic.muted)
            }

            Menu {
                ForEach(Array(ComicPalette.specs.enumerated()), id: \.offset) { idx, spec in
                    Button {
                        themeColor = idx
                    } label: {
                        HStack {
                            Text(spec.name)
                            if themeColor == idx {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 11, weight: .semibold))
                    Text(comic.paperName)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(comic.muted)
            }
        }
        .padding(.horizontal, ThemeTokens.gutter)
        .padding(.bottom, 6)
    }

    // MARK: - 底纸无框速记输入行

    private var quickInputRow: some View {
        HStack(spacing: 10) {
            Text("›")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(comic.accent)
                .accessibilityHidden(true)

            TextField(
                "",
                text: $quickSentence,
                prompt: Text("输入一句话创建提醒".localized).foregroundStyle(comic.muted.opacity(0.85))
            )
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(comic.ink)
            .frame(minHeight: 40)
            .focused(quickFocused)
            .submitLabel(.done)
            .onSubmit { quickFocused.wrappedValue = false }
            .accessibilityIdentifier("quick-reminder-input")

            Button("检查规则".localized, action: onCheckRule)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(comic.hero)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, ThemeTokens.gutter)
        .padding(.vertical, 2)
    }

    private var undoCreateStrip: some View {
        HStack {
            Text("刚创建了一条新提醒".localized)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(comic.muted)
            Spacer()
            Button("撤销刚创建的提醒".localized, action: onUndoCreate)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(comic.accent)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, ThemeTokens.gutter)
        .padding(.vertical, 6)
    }

    private var searchStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(comic.muted)
            TextField(
                "",
                text: $searchText,
                prompt: Text("搜索提醒、日期...".localized).foregroundStyle(comic.muted.opacity(0.8))
            )
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(comic.ink)
            .focused(searchFocused)
            .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(comic.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空搜索".localized)
            }
        }
        .padding(.horizontal, ThemeTokens.gutter)
        .padding(.vertical, 8)
        .accessibilityIdentifier("home-search")
    }

    // MARK: - 更多菜单

    @ViewBuilder
    private var overflowMenuContent: some View {
        Button(action: onCreateNew) {
            Label("新建提醒".localized, systemImage: "plus.circle")
        }
        Divider()
        NavigationLink {
            StatsView()
        } label: {
            Label("统计洞察".localized, systemImage: "chart.bar.fill")
        }
        Divider()
        Button(action: onSyncNow) {
            Label("立即同步".localized, systemImage: "arrow.triangle.2.circlepath")
        }
        NavigationLink {
            SyncSettingsView()
        } label: {
            Label("同步设置".localized, systemImage: "gearshape")
        }
        Divider()
        Button(action: onExportBackup) {
            Label("导出提醒".localized, systemImage: "square.and.arrow.up")
        }
        Button(action: onExportICS) {
            Label("导出日历(.ics)".localized, systemImage: "calendar.badge.plus")
        }
        Button(action: onShowNearbyShare) {
            Label("附近传输".localized, systemImage: "wifi")
        }
        Button(action: onCheckUpdates) {
            Label("检查更新".localized, systemImage: "arrow.clockwise")
        }
        Divider()
        NavigationLink {
            SettingsView()
        } label: {
            Label("设置".localized, systemImage: "gearshape")
        }
        Button(action: onShowImport) {
            Label("导入提醒".localized, systemImage: "square.and.arrow.down")
        }
        Button(action: onShowCardImport) {
            Label("导入分享卡片".localized, systemImage: "doc.on.clipboard")
        }
    }
}
