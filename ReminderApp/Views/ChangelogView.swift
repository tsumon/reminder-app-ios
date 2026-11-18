import SwiftUI

/// 更新日志（漫风印张化）
struct ChangelogView: View {
    @Environment(\.comic) private var comic

    private struct Entry {
        let version: String
        let items: [String]
    }

    private let changelog: [Entry] = [
        Entry(version: "v2.11.0", items: [
            "极简奶油漫风（Minimalist Cream Comic）全面重构：92% 暖奶油留白、斜切角墨线印张与圆体立体大字",
            "新增 6 款奶油漫纸色板（奶油橙 / 抹茶奶纸 / 海盐汽水 / 莓果奶昔 / 黄油柠檬 / 复古电紫）与暗夜暖琥珀模式",
            "抽离前端模块化架构，完整保留 WebDAV v4 同步、无签名 .ipa 升级与跨端备份协议"
        ]),
        Entry(version: "v2.10.0", items: [
            "统一浅/深色卡片视觉与高对比打卡反馈，打通本地备份恢复、双生日自动拆分及规则触发时间对齐",
            "修复调休补班顺延、闰日与跨年腊月计算、活跃重试防饥饿与统计漏掉口径"
        ]),
        Entry(version: "v2.9.0", items: [
            "双端对齐增量同步代际、删除墓碑与并发动作防护",
            "支持自定义重试间隔、勿扰时段与 AlarmKit 系统闹钟（iOS 26+）"
        ])
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(changelog, id: \.version) { entry in
                    ComicCard(cut: ThemeTokens.cardCut, padding: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.version)
                                .font(.system(size: 16, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(comic.hero)
                            ForEach(entry.items, id: \.self) { item in
                                Text("· \(item)")
                                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(comic.ink)
                            }
                        }
                    }
                }
            }
            .padding(ThemeTokens.gutter)
        }
        .background(ComicCanvas())
        .navigationTitle("更新日志".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(comic.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}
