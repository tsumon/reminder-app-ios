import SwiftUI
import SwiftData
import Network

/// 局域网近场互传（彻底移除旧紫色与毛玻璃，统一极简奶油漫风）
struct NearbyShareView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.comic) private var comic
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
    @State private var shareJSON = ""

    enum Mode: String, CaseIterable, Identifiable {
        case send = "发送"
        case receive = "接收"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 20) {
                    ForEach(Mode.allCases) { m in
                        let active = mode == m
                        Button {
                            mode = m
                        } label: {
                            VStack(spacing: 3) {
                                Text(m.rawValue.localized)
                                    .font(.system(size: 15, weight: active ? .heavy : .medium, design: .rounded))
                                    .foregroundStyle(active ? comic.ink : comic.muted)
                                Rectangle()
                                    .fill(active ? comic.accent : Color.clear)
                                    .frame(width: 22, height: 2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, ThemeTokens.gutter)
                .padding(.vertical, 10)

                ComicHairline(outer: true)

                ScrollView {
                    if mode == .send {
                        sendCard
                            .padding(ThemeTokens.gutter)
                    } else {
                        receiveCard
                            .padding(ThemeTokens.gutter)
                    }
                }
            }
            .background(ComicCanvas())
            .navigationTitle("附近传输".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(comic.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成".localized) { dismiss() }
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                        .foregroundStyle(comic.ink)
                }
            }
            .onDisappear { stopServer() }
        }
    }

    // MARK: - 发送面板

    private var sendCard: some View {
        ComicCard(cut: ThemeTokens.cardCut, padding: 20) {
            VStack(spacing: 14) {
                Text("两台设备连接同一 Wi-Fi 后即可互传".localized)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(comic.muted)

                if let ip = NearbyShareService.localIPAddress() {
                    Text("http://\(ip):\(NearbyShareService.portString)")
                        .font(.system(size: 16, weight: .heavy, design: .monospaced))
                        .foregroundStyle(comic.ink)
                        .textSelection(.enabled)

                    if let qr = QRCodeService.generateQRCode(from: "http://\(ip):\(NearbyShareService.portString)\(NearbyShareService.path)") {
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 184, height: 184)
                            .padding(10)
                            .background(Color.white)
                            .overlay(
                                ChamferShape(cut: 8)
                                    .stroke(comic.border, lineWidth: 1.5)
                            )
                    }

                    Text("对方用「扫码接收」扫上方二维码即可自动导入".localized)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(comic.muted)
                } else {
                    Text("无法获取局域网 IP，请确认已连接 Wi-Fi".localized)
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(comic.danger)
                }

                if !serverLog.isEmpty {
                    Text(serverLog)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(serverLogIsError ? comic.danger : comic.ok)
                }

                if listener != nil {
                    Button("停止共享".localized) {
                        stopServer()
                    }
                    .buttonStyle(ComicButtonStyle(variant: .danger, expand: true))
                } else {
                    Button {
                        startServer()
                    } label: {
                        Label(Localized("开始共享当前提醒（%d 条）", reminders.count), systemImage: "paperplane.fill")
                    }
                    .buttonStyle(ComicButtonStyle(variant: .accent, expand: true))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear { shareJSON = BackupHelper.exportJSON(reminders) }
        .onChange(of: reminders) { _, newValue in shareJSON = BackupHelper.exportJSON(newValue) }
    }

    private func startServer() {
        serverLog = ""; serverLogIsError = false
        do {
            listener = try NearbyShareService.startServer(
                jsonProvider: { shareJSON },
                onEvent: { msg, isErr in
                    Task { @MainActor in serverLog = msg; serverLogIsError = isErr }
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

    // MARK: - 接收面板

    private var receiveCard: some View {
        ComicCard(cut: ThemeTokens.cardCut, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("扫描发送方二维码，或手动输入局域网地址".localized)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(comic.muted)

                Button {
                    showScanner = true
                } label: {
                    Label("扫码接收（扫对方二维码）".localized, systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(ComicButtonStyle(variant: .accent, expand: true))

                ComicHairline(outer: false)

                TextField("192.168.1.100", text: $receiveIP)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(comic.ink)

                if isReceiving {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("正在下载...".localized)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(comic.muted)
                    }
                } else {
                    Button {
                        receive(from: receiveIP)
                    } label: {
                        Label("下载并导入".localized, systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(ComicButtonStyle(variant: .surface, expand: true))
                    .disabled(receiveIP.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if let msg = resultMsg {
                    Text(msg)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(isError ? comic.danger : comic.ok)
                }
            }
        }
        .sheet(isPresented: $showScanner) {
            NavigationStack {
                ZStack {
                    Color.black.ignoresSafeArea()
                    QRScannerView(
                        onScanned: { value in
                            showScanner = false
                            if let url = URL(string: value), let host = url.host {
                                receive(from: host)
                            } else {
                                receive(from: value)
                            }
                        },
                        onError: { msg in
                            showScanner = false; isError = true; resultMsg = msg
                        }
                    )
                    .ignoresSafeArea()

                    ChamferShape(cut: 14)
                        .stroke(Color.white.opacity(0.85), lineWidth: 2.5)
                        .frame(width: 230, height: 230)
                }
                .navigationTitle("扫码接收".localized)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("取消".localized) { showScanner = false }
                    }
                }
            }
        }
    }

    private func receive(from hostInput: String) {
        let host = hostInput.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }
        isReceiving = true; resultMsg = nil; isError = false
        Task {
            let json = await NearbyShareService.fetch(from: host)
            guard let json, let items = BackupHelper.importJSON(json) else {
                isReceiving = false; isError = true
                resultMsg = "下载失败：请确认两台设备在同一 Wi-Fi 且发送方已点「开始共享」。"
                return
            }
            let result = BackupHelper.importItems(items, existing: reminders, into: modelContext, json: json)
            isReceiving = false
            if let err = result.error {
                isError = true; resultMsg = "导入失败：\(err)"
            } else {
                isError = false
                resultMsg = Localized("导入完成：新增 %d 条，跳过重复 %d 条", result.imported, result.skipped)
                Task {
                    for r in result.inserted where r.isEnabled {
                        await ReminderEngine.shared.scheduleAllNotifications(for: r)
                    }
                }
            }
        }
    }
}
