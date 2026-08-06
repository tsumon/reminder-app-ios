import SwiftUI
import SwiftData
import Network

/// 近场传输：同一局域网内互传提醒
/// - 发送：启动本地服务，对方在「接收」页输入本机地址即可收到全部提醒
/// - 接收：输入对方 IP → 下载 → 导入（去重/过期重算/重新调度）
struct NearbyShareView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Reminder.title) private var reminders: [Reminder]

    @State private var mode: Mode = .send
    @State private var listener: NWListener?
    @State private var serverLog = ""
    @State private var serverLogIsError = false
    @State private var receiveIP = ""
    @State private var isReceiving = false
    @State private var resultMsg: String?
    @State private var isError = false
    /// 当前提醒的导出 JSON 缓存（@Query 变化时刷新，发送线程只读字符串，
    /// 避免在后台队列直接读 SwiftData 模型，也保证发送的是最新数据）
    @State private var shareJSON = ""

    enum Mode: String, CaseIterable, Identifiable {
        case send = "发送"
        case receive = "接收"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("模式", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                if mode == .send {
                    sendView
                } else {
                    receiveView
                }
            }
            .navigationTitle("附近传输")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onDisappear { stopServer() }
        }
    }

    // MARK: - 发送

    private var sendView: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 44))
                .foregroundStyle(.purple)
                .padding(.top, 24)

            Text("两台设备连接同一 Wi-Fi 后即可互传")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let ip = NearbyShareService.localIPAddress() {
                Text("本机地址")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("http://\(ip):\(NearbyShareService.port)")
                    .font(.title3.monospaced().weight(.semibold))
                    .textSelection(.enabled)
            } else {
                Text("无法获取局域网 IP\n请确认已连接 Wi-Fi")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.red)
            }

            if listener != nil {
                VStack(spacing: 8) {
                    if !serverLog.isEmpty {
                        Text(serverLog)
                            .font(.caption)
                            .foregroundStyle(serverLogIsError ? .red : .green)
                    }
                    Button("停止共享", role: .destructive) {
                        stopServer()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            } else {
                if !serverLog.isEmpty {
                    // 启动失败等错误日志在未运行时也显示（红色）
                    Text(serverLog)
                        .font(.caption)
                        .foregroundStyle(serverLogIsError ? .red : .green)
                }
                Button {
                    startServer()
                } label: {
                    Label("开始共享当前提醒（\(reminders.count) 条）", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)

                Text("对方在「接收」页输入上方地址即可收到全部提醒")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Spacer()
        }
        .padding()
        .onAppear {
            shareJSON = BackupHelper.exportJSON(reminders)
        }
        .onChange(of: reminders) { _, newValue in
            shareJSON = BackupHelper.exportJSON(newValue)
        }
    }

    private func startServer() {
        serverLog = ""
        serverLogIsError = false
        do {
            listener = try NearbyShareService.startServer(
                jsonProvider: {
                    shareJSON
                },
                onEvent: { msg, isErr in
                    Task { @MainActor in
                        serverLog = msg
                        serverLogIsError = isErr
                    }
                }
            )
        } catch {
            serverLog = "启动失败：\(error.localizedDescription)"
            serverLogIsError = true
        }
    }

    private func stopServer() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - 接收

    private var receiveView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.purple)
                .padding(.top, 24)

            Text("输入发送方显示的地址\n（支持 192.168.1.100 或完整 http://192.168.1.100:47823）")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("192.168.1.100", text: $receiveIP)
                .keyboardType(.numbersAndPunctuation)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding(.horizontal)

            if isReceiving {
                ProgressView("正在下载...")
            } else {
                Button {
                    receive()
                } label: {
                    Label("下载并导入", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(receiveIP.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let msg = resultMsg {
                Text(msg)
                    .font(.footnote)
                    .foregroundStyle(isError ? .red : .green)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding()
    }

    private func receive() {
        let host = receiveIP.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }
        isReceiving = true
        resultMsg = nil
        isError = false

        Task {
            let json = await NearbyShareService.fetch(from: host)
            guard let json, let items = BackupHelper.importJSON(json) else {
                isReceiving = false
                isError = true
                resultMsg = "下载失败：请确认两台设备在同一 Wi-Fi、地址正确，且发送方已开始共享"
                return
            }

            let result = BackupHelper.importItems(items, existing: reminders, into: modelContext)
            isReceiving = false
            isError = false
            resultMsg = "导入完成：新增 \(result.imported) 条，跳过重复 \(result.skipped) 条"

            // 重新调度本次导入的提醒通知
            Task {
                for r in result.inserted where r.isEnabled {
                    await ReminderEngine.shared.scheduleAllNotifications(for: r)
                }
            }
        }
    }
}

#Preview {
    NearbyShareView()
        .modelContainer(for: Reminder.self)
}
