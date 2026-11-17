import SwiftUI
import SwiftData

/// v2.1.1: 本地备份管理——自签环境没有 iCloud，备份到「文件」App 可见目录，
/// 可随时手动备份、查看/分享历史备份文件（保留最近 5 份）。
struct LocalBackupsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var reminders: [Reminder]

    @State private var files: [URL] = []
    @State private var lastResult: String?
    @State private var isError = false
    @State private var pendingRestoreURL: URL?

    var body: some View {
        List {
            Section {
                Label("备份保存在 App 文档目录：文件 App → 我的 iPhone → 循环提醒 → ReminderBackups".localized,
                      systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("备份文件".localized) {
                if files.isEmpty {
                    Text("暂无备份".localized)
                        .foregroundStyle(.secondary)
                }
                ForEach(files, id: \.self) { url in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent)
                                .font(.subheadline)
                            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                                Text("\(max(1, size / 1024)) KB".localized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            pendingRestoreURL = url
                        } label: {
                            Text("恢复".localized)
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(ThemeTokens.strong)

                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                                .frame(minWidth: 32, minHeight: 32)
                        }
                    }
                }
            }

            Section {
                Button {
                    if let url = LocalBackupService.backupNow(reminders: reminders) {
                        files = LocalBackupService.backups
                        isError = false
                        lastResult = Localized("已备份：%@", url.lastPathComponent)
                    } else {
                        isError = true
                        lastResult = "备份失败".localized
                    }
                } label: {
                    Label("立即备份".localized, systemImage: "externaldrive.badge.plus")
                }
            } footer: {
                if let lastResult {
                    Text(lastResult)
                        .foregroundStyle(isError ? ThemeTokens.statusOverdue : ThemeTokens.statusCompleted)
                }
            }
        }
        .navigationTitle("本地备份".localized)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            files = LocalBackupService.backups
        }
        .confirmationDialog(
            "恢复此备份？".localized,
            isPresented: Binding(
                get: { pendingRestoreURL != nil },
                set: { if !$0 { pendingRestoreURL = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("恢复并合并".localized) {
                if let url = pendingRestoreURL { restoreBackup(from: url) }
                pendingRestoreURL = nil
            }
            Button("取消".localized, role: .cancel) { pendingRestoreURL = nil }
        } message: {
            Text("将从选中的本地备份合并提醒与历史记录，不会丢弃已删除标记。".localized)
        }
    }

    private func restoreBackup(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let json = String(data: data, encoding: .utf8),
              let items = BackupHelper.importJSON(json) else {
            isError = true
            lastResult = "备份文件解析失败".localized
            return
        }
        let deleted = BackupHelper.deletionIDs(json)
        do {
            let merged = try ReminderMerge.apply(
                items,
                current: reminders,
                context: modelContext,
                deletedReminders: deleted.reminders,
                deletedRecords: deleted.records
            )
            SyncStore.touchLocalChange()
            Task { await ReminderEngine.shared.ensureRetryChains() }
            isError = false
            lastResult = Localized("已恢复备份，共 %d 条提醒", merged.count)
        } catch {
            isError = true
            lastResult = Localized("恢复失败：%@", error.localizedDescription)
        }
    }
}
