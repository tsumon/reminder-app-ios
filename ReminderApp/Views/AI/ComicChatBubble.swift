import SwiftUI

/// 轻漫风分镜消息块（用户橘底印深咖字 `#27140B`，助手亮奶油印张 + 单行工具轨迹）
struct ComicChatBubble: View {
    let message: ChatMessage
    var onOption: ((String) -> Void)? = nil

    @Environment(\.comic) private var comic

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user {
                Spacer(minLength: 52)
                userPanel
            } else {
                assistantPanel
                Spacer(minLength: 40)
            }
        }
        .padding(.vertical, 2)
    }

    private var userPanel: some View {
        Text(message.content)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(comic.onAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background {
                ZStack {
                    ChamferShape(cut: 8)
                        .fill(comic.shadow)
                        .offset(x: 1.8, y: 1.8)
                    ChamferShape(cut: 8)
                        .fill(comic.accent)
                    ChamferShape(cut: 8)
                        .stroke(comic.border, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }
            }
    }

    private var assistantPanel: some View {
        ComicCard(cut: 9, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                if !message.toolSteps.isEmpty {
                    ForEach(message.toolSteps) { step in
                        HStack(spacing: 6) {
                            Text("›")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundStyle(comic.accent)
                            Text("\(step.name) · \(step.status == "running" ? "执行中…" : (step.status == "error" ? "失败" : "已完成"))")
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(step.status == "error" ? comic.danger : comic.muted)
                        }
                    }
                }

                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(comic.ink)
                }

                if let opts = message.options, !opts.isEmpty, let onOption {
                    HStack(spacing: 10) {
                        ForEach(opts, id: \.self) { opt in
                            Button(opt) {
                                onOption(opt)
                            }
                            .buttonStyle(ComicButtonStyle(variant: .accent))
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }
}
