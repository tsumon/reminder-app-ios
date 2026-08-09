import SwiftUI

/// AI API 设置页 — 仅 API 模式（免 API 网页跳转模式已移除）
struct AISettingsView: View {
    @StateObject private var settings = AISettings.shared
    @Environment(\.dismiss) private var dismiss

    @State private var endpoint: String = ""
    @State private var apiKey: String = ""
    @State private var model: String = ""
    @State private var showKey = false

    var body: some View {
        NavigationStack {
            Form {
                // ── API 配置 ──
                Section {
                    HStack {
                        Text("接口地址".localized)
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
                        Text("模型".localized)
                            .frame(width: 80, alignment: .leading)
                        TextField("gpt-4o-mini", text: $model)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                } header: {
                    Text("API 配置".localized)
                } footer: {
                    Text("支持任意兼容 OpenAI 格式的 API。填写 /v1 结尾的 base URL。".localized)
                }

                // ── 快速模板 ──
                Section("快速模板".localized) {
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
                                Text("免费额度".localized)
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
                            Button("获取 API Key →".localized) {
                                UIApplication.shared.open(p.apiKeyURL)
                            }
                            .font(.caption.weight(.medium))
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("💰 免费获取 API Key".localized)
                } footer: {
                    Text("以上服务均提供免费额度，注册后即可获取 API Key。获取后粘贴到上方配置即可使用。".localized)
                }

                // ── 说明 ──
                Section("说明".localized) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("语音或文字输入即可管理提醒".localized, systemImage: "mic.fill")
                        Label("说「每天提醒我喝水」自动创建".localized, systemImage: "wand.and.stars")
                        Label("说「确认喝水提醒」即可标记完成".localized, systemImage: "checkmark.circle")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("AI 设置".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存".localized) {
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
