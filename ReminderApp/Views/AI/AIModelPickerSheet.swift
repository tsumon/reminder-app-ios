import SwiftUI

struct AIModelPickerState: Identifiable {
    let id = UUID()
    let models: [String]
    let isFallback: Bool
}

/// AI 模型列表搜索弹窗与快捷服务商模板卡片
struct AIModelPickerSheet: View {
    let picker: AIModelPickerState
    @Binding var searchText: String
    let currentSelected: String
    var onSelect: (String) -> Void
    var onCancel: () -> Void

    @Environment(\.comic) private var comic

    private var filtered: [String] {
        picker.models.filter { name in
            searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(comic.muted)
                    TextField("搜索模型".localized, text: $searchText)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(.system(size: 14.5, weight: .medium, design: .rounded))
                        .foregroundStyle(comic.ink)
                        .accessibilityIdentifier("model-search")
                }
                .padding(.horizontal, ThemeTokens.gutter)
                .padding(.vertical, 10)

                ComicHairline(outer: true)

                ScrollView {
                    ComicCard(cut: ThemeTokens.cardCut, padding: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(filtered, id: \.self) { name in
                                Button {
                                    onSelect(name)
                                } label: {
                                    HStack {
                                        Text(name)
                                            .font(.system(size: 14.5, weight: .bold, design: .rounded))
                                            .foregroundStyle(comic.ink)
                                        Spacer()
                                        if currentSelected == name {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 13, weight: .heavy))
                                                .foregroundStyle(comic.accent)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("model-choice-\(name)")
                            }
                        }
                    }
                    .padding(ThemeTokens.gutter)
                }
            }
            .background(ComicCanvas())
            .navigationTitle("选择模型".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消".localized, action: onCancel)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// AI 服务商快捷预设与免费额度卡片
struct AITemplatesAndGuideSection: View {
    var onApplyTemplate: (String, String) -> Void

    @Environment(\.comic) private var comic

    private let providerTemplates = [
        (name: "OpenAI", endpoint: "https://api.openai.com/v1", model: "gpt-4o-mini"),
        (name: "DeepSeek", endpoint: "https://api.deepseek.com/v1", model: "deepseek-chat"),
        (name: "通义千问", endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-plus"),
        (name: "豆包（火山引擎）", endpoint: "https://ark.cn-beijing.volces.com/api/v3", model: "doubao-lite-32k"),
        (name: "智谱 GLM", endpoint: "https://open.bigmodel.cn/api/paas/v4", model: "glm-4-flash"),
        (name: "Moonshot", endpoint: "https://api.moonshot.cn/v1", model: "moonshot-v1-8k")
    ]

    var body: some View {
        ComicCard(cut: ThemeTokens.cardCut, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("快速模板".localized)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(comic.ink)

                ForEach(providerTemplates, id: \.name) { tpl in
                    Button {
                        onApplyTemplate(tpl.endpoint, tpl.model)
                    } label: {
                        HStack {
                            Text(tpl.name)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(comic.ink)
                            Spacer()
                            Text(tpl.model)
                                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                .foregroundStyle(comic.muted)
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                ComicHairline(outer: false)

                Text("免费获取 API Key".localized)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(comic.ink)

                ForEach(ExternalAppService.Provider.allCases) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(p.name)
                                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                                .foregroundStyle(comic.ink)
                            Spacer()
                            Button("获取 API Key →".localized) {
                                UIApplication.shared.open(p.apiKeyURL)
                            }
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundStyle(comic.hero)
                            .buttonStyle(.plain)
                        }
                        Text(p.freeTierInfo)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(comic.muted)
                    }
                }
            }
        }
    }
}
