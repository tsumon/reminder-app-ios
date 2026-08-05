import SwiftUI

/// AI API 设置页
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
                Section("API 配置") {
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
                    Text("支持任意兼容 OpenAI 格式的 API（如 DeepSeek、通义千问、智谱等）。填写 /v1 结尾的 base URL。")
                }

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

                Section("说明") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("语音或文字输入即可管理提醒", systemImage: "mic.fill")
                        Label("说「每天提醒我喝水」自动创建", systemImage: "wand.and.stars")
                        Label("说「确认喝水提醒」即可标记完成", systemImage: "checkmark.circle")
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
        (name: "智谱 GLM",      endpoint: "https://open.bigmodel.cn/api/paas/v4", model: "glm-4-flash"),
        (name: "Moonshot",      endpoint: "https://api.moonshot.cn/v1",      model: "moonshot-v1-8k"),
    ]
}
