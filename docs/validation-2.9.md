# 2.9 validation / 验证记录

源码 2.9.0 / 71。基线：iOS `1815516`（master）、Android `850555d`（main），均为 2.8.0 / 70。本地分支 `codex/ui-sync-refresh-20261101`；未推送、未发布。

## 已通过

| 检查 | 结果与边界 |
| --- | --- |
| Android JVM 单测 | 119 项，0 失败；包含旧 v1/v2/v3 协议、节假日前移完成/跳过与重试、锚点编辑、策略和搜索解析 |
| Android lint / 构建 | lintDebug、assembleDebug、assembleDebugAndroidTest 通过；JDK 17、SDK 36 |
| Android API 36 设备测试 | 19 项，0 失败（含两个可选入口的默认分支）；Room 填充旧库 8→10 / 9→10、动作代际、同步冲突和删除历史测试通过。可选截图 / 往返入口另外实际执行成功 |
| Android 原生表单 | 实际输入后取消：数据库新增 0 条；连续点击保存：目标标题只有 1 条 |
| iOS 逻辑 | LunarCalendarCheck、ChatHistoryCheck、BackupProtocolCheck、SixFeaturesCheck（24 个检查）、UpgradeCheck 全部通过 |
| iOS 真实旧库升级 | 原始 2.7.2 填充模型与冻结 2.8.0/build70 模型分别升级到当前模型通过；旧字段、ID、记录、非默认策略、静默、撤销载荷保留 |
| iOS 原生 UI | RefreshUITests 2 项，0 失败；一句话填表、保存、取消返回、四 Tab、日历当天创建、健康诊断入口。真实运行截图已导出 |
| iOS 构建 | App + Widget build-for-testing 与 CODE_SIGNING_ALLOWED=NO Release archive 通过，本机 Xcode 27.2；原 CI Xcode 26.3 配置保留 |
| 跨端实际往返 | Android 产品导出 → iOS 产品导入/合并/导出 → Android 两次导入/导出；3 条提醒、16 条历史、1 个提醒删除标记、1 个撤销记录删除标记及双方支持的核心字段、历史备注一致 |
| 外观与无障碍 | 两端真实深色截图；Android 1.5× 字体、iOS XXXL 字体目检；可操作控件使用原生语义，iOS 核心路径通过 XCTest 辅助功能定位。不是完整读屏认证 |

## 实装证据

[首页](screenshots/runtime-2.9/home.png) · [日历](screenshots/runtime-2.9/calendar.png) · [统计](screenshots/runtime-2.9/stats.png) · [设置](screenshots/runtime-2.9/settings.png) · [创建](screenshots/runtime-2.9/create.png) · [深色](screenshots/runtime-2.9/home-dark.png) · [大字体](screenshots/runtime-2.9/home-large.png)

截图来自当前原生应用与独立测试设备，只含测试数据；未将概念图或旧 HTML mockup 冒充实装。iOS 已取消默认 Debug 自动插入演示提醒；保留显式 `-uitest_seed_demo` 测试开关，不删除存量用户数据。

iOS 验收发现并修复快速创建 sheet 捕获旧输入，以及保存/取消后的键盘焦点恢复影响 Tab 点击的问题。最终大字体筛选改为纵向布局，深色输入使用自适应提示色；修复后的原生测试 2 项、0 失败。

## 签名与交付边界

[签名配置比对](signing-audit-2.9.json)：Android release signingConfigs 和工作流、iOS 工作流与两个 entitlements 均与基线逐字相同；应用 ID / Bundle ID / App Group 保持原值，版本统一为 2.9.0 / 71。

Android `assembleRelease` 在原门禁处停止：`SigningConfig release is missing required property storeFile`。本机没有原 KEYSTORE_* / KEY_ALIAS 环境配置，未生成替代 keystore、未读取或输出密钥密码、未绕过门禁。因此未完成新正式签名制品与旧证书的实物比对，不能宣称正式覆盖安装已验证。iOS 继续原 unsigned 归档方式；未引入任何分发证书。

## 尚需原渠道 / 真机

- 原正式签名 APK 覆盖安装，及 iOS 原签名渠道的覆盖升级；数据库迁移检查不能替代实际签名渠道验收。
- 真机锁屏、重启、Doze / 厂商后台策略、声音、专注 / 勿扰和实际送达；权限与排期不证明送达。
- VoiceOver / TalkBack 全流程人工读屏。AI 与语音原入口保留，但本次未调用外部模型服务或付费模型进行验收。
- 旧客户端不能保留 v4 删除 / 历史元数据；无稳定 ID 的古老文件不能可靠识别删除。时间语义仍是设备当前日历与存量时间戳，未新增固定时区模式，详见协议说明。

## 复验

Android：`./gradlew testDebugUnitTest lintDebug assembleDebug assembleDebugAndroidTest connectedDebugAndroidTest`。

iOS：`scripts/check-upgrade.sh`（需 XcodeGen）执行逻辑与两个真实旧库迁移；UI 使用 `xcodebuild test -scheme ReminderApp -only-testing:ReminderAppUITests/RefreshUITests`，指定专用模拟器。旧项目其他需要本地 AI / WebDAV mock server 的 UI 套件未在本轮全量执行，不计入上述 2 项。
