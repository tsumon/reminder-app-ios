import SwiftUI
import SwiftData
import UIKit

/// WebDAV 同步设置
struct SyncSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var reminders: [Reminder]

    @State private var url = SyncStore.url
    @State private var username = SyncStore.username
    @State private var password = SyncStore.password
    @State private var autoSync = SyncStore.autoSync
    @State private var syncing = false
    @State private var testing = false
    @State private var resultMsg: String?
    @State private var isError = false

    // 批次3 功能4: 日历订阅链接
    @State private var icsBusy = false
    @State private var icsResult: WebDavSync.ICSUploadResult?
    @State private var icsCopied = false

    var body: some View {
        Form {
            Section {
                Text("通过 WebDAV 同步提醒数据（支持甲骨文 VPS 自建、坚果云等）。同步以最后修改时间为准，较新的覆盖较旧的。".localized)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("服务器".localized) {
                TextField("WebDAV 地址".localized, text: $url)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("用户名".localized, text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("密码", text: $password)
            }

            Section {
                Toggle("启动时自动同步".localized, isOn: $autoSync)
            } footer: {
                if SyncStore.lastSyncAt > 0 {
                    Text(Localized("上次同步：%@", formatted(SyncStore.lastSyncAt)))
                }
            }

            Section {
                // v1.9.1: 测试连接（先验证账号/路径，再同步）
                Button {
                    testConnection()
                } label: {
                    if testing {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else {
                        Text("测试连接".localized)
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(testing || url.trimmingCharacters(in: .whitespaces).isEmpty || username.isEmpty || password.isEmpty)

                Button {
                    saveAndSync()
                } label: {
                    if syncing {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else {
                        Text("保存并立即同步".localized)
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(syncing || url.trimmingCharacters(in: .whitespaces).isEmpty || username.isEmpty || password.isEmpty)
            }

            // 批次3 功能4: 系统日历订阅链接（.ics 上传 WebDAV，返回可订阅直链）
            Section("日历订阅".localized) {
                Text("把全部提醒导出为 .ics 日历文件上传到 WebDAV 目录。系统日历不能直接订阅带账号密码的地址——需在网盘网页端对该文件「创建分享链接」，再把分享直链填进日历订阅。".localized)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    generateSubscriptionLink()
                } label: {
                    if icsBusy {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else {
                        Label("生成日历订阅链接".localized, systemImage: "calendar.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(icsBusy || url.trimmingCharacters(in: .whitespaces).isEmpty || username.isEmpty || password.isEmpty)
            }

            if let resultMsg {
                Section {
                    Text(resultMsg.localized)
                        .foregroundStyle(isError ? Color.red : Color.green)
                }
            }
        }
        .navigationTitle("同步设置".localized)
        .navigationBarTitleDisplayMode(.inline)
        .alert("日历订阅链接".localized, isPresented: $icsAlertPresented) {
            if case .success(let url, _) = icsResult {
                Button("复制链接".localized) {
                    UIPasteboard.general.string = url
                    icsCopied = true
                }
            }
            Button("好".localized, role: .cancel) { icsCopied = false }
        } message: {
            switch icsResult {
            case .success(let url, let count):
                Text(Localized("已上传 %d 条提醒的日历文件。网盘网页端对该文件「创建分享链接」，再把分享直链填进系统日历的「订阅」即可。\n\n直链：%@", count, url))
            case .failure(let msg):
                Text(msg)
            case .none:
                Text("")
            }
        }
    }

    @State private var icsAlertPresented = false

    /// 测试连接：用当前输入验证（不持久化——避免手滑填错覆盖已有好配置），通过后再「保存并立即同步」
    private func testConnection() {
        testing = true
        resultMsg = nil

        Task {
            let result = await WebDavSync.testConnection(
                url: url,
                username: username,
                password: password
            )
            testing = false
            switch result {
            case .success:
                isError = false
                resultMsg = "连接成功 ✓ 账号与路径可用，点「保存并立即同步」开始同步。"
            case .failure(let msg):
                isError = true
                resultMsg = msg
            }
        }
    }

    private func saveAndSync() {
        SyncStore.save(url: url, username: username, password: password, autoSync: autoSync)
        syncing = true
        resultMsg = nil

        Task {
            let result = await WebDavSync.syncNow(reminders: reminders, modelContext: modelContext)
            syncing = false
            switch result {
            case .success(let conflict):
                isError = false
                // v2.0.16: 双端都改过 → 提示已按版本覆盖
                resultMsg = conflict ? "已用最新版本覆盖（检测到双端都有修改，未合并）" : "同步完成"
            case .failure(let msg):
                isError = true
                resultMsg = msg
            }
        }
    }

    // 批次3 功能4: 生成日历订阅链接
    private func generateSubscriptionLink() {
        icsBusy = true
        icsResult = nil
        Task {
            let result = await WebDavSync.uploadICS(reminders: reminders)
            icsBusy = false
            icsResult = result
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

#Preview {
    NavigationStack {
        SyncSettingsView()
            .modelContainer(for: [Reminder.self, ReminderRecord.self])
    }
}
