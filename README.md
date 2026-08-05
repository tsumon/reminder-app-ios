# 循环提醒器 - iOS 原生 App

## 功能概述

一个纯原生 SwiftUI iOS 提醒应用，支持：
- 设置循环周期：每天、每周、每月、每季度、每年、自定义天数
- 到期推送通知，带「确认完成」和「稍后提醒」两个操作按钮
- 未确认递增轰炸：1小时 → 4小时 → 12小时 → 每天
- 周期锚点防漂移：基于首次触发时间计算，不会因延迟确认而偏移
- 完整操作历史记录
- SwiftData 本地持久化，离线可用

## 方式一：XcodeGen（推荐，一键生成）

```bash
# 1. 安装 XcodeGen（如未安装）
brew install xcodegen

# 2. 生成 Xcode 项目
cd reminder-app-ios
xcodegen generate

# 3. 打开项目
open ReminderApp.xcodeproj

# 4. 选择 iOS 模拟器，按 Cmd+R 运行
```

## 方式二：手动创建 Xcode 项目

1. 打开 Xcode → File → New → Project → iOS → App
2. 项目名：`ReminderApp`，Interface：SwiftUI，Language：Swift，勾选 Use SwiftData
3. 创建后将以下文件覆盖/添加到项目：
   - `ReminderApp/ReminderApp.swift` → 替换自动生成的 App 文件
   - `ReminderApp/Info.plist` → 拖入项目
   - `ReminderApp/Models/` → 整个文件夹拖入
   - `ReminderApp/Views/` → 整个文件夹拖入
   - `ReminderApp/Services/` → 整个文件夹拖入
4. 设置 Deployment Target 为 iOS 17.0
5. 在 Signing & Capabilities 中添加 Push Notifications 和 Background Modes（remote-notification）
6. 按 Cmd+R 运行

## 项目结构

```
ReminderApp/
├── ReminderApp.swift              # @main 入口
├── Info.plist                     # 应用配置
├── Models/
│   └── Reminder.swift             # SwiftData 数据模型 + 枚举
├── Views/
│   ├── ReminderListView.swift     # 首页列表（分组：提醒中/等待中/已完成）
│   ├── ReminderRowView.swift      # 列表行组件
│   ├── CreateReminderView.swift   # 新建提醒表单
│   └── ReminderDetailView.swift   # 详情页 + 确认/稍后操作 + 历史记录
└── Services/
    ├── NotificationManager.swift  # 通知权限/分类注册/本地推送
    └── ReminderEngine.swift       # 周期计算/确认/递增重试/遗漏检查
```

## 技术栈

| 模块 | 技术 |
|------|------|
| UI | SwiftUI (iOS 17+) |
| 数据持久化 | SwiftData |
| 本地通知 | UserNotifications + UNNotificationAction |
| 状态管理 | @Observable / @StateObject / @Query |
| 通知事件 | NotificationCenter（App 内通知跨组件通信） |

## 通知按钮

收到推送时，iOS 通知横幅展示两个操作按钮：
- **确认完成** → 周期前进，基于 firstTriggerAt 锚点计算下次时间
- **稍后提醒** → 15 分钟后重推

如果用户什么都不做（滑动消除），进入递增重试：
- 第 1 次：1 小时后
- 第 2 次：4 小时后
- 第 3 次：12 小时后
- 第 4 次起：每天一次

## 系统要求

- Xcode 15.0+
- iOS 17.0+
- Swift 5.9+
