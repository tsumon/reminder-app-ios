import SwiftUI

/// 批次2 功能2: 正向反馈 —— 打卡成功卡片
///
/// 确认提醒后从顶部滑入「🎉 打卡成功 · 连续 N 天」，约 2 秒后自动淡出。
/// 用法：`CheckInFeedbackBanner(text: checkInText)`，text 非空即展示。
struct CheckInFeedbackBanner: View {
    let text: String?

    @State private var visible = false

    var body: some View {
        VStack {
            if visible {
                VStack(spacing: 4) {
                    Text("🎉")
                        .font(.system(size: 26))
                    Text(text ?? "")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color.green.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.85).combined(with: .opacity),
                    removal: .opacity
                ))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false) // 不拦截点击，纯展示
        .onChange(of: text) { _, newValue in
            guard newValue != nil else {
                visible = false
                return
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                visible = true
            }
            Task {
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                withAnimation(.easeOut(duration: 0.3)) {
                    visible = false
                }
            }
        }
    }
}

#Preview {
    CheckInFeedbackBanner(text: "打卡成功，已连续 3 天 🎉")
        .padding()
}
