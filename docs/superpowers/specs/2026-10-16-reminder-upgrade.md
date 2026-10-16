# Reminder 2.8 upgrade

Approved by the user on 2026-10-16: implement all proposed reliability and everyday-use improvements on Android and iOS. Android signing identity must remain unchanged. Layout changes are allowed; existing functions and user data must survive upgrades.

## Binding constraints

- Android applicationId/namespace remain `com.reminderapp`; preserve the release signing configuration, secret names, key alias, keystore, and certificate. Never generate or rotate a release key. The new signed APK certificate SHA-256 must equal v2.7.2 before distribution.
- Keep Android minSdk 26, iOS deployment target 17, existing iOS bundle IDs and app-group IDs. Increment version to 2.8.0, build/versionCode 70. Use additive Room/SwiftData migrations; no destructive fallback, database reset, or user-data deletion.
- Keep all existing reminder kinds, lunar birthdays, holiday rules, AI/BYOK, WebDAV, local backups, nearby sharing, widgets, and languages. Preserve current defaults for existing reminders.
- Retain native Kotlin/Compose and Swift/SwiftUI. Share a backward-compatible JSON contract and behavior fixtures.
- Work on feature branches; no merge, tag, production release, store submission, or key/secret change in this task. Builds and draft PRs are authorized implementation work.

## User-visible behavior

1. Reliable delivery: Android uses AlarmManager for timed user reminders, with explicit exact-alarm capability checks and a truthful inexact fallback. WorkManager remains suitable for deferred background work. Restore schedules on reboot/time/time-zone/exact-alarm permission changes. Do not double-fire or let an old notification operate on a later occurrence.
2. Synchronization keeps local-only reminders scheduled. Never silently overwrite simultaneous changes: stop and show an actionable conflict result, preserve a local backup before explicitly selected resolution, and upload/download only the selected revision. Do not imply deletion synchronizes where the legacy protocol cannot represent it.
3. All completion/snooze/skip paths (app, notifications, widget, AI) use consistent state transitions, recording, cancellation, rescheduling and sync invalidation. Complete from the widget counts in statistics.
4. Recurrence can stay anchored (`fixed`, existing behavior) or restart from actual completion (`afterCompletion`) for repeating cycle reminders. Once/date/rule reminders do not silently change meaning. Preview uses the same recurrence policy.
5. Reminder styles: `gentle` (one attempt), `persistent` (existing escalating defaults), `important` (same retry policy plus platform critical/AlarmKit option). Users can edit retry intervals and attempt cap and existing quiet hours. Every retry respects quiet hours. iOS allocates the notification budget globally so earlier primary reminders win over extra retries; show capability/coverage limitations accurately.
6. Skip this occurrence advances a recurring reminder without counting completion; once reminders cannot be skipped as a repeating item. Undo completion restores the previous reminder state and removes that completion's statistic only if no newer edit/action/sync superseded it. Show undo through an accessible in-app action; never erase unrelated records.
7. Quick creation from the home screen: enter a sentence, reuse the existing AI/local parser, show an editable rule summary for complex input, create only once, support undo. Existing manual creation, voice, batch import and model settings remain accessible. Reduce home header space and place due reminders first; expose complete/snooze/skip in existing card/detail patterns.
8. Onboarding/self-check: explain notification/exact alarm/AlarmKit permissions at use, show current capability and a test reminder button. Include an in-app privacy explanation of local data, user-configured AI endpoints and WebDAV uploads. Make sync conflicts understandable. Update development and public-test documentation.
9. iOS important reminders: integrate AlarmKit behind iOS 26 availability and user authorization; do not promise ordinary notifications bypass focus/silent mode. Use documented App Intents for stop/snooze and avoid duplicate notifications. Old iOS continues to work.

## Shared backup contract (schemaVersion 3, additive)

Existing fields remain readable. Missing new fields use the exact defaults below:

```json
{"recurrenceMode":"fixed","reminderStyle":"persistent","retryIntervalsMinutes":[60,240,720,1440],"maxReminderAttempts":5,"quietStartMinute":null,"quietEndMinute":null}
```

Use `retryIntervalsMinutes` as the cross-platform array field regardless of local storage representation. Intervals must be positive, bounded to 1..10080 minutes, at most 10 entries; attempts 1..10. Reject malformed input or fall back to the legacy policy without crashing. Quiet hours use minutes since midnight 0..1439, both nullable together. Keep legacy isCritical readable; a legacy critical reminder defaults to important when no explicit reminderStyle exists. Retain imported next trigger/retry state rather than recomputing snoozed/overdue reminders from scratch.

## Verification

- Test actual engine transitions: fixed and completion-relative monthly/day cycles, once behavior, skip vs complete statistics, guarded undo, quiet-hour retry scheduling, sync preserving local-only schedules, backup compatibility and the new field round trip.
- Test additive migration of an existing database with populated reminders and records. Verify all old columns/values and stable IDs survive.
- Compile and test both apps in CI. Android signed artifact must match old APK package name/certificate and have higher versionCode. Do not treat unsigned/debug builds as signature proof.
- Device checks remain separately reported: locked device, Doze, reboot, permission denial/revocation, widgets, notifications, existing-data install. Never claim checks ran without output evidence.
