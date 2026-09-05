[🇨🇳 简体中文](README.md) · [🇺🇸 English](README.en.md) · [🇹🇼 繁體中文](README.zh-TW.md) · [🇯🇵 日本語](README.ja.md) · [🇰🇷 한국어](README.ko.md)

---

# Recurring Reminder

Native iOS app.

| Home | Calendar | Stats | Settings |
|:---:|:---:|:---:|:---:|
| ![Home](docs/screenshots/home.png) | ![Calendar](docs/screenshots/calendar.png) | ![Stats](docs/screenshots/stats.png) | ![Settings](docs/screenshots/settings.png) |

## Current UI (v2.7.1)

Hammer-paper soft-shadow: light paper canvas / dark elevated surfaces. Cards have no stroke; actions are soft round buttons. Dock fills to the physical bottom (48pt). Four bottom tabs. Settings rows 52pt. AI lives in Settings, not as its own tab. iOS has no FAB.

- **Home** (title 「提醒事项」): inset search; chips 全部 / 今天 / 本周; today card + soft ring for pending count; groups 提醒中 / 等待中. Due rows confirm in-line (no large confirm dialog). Retry subtitle 「还没确认 · HH:MM 再响」. 44 emoji wells; light-blue wash cycle badges.
- **Calendar**: month as one elevated card; today as a vertical capsule + 🦊; solar + lunar + 班/休; adjacent-month dates dimmed; selecting a date lists that day's tasks. No weekly progress bar.
- **Stats**: three tiles (this-month done / streak / completion rate) + thick-stroke soft donut (rate / confirmed / missed) + monthly check-in heatmap + check-in castle + most-forgotten hours. Weekly garden is a caption line on the heatmap card.
- **Settings**: skins, etc.

```mermaid
flowchart TB
  app[Recurring Reminder]
  app --> home[Home]
  app --> cal[Calendar]
  app --> stats[Stats]
  app --> set[Settings]
```

```mermaid
flowchart LR
  waiting[Waiting] --> due[Due]
  due -->|Confirm| next[Next cycle]
  due -->|Unconfirmed| retry[Escalating retry]
  retry -->|Confirm| next
  retry -->|Cap| overdue[Overdue]
  overdue -->|Manual confirm| next
```

Retry engine remains 1h → 4h → 12h → 24h → overdue (then stops auto-ringing). Notification actions are Confirm and Later.

## 🌐 Multi-language Support

This app (iOS & Android) has built-in multi-language support that follows the system language automatically.

**Supported languages:**
- 🇨🇳 Simplified Chinese (zh-Hans) — default & fallback
- 🇺🇸 English (en)
- 🇹🇼 Traditional Chinese (zh-Hant)
- 🇯🇵 Japanese (ja)
- 🇰🇷 Korean (ko)

**Implementation:**
- **iOS**: `Localizable.xcstrings` localization catalog; SwiftUI retrieves strings via `String(localized:)`.
- **Android**: `res/values/strings.xml` (zh-Hans base) + `values-en` / `values-zh-rTW` / `values-ja` / `values-ko` resource qualifiers; runtime code resolves strings through `zh()` / `zhf()`.
- Both platforms share the "Chinese source string as key" approach — adding or modifying a string only requires maintaining the Chinese source and the translation table.

> All user-visible strings (~330) are localized; missing translations gracefully fall back to Simplified Chinese.

## Overview

A pure native SwiftUI iOS reminder app that supports:
- Set cycle: daily, weekly, monthly, quarterly, yearly, custom number of days
- Due push notification with two action buttons: "Confirm" and "Later"
- Unacknowledged escalating retry (aligned across platforms since v1.9.7): 1h → 4h → 12h → 24h → 24h
  - After the 5th escalation it is marked `overdue`, stops nagging, and waits for manual confirmation / re-open
- Cycle anchor anti-drift: computed from the first trigger time, won't shift due to delayed confirmation (month-end alignment, correct leap years)
- Full operation history
- SwiftData local persistence, available offline
- **Date reminder early preview**: pushes a preview daily N days in advance (cap 14 days)
- **AI voice assistant**: natural-language reminder creation, Function Calling
- **WebDAV sync**: Nutstore / generic WebDAV two-way sync
- **Nearby transfer**: scan a QR code on the same LAN to transfer reminders between devices
- **OTA upgrade**: checks GitHub Releases and downloads the latest .ipa

## Method 1: XcodeGen (recommended, one command)

```bash
# 1. Install XcodeGen (if not installed)
brew install xcodegen

# 2. Generate the Xcode project
cd reminder-app-ios
xcodegen generate

# 3. Open the project
open ReminderApp.xcodeproj

# 4. Select an iOS simulator and press Cmd+R to run
```

## Method 2: Create the Xcode project manually

1. Open Xcode → File → New → Project → iOS → App
2. Product Name: `ReminderApp`, Interface: SwiftUI, Language: Swift, check Use SwiftData
3. After creation, overwrite / add the following files to the project:
   - `ReminderApp/ReminderApp.swift` → replace the auto-generated App file
   - `ReminderApp/Info.plist` → drag into the project
   - `ReminderApp/Models/` → drag the whole folder in
   - `ReminderApp/Views/` → drag the whole folder in
   - `ReminderApp/Services/` → drag the whole folder in
4. Set Deployment Target to iOS 17.0
5. In Signing & Capabilities add Push Notifications and Background Modes (remote-notification)
6. Press Cmd+R to run

## Project Structure

```
ReminderApp/
├── ReminderApp.swift              # @main entry
├── Info.plist                     # App configuration
├── Models/
│   └── Reminder.swift             # SwiftData data model + enums
├── Views/
│   ├── ReminderListView.swift     # Home list (groups: active / waiting / done, incl. overdue)
│   ├── ReminderRowView.swift      # List row component
│   ├── CreateReminderView.swift   # New reminder form
│   ├── ReminderDetailView.swift   # Detail page + confirm / later actions + history
│   ├── CalendarView.swift         # Calendar view
│   ├── StatsView.swift            # Stats (month done / streak / completion rate)
│   ├── AIChatView.swift           # AI chat
│   ├── AISettingsView.swift       # AI config
│   ├── NearbyShareView.swift      # Nearby transfer (QR + TCP)
│   ├── SyncSettingsView.swift     # WebDAV sync settings
│   └── SettingsView.swift         # Settings (check update, etc.)
├── Services/
│   ├── ReminderEngine.swift       # Cycle calculation / confirm / escalating retry / missed check
│   ├── NotificationManager.swift  # Notification permission / category registration / local push
│   ├── HolidayService.swift       # Holiday service (with online fallback)
│   ├── LunarCalendarCheck.swift   # Lunar calendar conversion
│   ├── BackupHelper.swift         # JSON backup import / export
│   ├── WebDavSync.swift           # WebDAV two-way sync
│   ├── NearbyShareService.swift   # LAN TCP transfer on 47823
│   ├── QRCodeService.swift        # QR generation & scanning (AVFoundation)
│   ├── UpdateService.swift        # GitHub releases.atom update check
│   ├── TelemetryService.swift     # Analytics (confirm / escalate / ...)
│   └── SoftShadowCard.swift       # paper soft-shadow / donut / heatmap
└── Widgets/
    └── ReminderWidget.swift       # Home screen widget
```

## Tech Stack

| Module | Technology |
|--------|------------|
| UI | SwiftUI (iOS 17+) |
| Persistence | SwiftData |
| Local notifications | UserNotifications + UNNotificationAction |
| State management | @Observable / @StateObject / @Query |
| Notification events | NotificationCenter (in-app cross-component communication) |

## Notification Buttons

When a push arrives, the iOS notification banner shows two action buttons:
- **Confirm Complete** → advances the cycle, computing the next time based on the `firstTriggerAt` anchor
- **Remind Later** → re-pushes after 15 minutes

If the user does nothing (swipes it away), it enters escalating retry:

| Stage | Interval | Status |
|-------|----------|--------|
| 1st | after 1 hour | active |
| 2nd | after 4 hours | active |
| 3rd | after 12 hours | active |
| 4th | after 24 hours | active |
| 5th | after 24 hours | **overdue** (stops nagging) |

> Since v1.9.7: the cycle does not advance during escalating retry; once `overdue` is set it stops responding automatically, waiting for manual confirmation or re-open.

## System Requirements

- Xcode 15.0+
- iOS 17.0+
- Swift 5.9+

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| v2.7.1 | 2026-09 | soft-ui chrome: hammer 3D soft-shadow, dock fill to physical bottom (DockH 48 / selected 32), settings row 52 |
| v2.7.0 | 2026-09 | soft-ui paper elevation; today card + pending ring; stats donut + monthly heatmap |
| v2.6.0 | 2026-09 | In-row confirm, calendar day tasks, empty completion rate shows 0% |
| v2.4.14 | 2026-08 | AI asks one question at a time; solar+lunar birthday rows merged |
| v2.4.10 | 2026-08 | Skip weekends/holidays to next workday |
| v2.4.0 | 2026-08 | Home timeline + 6-color themes |
| v2.3.0 | 2026-08 | Brand color → teal |


Earlier releases: [https://github.com/tsumon/reminder-app-ios/releases](https://github.com/tsumon/reminder-app-ios/releases).
