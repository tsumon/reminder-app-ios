import SwiftUI

/// 批次2 功能2: 正向反馈 —— 打卡成功卡片
///
/// 确认提醒后从顶部滑入「🦊 打卡成功 · 连续 N 天 · +1 ⭐」，约 2 秒后自动淡出。
/// v2.5.0: 粘土拟态庆祝卡（吉祥物庆祝表情 + 星星奖励），全屏彩带由首页
/// ReminderListView 的 ConfettiBurst overlay 负责（同一 checkInToken 触发）。
/// 用法：`CheckInFeedbackBanner(text: checkInText)`，text 非空即展示。
struct CheckInFeedbackBanner: View {
    let text: String?

    @Environment(\.soft) private var soft
    @State private var visible = false
    @State private var pop = false

    var body: some View {
        VStack {
            if visible {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(ThemeTokens.strong.opacity(soft.isDark ? 0.22 : 0.14))
                            .frame(width: 44, height: 44)
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(ThemeTokens.strong)
                            .scaleEffect(pop ? 1.08 : 0.92)
                            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: pop)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(text ?? "")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(soft.text)
                            .lineLimit(2)

                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.caption2.weight(.bold))
                            Text("+1".localized)
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(ThemeTokens.strong)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(soft.elevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(soft.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(soft.isDark ? 0.35 : 0.10), radius: 14, y: 6)
                .padding(.top, 12)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))
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
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                visible = true
            }
            pop = false
            withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) {
                pop = true
            }
            Task {
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                withAnimation(.easeOut(duration: 0.25)) {
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
