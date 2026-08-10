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
    @State private var showScanner = false
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
                Picker("模式".localized, selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue.localized).tag($0) }
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
            .navigationTitle("附近传输".localized)
            .navigationBarTitleDisplayMode(.inline)
            .glassPageBackground()
            .glassNavigationBar()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成".localized) { dismiss() }
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

            Text("两台设备连接同一 Wi-Fi 后即可互传".localized)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let ip = NearbyShareService.localIPAddress() {
                Text("本机地址".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("http://\(ip):\(NearbyShareService.portString)")
                    .font(.title3.monospaced().weight(.semibold))
                    .textSelection(.enabled)

                // 二维码：对方扫码即自动填入地址
                VStack(spacing: 4) {
                    if let qr = QRCodeService.generateQRCode(from: "http://\(ip):\(NearbyShareService.portString)\(NearbyShareService.path)") {
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 190, height: 190)
                            .padding(8)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(.white.opacity(0.6), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                    }
                    Text("对方用「扫码」扫这里，自动开始接收".localized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("无法获取局域网 IP\n请确认已连接 Wi-Fi".localized)
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
                    Button("停止共享".localized, role: .destructive) {
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
                    Label(Localized("开始共享当前提醒（%d 条）", reminders.count), systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)

                Text("对方在「接收」页输入上方地址即可收到全部提醒".localized)
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
            serverLog = Localized("启动失败：%@", error.localizedDescription)
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

            Text("扫发送方二维码，或手动输入地址\n（支持 192.168.1.100 或完整 http://192.168.1.100:47823）".localized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // 扫码主操作
            Button {
                showScanner = true
            } label: {
                Label("扫码接收（扫对方二维码）".localized, systemImage: "qrcode.viewfinder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ThemeTokens.brandPrimary)
            .padding(.horizontal)

            HStack(spacing: 8) {
                Rectangle().fill(.secondary.opacity(0.3)).frame(height: 1)
                Text("或手动输入".localized).font(.caption2).foregroundStyle(.secondary)
                Rectangle().fill(.secondary.opacity(0.3)).frame(height: 1)
            }
            .padding(.horizontal)

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
                    receive(from: receiveIP)
                } label: {
                    Label("下载并导入".localized, systemImage: "arrow.down.circle")
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
        // 扫码 sheet：扫到后自动下载导入
        .sheet(isPresented: $showScanner) {
            NavigationStack {
                ZStack {
                    Color.black.ignoresSafeArea()
                    QRScannerView(
                        onScanned: { value in
                            showScanner = false
                            // 二维码内容是 http://ip:port/reminders.json → 解析后接收
                            if let url = URL(string: value), let host = url.host {
                                receive(from: host)
                            } else {
                                receive(from: value)
                            }
                        },
                        onError: { msg in
                            showScanner = false
                            isError = true
                            resultMsg = msg
                        }
                    )
                    .ignoresSafeArea()

                    VStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.8), lineWidth: 3)
                            .frame(width: 240, height: 240)
                        Text("对准对方的二维码".localized)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.top, 12)
                        Spacer().frame(height: 80)
                    }
                }
                .navigationTitle("扫码接收".localized)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("取消".localized) { showScanner = false }
                    }
                }
            }
            .presentationDetents([.large])
        }
    }

    private func receive(from hostInput: String) {
        let host = hostInput.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }
        isReceiving = true
        resultMsg = nil
        isError = false

        Task {
            let json = await NearbyShareService.fetch(from: host)
            guard let json, let items = BackupHelper.importJSON(json) else {
                isReceiving = false
                isError = true
                resultMsg = "下载失败：请确认两台设备在同一 Wi-Fi、发送方已点「开始共享」、地址正确；如仍失败请检查路由器是否开启客户端隔离，并请发送方在 iOS「设置 → 本应用 → 本地网络」中开启权限"
                return
            }

            let result = BackupHelper.importItems(items, existing: reminders, into: modelContext)
            isReceiving = false
            isError = false
            resultMsg = Localized("导入完成：新增 %d 条，跳过重复 %d 条", result.imported, result.skipped)

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
