import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import WidgetKit
import Combine

/// 导入/导出用的 JSON 文件文档
struct ReminderBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .plainText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// 首页：提醒列表
struct ReminderListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Reminder.nextTriggerAt) private var reminders: [Reminder]
    @State private var showCreateSheet = false

    // 智能清单筛选
    @State private var smartList: SmartList = .all

    // 搜索
    @State private var searchText = ""

    // 导入/导出
    @State private var showExportExporter = false
    @State private var exportDocument: ReminderBackupDocument?
    @State private var showImportImporter = false
    // v1.8.7 任务④: .ics 日历导出
    @State private var showIcsExporter = false
    @State private var showNearbyShare = false
    @State private var icsDocument: ReminderBackupDocument?
    // v1.8.7 在线升级
    @State private var updateInfo: AppUpdateInfo?
    @State private var downloading = false
    @State private var downloadError: String?
    @State private var downloadedIpaURL: URL?
    // v1.9.0: 手动检查结果提示（无新版/失败）
    @State private var updateResultMessage: String?

    // 同步提示
    @State private var syncMessage: String?
    // 点击日历某天 → 查看当日任务
    @State private var selectedDay: Date?
    @State private var showDaySheet = false

    var body: some View {
        // v1.9.8: NavigationStack 由 MainTabView 的 Tab 提供，避免嵌套双层导航栏
        mainContent
    }

    private var mainContent: some View {
        Group {
                if reminders.isEmpty {
                    emptyView
                } else {
                    listView
                }
            }
            .navigationTitle("提醒事项".localized)
            // v1.9.8.1: iPad 大屏下大标题区+玻璃背景形成大块空白，改 inline 更紧凑
            .navigationBarTitleDisplayMode(.inline)
            .glassNavigationBar()
            .searchable(text: $searchText, prompt: "搜索标题或备注")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink {
                        AIChatView()
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(ThemeTokens.brandPrimary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            menuAction { showCreateSheet = true }
                        } label: {
                            Label("新建提醒".localized, systemImage: "plus.circle")
                        }
                        Divider()
                        // v1.8.7 任务③: 统计洞察
                        NavigationLink {
                            StatsView()
                        } label: {
                            Label("统计洞察".localized, systemImage: "chart.bar.fill")
                        }
                        Divider()
                        Button {
                            syncNow()
                        } label: {
                            Label("立即同步".localized, systemImage: "arrow.triangle.2.circlepath")
                        }
                        NavigationLink {
                            SyncSettingsView()
                        } label: {
                            Label("同步设置".localized, systemImage: "gearshape")
                        }
                        Divider()
                        Button {
                            menuAction { exportBackup() }
                        } label: {
                            Label("导出提醒".localized, systemImage: "square.and.arrow.up")
                        }
                        // v1.8.7 任务④: 导出 .ics 日历（可导入系统日历/Google 日历）
                        Button {
                            menuAction { exportICS() }
                        } label: {
                            Label("导出日历(.ics)".localized, systemImage: "calendar.badge.plus")
                        }
                        // 近场传输: 同一局域网互传提醒
                        Button {
                            menuAction { showNearbyShare = true }
                        } label: {
                            Label("附近传输".localized, systemImage: "wifi")
                        }
                        // v1.9.0: 主动检查更新
                        Button {
                            menuAction { checkForUpdates() }
                        } label: {
                            Label("检查更新".localized, systemImage: "arrow.clockwise")
                        }
                        Divider()
                        // v1.9.2: 设置（版本/更新日志/AI/同步）
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Label("设置".localized, systemImage: "gearshape")
                        }
                        Button {
                            menuAction { showImportImporter = true }
                        } label: {
                            Label("导入提醒".localized, systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3.weight(.semibold))
                    }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateReminderView()
            }
            // 近场传输: 同一局域网互传提醒
            .sheet(isPresented: $showNearbyShare) {
                NearbyShareView()
            }
            .fileExporter(
                isPresented: $showExportExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "reminder_backup_\(Int(Date().timeIntervalSince1970))"
            ) { result in
                if case .failure(let error) = result {
                    print("[导出] 失败: \(error)")
                }
            }
            .fileExporter(
                isPresented: $showIcsExporter,
                document: icsDocument,
                contentType: .plainText,
                defaultFilename: "reminders"
            ) { result in
                if case .failure(let error) = result {
                    print("[.ics 导出] 失败: \(error)")
                }
            }
            .fileImporter(
                isPresented: $showImportImporter,
                allowedContentTypes: [.json, .plainText]
            ) { result in
                importBackup(result)
            }
            .onAppear {
                saveWidgetSnapshot(reminders)
                // 自动同步（限频 5 分钟）
                if SyncStore.autoSync && SyncStore.isConfigured &&
                    Date().timeIntervalSince1970 - SyncStore.lastSyncAt > 300 {
                    Task {
                        _ = await WebDavSync.syncNow(reminders: reminders, modelContext: modelContext)
                    }
                }
            }
            .task {
                // v1.8.7 在线升级: 启动后台检查 GitHub 最新版本
                if let info = await UpdateService.checkLatest(), info.isNewer {
                    updateInfo = info
                }
            }
            .onChange(of: reminders) { _, newValue in
                saveWidgetSnapshot(newValue)
            }
            // v1.9.6 fix: 通知动作全局处理（合并 publisher 减链长，处理逻辑在独立方法）。
            // 原实现只在详情页 onReceive → 其他页点通知按钮操作静默丢失；
            // dismiss(滑动消除) 也从未触发递增重试 → 统计「漏掉」恒为 0。
            .onReceive(notificationActionPublisher) { notification in
                handleNotificationAction(notification.name, notification)
            }
            .alert("同步".localized, isPresented: Binding(
                get: { syncMessage != nil },
                set: { if !$0 { syncMessage = nil } }
            )) {
                Button("好".localized, role: .cancel) {}
            } message: {
                Text((syncMessage ?? "").localized)
            }
            // v1.8.7 在线升级(自签): 发现新版本 → 下载 ipa 到本地文件 App
            .alert(
                Localized("发现新版本 v%@", updateInfo?.latestVersion ?? ""),
                isPresented: Binding(
                    get: { updateInfo != nil && downloadedIpaURL == nil && downloadError == nil },
                    set: { if !$0 { updateInfo = nil; downloading = false } }
                )
            ) {
                if let info = updateInfo, let ipa = info.ipaURL {
                    Button("下载到本地".localized) {
                        downloading = true
                        Task {
                            do {
                                downloadedIpaURL = try await UpdateService.downloadIpa(from: ipa, version: info.latestVersion)
                            } catch {
                                downloadError = error.localizedDescription
                            }
                            downloading = false
                        }
                    }
                    .disabled(downloading)
                } else if let info = updateInfo {
                    Button("查看发布页".localized) {
                        UIApplication.shared.open(info.releaseURL)
                        updateInfo = nil
                    }
                }
                Button("稍后再说".localized, role: .cancel) { updateInfo = nil }
            } message: {
                Text(
                    downloading ? "正在下载 .ipa…\n下载完成后请到「文件」App → 我的 iPhone → 循环提醒 → 用自签工具签名安装。".localized
                    : Localized("当前 v%@。本 App 通过 GitHub Releases 自签分发，请下载 .ipa 用 AltStore/爱思等工具签名安装。", UpdateService.currentVersion)
                )
            }
            // 下载结果：提示文件 App 路径 + 分享按钮
            .sheet(isPresented: Binding(
                get: { downloadedIpaURL != nil || downloadError != nil },
                set: { if !$0 { downloadedIpaURL = nil; downloadError = nil } }
            )) {
                downloadedResultSheet
            }
            // v1.9.0: 手动检查更新结果
            .alert(
                "检查更新",
                isPresented: Binding(
                    get: { updateResultMessage != nil },
                    set: { if !$0 { updateResultMessage = nil } }
                )
            ) {
                Button("好".localized, role: .cancel) { updateResultMessage = nil }
            } message: {
                Text((updateResultMessage ?? "").localized)
            }
            .sheet(isPresented: $showDaySheet) {
                if let day = selectedDay {
                    DayTasksSheet(day: day, reminders: reminders)
                }
            }
    }

    // MARK: - 小组件数据快照

    private func saveWidgetSnapshot(_ reminders: [Reminder]) {
        let now = Date()
        let unhandled = reminders.filter {
            $0.isEnabled && ($0.status == .active || $0.status == .snoozed ||
                ($0.status == .pending && $0.nextTriggerAt <= now))
        }
        let next = reminders
            .filter { $0.isEnabled && $0.nextTriggerAt > now }
            .min { $0.nextTriggerAt < $1.nextTriggerAt }

        WidgetSnapshot.save(WidgetReminderData(
            unhandledCount: unhandled.count,
            nextTitle: next?.title ?? "暂无提醒",
            nextTime: next?.nextTriggerAt,
            updatedAt: now,
            // v1.8.7: 供小组件「完成」按钮定位提醒
            nextReminderID: next?.id.uuidString
        ))

        // 主动刷新已添加的小组件
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// v1.9.0: 手动检查更新（有新版弹窗，无新版/失败提示结果）
    private func checkForUpdates() {
        Task {
            guard let info = await UpdateService.checkLatest() else {
                updateResultMessage = "检查更新失败，请检查网络后重试"
                return
            }
            if info.isNewer {
                updateInfo = info
            } else {
                updateResultMessage = Localized("当前已是最新版本 v%@", UpdateService.currentVersion)
            }
        }
    }

    // MARK: - 导入/导出

    /// iOS 17 Menu+sheet 竞争修复：Menu 内 Button 同步触发弹层会与菜单关闭动画
    /// 竞争导致不弹出，统一延迟一帧再触发
    private func menuAction(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            action()
        }
    }

    private func exportBackup() {
        let json = BackupHelper.exportJSON(reminders)
        exportDocument = ReminderBackupDocument(text: json)
        showExportExporter = true
    }

    /// v1.8.7 任务④: 生成 .ics 并弹出系统分享
    private func exportICS() {
        let ics = IcsExporter.generateICS(reminders: reminders)
        icsDocument = ReminderBackupDocument(text: ics)
        showIcsExporter = true
    }

    // MARK: - 通知动作（全局处理）

    /// 通知栏「确认/稍后/消除」合并 publisher（类型显式化，避免 body 链类型检查超时）
    private var notificationActionPublisher: AnyPublisher<Notification, Never> {
        NotificationCenter.default.publisher(for: .reminderConfirmed)
            .merge(with: NotificationCenter.default.publisher(for: .reminderSnoozed))
            .merge(with: NotificationCenter.default.publisher(for: .reminderDismissed))
            .eraseToAnyPublisher()
    }

    /// 处理通知栏「确认/稍后/消除」广播：在根视图统一监听，
    /// 避免只在详情页监听导致其他页面操作静默丢失
    private func handleNotificationAction(_ name: Notification.Name, _ notification: Notification) {
        guard let id = notification.userInfo?["reminderID"] as? UUID,
              let r = reminders.first(where: { $0.id == id }) else { return }
        switch name {
        case .reminderConfirmed:
            ReminderEngine.shared.confirmReminder(r)
        case .reminderSnoozed:
            ReminderEngine.shared.snoozeReminder(r)
        case .reminderDismissed:
            ReminderEngine.shared.escalateRetry(r)
        default:
            break
        }
    }

    // MARK: - 同步

    private func syncNow() {
        Task {
            let result = await WebDavSync.syncNow(reminders: reminders, modelContext: modelContext)
            switch result {
            case .success:
                syncMessage = "同步完成"
            case .failure(let msg):
                syncMessage = msg
            }
        }
    }

    private func importBackup(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: url),
                  let json = String(data: data, encoding: .utf8),
                  let items = BackupHelper.importJSON(json) else {
                print("[导入] 解析失败")
                return
            }

            // 通用导入（去重 / 过期重算 / 插入 / 保存 / touch 变更）
            let result = BackupHelper.importItems(items, existing: reminders, into: modelContext)
            print("[导入] 新增 \(result.imported) 条，跳过重复 \(result.skipped) 条")

            // 重新调度通知：必须遍历本次实际导入的模型对象。
            // 遍历 @Query 的 reminders 快照可能漏掉刚插入的行（SwiftData 刷新时机不确定）。
            Task {
                for reminder in result.inserted where reminder.isEnabled {
                    await ReminderEngine.shared.scheduleAllNotifications(for: reminder)
                }
            }
        case .failure(let error):
            print("[导入] 失败: \(error)")
        }
    }

    // MARK: - 空状态

    private var emptyView: some View {
        List {
            // 日历
            Section {
                CalendarCardView(reminders: reminders, onDateTap: { selectedDay = $0; showDaySheet = true })
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section {
                VStack(spacing: 20) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)

                    Text("暂无提醒".localized)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text("点击右上角 + 创建你的第一个循环提醒".localized)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)

                    Button {
                        showCreateSheet = true
                    } label: {
                        Label("创建提醒".localized, systemImage: "plus.circle.fill")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - 下载结果 sheet

    @ViewBuilder
    private var downloadedResultSheet: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if let ipaURL = downloadedIpaURL {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)
                    Text("下载完成".localized)
                        .font(.title2.weight(.bold))
                    Text(Localized("已保存到「文件」App：\n我的 iPhone → 循环提醒 → %@", ipaURL.lastPathComponent))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    // 主操作：分享给签名工具（AirDrop 到电脑等）
                    ShareLink(item: ipaURL) {
                        Label("分享 ipa 给签名工具".localized, systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ThemeTokens.brandPrimary)
                    .padding(.horizontal)

                    // 引导说明
                    Text("⚠️ 在「文件」App 里直接点击 .ipa 没反应是正常的——\niOS 不提供 .ipa 安装器，需要先签名。\n\n推荐流程：\n① 点上方「分享 ipa」→ AirDrop 到电脑\n② 用 AltStore / 爱思助手 / Sideloadly 签名安装\n③ 或先点「在文件 App 中查看」确认文件已下载".localized)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 24)

                    VStack(spacing: 10) {
                        Button {
                            if let dir = try? UpdateService.downloadsDirectory() {
                                UIApplication.shared.open(dir)
                            }
                        } label: {
                            Label("在文件 App 中查看".localized, systemImage: "folder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                } else if let err = downloadError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.orange)
                    Text("下载失败".localized)
                        .font(.title2.weight(.bold))
                    Text(err)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Spacer()
            }
            .padding(.top, 30)
            .navigationTitle("在线升级".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("好".localized) {
                        downloadedIpaURL = nil
                        downloadError = nil
                    }
                }
            }
        }
        .presentationDetents([.height(520)])
    }

    // MARK: - 提醒列表

    private var listView: some View {
        List {
            // 智能清单筛选条
            Section {
                smartListBar
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            // 概览（参考滴答清单：待处理数 + 最近提醒）
            let unhandled = reminders.filter { $0.isEnabled && $0.status != .confirmed }.count
            let next = reminders.filter { $0.isEnabled && $0.nextTriggerAt > Date() }.min { $0.nextTriggerAt < $1.nextTriggerAt }
            Section {
                OverviewCard(unhandledCount: unhandled, nextReminder: next)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            // v1.9.8: 日历卡片移到「日历」Tab（CalendarPageView），首页只保留列表

            // 应用智能清单筛选后的全集（叠加搜索）
            let query = searchText.trimmingCharacters(in: .whitespaces)
            let filtered = reminders.filter {
                matchSmartList($0) &&
                (query.isEmpty ||
                 $0.title.localizedCaseInsensitiveContains(query) ||
                 $0.note.localizedCaseInsensitiveContains(query))
            }

            // 正在提醒中（active / snoozed / overdue）
            let activeReminders = filtered.filter {
                $0.status == .active || $0.status == .snoozed || $0.status == .overdue
            }
            if !activeReminders.isEmpty {
                Section {
                    ForEach(activeReminders) { reminder in
                        NavigationLink {
                            ReminderDetailView(reminder: reminder)
                        } label: {
                            ReminderRowView(reminder: reminder)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                        .swipeActions(edge: .leading) {
                            completeSwipe(for: reminder)
                        }
                        .swipeActions(edge: .trailing) {
                            deleteSwipe(for: reminder)
                        }
                    }
                } header: {
                    sectionHeader(title: "提醒中", color: ThemeTokens.statusReminding, count: activeReminders.count)
                }
            }

            // 等待中
            let pendingReminders = filtered.filter { $0.status == .pending }
            if !pendingReminders.isEmpty {
                Section {
                    ForEach(pendingReminders) { reminder in
                        NavigationLink {
                            ReminderDetailView(reminder: reminder)
                        } label: {
                            ReminderRowView(reminder: reminder)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                        .swipeActions(edge: .leading) {
                            completeSwipe(for: reminder)
                        }
                        .swipeActions(edge: .trailing) {
                            deleteSwipe(for: reminder)
                        }
                    }
                } header: {
                    sectionHeader(title: "等待中", color: ThemeTokens.statusWaiting, count: pendingReminders.count)
                }
            }

            // 已完成
            let confirmedReminders = filtered.filter { $0.status == .confirmed }
            if !confirmedReminders.isEmpty {
                Section {
                    ForEach(confirmedReminders) { reminder in
                        NavigationLink {
                            ReminderDetailView(reminder: reminder)
                        } label: {
                            ReminderRowView(reminder: reminder)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                        .swipeActions(edge: .leading) {
                            reopenSwipe(for: reminder)
                        }
                        .swipeActions(edge: .trailing) {
                            deleteSwipe(for: reminder)
                        }
                    }
                } header: {
                    sectionHeader(title: "已完成", color: ThemeTokens.statusCompleted, count: confirmedReminders.count)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: searchText)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable {
            await ReminderEngine.shared.checkMissedReminders(reminders: reminders)
        }
    }

    // MARK: - 智能清单筛选条

    private var smartListBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SmartList.allCases, id: \.self) { list in
                    Button {
                        smartList = list
                    } label: {
                        Text(list.label)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(smartList == list ? Color.accentColor : Color.gray.opacity(0.18))
                            .foregroundStyle(smartList == list ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    // MARK: - 分组标题（设计图风格：小色条 + 标题 + 数量）

    @ViewBuilder
    private func sectionHeader(title: String, color: Color, count: Int) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 4, height: 14)
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text("· \(count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 滑动操作

    /// 右滑 → 完成
    @ViewBuilder
    private func completeSwipe(for reminder: Reminder) -> some View {
        Button {
            ReminderEngine.shared.confirmReminder(reminder)
        } label: {
            Label("完成".localized, systemImage: "checkmark")
        }
        .tint(.green)
    }

    /// 右滑（已完成行）→ 重新打开
    @ViewBuilder
    private func reopenSwipe(for reminder: Reminder) -> some View {
        Button {
            ReminderEngine.shared.reopenReminder(reminder)
        } label: {
            Label("重开".localized, systemImage: "arrow.uturn.backward")
        }
        .tint(.orange)
    }

    /// 左滑 → 删除
    @ViewBuilder
    private func deleteSwipe(for reminder: Reminder) -> some View {
        Button(role: .destructive) {
            deleteReminder(reminder)
        } label: {
            Label("删除".localized, systemImage: "trash")
        }
    }

    // MARK: - 智能清单匹配

    private func matchSmartList(_ reminder: Reminder) -> Bool {
        switch smartList {
        case .all:      return true
        case .done:     return reminder.status == .confirmed
        case .high:     return reminder.priority == .high
        case .today:    return occursWithin(reminder: reminder, days: 0...0)
        case .tomorrow: return occursWithin(reminder: reminder, days: 1...1)
        case .week:     return occursWithin(reminder: reminder, days: 0...7)
        case .month:    return occursWithin(reminder: reminder, days: 0...daysLeftInMonth())
        }
    }

    private func occursWithin(reminder: Reminder, days: ClosedRange<Int>) -> Bool {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for d in days.lowerBound...days.upperBound {
            guard let date = cal.date(byAdding: .day, value: d, to: today) else { continue }
            let y = cal.component(.year, from: date)
            let m = cal.component(.month, from: date)
            let day = cal.component(.day, from: date)
            if ReminderEngine.shared.occursOn(reminder: reminder, year: y, month: m, day: day) {
                return true
            }
        }
        return false
    }

    private func daysLeftInMonth() -> Int {
        let cal = Calendar.current
        let now = Date()
        guard let range = cal.range(of: .day, in: .month, for: now),
              let lastDay = cal.date(bySetting: .day, value: range.count, of: now) else { return 30 }
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: lastDay)).day ?? 30
    }

    private func deleteReminders(_ offsets: IndexSet, from items: [Reminder]) {
        for index in offsets {
            guard index < items.count else { continue }
            let reminder = items[index]
            Task {
                await NotificationManager.shared.removePendingNotification(for: reminder.id)
            }
            modelContext.delete(reminder)
        }
        try? modelContext.save()
        SyncStore.touchLocalChange()
    }

    private func deleteReminder(_ reminder: Reminder) {
        Task {
            await NotificationManager.shared.removePendingNotification(for: reminder.id)
        }
        modelContext.delete(reminder)
        try? modelContext.save()
        SyncStore.touchLocalChange()
    }
}

// MARK: - 智能清单类型

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

// MARK: - 点击日历某天 → 当日任务弹窗

struct DayTasksSheet: View {
    let day: Date
    let reminders: [Reminder]

    @MainActor private var dateReminders: [Reminder] {
        let cal = Calendar.current
        let y = cal.component(.year, from: day)
        let m = cal.component(.month, from: day)
        let d = cal.component(.day, from: day)
        return reminders.filter {
            $0.isEnabled && ReminderEngine.shared.occursOn(reminder: $0, year: y, month: m, day: d)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if dateReminders.isEmpty {
                    Spacer()
                    Text("这一天没有提醒".localized)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    List(dateReminders) { r in
                        NavigationLink {
                            ReminderDetailView(reminder: r)
                        } label: {
                            ReminderRowView(reminder: r)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var title: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: day) + " 的任务"
    }
}

// MARK: - 首页概览卡片（参考滴答清单：待处理数 + 最近提醒）

struct OverviewCard: View {
    let unhandledCount: Int
    let nextReminder: Reminder?

    var body: some View {
        // 液态玻璃版：品牌渐变玻璃 + 顶部高光 + 大圆角柔和阴影
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge.fill")
                        .font(.title3)
                        .symbolEffect(.bounce, value: unhandledCount)
                    Text(Localized("待处理 %d 项", unhandledCount))
                        .font(.headline)
                }
                if let r = nextReminder {
                    Text("\(r.title) · \(r.nextTriggerAt.formatted(date: .numeric, time: .shortened))")
                        .font(.subheadline)
                        .lineLimit(1)
                        .opacity(0.9)
                } else {
                    Text("暂无即将到来的提醒".localized)
                        .font(.subheadline)
                        .opacity(0.9)
                }
            }
            Spacer()
            // 大数字装饰（滴答清单式数据强调）
            Text("\(unhandledCount)")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .opacity(0.9)
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [ThemeTokens.brandPrimary, ThemeTokens.brandPrimaryDark],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        // 玻璃高光：顶部白色渐变
        .overlay(
            LinearGradient(
                colors: [.white.opacity(0.28), .white.opacity(0.0)],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: ThemeTokens.brandPrimary.opacity(0.30), radius: 16, y: 8)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}
