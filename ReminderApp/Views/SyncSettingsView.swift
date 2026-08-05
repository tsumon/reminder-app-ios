import SwiftUI
import SwiftData

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
    @State private var resultMsg: String?
    @State private var isError = false

    var body: some View {
        Form {
            Section {
                Text("通过 WebDAV 同步提醒数据（支持甲骨文 VPS 自建、坚果云等）。同步以最后修改时间为准，较新的覆盖较旧的。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("服务器") {
                TextField("WebDAV 地址", text: $url)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("用户名", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("密码", text: $password)
            }

            Section {
                Toggle("启动时自动同步", isOn: $autoSync)
            } footer: {
                if SyncStore.lastSyncAt > 0 {
                    Text("上次同步：\(formatted(SyncStore.lastSyncAt))")
                }
            }

            Section {
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
                        Text("立即同步")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(syncing || url.trimmingCharacters(in: .whitespaces).isEmpty || username.isEmpty)
            }

            if let resultMsg {
                Section {
                    Text(resultMsg)
                        .foregroundStyle(isError ? Color.red : Color.green)
                }
            }
        }
        .navigationTitle("同步设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func saveAndSync() {
        SyncStore.save(url: url, username: username, password: password, autoSync: autoSync)
        syncing = true
        resultMsg = nil

        Task {
            let result = await WebDavSync.syncNow(reminders: reminders, modelContext: modelContext)
            syncing = false
            switch result {
            case .success:
                isError = false
                resultMsg = "同步完成"
            case .failure(let msg):
                isError = true
                resultMsg = msg
            }
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
