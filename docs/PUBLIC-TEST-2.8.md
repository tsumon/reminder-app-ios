# Reminder 2.8 public testing

The iOS target remains iOS 17, `com.reminder.app`, widget `com.reminder.app.widget`, app group `group.com.reminder.app`. Version 2.8.0/build 70 uses additive SwiftData defaults. Keep a local backup before testing an upgrade. A failed store open retains the store; do not remove/reinstall the app to diagnose it.

## Everyday behavior

- Home sentence entry opens the existing parser and editable full form before saving. Complex unsupported rules require manual confirmation or the existing AI entry. Manual entry, voice, templates, batch/nearby import and AI model settings remain available.
- Fixed recurrence keeps the original anchor. Completion-relative cycle reminders start the next interval from actual completion. Date, lunar birthday, holiday and calendar-rule reminders keep their own calendars.
- Gentle reminders automatically attempt once. Explicit snooze still delivers again. Persistent/important styles support 1–10 attempts and configurable minute intervals (1–10080, up to ten). All attempts respect per-reminder quiet hours.
- Skip advances a repeating occurrence without a completion statistic. Undo removes only the exact last completion record and restores its state, provided no newer edit/action/sync superseded it. The full rule editor preserves current occurrence and retry state for metadata edits.
- Notification and widget action tokens identify the current occurrence/edit generation. Actions from an earlier completed/edited occurrence are ignored. Widget completion uses the same persisted action service and counts in statistics.

## Capabilities and privacy

Open Settings → 提醒诊断 for notification status, primary coverage, a ten-second test, AlarmKit authorization and privacy details. iOS keeps a maximum of 64 pending ordinary notifications, including retries, advance messages and weekly reports. Earliest primary reminders receive slots first. More than 64 items cannot all be guaranteed while the app remains closed; open the app to refresh coverage.

AlarmKit is optional for important reminders on iOS 26+. It uses fixed alert-only alarms with persisted complete/snooze App Intents; no countdown is used. Denied/unavailable/failed scheduling falls back to ordinary notifications. Ordinary notifications remain affected by focus/silent/system settings. Validate actual AlarmKit delivery on supported physical hardware; simulator builds are not delivery proof.

Reminder data stays local unless the user chooses AI, WebDAV, export or nearby sharing. AI sends conversation/relevant reminder content to the configured endpoint. WebDAV uploads a JSON backup to the configured server; passwords/API keys use Keychain. Share backups only with trusted recipients.

## Synchronization

Simultaneous edits stop before writes and present local/remote choices. Each selected overwrite first saves a local JSON snapshot in Application Support/webdav_snapshots. Remote merges retain local-only reminders and schedules. The existing protocol has no deletion tombstones: deleting on one device does not promise deletion elsewhere. Existing remote files require ETag support for conditional overwrites; an absent ETag fails safely with an actionable message.

Schema 3 adds recurrence/style/retry/quiet fields while reading legacy schema 1/2. Missing fields retain legacy persistent defaults (60,240,720,1440 minutes; five attempts). Legacy critical flags become important. Imported next-trigger/status/retry state and stable UUIDs are retained; exported UUIDs use lowercase and active retry status uses `notifying` for Android compatibility.

## Verification

CI explicitly selects Xcode 26.3 and builds app/widget unsigned for verification. It runs lunar/retry, chat persistence, backup protocol, six existing features, new policy/actions/global-queue checks, and a separate original v2.7.2 populated-store producer followed by the upgraded model opener. Both migration executables use the same Swift module/entity identities. UI tests start the existing local AI mock server and publish xcresult output. The actual Swift v3 backup output is published as `ios-protocol-v3-export`.

Before distribution, separately record physical-device checks: populated upgrade install, locked delivery, permission denial/revocation, focus/silent behavior, important alarms and stop/snooze, widget completion statistics, notification stale actions, >64 reminder coverage, timezone changes, WebDAV conflicts and both resolution choices. CI artifacts are unsigned and require the user's usual signing/install process. No signing identity, tag, release or store submission is changed by this upgrade.
