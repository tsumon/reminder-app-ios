import SwiftUI

/// AI 设置页（全漫风印张化，保留全部连通性与模型搜索测试标识）
struct AISettingsView: View {
    @StateObject private var settings = AISettings.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.comic) private var comic

    @State private var endpoint: String = ""
    @State private var apiKey: String = ""
    @State private var model: String = ""
    @State private var showKey = false

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
    @State private var modelPicker: AIModelPickerState?
    @State private var modelSearch = ""
    @State private var alertMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                primaryApiCard
                localAndFallbackCard
                AITemplatesAndGuideSection { ep, m in
                    endpoint = ep
                    model = m
                }
            }
            .padding(.horizontal, ThemeTokens.gutter)
            .padding(.vertical, 14)
        }
        .background(ComicCanvas())
        .navigationTitle("AI 设置".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(comic.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存".localized) { saveSettings() }
                    .buttonStyle(ComicButtonStyle(variant: .accent, horizontalPadding: 12, verticalPadding: 6))
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
            AIModelPickerSheet(
                picker: picker,
                searchText: $modelSearch,
                currentSelected: picker.isFallback ? fallbackModel : model,
                onSelect: { name in
                    if picker.isFallback { fallbackModel = name } else { model = name }
                    AIModelsAPI.LastSelected.save(name, isFallback: picker.isFallback)
                    modelPicker = nil
                    modelSearch = ""
                },
                onCancel: {
                    modelPicker = nil
                    modelSearch = ""
                }
            )
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

    private var primaryApiCard: some View {
        ComicCard(cut: ThemeTokens.cardCut, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("API 配置".localized)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(comic.ink)

                fieldRow(label: "接口地址".localized) {
                    TextField("https://api.openai.com/v1", text: $endpoint)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(comic.ink)
                        .accessibilityIdentifier("ai-endpoint")
                }

                ComicHairline(outer: false)

                fieldRow(label: "API Key") {
                    HStack {
                        if showKey {
                            TextField("sk-...", text: $apiKey)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                        } else {
                            SecureField("sk-...", text: $apiKey)
                        }
                        Button { showKey.toggle() } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .foregroundStyle(comic.muted)
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(comic.ink)
                }

                ComicHairline(outer: false)

                fieldRow(label: "模型".localized) {
                    TextField("gpt-4o-mini", text: $model)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(comic.ink)
                        .accessibilityIdentifier("ai-model")
                }

                ComicHairline(outer: false)

                HStack(spacing: 12) {
                    fetchModelsButton(isFallback: false)
                    pingButton(isFallback: false)
                }

                Text("支持任意兼容 OpenAI 格式的 API，填写 /v1 结尾的 base URL。".localized)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(comic.muted)
            }
        }
    }

    private var localAndFallbackCard: some View {
        ComicCard(cut: ThemeTokens.cardCut, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("本地模型（Ollama）".localized, isOn: $isLocal)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(comic.ink)
                    .tint(comic.accent)

                if isLocal {
                    Text("本地模型无需 API Key，例如 http://localhost:11434/v1".localized)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(comic.muted)
                }

                ComicHairline(outer: false)

                Toggle("启用备用模型".localized, isOn: $fallbackEnabled)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(comic.ink)
                    .tint(comic.accent)

                if fallbackEnabled {
                    fieldRow(label: "接口地址".localized) {
                        TextField("https://api.deepseek.com/v1", text: $fallbackEndpoint)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                    }
                    fieldRow(label: "API Key") {
                        HStack {
                            if showFallbackKey {
                                TextField("sk-...", text: $fallbackKey)
                                    .textInputAutocapitalization(.never)
                                    .disableAutocorrection(true)
                            } else {
                                SecureField("sk-...", text: $fallbackKey)
                            }
                            Button { showFallbackKey.toggle() } label: {
                                Image(systemName: showFallbackKey ? "eye.slash" : "eye")
                                    .foregroundStyle(comic.muted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    fieldRow(label: "模型".localized) {
                        TextField("deepseek-chat", text: $fallbackModel)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                    }
                    HStack(spacing: 12) {
                        fetchModelsButton(isFallback: true)
                        pingButton(isFallback: true)
                    }
                }
            }
        }
    }

    private func fieldRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                .foregroundStyle(comic.muted)
                .frame(width: 76, alignment: .leading)
            content()
        }
    }

    private func fetchModelsButton(isFallback: Bool) -> some View {
        let loading = isFallback ? fetchingFallback : fetchingPrimary
        return Button {
            fetchModelList(
                base: isFallback ? fallbackEndpoint : endpoint,
                key: isFallback ? fallbackKey : apiKey,
                isFallback: isFallback
            )
        } label: {
            HStack(spacing: 6) {
                if loading { ProgressView().controlSize(.small) }
                Text("获取模型列表".localized)
            }
        }
        .buttonStyle(ComicButtonStyle(variant: .surface, expand: true))
        .disabled(loading)
        .accessibilityIdentifier(isFallback ? "fetch-models-fallback" : "fetch-models-primary")
    }

    private func pingButton(isFallback: Bool) -> some View {
        let loading = isFallback ? pingingFallback : pingingPrimary
        return Button {
            pingModels(
                base: isFallback ? fallbackEndpoint : endpoint,
                key: isFallback ? fallbackKey : apiKey,
                isFallback: isFallback
            )
        } label: {
            HStack(spacing: 6) {
                if loading { ProgressView().controlSize(.small) }
                Text("测连通".localized)
            }
        }
        .buttonStyle(ComicButtonStyle(variant: .accent, expand: true))
        .disabled(loading)
        .accessibilityIdentifier(isFallback ? "ping-models-fallback" : "ping-models-primary")
    }

    private func saveSettings() {
        settings.apiEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "https://api.openai.com/v1" : endpoint
        settings.apiKey = apiKey
        settings.model = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "gpt-4o-mini" : model
        settings.isLocal = isLocal
        settings.fallbackEnabled = fallbackEnabled
        settings.fallbackEndpoint = fallbackEndpoint
        settings.fallbackKey = fallbackKey
        settings.fallbackModel = fallbackModel
        dismiss()
    }

    private func fetchModelList(base: String, key: String, isFallback: Bool) {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { alertMessage = "请先填写接口地址".localized; return }
        if isFallback { guard !fetchingFallback else { return }; fetchingFallback = true }
        else { guard !fetchingPrimary else { return }; fetchingPrimary = true }
        Task {
            defer { if isFallback { fetchingFallback = false } else { fetchingPrimary = false } }
            do {
                let ids = try await AIService.shared.fetchModels(base: trimmed, key: key)
                modelSearch = ""
                modelPicker = AIModelPickerState(models: AIModelsAPI.LastSelected.ordered(ids, isFallback: isFallback), isFallback: isFallback)
            } catch { alertMessage = error.localizedDescription }
        }
    }

    private func pingModels(base: String, key: String, isFallback: Bool) {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { alertMessage = "请先填写接口地址".localized; return }
        if isFallback { guard !pingingFallback else { return }; pingingFallback = true }
        else { guard !pingingPrimary else { return }; pingingPrimary = true }
        Task {
            defer { if isFallback { pingingFallback = false } else { pingingPrimary = false } }
            do {
                let ids = try await AIService.shared.fetchModels(base: trimmed, key: key)
                alertMessage = Localized("连通成功，共 %d 个模型", ids.count)
            } catch { alertMessage = error.localizedDescription }
        }
    }
}
