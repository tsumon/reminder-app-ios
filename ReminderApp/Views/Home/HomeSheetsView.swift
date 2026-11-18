import SwiftUI
import UniformTypeIdentifiers

/// 导入/导出用的 JSON / ICS 文件文档
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

/// 当日任务弹窗（漫风化）
struct DayTasksSheet: View {
    let day: Date
    let reminders: [Reminder]
    @Environment(\.comic) private var comic

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
            ScrollView {
                VStack(spacing: 14) {
                    if dateReminders.isEmpty {
                        Text("这一天没有提醒".localized)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(comic.muted)
                            .padding(.top, 48)
                    } else {
                        ComicCard {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(dateReminders) { r in
                                    NavigationLink {
                                        ReminderDetailView(reminder: r)
                                    } label: {
                                        HStack {
                                            Text(r.title)
                                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                                .foregroundStyle(comic.ink)
                                            Spacer()
                                            Text(r.dateDisplayText)
                                                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                                .foregroundStyle(comic.muted)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(ThemeTokens.gutter)
            }
            .background(ComicCanvas())
            .navigationTitle(dayTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var dayTitle: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: day) + " 的任务"
    }
}

/// 在线升级下载结果弹窗（漫风化）
struct DownloadedIpaSheet: View {
    let downloadedIpaURL: URL?
    let downloadError: String?
    var onClose: () -> Void

    @Environment(\.comic) private var comic

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let ipaURL = downloadedIpaURL {
                        ComicCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("下载完成".localized)
                                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                                    .foregroundStyle(comic.ink)
                                Text(Localized("已保存到「文件」App：\n我的 iPhone → 循环提醒 → %@", ipaURL.lastPathComponent))
                                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(comic.muted)

                                ShareLink(item: ipaURL) {
                                    Label("分享 ipa 给签名工具".localized, systemImage: "square.and.arrow.up")
                                }
                                .buttonStyle(ComicButtonStyle(variant: .accent, expand: true))

                                Button {
                                    if let dir = try? UpdateService.downloadsDirectory() {
                                        UIApplication.shared.open(dir)
                                    }
                                } label: {
                                    Label("在文件 App 中查看".localized, systemImage: "folder")
                                }
                                .buttonStyle(ComicButtonStyle(variant: .surface, expand: true))

                                Text("iOS 不提供直接安装器，请通过 AltStore / 爱思助手 / Sideloadly 签名安装。".localized)
                                    .font(.system(size: 12, weight: .regular, design: .rounded))
                                    .foregroundStyle(comic.muted)
                            }
                        }
                    } else if let err = downloadError {
                        ComicCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("下载失败".localized)
                                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                                    .foregroundStyle(comic.danger)
                                Text(err)
                                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(comic.muted)
                            }
                        }
                    }
                }
                .padding(ThemeTokens.gutter)
            }
            .background(ComicCanvas())
            .navigationTitle("在线升级".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("好".localized, action: onClose)
                }
            }
        }
        .presentationDetents([.height(480)])
    }
}

/// 分享卡片 JSON 粘贴导入弹窗（漫风化）
struct CardImportSheet: View {
    @Binding var text: String
    let message: String?
    var onCancel: () -> Void
    var onImport: () -> Void

    @Environment(\.comic) private var comic

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ComicCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("粘贴分享卡片".localized)
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundStyle(comic.ink)
                            TextEditor(text: $text)
                                .scrollContentBackground(.hidden)
                                .font(.system(size: 13.5, design: .monospaced))
                                .foregroundStyle(comic.ink)
                                .frame(minHeight: 180)
                        }
                    }
                    if let msg = message {
                        Text(msg)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(msg.hasPrefix("✅") ? comic.ok : comic.danger)
                    }
                }
                .padding(ThemeTokens.gutter)
            }
            .background(ComicCanvas())
            .navigationTitle("导入分享卡片".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消".localized, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入".localized, action: onImport)
                        .fontWeight(.bold)
                }
            }
        }
    }
}
