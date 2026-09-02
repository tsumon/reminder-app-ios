[🇨🇳 简体中文](README.md) · [🇺🇸 English](README.en.md) · [🇹🇼 繁體中文](README.zh-TW.md) · [🇯🇵 日本語](README.ja.md) · [🇰🇷 한국어](README.ko.md)

---

# 循環提醒

![Home](docs/screenshots/home.png)

![Calendar](docs/screenshots/calendar.png)

![Stats](docs/screenshots/stats.png)

## 🌐 多語言支援 / Multi-language Support

本應用（iOS 與 Android 雙端）內建多語言支援，跟隨系統語言自動切換。

**支援語言：**
- 🇨🇳 簡體中文（zh-Hans）— 預設語言 / 回退語言 (default & fallback)
- 🇺🇸 English (en)
- 🇹🇼 繁體中文 (zh-Hant)
- 🇯🇵 日本語 (ja)
- 🇰🇷 한국어 (ko)

**實作方式 / Implementation：**
- **iOS**：`Localizable.xcstrings` 多語言目錄，SwiftUI 透過 `String(localized:)` 取得多語言文案。
- **Android**：`res/values/strings.xml`（簡體中文基準）+ `values-en` / `values-zh-rTW` / `values-ja` / `values-ko` 資源限定符，執行時代碼統一透過 `zh()` / `zhf()` 查表。
- 雙端共用「中文原串即 key」方案，新增 / 修改文案只需維護中文源串與譯文表。

> 多語言文案已涵蓋全部使用者可見介面（約 330 條），翻譯缺失時自動回退為簡體中文原串。
> All user-visible strings (~330) are localized; missing translations gracefully fall back to Simplified Chinese.

## 功能概述

一套純原生 SwiftUI iOS 提醒應用，支援：
- 設定循環週期：每天、每週、每月、每季、每年、自訂天數
- 到期推播通知，帶「確認完成」和「稍後提醒」兩個操作按鈕
- 未確認遞增重試（v1.9.7 起雙端對齊）：1 小時 → 4 小時 → 12 小時 → 24 小時 → 24 小時
  - 第 5 次到達後標 `overdue`（逾期），停止轟炸，等使用者手動確認 / 重新開啟
- 週期錨點防漂移：基於首次觸發時間計算，不會因延遲確認而偏移（月末對齊、閏年正確）
- 完整操作歷史記錄
- SwiftData 本地持久化，離線可用
- **日期提醒提前預告**：提前 N 天每日推送預告（上限 14 天）
- **AI 語音助理**：自然語言建提醒、Function Calling
- **WebDAV 同步**：堅果雲 / 通用 WebDAV 雙向同步
- **近場傳輸**：同一區域網路掃描 QR Code 互傳提醒
- **線上升級**：檢查 GitHub Releases 並下載最新 .ipa

## 方式一：XcodeGen（推薦，一鍵生成）

```bash
# 1. 安裝 XcodeGen（如未安裝）
brew install xcodegen

# 2. 生成 Xcode 專案
cd reminder-app-ios
xcodegen generate

# 3. 開啟專案
open ReminderApp.xcodeproj

# 4. 選擇 iOS 模擬器，按 Cmd+R 執行
```

## 方式二：手動建立 Xcode 專案

1. 開啟 Xcode → File → New → Project → iOS → App
2. 專案名：`ReminderApp`，Interface：SwiftUI，Language：Swift，勾選 Use SwiftData
3. 建立後將以下檔案覆蓋 / 加入專案：
   - `ReminderApp/ReminderApp.swift` → 替換自動生成的 App 檔案
   - `ReminderApp/Info.plist` → 拖入專案
   - `ReminderApp/Models/` → 整個資料夾拖入
   - `ReminderApp/Views/` → 整個資料夾拖入
   - `ReminderApp/Services/` → 整個資料夾拖入
4. 設定 Deployment Target 為 iOS 17.0
5. 在 Signing & Capabilities 中加入 Push Notifications 和 Background Modes（remote-notification）
6. 按 Cmd+R 執行

## 專案結構

```
ReminderApp/
├── ReminderApp.swift              # @main 入口
├── Info.plist                     # 應用設定
├── Models/
│   └── Reminder.swift             # SwiftData 資料模型 + 列舉
├── Views/
│   ├── ReminderListView.swift     # 首頁列表（分組：提醒中 / 等待中 / 已完成，含逾期）
│   ├── ReminderRowView.swift      # 列表行元件
│   ├── CreateReminderView.swift   # 新建提醒表單
│   ├── ReminderDetailView.swift   # 詳情頁 + 確認 / 稍後操作 + 歷史記錄
│   ├── CalendarView.swift         # 日曆視圖
│   ├── StatsView.swift            # 統計 / 熱力圖
│   ├── AIChatView.swift           # AI 對話
│   ├── AISettingsView.swift       # AI 設定
│   ├── NearbyShareView.swift      # 近場傳輸（QR Code + TCP）
│   ├── SyncSettingsView.swift     # WebDAV 同步設定
│   └── SettingsView.swift         # 設定（檢查更新等）
├── Services/
│   ├── ReminderEngine.swift       # 週期計算 / 確認 / 遞增重試 / 遺漏檢查
│   ├── NotificationManager.swift  # 通知權限 / 分類註冊 / 本機推播
│   ├── HolidayService.swift       # 節假日服務（含聯網兜底）
│   ├── LunarCalendarCheck.swift   # 農曆轉換
│   ├── BackupHelper.swift         # JSON 備份匯入匯出
│   ├── WebDavSync.swift           # WebDAV 雙向同步
│   ├── NearbyShareService.swift   # 區域網路 TCP 47823 互傳
│   ├── QRCodeService.swift        # QR Code 生成與掃碼（AVFoundation）
│   ├── UpdateService.swift        # GitHub releases.atom 檢查更新
│   ├── TelemetryService.swift     # 埋點（confirm / escalate / ...）
│   └── LiquidGlass.swift          # 液態玻璃樣式庫
└── Widgets/
    └── ReminderWidget.swift       # 桌面小工具
```

## 技術堆疊

| 模組 | 技術 |
|------|------|
| UI | SwiftUI (iOS 17+) |
| 資料持久化 | SwiftData |
| 本機通知 | UserNotifications + UNNotificationAction |
| 狀態管理 | @Observable / @StateObject / @Query |
| 通知事件 | NotificationCenter（App 內通知跨元件通訊） |

## 通知按鈕

收到推播時，iOS 通知橫幅展示兩個操作按鈕：
- **確認完成** → 週期前進，基於 firstTriggerAt 錨點計算下次時間
- **稍後提醒** → 15 分鐘後重推

如果使用者什麼都不做（滑動消除），進入遞增重試：

| 階段 | 間隔 | 狀態 |
|------|------|------|
| 第 1 次 | 1 小時後 | active（提醒中） |
| 第 2 次 | 4 小時後 | active |
| 第 3 次 | 12 小時後 | active |
| 第 4 次 | 24 小時後 | active |
| 第 5 次 | 24 小時後 | **overdue**（逾期，停止轟炸） |

> v1.9.7 起：遞增重試期間不推進週期；標 overdue 後不再自動響，等使用者手動確認或重新開啟。

## 系統需求

- Xcode 15.0+
- iOS 17.0+
- Swift 5.9+

## 版本歷史

| 版本 | 日期 | 更新內容 |
|------|------|----------|
| v1.9.7 | 2026-08 | 遞增重試上限封頂 overdue、液態玻璃 UI、掃碼互傳 |
| v1.9.6 | 2026-08 | 五輪審查 70 項修復 + 近場傳輸 + 刪除 AI 免 API 模式 |
| v1.9.5 | 2026-08 | 檢查更新改 `releases.atom` 防 API 限流 |
| v1.9.4 | 2026-08 | WebDAV 同步 404 → 自動 MKCOL 建目錄 |
| v1.9.3 | 2026-08 | 設定頁（版本號 / 檢查更新 / 更新日誌） |
| v1.9.2 | 2026-08 | 更新檢查逾時重試 + WebDAV 友好提示 |
| v1.9.1 | 2026-08 | AI 規則提醒 + 首頁選單「檢查更新」 |
| v1.9.0 | 2026-08 | UI 優化（液態玻璃）+ 線上升級 + App 圖示 |
| v1.8.7 | 2026-08 | 小工具增強 / 節假日聯網 / 統計洞察 / .ics 匯出 / 設計令牌 / 崩潰監控 |
