import SwiftUI

// MARK: - 液态玻璃样式库（Liquid Glass，手动实现，兼容 iOS 17）
//
// 视觉特征：半透明玻璃材质 + 顶部高光描边 + 大圆角 + 柔和投影，
// 模拟 iOS 26 Liquid Glass 的"漂浮玻璃"质感。所有新 UI 优先复用这些组件，
// 颜色/圆角走 ThemeTokens，不写硬编码。

// MARK: - 页面背景（品牌紫微光 + 玻璃感渐变）

struct GlassBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    ThemeTokens.brandPrimary.opacity(0.10),
                    Color(.systemBackground),
                    ThemeTokens.brandPrimary.opacity(0.06),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // 顶部品牌光晕
            Circle()
                .fill(ThemeTokens.brandPrimary.opacity(0.12))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: 140, y: -260)
                .ignoresSafeArea()
        }
    }
}

extension View {
    /// 页面级玻璃背景
    func glassPageBackground() -> some View {
        self.background(GlassBackground())
    }
}

// MARK: - 玻璃卡片

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 24
    var padding: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.55),
                                .white.opacity(0.12),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: ThemeTokens.brandPrimary.opacity(0.10), radius: 14, y: 6)
    }
}

extension View {
    /// 任意内容玻璃卡片化（背景材质 + 高光描边 + 阴影）
    func glassCard(cornerRadius: CGFloat = 24, padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.55), .white.opacity(0.12)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: ThemeTokens.brandPrimary.opacity(0.10), radius: 14, y: 6)
    }

    /// 玻璃卡片（小号，用于行内/紧凑场景）
    func glassCell(cornerRadius: CGFloat = 18, padding: CGFloat = 12) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.35), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }
}

// MARK: - 玻璃导航栏

struct GlassNavigationBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

extension View {
    /// 导航栏玻璃材质
    func glassNavigationBar() -> some View {
        modifier(GlassNavigationBarModifier())
    }
}

// MARK: - 玻璃按钮

/// 品牌玻璃按钮（渐变主色 + 高光）
struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [ThemeTokens.brandPrimary, ThemeTokens.brandPrimaryDark],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: ThemeTokens.brandPrimary.opacity(0.35), radius: 10, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension View {
    /// 品牌玻璃按钮
    func glassButtonStyle() -> some View {
        self.buttonStyle(GlassButtonStyle())
    }
}

// MARK: - 分组标题

/// 玻璃感分组标题（小写标签 + 副标题）
struct GlassSectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}
