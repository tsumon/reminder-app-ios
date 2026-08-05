import SwiftUI

/// AI API 设置页 — 支持免 API 模式 + 多厂商
struct AISettingsView: View {
    @StateObject private var settings = AISettings.shared
    @Environment(\.dismiss) private var dismiss

    @State private var endpoint: String = ""
    @State private var apiKey: String = ""
    @State private var model: String = ""
    @State private var showKey = false
    @State private var noAPIProvider: String = "deepseek"
    @State private var useNoAPI: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                // ── 模式开关 ──
                Section {
                    Toggle(isOn: $useNoAPI.animation()) {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(.orange)
                            Text("免 API 模式")
                            Text("无需 Key")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.orange.opacity(0.15))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }
                } header: {
                    Text("模式选择")
                } footer: {
                    if useNoAPI {
                        Text("无需 API Key，输入问题后自动复制并跳转到 AI 网页版粘贴发送。")
                    } else {
                        Text("使用你自己的 API Key 调用 AI，数据不走第三方网页。")
                    }
                }

                // ── 免 API 模式：选择服务商 ──
                if useNoAPI {
                    Section("免 API 服务商") {
                        ForEach(ExternalAppService.Provider.allCases) { p in
                            HStack {
                                Image(systemName: p.icon)
                                    .foregroundStyle(Color(hex: p.color))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name)
                                        .font(.body)
                                    Text(p.webURL.absoluteString)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if noAPIProvider == p.rawValue {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.orange)
                                        .fontWeight(.bold)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { noAPIProvider = p.rawValue }
                        }
                    }

                    Section {
                        Button {
                            if let url = URL(string: "https://chat.deepseek.com/") { UIApplication.shared.open(url) }
                        } label: {
                            Label("打开 DeepSeek 网页版", systemImage: "safari")
                        }
                        Button {
                            if let url = URL(string: "https://tongyi.aliyun.com/qianwen/") { UIApplication.shared.open(url) }
                        } label: {
                            Label("打开通义千问网页版", systemImage: "safari")
                        }
                        Button {
                            if let url = URL(string: "https://www.doubao.com/chat/") { UIApplication.shared.open(url) }
                        } label: {
                            Label("打开豆包网页版", systemImage: "safari")
                        }
                    } header: {
                        Text("快速打开")
                    } footer: {
                        Text("点击即可在 Safari 中打开对应 AI 服务。")
                    }
                }

                // ── API 模式配置 ──
                if !useNoAPI {
                    Section {
                        HStack {
                            Text("接口地址")
                                .frame(width: 80, alignment: .leading)
                            TextField("https://api.openai.com/v1", text: $endpoint)
                                .keyboardType(.URL)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }

                        HStack {
                            Text("API Key")
                                .frame(width: 80, alignment: .leading)
                            HStack {
                                if showKey {
                                    TextField("sk-...", text: $apiKey)
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)
                                } else {
                                    SecureField("sk-...", text: $apiKey)
                                }
                                Button {
                                    showKey.toggle()
                                } label: {
                                    Image(systemName: showKey ? "eye.slash" : "eye")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        HStack {
                            Text("模型")
                                .frame(width: 80, alignment: .leading)
                            TextField("gpt-4o-mini", text: $model)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                    } header: {
                        Text("API 配置")
                    } footer: {
                        Text("支持任意兼容 OpenAI 格式的 API。填写 /v1 结尾的 base URL。")
                    }

                    // ── 快速模板 ──
                    Section("快速模板") {
                        ForEach(providerTemplates, id: \.name) { tpl in
                            Button {
                                endpoint = tpl.endpoint
                                model = tpl.model
                            } label: {
                                HStack {
                                    Text(tpl.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(tpl.model)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    // ── 免费获取 API Key 指引 ──
                    Section {
                        ForEach(ExternalAppService.Provider.allCases) { p in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(p.name)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("免费额度")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.green.opacity(0.15))
                                        .foregroundStyle(.green)
                                        .clipShape(Capsule())
                                }
                                Text(p.freeTierInfo)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button("获取 API Key →") {
                                    UIApplication.shared.open(p.apiKeyURL)
                                }
                                .font(.caption.weight(.medium))
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text("💰 免费获取 API Key")
                    } footer: {
                        Text("以上服务均提供免费额度，注册后即可获取 API Key。获取后粘贴到上方配置即可使用。")
                    }
                }

                // ── 说明（通用） ──
                Section("说明") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("语音或文字输入即可管理提醒", systemImage: "mic.fill")
                        Label("说「每天提醒我喝水」自动创建", systemImage: "wand.and.stars")
                        Label("说「确认喝水提醒」即可标记完成", systemImage: "checkmark.circle")
                        if useNoAPI {
                            Label("输入问题 → 自动跳转网页粘贴发送", systemImage: "arrow.up.forward.square")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("AI 设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        settings.useNoAPIMode = useNoAPI
                        settings.noAPIProvider = noAPIProvider
                        settings.apiEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "https://api.openai.com/v1" : endpoint
                        settings.apiKey = apiKey
                        settings.model = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "gpt-4o-mini" : model
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                endpoint = settings.apiEndpoint
                apiKey = settings.apiKey
                model = settings.model
                useNoAPI = settings.useNoAPIMode
                noAPIProvider = settings.noAPIProvider
            }
        }
    }

    // MARK: - Quick templates

    private let providerTemplates = [
        (name: "OpenAI",        endpoint: "https://api.openai.com/v1",       model: "gpt-4o-mini"),
        (name: "DeepSeek",      endpoint: "https://api.deepseek.com/v1",     model: "deepseek-chat"),
        (name: "通义千问",      endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-plus"),
        (name: "豆包（火山引擎）", endpoint: "https://ark.cn-beijing.volces.com/api/v3", model: "doubao-lite-32k"),
        (name: "智谱 GLM",      endpoint: "https://open.bigmodel.cn/api/paas/v4", model: "glm-4-flash"),
        (name: "Moonshot",      endpoint: "https://api.moonshot.cn/v1",      model: "moonshot-v1-8k"),
    ]
}

// MARK: - Hex Color Helper

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}
