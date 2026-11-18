import SwiftUI
import SwiftData

/// AI 对话页（极简奶油漫风分镜卡 + 自动滚底 + 隐藏底栏）
struct AIChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.comic) private var comic
    @StateObject private var settings = AISettings.shared
    @StateObject private var voice = VoiceRecognizer.shared
    @StateObject private var vm = AIChatViewModel()

    @State private var historyScrollTrigger = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if vm.messages.isEmpty {
                            welcomeView
                        }

                        ForEach(vm.messages) { msg in
                            ComicChatBubble(message: msg) { option in
                                vm.sendOption(option, from: msg, settings: settings, context: modelContext)
                            }
                            .id(msg.id)
                        }

                        if vm.isLoading {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .tint(comic.accent)
                                Text("正在思考…".localized)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(comic.muted)
                            }
                            .padding(.vertical, 8)
                        }

                        if let err = vm.errorMessage {
                            Text(err)
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(comic.danger)
                                .padding(.horizontal, 12)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("chat-bottom-sentinel")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .onAppear {
                        scrollToLatest(proxy: proxy)
                    }
                }
                .onChange(of: vm.messages.count) { _, _ in
                    if let last = vm.messages.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
                .onChange(of: historyScrollTrigger) { _, _ in
                    if let first = vm.messages.first?.id {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(first, anchor: .top) }
                    }
                }
                .onChange(of: vm.isLoading) { _, _ in
                    if let last = vm.messages.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
            .background(ComicCanvas())

            inputBar
        }
        .navigationTitle("AI 助手".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(comic.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        historyScrollTrigger += 1
                    } label: {
                        Label(String(format: "查看历史（%d 条）".localized, vm.messages.count), systemImage: "clock.arrow.circlepath")
                    }
                    .disabled(vm.messages.isEmpty)

                    Button(role: .destructive) {
                        vm.clearHistory()
                    } label: {
                        Label("清空历史".localized, systemImage: "trash")
                    }
                    .disabled(vm.messages.isEmpty)
                    .accessibilityIdentifier("clear-history")
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(comic.ink)
                }
                .accessibilityIdentifier("history-menu")
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    vm.sendWeeklyInsight(settings: settings, context: modelContext)
                } label: {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(comic.ink)
                }
                .accessibilityLabel("本周洞察")
                .accessibilityIdentifier("weekly-insight")
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    AISettingsView()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(comic.ink)
                }
                .accessibilityIdentifier("ai-settings-entry")
            }
        }
        .onAppear {
            vm.syncOnAppear(isConfigured: settings.isConfigured)
        }
        .sheet(item: $vm.importPreview) { preview in
            importPreviewSheet(preview)
        }
        .hidesSoftTabDock()
    }

    private func scrollToLatest(proxy: ScrollViewProxy) {
        if let last = vm.messages.last?.id {
            proxy.scrollTo(last, anchor: .bottom)
        }
        Task { @MainActor in
            for delayNs: UInt64 in [80_000_000, 220_000_000, 450_000_000] {
                try? await Task.sleep(nanoseconds: delayNs)
                if let last = vm.messages.last?.id {
                    proxy.scrollTo(last, anchor: .bottom)
                }
                proxy.scrollTo("chat-bottom-sentinel", anchor: .bottom)
            }
        }
    }

    private var welcomeView: some View {
        ComicCard(cut: ThemeTokens.cardCut, padding: 20) {
            VStack(alignment: .leading, spacing: 8) {
                ComicBrandTitle(text: "跟我说你想提醒什么".localized, size: 18, showShard: true)
                Text("「每天8点提醒我吃药」 · 「每年提醒我妈生日」 · 「每周一早上开会」".localized)
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .foregroundStyle(comic.muted)
            }
        }
        .padding(.top, 16)
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            ComicHairline(outer: true)

            if voice.isRecording {
                HStack(spacing: 8) {
                    Image(systemName: "waveform").foregroundStyle(comic.danger)
                    Text(voice.transcribedText.isEmpty ? "正在聆听..." : voice.transcribedText)
                        .font(.system(size: 13.5, weight: .medium, design: .rounded))
                        .foregroundStyle(comic.ink)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(comic.surface)
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button { toggleVoice() } label: {
                    Image(systemName: voice.isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(voice.isRecording ? comic.danger : comic.muted)
                        .frame(width: 36, height: 38)
                }
                .buttonStyle(.plain)
                .disabled(vm.isLoading)

                TextField("输入或点击麦克风说话...".localized, text: $vm.inputText, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.system(size: 14.5, weight: .medium, design: .rounded))
                    .foregroundStyle(comic.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background {
                        ChamferShape(cut: 6).fill(comic.surface)
                        ChamferShape(cut: 6).stroke(comic.border, lineWidth: 1.3)
                    }
                    .disabled(vm.isLoading)
                    .accessibilityIdentifier("ai-input")

                Button {
                    vm.sendMessage(settings: settings, context: modelContext)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .heavy))
                }
                .buttonStyle(ComicButtonStyle(variant: .accent, horizontalPadding: 11, verticalPadding: 9))
                .disabled(vm.inputText.trimmingCharacters(in: .whitespaces).isEmpty || vm.isLoading)
                .accessibilityLabel("发送".localized)
                .accessibilityIdentifier("send-button")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(comic.canvas)
        }
    }

    private func toggleVoice() {
        if voice.isRecording {
            voice.stopRecording()
            if !voice.transcribedText.isEmpty {
                vm.inputText = voice.transcribedText
                vm.sendMessage(settings: settings, context: modelContext)
            }
        } else {
            Task {
                if await voice.requestAuthorization() {
                    do { try voice.startRecording() } catch { vm.errorMessage = error.localizedDescription }
                } else {
                    vm.errorMessage = "请在系统设置中允许语音识别权限"
                }
            }
        }
    }

    private func importPreviewSheet(_ preview: ImportPreview) -> some View {
        NavigationStack {
            ScrollView {
                ComicCard {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(preview.items.enumerated()), id: \.offset) { _, item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(comic.ink)
                                Text(AIChatToolExecutor.describeReminder(item))
                                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(comic.muted)
                            }
                        }
                    }
                }
                .padding(ThemeTokens.gutter)
            }
            .background(ComicCanvas())
            .navigationTitle("批量创建预览".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消".localized) { vm.importPreview = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认创建".localized) { vm.confirmBatchImport(preview.items, context: modelContext) }
                        .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
