import SwiftUI
import SwiftData
import UIKit

/// WebDAV 同步设置（漫风印张化，保留全部冲突确认对话框与日历订阅直链能力）
struct SyncSettingsView: View {
    @State private var showSyncConflict = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.comic) private var comic
    @Query private var reminders: [Reminder]

    @State private var url = SyncStore.url
    @State private var username = SyncStore.username
    @State private var password = SyncStore.password
    @State private var autoSync = SyncStore.autoSync
    @State private var syncing = false
    @State private var testing = false
    @State private var resultMsg: String?
    @State private var isError = false

    @State private var icsBusy = false
    @State private var icsResult: WebDavSync.ICSUploadResult?
    @State private var icsCopied = false
    @State private var icsAlertPresented = false

    private var credentialsIncomplete: Bool {
        url.trimmingCharacters(in: .whitespaces).isEmpty || username.isEmpty || password.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ComicCard(cut: ThemeTokens.cardCut, padding: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("WebDAV 服务器".localized)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(comic.ink)

                        Text("通过 WebDAV 同步提醒数据（支持自建服务、坚果云等），以最后修改时间为准。".localized)
                            .font(.system(size: 12.5, weight: .regular, design: .rounded))
                            .foregroundStyle(comic.muted)

                        TextField("WebDAV 地址".localized, text: $url)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(comic.ink)

                        ComicHairline(outer: false)

                        TextField("用户名".localized, text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(comic.ink)

                        ComicHairline(outer: false)

                        SecureField("密码", text: $password)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(comic.ink)

                        ComicHairline(outer: false)

                        Toggle("启动时自动同步".localized, isOn: $autoSync)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(comic.ink)
                            .tint(comic.accent)

                        if SyncStore.lastSyncAt > 0 {
                            Text(Localized("上次同步：%@", formatted(SyncStore.lastSyncAt)))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(comic.muted)
                        }

                        HStack(spacing: 12) {
                            Button {
                                testConnection()
                            } label: {
                                if testing { ProgressView().controlSize(.small) }
                                Text("测试连接".localized)
                            }
                            .buttonStyle(ComicButtonStyle(variant: .surface, expand: true))
                            .disabled(testing || credentialsIncomplete)

                            Button {
                                saveAndSync()
                            } label: {
                                if syncing { ProgressView().controlSize(.small) }
                                Text("保存并立即同步".localized)
                            }
                            .buttonStyle(ComicButtonStyle(variant: .accent, expand: true))
                            .disabled(syncing || credentialsIncomplete)
                        }

                        if let resultMsg {
                            Text(resultMsg.localized)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(isError ? comic.danger : comic.ok)
                        }
                    }
                }

                ComicCard(cut: ThemeTokens.cardCut, padding: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("日历订阅".localized)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(comic.ink)

                        Text("将全部提醒导出为 .ics 上传到 WebDAV 目录，在网盘网页端创建分享链接后即可填入系统日历订阅。".localized)
                            .font(.system(size: 12.5, weight: .regular, design: .rounded))
                            .foregroundStyle(comic.muted)

                        Button {
                            generateSubscriptionLink()
                        } label: {
                            if icsBusy { ProgressView().controlSize(.small) }
                            Label("生成日历订阅链接".localized, systemImage: "calendar.badge.plus")
                        }
                        .buttonStyle(ComicButtonStyle(variant: .surface, expand: true))
                        .disabled(icsBusy || credentialsIncomplete)
                    }
                }
            }
            .padding(ThemeTokens.gutter)
        }
        .background(ComicCanvas())
        .confirmationDialog("两边都有修改，已停止同步。选择前会保存本地快照；双端升级后可同步删除。", isPresented: $showSyncConflict) {
            Button("使用本地并上传".localized) { resolveSync(.local) }
            Button("使用远程并保留本机独有提醒".localized) { resolveSync(.remote) }
            Button("取消".localized, role: .cancel) {}
        }
        .navigationTitle("同步设置".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(comic.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .alert("日历订阅链接".localized, isPresented: $icsAlertPresented) {
            if case .success(let link, _) = icsResult {
                Button("复制链接".localized) {
                    UIPasteboard.general.string = link
                    icsCopied = true
                }
            }
            Button("好".localized, role: .cancel) { icsCopied = false }
        } message: {
            switch icsResult {
            case .success(let link, let count):
                Text(Localized("已上传 %d 条提醒的日历文件。\n\n直链：%@", count, link))
            case .failure(let msg):
                Text(msg)
            case .none:
                Text("")
            }
        }
    }

    private func resolveSync(_ choice: WebDavSync.ConflictChoice) {
        Task {
            switch await WebDavSync.resolve(choice, context: modelContext) {
            case .success:
                isError = false
                resultMsg = "同步完成；本机独有提醒已保留。双端升级后支持删除同步。"
            case .conflict:
                showSyncConflict = true
            case .failure(let message):
                isError = true
                resultMsg = message
            }
        }
    }

    private func testConnection() {
        testing = true; resultMsg = nil
        Task {
            let result = await WebDavSync.testConnection(url: url, username: username, password: password)
            testing = false
            switch result {
            case .success:
                isError = false
                resultMsg = "连接成功 ✓ 账号与路径可用，点「保存并立即同步」开始同步。"
            case .conflict:
                showSyncConflict = true
            case .failure(let msg):
                isError = true
                resultMsg = msg
            }
        }
    }

    private func saveAndSync() {
        SyncStore.save(url: url, username: username, password: password, autoSync: autoSync)
        syncing = true; resultMsg = nil
        Task {
            let result = await WebDavSync.syncNow(reminders: reminders, modelContext: modelContext)
            syncing = false
            switch result {
            case .success(let conflict):
                isError = false
                resultMsg = conflict ? "已用最新版本覆盖（检测到双端都有修改，未合并）" : "同步完成"
            case .conflict:
                showSyncConflict = true
            case .failure(let msg):
                isError = true
                resultMsg = msg
            }
        }
    }

    private func generateSubscriptionLink() {
        icsBusy = true; icsResult = nil
        Task {
            icsResult = await WebDavSync.uploadICS(reminders: reminders)
            icsBusy = false
            icsAlertPresented = true
        }
    }

    private func formatted(_ ts: TimeInterval) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "yyyy-MM-dd HH:mm"
        return df.string(from: Date(timeIntervalSince1970: ts))
    }
}
