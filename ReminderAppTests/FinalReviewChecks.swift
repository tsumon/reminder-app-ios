import Foundation
import SwiftData

@MainActor enum FinalReviewChecks {
    static func run(context: ModelContext) async throws {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone.current
        func date(_ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
            cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
        }
        let now = date(10, 16, 12)
        for cycle in [ReminderCycle.daily, .weekly, .monthly, .custom] {
            let old = Reminder(title: "Historical edit", cycle: cycle, customDays: 3,
                firstTriggerAt: date(1, 31), nextTriggerAt: date(10, 17), status: .snoozed, retryStage: 2)
            context.insert(old); try context.save()
            let anchor = ReminderEdits.cycleAnchor(date: date(1, 31), time: date(1, 31, 10), editing: true, now: now, calendar: cal)
            precondition(anchor == date(1, 31, 10), "Historical edit must retain the selected clock")
            let draft = Reminder(title: "Historical edit", cycle: cycle, customDays: 5, firstTriggerAt: anchor, nextTriggerAt: anchor)
            precondition(ReminderEdits.apply(draft, to: old, expectedToken: old.actionToken, scheduleChanged: true,
                context: context, now: now, calculate: { after, r in ReminderPolicy.nextCycle(after: after, reminder: r, calendar: cal) }))
            precondition(old.firstTriggerAt == anchor && old.nextTriggerAt > now)
            precondition(cal.component(.hour, from: old.nextTriggerAt) == 10 && cal.component(.minute, from: old.nextTriggerAt) == 0)
            if cycle == .monthly { precondition(old.nextTriggerAt == date(10, 31, 10)) }
            precondition(!ReminderPolicy.deliveryDates(for: old, now: now).isEmpty)
        }
        // Use the form's original inputs, derived draft mapping and real predicate together.
        // A derived first occurrence alone cannot tell whether the start control was edited.
        for (oldStart, selectedStart, expectedFirst, expectedNext, hour) in [
            (date(1, 13), date(12, 1), date(12, 8), date(12, 8), 9),
            (date(12, 8), date(10, 1), date(10, 13), date(11, 10), 9),
            (date(1, 13), date(1, 13), date(1, 13, 10), date(11, 10, 10), 10)] {
            let rule = Reminder(title: "Rule edit", kind: .rule, reminderHour: 9, rulePeriod: .monthly,
                ruleWeek: .w2, ruleWeekday: .tue, firstTriggerAt: oldStart, nextTriggerAt: date(11, 10))
            context.insert(rule); try context.save()
            let original = ReminderEdits.RuleStartInput(date: oldStart, time: oldStart, calendar: cal)
            let selected = ReminderEdits.RuleStartInput(date: selectedStart, time: oldStart, calendar: cal)
            let mapped = ReminderEdits.ruleFirstTrigger(start: selected, period: .monthly, week: .w2,
                weekday: .tue, hour: hour, minute: 0, calendar: cal)
            let draft = Reminder(title: "Rule edit", kind: .rule, reminderHour: hour, rulePeriod: .monthly,
                ruleWeek: .w2, ruleWeekday: .tue, firstTriggerAt: mapped, nextTriggerAt: mapped)
            let changed = ReminderEdits.scheduleChanged(draft, from: rule, ruleStart: selected, originalRuleStart: original)
            precondition(changed, "Actual form predicate must detect the edited rule start/clock")
            precondition(ReminderEdits.apply(draft, to: rule, expectedToken: rule.actionToken, scheduleChanged: changed,
                context: context, now: now, calculate: { after, r in ReminderPolicy.nextRuleDate(period: r.rulePeriod,
                    week: r.ruleWeek.rawValue, weekday: r.ruleWeekday.rawValue, hour: r.reminderHour, minute: r.reminderMinute, from: after, calendar: cal) }))
            precondition(rule.firstTriggerAt == expectedFirst && rule.nextTriggerAt == expectedNext)
            precondition(!ReminderPolicy.deliveryDates(for: rule, now: now).isEmpty)
        }
        for advanceOnly in [false, true] {
            let oldStart = date(1, 13), due = date(11, 11), retry = date(11, 10)
            let rule = Reminder(title: "Preserve rule", kind: .rule, reminderHour: 9, rulePeriod: .monthly,
                ruleWeek: .w2, ruleWeekday: .tue, firstTriggerAt: oldStart, nextTriggerAt: due, status: .snoozed, retryStage: 2)
            rule.lastRetryAt = retry
            context.insert(rule); try context.save()
            let original = ReminderEdits.RuleStartInput(date: oldStart, time: oldStart, calendar: cal)
            let untouched = ReminderEdits.RuleStartInput(date: oldStart, time: oldStart, calendar: cal)
            let mapped = ReminderEdits.ruleFirstTrigger(start: untouched, period: .monthly, week: .w2,
                weekday: .tue, hour: 9, minute: 0, calendar: cal)
            precondition(mapped != oldStart, "Untouched form still derives a different next rule date")
            let draft = Reminder(title: advanceOnly ? rule.title : "Metadata renamed", note: advanceOnly ? "" : "Edited note",
                kind: .rule, advanceDays: advanceOnly ? 7 : rule.advanceDays, reminderHour: 9, rulePeriod: .monthly,
                ruleWeek: .w2, ruleWeekday: .tue, firstTriggerAt: mapped, nextTriggerAt: mapped)
            let changed = ReminderEdits.scheduleChanged(draft, from: rule, ruleStart: untouched, originalRuleStart: original)
            precondition(!changed, "Untouched start must preserve snooze/retries for metadata or advance-only form edits")
            precondition(ReminderEdits.apply(draft, to: rule, expectedToken: rule.actionToken, scheduleChanged: changed,
                context: context, now: now, calculate: { _, _ in fatalError("Untouched rule start must not recalculate") }))
            precondition(rule.firstTriggerAt == oldStart && rule.nextTriggerAt == due && rule.status == .snoozed &&
                rule.retryStage == 2 && rule.lastRetryAt == retry)
            precondition(advanceOnly ? rule.advanceDays == 7 : rule.title == "Metadata renamed" && rule.note == "Edited note")
        }
        for (relative, future) in [(false, true), (true, false), (true, true)] {
            let anchor = future ? date(12, 1, 10) : date(1, 1, 10)
            let row = Reminder(title: "Edited start", cycle: .daily, firstTriggerAt: anchor, nextTriggerAt: anchor)
            let draft = Reminder(title: "Edited start", cycle: .daily, firstTriggerAt: anchor, nextTriggerAt: anchor)
            draft.recurrenceMode = relative ? "afterCompletion" : "fixed"
            context.insert(row); try context.save()
            precondition(ReminderEdits.apply(draft, to: row, expectedToken: row.actionToken, scheduleChanged: true,
                context: context, now: now, calculate: { after, r in ReminderPolicy.nextCycle(after: after, reminder: r, calendar: cal) }))
            precondition(row.nextTriggerAt == (future ? anchor : date(10, 17, 10)))
            row.status = .snoozed; row.retryStage = 2; row.lastRetryAt = now; draft.advanceDays = 12
            precondition(!ReminderEdits.scheduleChanged(draft, from: row), "Advance window must preserve runtime")
            precondition(ReminderEdits.apply(draft, to: row, expectedToken: row.actionToken,
                scheduleChanged: ReminderEdits.scheduleChanged(draft, from: row), context: context, now: now,
                calculate: { _, _ in fatalError("Advance-only form edit cannot recalculate") }))
            precondition(row.advanceDays == 12 && row.status == .snoozed && row.retryStage == 2 && row.lastRetryAt == now)
        }
        var berlin = Calendar(identifier: .gregorian); berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        func local(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            berlin.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
        }
        for (month, day) in [(3, 29), (10, 25)] {
            for (start, end, input, expected) in [
                (360, 480, local(month, day, 6, 30), local(month, day, 8)),
                (60, 480, local(month, day, 1, 30), local(month, day, 8)),
                (1320, 480, local(month, day - 1, 23), local(month, day, 8)),
                (1320, 480, local(month, day, 6, 30), local(month, day, 8))] {
                let policy = ReminderPolicy(intervals: [15], attempts: 4, quietStart: start, quietEnd: end)
                precondition(policy.adjust(input, calendar: berlin) == expected)
                let row = Reminder(title: "DST chain", firstTriggerAt: input, nextTriggerAt: input)
                row.quietStartMinute = start; row.quietEndMinute = end; row.retryIntervalsMinutes = [15]; row.maxReminderAttempts = 4
                let chain = ReminderPolicy.deliveryDates(for: row, now: input.addingTimeInterval(-1), calendar: berlin)
                precondition(chain.count == 4 && chain.first == expected)
                for retry in chain {
                    let m = berlin.component(.hour, from: retry) * 60 + berlin.component(.minute, from: retry)
                    precondition(!(start < end ? m >= start && m < end : m >= start || m < end))
                }
            }
        }
        precondition(ReminderPolicy(quietStart: 60, quietEnd: 150).adjust(local(3, 29, 1, 30), calendar: berlin) == local(3, 29, 3))
        let first0230 = berlin.date(bySettingHour: 2, minute: 30, second: 0, of: local(10, 25, 0), matchingPolicy: .nextTime, repeatedTimePolicy: .first)!
        precondition(ReminderPolicy(quietStart: 60, quietEnd: 150).adjust(local(10, 25, 1, 30), calendar: berlin) == first0230)
        try await sync(now: now)
        print("Final review historical editor / DST / live sync checks passed")
    }

    static func sync(now: Date) async throws {
        let box = try ModelContainer(for: Reminder.self, ReminderRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let c = box.mainContext
        SyncStore.setLocalVersion(100)
        let android = Reminder(title: "Android 100", firstTriggerAt: now, nextTriggerAt: now.addingTimeInterval(86400))
        var server = BackupHelper.exportJSON([android]); var puts = 0
        let android100 = server
        var transport = WebDavSync.Transport(download: { WebDavSync.Remote(json: server, etag: "v1") },
            upload: { json, _ in server = json; puts += 1 }, restore: {})
        SyncStore.setLocalVersion(0); SyncStore.setLastSyncVersion(0)
        UserDefaults.standard.removeObject(forKey: "sync_remote_stamp_v3")
        guard case .success = await WebDavSync.syncNow(reminders: [], modelContext: c, transport: transport) else { fatalError("Fresh pull") }
        precondition(SyncStore.localVersion >= 100 && puts == 0)
        let pulled = try c.fetch(FetchDescriptor<Reminder>()).first!
        pulled.title = "iOS edit survives"; precondition(ReminderActions.changed(pulled, context: c))
        guard case .success = await WebDavSync.syncNow(reminders: [pulled], modelContext: c, transport: transport) else { fatalError("iOS upload") }
        precondition(BackupHelper.dataVersion(of: server) > 100 && puts == 1)
        precondition(BackupHelper.importJSON(server)!.first!.title == "iOS edit survives")
        try server.write(toFile: "ios-sync-edit-v3.json", atomically: true, encoding: .utf8)
        for localChoice in [true, false] {
            server = android100
            pulled.title = "Local alternative"
            precondition(ReminderActions.changed(pulled, context: c))
            SyncStore.setLocalVersion(200); SyncStore.setLastSyncVersion(199)
            let before = puts
            guard case .conflict = await WebDavSync.syncNow(reminders: [pulled], modelContext: c, transport: transport) else { fatalError("Concurrent conflict") }
            precondition(puts == before)
            guard case .success = await WebDavSync.resolve(localChoice ? .local : .remote, context: c, transport: transport) else { fatalError("Explicit resolution") }
            precondition(BackupHelper.dataVersion(of: server) > 200 && puts == before + 1)
            precondition(BackupHelper.importJSON(server)!.first!.title == (localChoice ? "Local alternative" : "Android 100"))
        }
        let only = Reminder(title: "Local only", firstTriggerAt: now, nextTriggerAt: now.addingTimeInterval(172800))
        c.insert(only); try c.save(); SyncStore.touchLocalChange()
        server = android100
        guard case .conflict = await WebDavSync.syncNow(reminders: [pulled, only], modelContext: c, transport: transport) else { fatalError("Local-only conflict") }
        guard case .success = await WebDavSync.resolve(.remote, context: c, transport: transport) else { fatalError("Retained merge") }
        precondition(BackupHelper.importJSON(server)!.contains { $0.stableID == only.id })
        let captured = SyncStore.localVersion
        pulled.note = "before await"; precondition(ReminderActions.changed(pulled, context: c))
        transport = WebDavSync.Transport(download: { WebDavSync.Remote(json: server, etag: "v1") }, upload: { json, _ in
            pulled.note = "during await"; precondition(ReminderActions.changed(pulled, context: c)); await Task.yield(); server = json
        }, restore: {})
        guard case .success = await WebDavSync.syncNow(reminders: [pulled, only], modelContext: c, transport: transport) else { fatalError("Concurrent upload") }
        precondition(SyncStore.lastSyncVersion == captured + 1 && SyncStore.localVersion > SyncStore.lastSyncVersion)
        precondition(BackupHelper.importJSON(server)!.first { $0.stableID == pulled.id }!.note == "before await")
    }
}
