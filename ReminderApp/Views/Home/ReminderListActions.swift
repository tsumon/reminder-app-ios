import SwiftUI
import SwiftData
import WidgetKit

/// 首页数据操作与导入/同步/小组件快照扩展
extension ReminderListView {

    func menuAction(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: action)
    }

    func saveWidgetSnapshot(_ list: [Reminder]) {
        let now = Date()
        let unhandled = list.filter {
            $0.isEnabled && ($0.status == .active || $0.status == .snoozed || $0.status == .overdue || ($0.status == .pending && $0.nextTriggerAt <= now))
        }
        let next = list.filter { $0.isEnabled && $0.status != .confirmed }.min { $0.nextTriggerAt < $1.nextTriggerAt }
        WidgetSnapshot.save(WidgetReminderData(
            unhandledCount: unhandled.count,
            nextTitle: next?.title ?? "暂无提醒",
            nextTime: next?.nextTriggerAt,
            updatedAt: now,
            nextReminderID: next?.id.uuidString,
            nextActionToken: next?.actionToken
        ))
        WidgetCenter.shared.reloadAllTimelines()
    }

    func checkForUpdates() {
        Task {
            guard let info = await UpdateService.checkLatest() else {
                updateResultMessage = "检查更新失败，请检查网络后重试"; return
            }
            if info.isNewer { updateInfo = info }
            else { updateResultMessage = Localized("当前已是最新版本 v%@", UpdateService.currentVersion) }
        }
    }

    func exportBackup() {
        exportDocument = ReminderBackupDocument(text: BackupHelper.exportJSON(reminders))
        showExportExporter = true
    }

    func exportICS() {
        icsDocument = ReminderBackupDocument(text: IcsExporter.generateICS(reminders: reminders))
        showIcsExporter = true
    }

    func resolveSync(_ choice: WebDavSync.ConflictChoice) {
        Task {
            switch await WebDavSync.resolve(choice, context: modelContext) {
            case .success: syncMessage = "同步完成；本机独有提醒已保留。双端升级后支持删除同步。"
            case .conflict: showSyncConflict = true
            case .failure(let msg): syncMessage = msg
            }
        }
    }

    func handleSyncResult(_ result: WebDavSync.SyncResult) {
        switch result {
        case .success: syncMessage = "同步完成"
        case .conflict: showSyncConflict = true
        case .failure(let msg): syncMessage = msg
        }
    }

    func syncNow() {
        Task { handleSyncResult(await WebDavSync.syncNow(reminders: reminders, modelContext: modelContext)) }
    }

    func importBackup(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let json = String(data: data, encoding: .utf8),
              let items = BackupHelper.importJSON(json) else { return }
        let res = BackupHelper.importItems(items, existing: reminders, into: modelContext, json: json)
        guard res.error == nil else { return }
        Task {
            for r in res.inserted where r.isEnabled {
                await ReminderEngine.shared.scheduleAllNotifications(for: r)
            }
        }
    }

    func importCard() {
        guard let item = BackupHelper.importSingle(cardImportText) else {
            cardImportMsg = "无法解析：请粘贴有效的分享卡片 JSON"; return
        }
        let res = BackupHelper.importItems([item], existing: reminders, into: modelContext)
        if let err = res.error {
            cardImportMsg = "导入失败：\(err)"
        } else if res.imported > 0 {
            Task {
                for r in res.inserted where r.isEnabled {
                    await ReminderEngine.shared.scheduleAllNotifications(for: r)
                }
            }
            cardImportMsg = "✅ 已导入 1 条提醒"
            cardImportText = ""
        } else {
            cardImportMsg = "该提醒已存在，跳过导入"
        }
    }

    func fixAnchorMismatches() {
        let cal = Calendar.current
        for r in anchorMismatches {
            guard let intended = WeeklyWeekdayStore.get(for: r.id) else { continue }
            var target = cal.date(
                bySettingHour: cal.component(.hour, from: r.firstTriggerAt),
                minute: cal.component(.minute, from: r.firstTriggerAt),
                second: 0,
                of: Date()
            ) ?? Date()
            let cur = ((cal.component(.weekday, from: target) + 5) % 7) + 1
            var diff = (intended - cur + 7) % 7
            if diff == 0 && target <= Date() { diff = 7 }
            target = cal.date(byAdding: .day, value: diff, to: target) ?? target
            r.firstTriggerAt = target; r.nextTriggerAt = target; r.updatedAt = Date()
            r.actionRevision += 1; r.undoCompletion = nil
        }
        try? modelContext.save()
        SyncStore.touchLocalChange()
        Task {
            for r in anchorMismatches where r.isEnabled {
                await ReminderEngine.shared.scheduleAllNotifications(for: r)
            }
        }
        anchorMismatches = []
    }
}
