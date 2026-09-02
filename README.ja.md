[🇨🇳 简体中文](README.md) · [🇺🇸 English](README.en.md) · [🇹🇼 繁體中文](README.zh-TW.md) · [🇯🇵 日本語](README.ja.md) · [🇰🇷 한국어](README.ko.md)

---

# 繰り返しリマインダー — ネイティブ iOS アプリ

![Home](docs/screenshots/home.png)

![Calendar](docs/screenshots/calendar.png)

![Stats](docs/screenshots/stats.png)

## 🌐 多言語対応 / Multi-language Support

本アプリ（iOS と Android の両方）は端末の言語設定に自動的に追従する多言語対応を内蔵しています。

**対応言語：**
- 🇨🇳 簡体字中国語（zh-Hans）— デフォルト & フォールバック
- 🇺🇸 English (en)
- 🇹🇼 繁体字中国語 (zh-Hant)
- 🇯🇵 日本語 (ja)
- 🇰🇷 한국어 (ko)

**実装 / Implementation：**
- **iOS**：`Localizable.xcstrings` ローカリゼーションカタログ。SwiftUI は `String(localized:)` で多言語文字列を取得します。
- **Android**：`res/values/strings.xml`（簡体字中国語ベース）+ `values-en` / `values-zh-rTW` / `values-ja` / `values-ko` のリソース修飾子。実行時は `zh()` / `zhf()` を通じて文字列を検索します。
- 両プラットフォームで「中国語の原文をキーとする」方式を共有しており、文字列の追加・変更は中国語の原文と翻訳表を管理するだけで済みます。

> ユーザーに表示される文字列（約 330 件）はすべて多言語化されており、翻訳が欠落している場合は簡体字中国語の原文にフォールバックします。
> All user-visible strings (~330) are localized; missing translations gracefully fall back to Simplified Chinese.

## 機能概要

純粋なネイティブ SwiftUI の iOS リマインダーアプリで、以下をサポートしています：
- 周期の設定：毎日、毎週、毎月、四半期ごと、毎年、任意の日数
- 期限のプッシュ通知に「完了確認」と「後で通知」の 2 つのアクションボタン
- 未確認時の段階的再通知（v1.9.7 以降は両プラットフォームで統一）：1 時間 → 4 時間 → 12 時間 → 24 時間 → 24 時間
  - 5 回目に達すると `overdue`（未完了）とマークし、通知を止めて手動での確認 / 再オープンを待ちます
- 周期アンカーによるズレ防止：初回発火時刻を基準とするため、確認遅れによるズレは発生しません（月末の調整やうるう年の処理も正確）
- 完全な操作履歴
- SwiftData によるローカル永続化、オフラインで利用可能
- **日付リマインダーの事前お知らせ**：N 日前から毎日プレビューを送信（上限 14 日）
- **AI 音声アシスタント**：自然言語でのリマインダー作成、Function Calling
- **WebDAV 同期**：Nutstore / 汎用 WebDAV の双方向同期
- **近距離転送**：同じローカルネットワークで QR コードを読み取り、デバイス間でリマインダーを転送
- **OTA アップデート**：GitHub Releases を確認し、最新の .ipa をダウンロード

## 方法 1：XcodeGen（推奨、1 コマンド）

```bash
# 1. XcodeGen をインストール（未導入の場合）
brew install xcodegen

# 2. Xcode プロジェクトを生成
cd reminder-app-ios
xcodegen generate

# 3. プロジェクトを開く
open ReminderApp.xcodeproj

# 4. iOS シミュレータを選択し、Cmd+R で実行
```

## 方法 2：Xcode プロジェクトを手動で作成

1. Xcode を開く → File → New → Project → iOS → App
2. プロダクト名：`ReminderApp`、Interface：SwiftUI、Language：Swift、Use SwiftData にチェック
3. 作成後、以下のファイルをプロジェクトに上書き / 追加：
   - `ReminderApp/ReminderApp.swift` → 自動生成された App ファイルを置き換え
   - `ReminderApp/Info.plist` → プロジェクトにドラッグ
   - `ReminderApp/Models/` → フォルダごとドラッグ
   - `ReminderApp/Views/` → フォルダごとドラッグ
   - `ReminderApp/Services/` → フォルダごとドラッグ
4. Deployment Target を iOS 17.0 に設定
5. Signing & Capabilities で Push Notifications と Background Modes（remote-notification）を追加
6. Cmd+R で実行

## プロジェクト構成

```
ReminderApp/
├── ReminderApp.swift              # @main エントリ
├── Info.plist                     # アプリ設定
├── Models/
│   └── Reminder.swift             # SwiftData データモデル + 列挙型
├── Views/
│   ├── ReminderListView.swift     # ホームリスト（グループ：アクティブ / 待機 / 完了、期限超過含む）
│   ├── ReminderRowView.swift      # リスト行コンポーネント
│   ├── CreateReminderView.swift   # 新規リマインダーフォーム
│   ├── ReminderDetailView.swift   # 詳細ページ + 確認 / 後で操作 + 履歴
│   ├── CalendarView.swift         # カレンダービュー
│   ├── StatsView.swift            # 統計 / ヒートマップ
│   ├── AIChatView.swift           # AI チャット
│   ├── AISettingsView.swift       # AI 設定
│   ├── NearbyShareView.swift      # 近距離転送（QR + TCP）
│   ├── SyncSettingsView.swift     # WebDAV 同期設定
│   └── SettingsView.swift         # 設定（アップデート確認など）
├── Services/
│   ├── ReminderEngine.swift       # 周期計算 / 確認 / 段階的再通知 / 見落としチェック
│   ├── NotificationManager.swift  # 通知権限 / カテゴリ登録 / ローカルプッシュ
│   ├── HolidayService.swift       # 祝日サービス（オンライン兜底付き）
│   ├── LunarCalendarCheck.swift   # 旧暦変換
│   ├── BackupHelper.swift         # JSON バックアップのインポート / エクスポート
│   ├── WebDavSync.swift           # WebDAV 双方向同期
│   ├── NearbyShareService.swift   # LAN TCP 転送（47823）
│   ├── QRCodeService.swift        # QR 生成と読み取り（AVFoundation）
│   ├── UpdateService.swift        # GitHub releases.atom アップデート確認
│   ├── TelemetryService.swift     # アクセス解析（confirm / escalate / ...）
│   └── LiquidGlass.swift          # リキッドガラススタイルライブラリ
└── Widgets/
    └── ReminderWidget.swift       # ホーム画面ウィジェット
```

## 技術スタック

| モジュール | 技術 |
|------------|------|
| UI | SwiftUI (iOS 17+) |
| データ永続化 | SwiftData |
| ローカル通知 | UserNotifications + UNNotificationAction |
| 状態管理 | @Observable / @StateObject / @Query |
| 通知イベント | NotificationCenter（アプリ内のコンポーネント間通信用） |

## 通知ボタン

プッシュを受信すると、iOS の通知バナーに 2 つのアクションボタンが表示されます：
- **完了確認** → 周期を進め、`firstTriggerAt` アンカーに基づいて次回の時刻を計算
- **後で通知** → 15 分後に再プッシュ

何もしない（スワイプして消去）場合は、段階的再通知に入ります：

| 段階 | 間隔 | 状態 |
|------|------|------|
| 1 回目 | 1 時間後 | active（提醒中） |
| 2 回目 | 4 時間後 | active |
| 3 回目 | 12 時間後 | active |
| 4 回目 | 24 時間後 | active |
| 5 回目 | 24 時間後 | **overdue**（未完了、通知停止） |

> v1.9.7 以降：段階的再通知中は周期を進めません。`overdue` が設定されると自動的な応答を停止し、手動確認または再オープンを待ちます。

## システム要件

- Xcode 15.0+
- iOS 17.0+
- Swift 5.9+

## 変更履歴

| バージョン | 日付 | 更新内容 |
|------------|------|----------|
| v1.9.7 | 2026-08 | 段階的再通知を `overdue` で上限化、リキッドガラス UI、QR 転送 |
| v1.9.6 | 2026-08 | 5 回のレビューで 70 件の修正 + 近距離転送 + AI 無料 API なしモードの削除 |
| v1.9.5 | 2026-08 | アップデート確認を `releases.atom` に変更（API レート制限を回避） |
| v1.9.4 | 2026-08 | WebDAV 同期の 404 → 自動 `MKCOL` でディレクトリ作成 |
| v1.9.3 | 2026-08 | 設定ページ（バージョン / アップデート確認 / 変更履歴） |
| v1.9.2 | 2026-08 | アップデート確認のタイムアウト再試行 + WebDAV の親切な案内 |
| v1.9.1 | 2026-08 | AI ルールリマインダー + ホームメニューの「アップデート確認」 |
| v1.9.0 | 2026-08 | UI 最適化（リキッドガラス）+ OTA アップデート + アプリアイコン |
| v1.8.7 | 2026-08 | ウィジェット強化 / 祝日のオンライン取得 / 統計インサイト / .ics 書き出し / デザイントークン / クラッシュ監視 |
