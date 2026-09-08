import SwiftUI

/// AI API 设置页 — 仅 API 模式（免 API 网页跳转模式已移除）
struct AISettingsView: View {
    @StateObject private var settings = AISettings.shared
    @Environment(\.dismiss) private var dismiss

    @State private var endpoint: String = ""
    @State private var apiKey: String = ""
    @State private var model: String = ""
    @State private var showKey = false
    // v2.2.0: 本地模型 + 备用配置
    @State private var isLocal = false
    @State private var fallbackEnabled = false
    @State private var fallbackEndpoint = ""
    @State private var fallbackKey = ""
    @State private var fallbackModel = ""
    @State private var showFallbackKey = false
    @State private var fetchingPrimary = false
    @State private var fetchingFallback = false
    @State private var pingingPrimary = false
    @State private var pingingFallback = false
    @State private var modelPicker: ModelPickerState?
    @State private var modelSearch = ""
    @State private var alertMessage: String?

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
                            .accessibilityIdentifier("ai-endpoint")
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
                            .accessibilityIdentifier("ai-model")
                    }
                    fetchModelsButton(isFallback: false)
                    pingButton(isFallback: false)
                } header: {
                    Text("API 配置".localized)
                } footer: {
                    Text("支持任意兼容 OpenAI 格式的 API。填写 /v1 结尾的 base URL。".localized)
                }

                // v2.2.0: 本地模型（Ollama）——无需 API Key
                Section {
                    Toggle("本地模型（Ollama）".localized, isOn: $isLocal)
                        .tint(ThemeTokens.brandPrimary)
                    if isLocal {
                        Text("本地模型无需 API Key，例如 http://localhost:11434/v1".localized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("本地模型".localized)
                }

                // v2.2.0: 备用模型（主配置失败自动降级）
                Section {
                    Toggle("启用备用模型".localized, isOn: $fallbackEnabled)
                        .tint(ThemeTokens.brandPrimary)
                    if fallbackEnabled {
                        HStack {
                            Text("接口地址".localized)
                                .frame(width: 80, alignment: .leading)
                            TextField("https://api.deepseek.com/v1", text: $fallbackEndpoint)
                                .keyboardType(.URL)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        HStack {
                            Text("API Key")
                                .frame(width: 80, alignment: .leading)
                            HStack {
                                if showFallbackKey {
                                    TextField("sk-...", text: $fallbackKey)
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)
                                } else {
                                    SecureField("sk-...", text: $fallbackKey)
                                }
                                Button {
                                    showFallbackKey.toggle()
                                } label: {
                                    Image(systemName: showFallbackKey ? "eye.slash" : "eye")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        HStack {
                            Text("模型".localized)
                                .frame(width: 80, alignment: .leading)
                            TextField("deepseek-chat", text: $fallbackModel)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        fetchModelsButton(isFallback: true)
                        pingButton(isFallback: true)
                    }
                } header: {
                    Text("备用模型（自动降级）".localized)
                } footer: {
                    Text("主模型不可用（网络错误/超时/5xx）时自动切换到备用模型重试一次".localized)
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
                        // v2.2.0: 保存本地/备用配置
                        settings.isLocal = isLocal
                        settings.fallbackEnabled = fallbackEnabled
                        settings.fallbackEndpoint = fallbackEndpoint
                        settings.fallbackKey = fallbackKey
                        settings.fallbackModel = fallbackModel
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                endpoint = settings.apiEndpoint
                apiKey = settings.apiKey
                model = settings.model
                isLocal = settings.isLocal
                fallbackEnabled = settings.fallbackEnabled
                fallbackEndpoint = settings.fallbackEndpoint
                fallbackKey = settings.fallbackKey
                fallbackModel = settings.fallbackModel
            }
            .sheet(item: $modelPicker) { picker in
                NavigationStack {
                    let filtered = picker.models.filter { name in
                        modelSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || name.localizedCaseInsensitiveContains(modelSearch)
                    }
                    List {
                        Section {
                            TextField("搜索模型".localized, text: $modelSearch)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                                .accessibilityIdentifier("model-search")
                        }
                        ForEach(filtered, id: \.self) { name in
                            Button {
                                if picker.isFallback {
                                    fallbackModel = name
                                } else {
                                    model = name
                                }
                                AIModelsAPI.LastSelected.save(name, isFallback: picker.isFallback)
                                modelPicker = nil
                                modelSearch = ""
                            } label: {
                                HStack {
                                    Text(name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if (picker.isFallback ? fallbackModel : model) == name {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(ThemeTokens.brandPrimary)
                                    }
                                }
                            }
                            .accessibilityIdentifier("model-choice-\(name)")
                        }
                    }
                    .navigationTitle("选择模型".localized)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消".localized) {
                                modelPicker = nil
                                modelSearch = ""
                            }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .alert("提示".localized, isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("好".localized) { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
            .hidesSoftTabDock()
        }
    }

    private struct ModelPickerState: Identifiable {
        let id = UUID()
        let models: [String]
        let isFallback: Bool
    }

    @ViewBuilder
    private func fetchModelsButton(isFallback: Bool) -> some View {
        let loading = isFallback ? fetchingFallback : fetchingPrimary
        Button {
            fetchModelList(
                base: isFallback ? fallbackEndpoint : endpoint,
                key: isFallback ? fallbackKey : apiKey,
                isFallback: isFallback
            )
        } label: {
            HStack(spacing: 8) {
                if loading { ProgressView() }
                Text("获取模型列表".localized)
                Spacer()
            }
        }
        .disabled(loading)
        .accessibilityIdentifier(isFallback ? "fetch-models-fallback" : "fetch-models-primary")
    }

    @ViewBuilder
    private func pingButton(isFallback: Bool) -> some View {
        let loading = isFallback ? pingingFallback : pingingPrimary
        Button {
            pingModels(
                base: isFallback ? fallbackEndpoint : endpoint,
                key: isFallback ? fallbackKey : apiKey,
                isFallback: isFallback
            )
        } label: {
            HStack(spacing: 8) {
                if loading { ProgressView() }
                Text("测连通".localized)
                Spacer()
            }
        }
        .disabled(loading)
        .accessibilityIdentifier(isFallback ? "ping-models-fallback" : "ping-models-primary")
    }

    private func fetchModelList(base: String, key: String, isFallback: Bool) {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            alertMessage = "请先填写接口地址".localized
            return
        }
        if isFallback {
            guard !fetchingFallback else { return }
            fetchingFallback = true
        } else {
            guard !fetchingPrimary else { return }
            fetchingPrimary = true
        }
        Task {
            defer {
                if isFallback { fetchingFallback = false }
                else { fetchingPrimary = false }
            }
            do {
                let ids = try await AIService.shared.fetchModels(base: trimmed, key: key)
                modelSearch = ""
                modelPicker = ModelPickerState(
                    models: AIModelsAPI.LastSelected.ordered(ids, isFallback: isFallback),
                    isFallback: isFallback
                )
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    private func pingModels(base: String, key: String, isFallback: Bool) {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            alertMessage = "请先填写接口地址".localized
            return
        }
        if isFallback {
            guard !pingingFallback else { return }
            pingingFallback = true
        } else {
            guard !pingingPrimary else { return }
            pingingPrimary = true
        }
        Task {
            defer {
                if isFallback { pingingFallback = false }
                else { pingingPrimary = false }
            }
            do {
                let ids = try await AIService.shared.fetchModels(base: trimmed, key: key)
                alertMessage = Localized("连通成功，共 %d 个模型", ids.count)
            } catch {
                alertMessage = error.localizedDescription
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
