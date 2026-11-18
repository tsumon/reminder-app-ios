import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import WidgetKit

/// 首页协调容器：两张通透大卡 + 底纸纯文字穿插行 + 完整同步/升级/备份生命周期
struct ReminderListView: View {
    @State var showSyncConflict = false
    @Environment(\.modelContext) var modelContext
    @Environment(\.comic) private var comic
    @Query(sort: \Reminder.nextTriggerAt) var reminders: [Reminder]
    @Query(sort: \ReminderRecord.performedAt) private var records: [ReminderRecord]

    struct CreateRequest: Identifiable {
        let id = UUID()
        let sentence: String
    }

    @State private var createRequest: CreateRequest?
    @State private var quickSentence = ""
    @FocusState private var quickFocused: Bool
    @State private var createdID: UUID?
    @State private var createdToken: String?

    @State private var smartList: SmartList = .all
    @State private var kindFilter = "all"
    @State private var sortOrder = "time"
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @FocusState private var searchFocused: Bool
    @State private var showCompletedSection = false

    @State var anchorMismatches: [Reminder] = []
    @State var showExportExporter = false
    @State var exportDocument: ReminderBackupDocument?
    @State var showImportImporter = false
    @State var showCardImport = false
    @State var cardImportText = ""
    @State var cardImportMsg: String?
    @State var showIcsExporter = false
    @State var showNearbyShare = false
    @State var icsDocument: ReminderBackupDocument?

    @State private var pendingDetailID: UUID?
    @State private var showDiagnostics = false
    @State private var checkInText: String?
    @State private var checkInToken = 0

    @State var updateInfo: AppUpdateInfo?
    @State var downloading = false
    @State var downloadError: String?
    @State var downloadedIpaURL: URL?
    @State var updateResultMessage: String?
    @State var syncMessage: String?
    @State private var deleteError: String?
    @State private var selectedDay: Date?
    @State private var showDaySheet = false

    var body: some View {
        lifecycleWrapped
            .confirmationDialog(
                "同步冲突：两边都有修改，已停止写入。选择前将保存本地快照。双端升级后可同步删除。",
                isPresented: $showSyncConflict
            ) {
                Button("使用本地并上传".localized) { resolveSync(.local) }
                Button("使用远程并保留本机独有提醒".localized) { resolveSync(.remote) }
                Button("取消".localized, role: .cancel) {}
            }
    }

    private var mainContent: some View {
        let filtered = filteredReminders
        let dueList = filtered.filter { $0.status == .active || $0.status == .snoozed || $0.status == .overdue }
        let unconfirmed = filtered.filter { $0.status != .confirmed }
        let confirmed = filtered.filter { $0.status == .confirmed }
        let nextUpcoming = reminders.filter { $0.isEnabled && $0.status != .confirmed }.min { $0.nextTriggerAt < $1.nextTriggerAt }
        let doneToday = records.filter {
            $0.type == ReminderRecordType.confirm.rawValue && Calendar.current.isDateInToday($0.performedAt)
        }.count

        return VStack(spacing: 0) {
            HomeHeaderSection(
                smartList: $smartList, kindFilter: $kindFilter, sortOrder: $sortOrder,
                quickSentence: $quickSentence, quickFocused: $quickFocused,
                searchText: $searchText, isSearchPresented: $isSearchPresented, searchFocused: $searchFocused,
                hasUndoCreate: createdID != nil, onUndoCreate: undoJustCreated,
                onCreateNew: { menuAction { presentCreate(sentence: "") } },
                onCheckRule: { presentCreate(sentence: quickSentence) },
                onSyncNow: syncNow,
                onExportBackup: { menuAction { exportBackup() } },
                onExportICS: { menuAction { exportICS() } },
                onShowNearbyShare: { menuAction { showNearbyShare = true } },
                onCheckUpdates: { menuAction { checkForUpdates() } },
                onShowImport: { menuAction { showImportImporter = true } },
                onShowCardImport: { menuAction { showCardImport = true } }
            )

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    HomeHeroCard(
                        totalCount: reminders.count,
                        enabledCount: reminders.filter(\.isEnabled).count,
                        doneTodayCount: doneToday,
                        dueReminders: dueList,
                        nextUpcoming: nextUpcoming,
                        onCreate: { presentCreate(sentence: "") },
                        onOpenDetail: { pendingDetailID = $0 },
                        onConfirm: confirmItem,
                        onSnooze: snoozeItem,
                        onSkip: skipItem
                    )

                    NotificationHealthCard { showDiagnostics = true }

                    if !reminders.isEmpty {
                        HomeEventListCard(
                            title: smartList == .all ? "即将到来".localized : smartList.label.localized,
                            rows: pairHomeBirthdayRows(unconfirmed),
                            onOpenDetail: { pendingDetailID = $0 },
                            onConfirm: confirmItem,
                            onSnooze: snoozeItem,
                            onSkip: skipItem,
                            onDelete: deleteReminder
                        )
                    }

                    if !confirmed.isEmpty {
                        ComicCollapsibleLine(
                            title: Localized("已完成 %d 项", confirmed.count),
                            isExpanded: showCompletedSection
                        ) {
                            withAnimation(.easeOut(duration: 0.18)) { showCompletedSection.toggle() }
                        }

                        if showCompletedSection {
                            HomeCompletedCard(
                                items: confirmed,
                                onOpenDetail: { pendingDetailID = $0 },
                                onReopen: { ReminderEngine.shared.reopenReminder($0) },
                                onDelete: deleteReminder
                            )
                        }
                    }
                }
                .padding(.horizontal, ThemeTokens.gutter)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
            .refreshable {
                await ReminderEngine.shared.checkMissedReminders(reminders: reminders)
            }
        }
        .background(ComicCanvas())
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var filteredReminders: [Reminder] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return reminders.filter {
            matchSmartList($0) &&
            (kindFilter == "all" || $0.kind.rawValue == kindFilter) &&
            (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.note.localizedCaseInsensitiveContains(query))
        }.sorted {
            if sortOrder == "title" { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            if sortOrder == "priority" && $0.priority != $1.priority {
                let p0 = $0.priority == .high ? 0 : ($0.priority == .normal ? 1 : 2)
                let p1 = $1.priority == .high ? 0 : ($1.priority == .normal ? 1 : 2)
                return p0 < p1
            }
            return $0.nextTriggerAt < $1.nextTriggerAt
        }
    }

    private func matchSmartList(_ reminder: Reminder) -> Bool {
        switch smartList {
        case .all:      return true
        case .done:     return reminder.status == .confirmed
        case .high:     return reminder.priority == .high
        case .today:    return occursWithin(reminder: reminder, days: 0...0)
        case .tomorrow: return occursWithin(reminder: reminder, days: 1...1)
        case .week:     return occursWithin(reminder: reminder, days: 0...7)
        case .month:    return occursWithin(reminder: reminder, days: 0...30)
        }
    }

    private func occursWithin(reminder: Reminder, days: ClosedRange<Int>) -> Bool {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for d in days {
            guard let date = cal.date(byAdding: .day, value: d, to: today) else { continue }
            if ReminderEngine.shared.occursOn(reminder: reminder, year: cal.component(.year, from: date),
                                              month: cal.component(.month, from: date), day: cal.component(.day, from: date)) {
                return true
            }
        }
        return false
    }

    private func presentCreate(sentence: String) {
        quickFocused = false; searchFocused = false
        createRequest = CreateRequest(sentence: sentence)
    }

    private func undoJustCreated() {
        guard let id = createdID, let r = reminders.first(where: { $0.id == id }),
              r.actionToken == createdToken, r.records.isEmpty else {
            createdID = nil; return
        }
        if ReminderActions.delete(r, context: modelContext) {
            Task {
                await NotificationManager.shared.removePendingNotification(for: id)
                await ReminderEngine.shared.ensureRetryChains()
            }
        }
        createdID = nil
    }

    private func confirmItem(_ r: Reminder) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        _ = ReminderEngine.shared.confirmReminder(r, expectedToken: r.actionToken)
    }

    private func snoozeItem(_ r: Reminder) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        _ = ReminderEngine.shared.snoozeReminder(r, afterMinutes: 15, expectedToken: r.actionToken)
    }

    private func skipItem(_ r: Reminder) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        ReminderActions.skip(r, expectedToken: r.actionToken, context: modelContext)
        Task { await ReminderEngine.shared.scheduleAllNotifications(for: r) }
    }

    private func deleteReminder(_ reminder: Reminder) {
        let id = reminder.id
        guard ReminderActions.delete(reminder, context: modelContext) else {
            deleteError = "删除失败，请重试".localized; return
        }
        Task { await NotificationManager.shared.removePendingNotification(for: id) }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private var lifecycleWrapped: some View {
        alertsAndSheetsLayer
            .onAppear {
                saveWidgetSnapshot(reminders)
                if let pending = NotificationManager.takePendingDetailID(), let uuid = UUID(uuidString: pending) {
                    pendingDetailID = uuid
                } else if let widgetID = WidgetSnapshot.takeOpenDetailID(), let uuid = UUID(uuidString: widgetID) {
                    pendingDetailID = uuid
                    if WidgetSnapshot.takeHighlightConfirm() { NotificationManager.savePendingHighlightConfirm(true) }
                }
                if SyncStore.autoSync && SyncStore.isConfigured && Date().timeIntervalSince1970 - SyncStore.lastSyncAt > 300 {
                    Task { handleSyncResult(await WebDavSync.syncNow(reminders: reminders, modelContext: modelContext)) }
                }
            }
            .task {
                let mismatches = WeeklyWeekdayStore.anchorMismatches(reminders: reminders)
                if !mismatches.isEmpty { anchorMismatches = mismatches }
                if let info = await UpdateService.checkLatest(), info.isNewer { updateInfo = info }
                LocalBackupService.backupOnLaunch(reminders: reminders)
            }
            .onChange(of: reminders) { _, newValue in saveWidgetSnapshot(newValue) }
            .navigationDestination(item: $pendingDetailID) { id in
                if let reminder = reminders.first(where: { $0.id == id }) {
                    ReminderDetailView(reminder: reminder, highlightConfirm: NotificationManager.takePendingHighlightConfirm())
                }
            }
            .navigationDestination(isPresented: $showDiagnostics) { DiagnosticsView() }
            .onReceive(NotificationCenter.default.publisher(for: .openReminderDetail)) { note in
                if let idString = note.object as? String, let uuid = UUID(uuidString: idString) { pendingDetailID = uuid }
            }
            .onReceive(NotificationCenter.default.publisher(for: .reminderConfirmed)) { _ in
                let all = (try? modelContext.fetch(FetchDescriptor<ReminderRecord>())) ?? []
                let streak = StatsService.summarize(records: all).currentStreak
                checkInText = streak > 1 ? "打卡成功，已连续 \(streak) 天" : "打卡成功"
                checkInToken += 1
            }
            .overlay { CheckInFeedbackBanner(text: checkInText) }
            .task(id: checkInToken) {
                guard checkInToken > 0, checkInText != nil else { return }
                try? await Task.sleep(nanoseconds: 2_800_000_000)
                if !Task.isCancelled { checkInText = nil }
            }
    }

    private var alertsAndSheetsLayer: some View {
        mainContent
            .sheet(item: $createRequest, onDismiss: { quickFocused = false }) { req in
                CreateReminderView(initialSentence: req.sentence) { r in
                    createdID = r.id; createdToken = r.actionToken; quickSentence = ""; quickFocused = false
                }
            }
            .sheet(isPresented: $showNearbyShare) { NearbyShareView() }
            .sheet(isPresented: $showDaySheet) { if let day = selectedDay { DayTasksSheet(day: day, reminders: reminders) } }
            .sheet(isPresented: Binding(get: { downloadedIpaURL != nil || downloadError != nil }, set: { if !$0 { downloadedIpaURL = nil; downloadError = nil } })) {
                DownloadedIpaSheet(downloadedIpaURL: downloadedIpaURL, downloadError: downloadError) { downloadedIpaURL = nil; downloadError = nil }
            }
            .sheet(isPresented: $showCardImport) {
                CardImportSheet(text: $cardImportText, message: cardImportMsg, onCancel: { showCardImport = false; cardImportMsg = nil; cardImportText = "" }, onImport: importCard)
            }
            .fileExporter(isPresented: $showExportExporter, document: exportDocument, contentType: .json, defaultFilename: "reminder_backup_\(Int(Date().timeIntervalSince1970))") { _ in }
            .fileExporter(isPresented: $showIcsExporter, document: icsDocument, contentType: .plainText, defaultFilename: "reminders") { _ in }
            .fileImporter(isPresented: $showImportImporter, allowedContentTypes: [.json, .plainText], onCompletion: importBackup)
            .alert(Localized("发现新版本 v%@", updateInfo?.latestVersion ?? ""), isPresented: Binding(get: { updateInfo != nil && downloadedIpaURL == nil && downloadError == nil }, set: { if !$0 { updateInfo = nil; downloading = false } })) {
                if let info = updateInfo, info.ipaURL != nil {
                    Button("下载到本地".localized) {
                        downloading = true
                        Task { do { downloadedIpaURL = try await UpdateService.downloadIpa(info: info) } catch { downloadError = error.localizedDescription }; downloading = false }
                    }.disabled(downloading)
                } else if let info = updateInfo {
                    Button("查看发布页".localized) { UIApplication.shared.open(info.releaseURL); updateInfo = nil }
                }
                Button("稍后再说".localized, role: .cancel) { updateInfo = nil }
            } message: { Text(downloading ? "正在下载 .ipa…".localized : Localized("当前 v%@。", UpdateService.currentVersion)) }
            .alert("检查更新", isPresented: Binding(get: { updateResultMessage != nil }, set: { if !$0 { updateResultMessage = nil } })) {
                Button("好".localized, role: .cancel) { updateResultMessage = nil }
            } message: { Text((updateResultMessage ?? "").localized) }
            .alert("同步".localized, isPresented: Binding(get: { syncMessage != nil }, set: { if !$0 { syncMessage = nil } })) {
                Button("好".localized, role: .cancel) {}
            } message: { Text((syncMessage ?? "").localized) }
            .alert("提醒日错位".localized, isPresented: Binding(get: { !anchorMismatches.isEmpty }, set: { if !$0 { anchorMismatches = [] } })) {
                Button("修正为设定星期".localized) { fixAnchorMismatches() }
                Button("忽略".localized, role: .cancel) { anchorMismatches = [] }
            } message: { Text("检测到每周提醒锚点与设定星期不一致，是否自动修正？".localized) }
            .alert("删除失败".localized, isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
                Button("好".localized, role: .cancel) {}
            } message: { Text(deleteError ?? "") }
    }
}
