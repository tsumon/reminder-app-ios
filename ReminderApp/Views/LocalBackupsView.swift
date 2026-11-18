import SwiftUI
import SwiftData

/// 本地备份管理（漫风印张化，保留合并恢复与分享导出能力）
struct LocalBackupsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.comic) private var comic
    @Query private var reminders: [Reminder]

    @State private var files: [URL] = []
    @State private var lastResult: String?
    @State private var isError = false
    @State private var pendingRestoreURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ComicCard(cut: ThemeTokens.cardCut, padding: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("本地备份".localized)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(comic.ink)

                        Text("备份保存在：文件 App → 我的 iPhone → 循环提醒 → ReminderBackups（自动保留最近 5 份）。".localized)
                            .font(.system(size: 12.5, weight: .regular, design: .rounded))
                            .foregroundStyle(comic.muted)

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
                        .buttonStyle(ComicButtonStyle(variant: .accent, expand: true))

                        if let lastResult {
                            Text(lastResult)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(isError ? comic.danger : comic.ok)
                        }
                    }
                }

                ComicCard(cut: ThemeTokens.cardCut, padding: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("历史备份文件".localized)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(comic.ink)

                        if files.isEmpty {
                            Text("暂无备份".localized)
                                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                                .foregroundStyle(comic.muted)
                        } else {
                            ForEach(files, id: \.self) { url in
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(url.lastPathComponent)
                                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                                            .monospacedDigit()
                                            .foregroundStyle(comic.ink)
                                            .lineLimit(1)
                                        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                                            Text("\(max(1, size / 1024)) KB")
                                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                                .monospacedDigit()
                                                .foregroundStyle(comic.muted)
                                        }
                                    }
                                    Spacer()
                                    Button("恢复".localized) {
                                        pendingRestoreURL = url
                                    }
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .foregroundStyle(comic.hero)
                                    .buttonStyle(.plain)

                                    ShareLink(item: url) {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(comic.ink)
                                            .frame(width: 30, height: 30)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(ThemeTokens.gutter)
        }
        .background(ComicCanvas())
        .navigationTitle("本地备份".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(comic.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
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
