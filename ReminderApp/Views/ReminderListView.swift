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
    // 批次3 功能6: 单条分享卡片粘贴导入
    @State private var showCardImport = false
    @State private var cardImportText = ""
    @State private var cardImportMsg: String?
    // v1.8.7 任务④: .ics 日历导出
    @State private var showIcsExporter = false
    @State private var showNearbyShare = false
    @State private var icsDocument: ReminderBackupDocument?
    // 批次2 功能1: 通知点击直达确认面板 —— 待 push 的提醒 id
    @State private var pendingDetailID: UUID?
    // 批次2 功能2: 打卡成功 → 正向反馈卡片文案（非空即展示）
    @State private var checkInText: String?
    // v2.0.21 G3: 每次打卡自增，作为自动消失计时器的 id（换值即取消上一条的计时，防提前清空）
    @State private var checkInToken = 0
    // v1.8.7 在线升级
    @State private var updateInfo: AppUpdateInfo?
    @State private var downloading = false
    @State private var downloadError: String?
    @State private var downloadedIpaURL: URL?
    // v1.9.0: 手动检查结果提示（无新版/失败）
    @State private var updateResultMessage: String?

    // 同步提示
    @State private var syncMessage: String?
    // v2.0.22: 删除保存失败提示（不再吞错后假装删除成功）
    @State private var deleteError: String?
    // 点击日历某天 → 查看当日任务
    @State private var selectedDay: Date?
    @State private var showDaySheet = false

    var body: some View {
        // v1.9.8: NavigationStack 由 MainTabView 的 Tab 提供，避免嵌套双层导航栏
        mainContentWrapped
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
                        // 批次3 功能6: 单条分享卡片粘贴导入（聊天里收到的 JSON 直接粘进来）
                        Button {
                            menuAction { showCardImport = true }
                        } label: {
                            Label("导入分享卡片".localized, systemImage: "doc.on.clipboard")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3.weight(.semibold))
                    }
                }
            }
    }

    private var mainContentWrapped: some View {
        sheetsWrapped
            .onAppear {
                saveWidgetSnapshot(reminders)
                // 批次2 功能1: 冷启动兜底 —— 消费持久化的「通知点击直达确认面板」目标
                if let pending = NotificationManager.takePendingDetailID(),
                   let uuid = UUID(uuidString: pending) {
                    pendingDetailID = uuid
                }
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
            // 批次2 功能1: 点击通知本体 → 直达该提醒的确认面板
            // navigationDestination(item:) 需 Hashable → 用 UUID（SwiftData 模型非 Hashable，规避）
            .navigationDestination(item: $pendingDetailID) { id in
                if let reminder = reminders.first(where: { $0.id == id }) {
                    ReminderDetailView(reminder: reminder)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openReminderDetail)) { note in
                guard let idString = note.object as? String,
                      let uuid = UUID(uuidString: idString) else { return }
                pendingDetailID = uuid
            }
            // 批次2 功能2: 确认完成 → 打卡成功卡片（含当前连续天数）
            .onReceive(NotificationCenter.default.publisher(for: .reminderConfirmed)) { _ in
                let descriptor = FetchDescriptor<ReminderRecord>()
                let records = (try? modelContext.fetch(descriptor)) ?? []
                let streak = StatsService.summarize(records: records).currentStreak
                checkInText = streak > 1
                    ? "打卡成功，已连续 \(streak) 天 🎉"
                    : "打卡成功 🎉"
                checkInToken += 1
            }
            .overlay {
                CheckInFeedbackBanner(text: checkInText)
            }
            // v2.0.21 G3: 自动消失改用可取消的 task —— 原 asyncAfter(2.8s) 无法撤销，
            // 连续确认两条时第一条的计时器会把第二条卡片提前清掉。
            // task(id:) 在 token 变化时自动取消上一个（对齐 Android LaunchedEffect(text) 语义）。
            .task(id: checkInToken) {
                guard checkInToken > 0, checkInText != nil else { return }
                try? await Task.sleep(nanoseconds: 2_800_000_000)
                guard !Task.isCancelled else { return }
                checkInText = nil
            }
            .alert("同步".localized, isPresented: Binding(
                get: { syncMessage != nil },
                set: { if !$0 { syncMessage = nil } }
            )) {
                Button("好".localized, role: .cancel) {}
            } message: {
                Text((syncMessage ?? "").localized)
            }
            // v2.0.22: 删除保存失败提示
            .alert("删除失败".localized, isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("好".localized, role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
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

    private var sheetsWrapped: some View {
        mainContent
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
            // 批次3 功能6: 单条分享卡片粘贴导入
            .sheet(isPresented: $showCardImport) {
                NavigationStack {
                    Form {
                        Section("粘贴分享卡片".localized) {
                            TextEditor(text: $cardImportText)
                                .frame(minHeight: 200)
                        }
                        if let msg = cardImportMsg {
                            Section {
                                Text(msg)
                                    .foregroundStyle(msg.hasPrefix("✅") ? .green : .red)
                            }
                        }
                    }
                    .navigationTitle("导入分享卡片".localized)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消".localized) {
                                showCardImport = false
                                cardImportMsg = nil
                                cardImportText = ""
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("导入".localized) { importCard() }
                                .fontWeight(.semibold)
                        }
                    }
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

    // MARK: - 同步

    private func syncNow() {
        Task {
            let result = await WebDavSync.syncNow(reminders: reminders, modelContext: modelContext)
            switch result {
            case .success(let conflict):
                // v2.0.16: 双端都改过 → 提示已按版本覆盖
                syncMessage = conflict ? "已用最新版本覆盖（检测到双端都有修改，未合并）" : "同步完成"
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
            // I8: 写入失败（区别于「重复跳过」）直接返回，不再调度空列表、不误报成功
            if let err = result.error {
                print("[导入] 保存失败: \(err)")
                return
            }
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

    /// 批次3 功能6: 单条分享卡片粘贴导入
    private func importCard() {
        guard let item = BackupHelper.importSingle(cardImportText) else {
            cardImportMsg = "无法解析：请粘贴有效的分享卡片 JSON"
            return
        }
        let result = BackupHelper.importItems([item], existing: reminders, into: modelContext)
        // I8: 区分「写入失败」与「重复跳过」，避免保存失败被误报成「已存在」
        if let err = result.error {
            cardImportMsg = "导入失败：\(err)"
        } else if result.imported > 0 {
            Task {
                for reminder in result.inserted where reminder.isEnabled {
                    await ReminderEngine.shared.scheduleAllNotifications(for: reminder)
                }
            }
            cardImportMsg = "✅ 已导入 1 条提醒"
            cardImportText = ""
        } else {
            cardImportMsg = "该提醒已存在，跳过导入"
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

    /// 右滑 → 完成。已逾期的额外给一个「补打今天」入口（记录备注区分为补打卡）
    @ViewBuilder
    private func completeSwipe(for reminder: Reminder) -> some View {
        Button {
            ReminderEngine.shared.confirmReminder(reminder)
        } label: {
            Label("完成".localized, systemImage: "checkmark")
        }
        .tint(.green)

        if reminder.status == .overdue {
            Button {
                ReminderEngine.shared.confirmReminder(reminder, source: "补打卡")
            } label: {
                Label("补打今天".localized, systemImage: "checkmark.circle.badge.questionmark")
            }
            .tint(ThemeTokens.statusOverdue)
        }
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
        // v2.0.22: 保存失败时回滚并提示，不推进同步版本（否则会上传不完整数据）
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            deleteError = Localized("删除失败，请重试：%@", error.localizedDescription)
            return
        }
        SyncStore.touchLocalChange()
    }

    private func deleteReminder(_ reminder: Reminder) {
        Task {
            await NotificationManager.shared.removePendingNotification(for: reminder.id)
        }
        modelContext.delete(reminder)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            deleteError = Localized("删除失败，请重试：%@", error.localizedDescription)
            return
        }
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
