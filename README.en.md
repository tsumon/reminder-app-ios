[简体中文](README.md) · [English](README.en.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

<img src="assets/readme/hero.svg" width="100%" alt="Reminder — a calmer rhythm">

# Reminder

**Keep what needs a confirmation in view.**

Native reminders for iOS and Android. Confirm to move to the next cycle; use your chosen retry style and intervals while a task remains unconfirmed. Local data first, optional sync.

Source **2.9.0 / 71** · development branch, not released. See Releases for public downloads.

[**Downloads & releases ↗**](https://github.com/tsumon/reminder-app-ios/releases/latest) · [Other platform](https://github.com/tsumon/reminder-app-android)

## What it does

| Capability | iOS | Android |
| :--- | :---: | :---: |
| Cycles, dates, lunar birthdays, holidays, nth-week rules | ✓ | ✓ |
| Fixed schedule / restart from completion | ✓ | ✓ |
| Gentle / persistent / important, retries and quiet hours | ✓ | ✓ |
| Complete, snooze, tomorrow, skip and undo | ✓ | ✓ |
| Search, combined type filters, due / title / priority sorting | ✓ | ✓ |
| Day agenda, week / month statistics, widgets | ✓ | ✓ |
| Offline natural language, voice, templates, configurable AI | ✓ | ✓ |
| JSON, ICS, nearby transfer, local backups, WebDAV | ✓ | ✓ |

## Start in three steps

1. Create a reminder manually or fill the editable form with a sentence, voice or a template. Review the complete rule.
2. Choose the style, recurrence anchor, retry intervals and quiet hours. Review the next three occurrences before saving.
3. Open the notification check on Home, inspect permissions and system settings, then schedule a test and lock your device.

## Running app

Only actual runtime captures are shown. Example reminders belong to an isolated test device, not default user data.

<p align="center">
  <img src="docs/screenshots/runtime-2.9/home.png" width="280" alt="Home — iOS 2.9">
  <img src="docs/screenshots/runtime-2.9/calendar.png" width="280" alt="Calendar — iOS 2.9">
</p>
<p align="center">
  <img src="docs/screenshots/runtime-2.9/stats.png" width="280" alt="Statistics — iOS 2.9">
  <img src="docs/screenshots/runtime-2.9/settings.png" width="280" alt="Settings — iOS 2.9">
</p>

[Create form](docs/screenshots/runtime-2.9/create.png) · [Capture details](docs/screenshots/runtime-2.9/README.md)

## How reminders repeat

**Fixed** preserves the original schedule after a late completion; an early completion of a holiday-shifted reminder consumes its original slot. **After completion** starts a new interval from your confirmation. Existing reminders keep their policy.

**Gentle** sends one automatic alert. **Persistent** defaults to 60 → 240 → 720 → 1440 minutes, up to 5 alerts including the first, with individually editable intervals. **Important** uses only capabilities granted by the OS. Retries respect quiet hours.

Calculations use the device calendar and stored anchor timestamps. A time-zone change does not rewrite existing anchors: review the next alert. Previews assume on-time confirmation and may change with holiday data.

Completed and skipped count actions separately. Missed counts dates with retries; it does not prove notification delivery.

## Sync & recovery

Use your own WebDAV server. Conflicting edits pause for an explicit choice. Private local snapshots are saved first, and uploads retain ETag preconditions. Schema v4 merges history by stable ID and keeps deletion markers for reminders and undone records.

Upgrade both devices for full history and deletion sync. v1–v3 backups remain readable, but older clients discard the new metadata. Ancient files without stable IDs cannot reliably identify deletions. Markers do not expire; restore a deleted reminder under a new ID and keep complete v4 backups. Single-item share cards do not carry global deletions.

## Install & upgrade in place

iOS 17+. The release workflow produces an unsigned IPA. Continue using your original signing / sideloading channel. App, Widget and App Group identities are retained; without the original signing channel, in-place upgrade and data continuity cannot be promised.

## What delivery status means

Permissions and scheduled counts describe configuration, not confirmed delivery. Silent mode, Focus / Do Not Disturb, notification channels, power policies and vendor background restrictions can affect alerts. Test on a locked physical device, after reboot and in the background.

iOS limits pending ordinary notifications. Important reminders can separately request AlarmKit on iOS 26+; unavailable or unauthorized alarms fall back to ordinary notifications.

## Build locally

Xcode 26.3+ · XcodeGen · iOS 17+

```sh
xcodegen generate
xcodebuild build -project ReminderApp.xcodeproj -scheme ReminderApp \
  -sdk iphonesimulator -destination "generic/platform=iOS Simulator" \
  CODE_SIGNING_ALLOWED=NO
xcodebuild build -project ReminderApp.xcodeproj -scheme UpgradeCheck \
  -destination "platform=macOS" -derivedDataPath DerivedDataChecks CODE_SIGNING_ALLOWED=NO
./DerivedDataChecks/Build/Products/Debug/UpgradeCheck
```

App: `com.reminder.app` · Widget: `com.reminder.app.widget` · App Group: `group.com.reminder.app`

Release: `CODE_SIGNING_ALLOWED=NO` (unsigned IPA).

## Privacy

Reminders and history stay on-device. AI sends conversations and relevant content to your configured model service. WebDAV, nearby sharing and exported files contain reminder data. Choose trusted endpoints and protect your backups.

[**Validation & protocol →**](docs/upgrade-2.9.md) · [Validation](docs/validation-2.9.md)
