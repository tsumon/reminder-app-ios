import SwiftUI

/// 打卡成功轻漫风印章横幅（顶部滑入，零模糊硬投影，不拦截点击）
struct CheckInFeedbackBanner: View {
    let text: String?

    @Environment(\.comic) private var comic
    @State private var visible = false

    var body: some View {
        VStack {
            if visible, let text {
                HStack(spacing: 10) {
                    ComicShardMark(size: 16)
                    Text(text)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(comic.ink)
                        .lineLimit(2)
                    Text("+1")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(comic.hero)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background {
                    ZStack {
                        ChamferShape(cut: 8)
                            .fill(comic.shadow)
                            .offset(x: 2.0, y: 2.0)
                        ChamferShape(cut: 8)
                            .fill(comic.surface)
                        ChamferShape(cut: 8)
                            .stroke(
                                comic.border,
                                style: StrokeStyle(lineWidth: ThemeTokens.strokeWidth, lineJoin: .round)
                            )
                    }
                }
                .padding(.top, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onChange(of: text) { _, newValue in
            guard newValue != nil else {
                visible = false
                return
            }
            withAnimation(.easeOut(duration: 0.22)) {
                visible = true
            }
            Task {
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                withAnimation(.easeOut(duration: 0.2)) {
                    visible = false
                }
            }
        }
    }
}

#Preview {
    CheckInFeedbackBanner(text: "打卡成功，已连续 3 天")
        .padding()
}
