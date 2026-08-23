import SwiftUI

/// 批次2 功能2: 正向反馈 —— 打卡成功卡片
///
/// 确认提醒后从顶部滑入「🦊 打卡成功 · 连续 N 天 · +1 ⭐」，约 2 秒后自动淡出。
/// v2.5.0: 粘土拟态庆祝卡（吉祥物庆祝表情 + 星星奖励），全屏彩带由首页
/// ReminderListView 的 ConfettiBurst overlay 负责（同一 checkInToken 触发）。
/// 用法：`CheckInFeedbackBanner(text: checkInText)`，text 非空即展示。
struct CheckInFeedbackBanner: View {
    let text: String?

    @State private var visible = false
    @State private var pop = false

    var body: some View {
        VStack {
            if visible {
                VStack(spacing: 8) {
                    ZStack(alignment: .topTrailing) {
                        MascotView(mood: .cheer, size: 56)
                        Text("🎉")
                            .font(.system(size: 17))
                            .scaleEffect(pop ? 1.2 : 0.85)
                            .animation(.spring(response: 0.4, dampingFraction: 0.5).repeatForever(autoreverses: true), value: pop)
                            .offset(x: 8, y: -2)
                    }

                    Text(text ?? "")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Playful.ink)

                    Text("+1 ⭐")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Playful.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Playful.gold.opacity(0.35)))
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 16)
                .clayCard(radius: 22)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.7).combined(with: .opacity),
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
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                visible = true
            }
            pop = false
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                pop = true
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
