import SwiftUI
import SwiftData

/// v2.1.1: 本地备份管理——自签环境没有 iCloud，备份到「文件」App 可见目录，
/// 可随时手动备份、查看/分享历史备份文件（保留最近 5 份）。
struct LocalBackupsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var reminders: [Reminder]

    @State private var files: [URL] = []
    @State private var lastResult: String?

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
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent)
                                .font(.subheadline)
                            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                                Text("\(size / 1024) KB".localized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }

            Section {
                Button {
                    if let url = LocalBackupService.backupNow(reminders: reminders) {
                        files = LocalBackupService.backups
                        lastResult = "已备份：\(url.lastPathComponent)".localized
                    } else {
                        lastResult = "备份失败".localized
                    }
                } label: {
                    Label("立即备份".localized, systemImage: "externaldrive.badge.plus")
                }
            } footer: {
                if let lastResult {
                    Text(lastResult)
                        .foregroundStyle(ThemeTokens.statusCompleted)
                }
            }
        }
        .navigationTitle("本地备份".localized)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            files = LocalBackupService.backups
        }
    }
}
