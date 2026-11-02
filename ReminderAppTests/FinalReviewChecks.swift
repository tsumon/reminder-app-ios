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
        let defaults = UserDefaults.standard
        let saved = SyncConflictChecks.keys.map { ($0, defaults.object(forKey: $0)) }
        let removed = SyncDeletionLedger.reminders, records = SyncDeletionLedger.records
        defer {
            for (key, value) in saved { if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } }
            SyncDeletionLedger.store(reminders: removed, records: records)
        }
        for key in SyncConflictChecks.keys { defaults.removeObject(forKey: key) }
        SyncDeletionLedger.store(reminders: [], records: [])
        let box = try ModelContainer(for: Reminder.self, ReminderRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let c = box.mainContext
        SyncStore.setLocalVersion(100)
        let android = Reminder(title: "Android 100", firstTriggerAt: now, nextTriggerAt: now.addingTimeInterval(86400))
        var server = BackupHelper.exportJSON([android]); var puts = 0
        let android100 = server
        var transport = WebDavSync.Transport(download: { WebDavSync.Remote(json: server, etag: "v1") },
            upload: { json, _ in server = json; puts += 1 }, restore: {}, snapshot: { _ in })
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
            pulled.title = localChoice ? "Local alternative" : "Second local alternative"
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
        server = android100.replacingOccurrences(of: "Android 100", with: "Android changed again")
        guard case .conflict = await WebDavSync.syncNow(reminders: [pulled, only], modelContext: c, transport: transport) else { fatalError("Local-only conflict") }
        guard case .success = await WebDavSync.resolve(.remote, context: c, transport: transport) else { fatalError("Retained merge") }
        precondition(BackupHelper.importJSON(server)!.contains { $0.stableID == only.id })
        let captured = SyncStore.localVersion
        pulled.note = "before await"; precondition(ReminderActions.changed(pulled, context: c))
        transport = WebDavSync.Transport(download: { WebDavSync.Remote(json: server, etag: "v1") }, upload: { json, _ in
            pulled.note = "during await"; precondition(ReminderActions.changed(pulled, context: c)); await Task.yield(); server = json
        }, restore: {}, snapshot: { _ in })
        guard case .success = await WebDavSync.syncNow(reminders: [pulled, only], modelContext: c, transport: transport) else { fatalError("Concurrent upload") }
        precondition(SyncStore.lastSyncVersion == captured + 1 && SyncStore.localVersion > SyncStore.lastSyncVersion)
        precondition(BackupHelper.importJSON(server)!.first { $0.stableID == pulled.id }!.note == "before await")
    }
}


/// Synthetic in-memory transport only. Never reads credentials or contacts WebDAV.
@MainActor enum SyncConflictChecks {
    static let keys = ["sync_local_version", "sync_last_sync_version", "sync_last_sync", "sync_has_synced_once", "sync_remote_stamp_v3", "sync_remote_content_stamp_v4", "sync_local_content_stamp_v4", "sync_pending_upload_v4"]
    static func runChild(_ path: String) async throws {
        let payload = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [String: String]
        let box = try ModelContainer(for: Reminder.self, ReminderRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let c = box.mainContext
        for item in BackupHelper.importJSON(payload["local"]!)! { c.insert(BackupHelper.makeReminder(from: item)) }
        try c.save()
        let expectedWrites = payload["expectUpload"] == "1" ? 1 : 0
        var writes = 0, uploaded = ""
        let transport = WebDavSync.Transport(download: { WebDavSync.Remote(json: payload["remote"], etag: "child-etag") }, upload: { json, replacing in
            precondition(replacing.etag == "child-etag")
            writes += 1; uploaded = json
        }, restore: {}, snapshot: { _ in fatalError("Restart must not merge") })
        guard case .success = await WebDavSync.syncNow(reminders: [], modelContext: c, transport: transport) else { fatalError("Restart repeated a resolved conflict") }
        if writes != expectedWrites {
            FileHandle.standardError.write(Data("FAIL restart expected \(expectedWrites) PUT, got \(writes)\n".utf8))
            throw NSError(domain: "SyntheticSyncRestart", code: 1)
        }
        if expectedWrites == 1 { try uploaded.write(toFile: path + ".uploaded", atomically: true, encoding: .utf8) }
        print("PASS fresh process reloaded persisted sync baseline and publication intent")
    }
    static func run() async throws {
        precondition(Bundle.main.bundleIdentifier != "com.reminder.app", "Synthetic checks must never run in the real app domain")
        let defaults = UserDefaults.standard
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        let removed = SyncDeletionLedger.reminders, records = SyncDeletionLedger.records
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("reminder-sync-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            for (key, value) in saved { if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } }
            SyncDeletionLedger.store(reminders: removed, records: records)
            try? FileManager.default.removeItem(at: directory)
        }
        for key in keys { defaults.removeObject(forKey: key) }
        SyncDeletionLedger.store(reminders: [], records: [])
        let box = try ModelContainer(for: Reminder.self, ReminderRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let c = box.mainContext
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let row = Reminder(title: "Synthetic baseline", firstTriggerAt: now, nextTriggerAt: now)
        row.createdAt = now; row.updatedAt = now
        row.records.append(ReminderRecord(performedAt: now, type: .confirm, note: "preserve-note"))
        c.insert(row); try c.save(); SyncStore.setLocalVersion(7)
        var server: String? = nil, etag = "initial"
        var puts = 0, snapshots = 0, failDownload = false, refuseUpload = false, refuseSnapshot = false
        let transport = WebDavSync.Transport(download: {
            if failDownload { throw URLError(.notConnectedToInternet) }
            return WebDavSync.Remote(json: server, etag: server == nil ? nil : etag)
        }, upload: { json, expected in
            precondition(expected.json == server && expected.etag == (server == nil ? nil : etag), "conditional replacement snapshot retained")
            if refuseUpload { throw URLError(.notConnectedToInternet) }
            server = json; puts += 1; etag += "x"
        }, restore: {}, snapshot: { _ in
            if refuseSnapshot { throw URLError(.cannotWriteToFile) }
            snapshots += 1
        })
        var assertions = 0
        func check(_ value: Bool, _ name: String) {
            if !value { FileHandle.standardError.write(Data(("FAIL: " + name + "\n").utf8)); preconditionFailure(name) }
            assertions += 1; print("PASS " + name)
        }
        func success(_ value: WebDavSync.SyncResult, _ name: String) { guard case .success = value else { fatalError("FAIL: " + name) }; assertions += 1; print("PASS " + name) }
        func conflict(_ value: WebDavSync.SyncResult, _ name: String) { guard case .conflict = value else { fatalError("FAIL: " + name) }; assertions += 1; print("PASS " + name) }
        func failure(_ value: WebDavSync.SyncResult, _ name: String) { guard case .failure = value else { fatalError("FAIL: " + name) }; assertions += 1; print("PASS " + name) }
        func mutate(_ input: String, title: String? = nil, cosmetic: Bool = false) throws -> String {
            var root = try JSONSerialization.jsonObject(with: Data(input.utf8)) as! [String: Any]
            if cosmetic { root["exportedAt"] = 2_000_000_000_000.0; root["dataVersion"] = 1000 }
            if let title { var items = root["reminders"] as! [[String: Any]]; items[0]["title"] = title; root["reminders"] = items }
            return String(decoding: try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]), as: UTF8.self)
        }
        func restart(expectedUpload: Bool = false) throws {
            let file = directory.appendingPathComponent("restart.json")
            let local = BackupHelper.exportJSON(try c.fetch(FetchDescriptor<Reminder>()), exportedAt: 0)
            try JSONSerialization.data(withJSONObject: ["local": local, "remote": server!, "expectUpload": expectedUpload ? "1" : "0"]).write(to: file)
            defaults.synchronize()
            let child = Process(); child.executableURL = Bundle.main.executableURL!
            child.arguments = ["--sync-conflict-child", file.path]
            child.standardError = FileHandle.standardError
            try child.run(); child.waitUntilExit(); defaults.synchronize()
            check(child.terminationStatus == 0, expectedUpload ? "pending publication survives restart with one PUT" : "successful baseline survives process restart with zero PUT/merge")
            if expectedUpload { server = try String(contentsOfFile: file.path + ".uploaded", encoding: .utf8); puts += 1; etag += "child" }
        }
        success(await WebDavSync.syncNow(reminders: [row], modelContext: c, transport: transport), "initial synthetic upload")
        let initial = server!
        // Same data in another serializer/order must retain its identity, while real
        // field changes (including unknown future fields) must remain detectable.
        var ordered = try JSONSerialization.jsonObject(with: Data(initial.utf8)) as! [String: Any]
        let removedID = UUID(), removedRecordID = UUID()
        ordered["deletedReminderIds"] = [removedID.uuidString]
        ordered["deletedRecordIds"] = [removedRecordID.uuidString]
        var orderedItems = ordered["reminders"] as! [[String: Any]]
        var second = orderedItems[0]; second["syncId"] = UUID().uuidString; second["title"] = "Other synthetic"
        orderedItems.append(second)
        var history = orderedItems[0]["records"] as! [[String: Any]]
        var anotherRecord = history[0]; anotherRecord["id"] = UUID().uuidString; anotherRecord["note"] = "other note"; history.append(anotherRecord)
        orderedItems[0]["records"] = history; ordered["reminders"] = orderedItems
        func wire(_ object: [String: Any]) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self) }
        let orderedWire = try wire(ordered)
        var reordered = ordered
        orderedItems[0]["records"] = Array(history.reversed())
        orderedItems[0]["syncId"] = (orderedItems[0]["syncId"] as! String).uppercased()
        reordered["reminders"] = Array(orderedItems.reversed())
        reordered["deletedReminderIds"] = [removedID.uuidString.lowercased(), removedID.uuidString]
        reordered["deletedRecordIds"] = [removedRecordID.uuidString.lowercased()]
        reordered["exportedAt"] = 1; reordered["dataVersion"] = 999
        check(WebDavSync.contentStamp(orderedWire) == WebDavSync.contentStamp(try wire(reordered)), "ordering/casing/duplicate tombstones/clock do not change content")
        var unknown = ordered; unknown["futureRule"] = "different"
        check(WebDavSync.contentStamp(orderedWire) != WebDavSync.contentStamp(try wire(unknown)), "unknown future fields are not ignored")
        var nestedFuture = ordered; nestedFuture["futureRule"] = ["reminders": ["updatedAt": 1]]
        let oldNested = try wire(nestedFuture); nestedFuture["futureRule"] = ["reminders": ["updatedAt": 2]]
        check(WebDavSync.contentStamp(oldNested) != WebDavSync.contentStamp(try wire(nestedFuture)), "unknown nested clocks are not stripped")
        nestedFuture["futureRule"] = ["records": ["a", "b"]]
        let oldFutureOrder = try wire(nestedFuture); nestedFuture["futureRule"] = ["records": ["b", "a"]]
        check(WebDavSync.contentStamp(oldFutureOrder) != WebDavSync.contentStamp(try wire(nestedFuture)), "unknown array ordering is not ignored")
        orderedItems = ordered["reminders"] as! [[String: Any]]; orderedItems[0]["retryIntervalsMinutes"] = [240,60]
        var policyChanged = ordered; policyChanged["reminders"] = orderedItems
        check(WebDavSync.contentStamp(orderedWire) != WebDavSync.contentStamp(try wire(policyChanged)), "retry interval ordering remains meaningful")
        var historyChanged = ordered; orderedItems = ordered["reminders"] as! [[String: Any]]
        var changedRecords = orderedItems[0]["records"] as! [[String: Any]]; changedRecords[0]["note"] = "real changed note"
        orderedItems[0]["records"] = changedRecords; historyChanged["reminders"] = orderedItems
        check(WebDavSync.contentStamp(orderedWire) != WebDavSync.contentStamp(try wire(historyChanged)), "history notes remain meaningful")
        var actualDeletion = ordered; actualDeletion["deletedReminderIds"] = [UUID().uuidString]
        check(WebDavSync.contentStamp(orderedWire) != WebDavSync.contentStamp(try wire(actualDeletion)), "new tombstones remain meaningful")
        row.title = "Local edit"; check(ReminderActions.changed(row, context: c), "local real edit")
        server = try mutate(initial, cosmetic: true)
        success(await WebDavSync.syncNow(reminders: [row], modelContext: c, transport: transport), "metadata rewrite must not conflict with a real local edit")
        check(puts == 2 && BackupHelper.dataVersion(of: server!) > 1000, "upload retains content and advances remote counter floor")
        try restart()
        let beforeNoop = puts
        success(await WebDavSync.syncNow(reminders: [row], modelContext: c, transport: transport), "unchanged repeated foreground sync")
        check(puts == beforeNoop, "unchanged sync has zero PUT")
        for key in ["sync_remote_stamp_v3", "sync_remote_content_stamp_v4", "sync_local_content_stamp_v4", "sync_pending_upload_v4"] { defaults.removeObject(forKey: key) }
        success(await WebDavSync.syncNow(reminders: [row], modelContext: c, transport: transport), "equal existing data establishes missing legacy baseline without choosing a side")
        check(puts == beforeNoop, "baseline repair never overwrites cloud data")
        // A generation-only no-op is not a local content edit; a real remote edit pulls safely.
        SyncStore.touchLocalChange(); row.updatedAt = Date()
        server = try mutate(server!, title: "Remote-only edit")
        success(await WebDavSync.syncNow(reminders: [row], modelContext: c, transport: transport), "no-op local generation does not create false bilateral conflict")
        check(row.title == "Remote-only edit", "remote-only real data retained")
        try restart()
        for localChoice in [true, false] {
            row.title = localChoice ? "Local chosen" : "Local alternative"; check(ReminderActions.changed(row, context: c), "true local change")
            server = try mutate(server!, title: "Remote chosen")
            let priorPuts = puts, priorSync = SyncStore.lastSyncAt, priorAck = SyncStore.lastSyncVersion
            conflict(await WebDavSync.syncNow(reminders: [row], modelContext: c, transport: transport), "true bilateral conflict still asks")
            check(puts == priorPuts && SyncStore.lastSyncAt == priorSync, "conflict never uploads or marks success")
            // Cancel invokes no resolution. The unresolved changes must not be acknowledged/hidden.
            conflict(await WebDavSync.syncNow(reminders: [row], modelContext: c, transport: transport), "cancel retains unresolved true conflict")
            check(SyncStore.lastSyncVersion == priorAck, "cancel does not mark revisions synchronized")
            success(await WebDavSync.resolve(localChoice ? .local : .remote, context: c, transport: transport), "explicit choice succeeds")
            check(row.title == (localChoice ? "Local chosen" : "Remote chosen"), "chosen revision survives")
            check(row.records.count == 1 && row.records[0].note == "preserve-note", "history identity and note not duplicated/lost")
            try restart()
        }
        // Failed PUT after a remote merge requiring retained local data: consumed remote
        // baseline persists, but successful generation/time must not advance.
        let only = Reminder(title: "Local-only retained", firstTriggerAt: now, nextTriggerAt: now)
        only.createdAt = now; only.updatedAt = now; c.insert(only); try c.save(); SyncStore.touchLocalChange()
        server = try mutate(server!, title: "Remote merge pending")
        conflict(await WebDavSync.syncNow(reminders: [], modelContext: c, transport: transport), "local-only versus remote change conflict")
        let beforeFailure = SyncStore.lastSyncAt, ackBeforeFailure = SyncStore.lastSyncVersion, putsBeforeFailure = puts
        refuseUpload = true
        failure(await WebDavSync.resolve(.remote, context: c, transport: transport), "merged PUT failure reported")
        check(SyncStore.lastSyncAt == beforeFailure && SyncStore.lastSyncVersion == ackBeforeFailure, "failed merged PUT never marks successful sync")
        let retainedRows = try c.fetch(FetchDescriptor<Reminder>())
        check(row.title == "Remote merge pending" && retainedRows.contains { $0.id == only.id }, "durable merge preserves both remote and local-only data")
        refuseUpload = false
        success(await WebDavSync.syncNow(reminders: [], modelContext: c, transport: transport), "retry consumed remote revision without repeating conflict choice")
        check(puts == putsBeforeFailure + 1, "retry performs one conditional PUT")
        try restart()
        // A peer omits a local-only reminder without a tombstone. Merge retains it,
        // so the local content can equal its *old* baseline despite a required PUT.
        var omitted = try JSONSerialization.jsonObject(with: Data(server!.utf8)) as! [String: Any]
        omitted["reminders"] = (omitted["reminders"] as! [[String: Any]]).filter { ($0["syncId"] as? String)?.lowercased() != only.id.uuidString.lowercased() }
        server = try wire(omitted)
        let omittedFailureTime = SyncStore.lastSyncAt
        refuseUpload = true
        failure(await WebDavSync.syncNow(reminders: [], modelContext: c, transport: transport), "retained unchanged local data still requires publication")
        check(SyncStore.lastSyncAt == omittedFailureTime, "retained-data PUT failure does not acknowledge success")
        refuseUpload = false
        try restart(expectedUpload: true)
        check(BackupHelper.importJSON(server!)!.contains { $0.stableID == only.id }, "restart repairs omitted local-only reminder on server")
        // Local choice PUT failure follows the same acknowledgement rule.
        row.title = "Chosen local retry"; check(ReminderActions.changed(row, context: c), "local choice edit")
        server = try mutate(server!, title: "Remote alternative retry")
        conflict(await WebDavSync.syncNow(reminders: [], modelContext: c, transport: transport), "second real bilateral conflict")
        let localFailureTime = SyncStore.lastSyncAt, localFailureAck = SyncStore.lastSyncVersion
        refuseUpload = true
        failure(await WebDavSync.resolve(.local, context: c, transport: transport), "local choice PUT failure reported")
        check(SyncStore.lastSyncAt == localFailureTime && SyncStore.lastSyncVersion == localFailureAck, "local failed PUT never marks success")
        refuseUpload = false
        success(await WebDavSync.syncNow(reminders: [], modelContext: c, transport: transport), "local choice retry preserves the explicitly chosen revision")
        check(BackupHelper.importJSON(server!)!.first { $0.stableID == row.id }!.title == "Chosen local retry", "local choice payload survives failure")
        try restart()
        let offlineTime = SyncStore.lastSyncAt
        failDownload = true
        failure(await WebDavSync.syncNow(reminders: [], modelContext: c, transport: transport), "offline download reports failure")
        check(SyncStore.lastSyncAt == offlineTime, "offline launch never marks success")
        failDownload = false
        success(await WebDavSync.syncNow(reminders: [], modelContext: c, transport: transport), "network recovery no conflict")
        // Invalid remote data and save rejection must never acknowledge successful sync.
        let validServer = server!, beforeInvalid = SyncStore.lastSyncAt, invalidPuts = puts
        server = "{broken"
        failure(await WebDavSync.syncNow(reminders: [], modelContext: c, transport: transport), "invalid remote JSON refused")
        check(SyncStore.lastSyncAt == beforeInvalid && puts == invalidPuts, "parse failure leaves baseline/cloud untouched")
        server = validServer
        let deniedURL = directory.appendingPathComponent("read-only.store")
        func seedReadOnlyStore() throws {
            let seed = try ModelContainer(for: Reminder.self, ReminderRecord.self, configurations: ModelConfiguration(url: deniedURL))
            try seed.mainContext.save()
        }
        try seedReadOnlyStore()
        let deniedBox = try ModelContainer(for: Reminder.self, ReminderRecord.self, configurations: ModelConfiguration(url: deniedURL, allowsSave: false))
        let stampBeforeSave = defaults.string(forKey: "sync_remote_content_stamp_v4")
        let localBeforeSave = SyncStore.localVersion
        server = try mutate(validServer, title: "Remote save rejection")
        failure(await WebDavSync.syncNow(reminders: [], modelContext: deniedBox.mainContext, transport: transport), "read-only local model rejects merge")
        check(SyncStore.lastSyncAt == beforeInvalid && SyncStore.localVersion == localBeforeSave && defaults.string(forKey: "sync_remote_content_stamp_v4") == stampBeforeSave, "save failure leaves successful/observed baselines untouched")
        server = validServer
        // Already-synced old installations only have the raw v3 hash. Matching raw
        // revision remains usable; it must not manufacture a new conflict.
        defaults.removeObject(forKey: "sync_remote_content_stamp_v4"); defaults.removeObject(forKey: "sync_local_content_stamp_v4")
        row.note = "Legacy baseline local edit"; check(ReminderActions.changed(row, context: c), "old baseline local edit")
        success(await WebDavSync.syncNow(reminders: [], modelContext: c, transport: transport), "legacy raw baseline migrates without losing local edit")
        defaults.removeObject(forKey: "sync_remote_content_stamp_v4"); defaults.removeObject(forKey: "sync_local_content_stamp_v4")
        row.note = "Legacy edit without generation bump"; try c.save()
        check(SyncStore.localVersion == SyncStore.lastSyncVersion, "legacy untracked content fixture has unchanged generation")
        success(await WebDavSync.syncNow(reminders: [], modelContext: c, transport: transport), "known unchanged raw remote baseline preserves untracked legacy content")
        check(BackupHelper.importJSON(server!)!.first { $0.stableID == row.id }!.note == "Legacy edit without generation bump", "legacy content difference is uploaded, not falsely acknowledged")
        // Read a genuine older envelope with legacy id and absent policy/history fields.
        var legacy = try JSONSerialization.jsonObject(with: Data(server!.utf8)) as! [String: Any]
        legacy.removeValue(forKey: "schemaVersion"); legacy.removeValue(forKey: "dataVersion")
        var legacyItems = legacy["reminders"] as! [[String: Any]]
        for index in legacyItems.indices {
            legacyItems[index]["id"] = legacyItems[index].removeValue(forKey: "syncId")
            for key in ["records","createdAt","updatedAt","recurrenceMode","reminderStyle","retryIntervalsMinutes","maxReminderAttempts","scheduledOccurrenceAt","timeZoneMode"] { legacyItems[index].removeValue(forKey: key) }
        }
        legacyItems[0]["title"] = "Legacy remote selected"; legacy["reminders"] = legacyItems
        row.title = "Local legacy alternative"; check(ReminderActions.changed(row, context: c), "real local change against old format")
        server = try wire(legacy)
        conflict(await WebDavSync.syncNow(reminders: [], modelContext: c, transport: transport), "different legacy data remains a real conflict")
        success(await WebDavSync.resolve(.remote, context: c, transport: transport), "legacy remote choice merges compatible fields")
        check(row.records.count == 1 && row.records[0].note == "preserve-note", "old protocol cannot erase newer stable history")
        try restart()
        let staleBeforeDeletion = server!
        var withDeletion = try JSONSerialization.jsonObject(with: Data(server!.utf8)) as! [String: Any]
        withDeletion["deletedReminderIds"] = [only.id.uuidString]
        withDeletion["deletedRecordIds"] = [row.records[0].id.uuidString]
        server = try wire(withDeletion)
        row.note = "Local edit with deletion"; check(ReminderActions.changed(row, context: c), "real local change with remote tombstones")
        conflict(await WebDavSync.syncNow(reminders: [], modelContext: c, transport: transport), "new deletion participates in true conflict")
        success(await WebDavSync.resolve(.local, context: c, transport: transport), "local choice still honors remote tombstones")
        let afterDeletion = try c.fetch(FetchDescriptor<Reminder>())
        check(row.records.isEmpty && !afterDeletion.contains { $0.id == only.id }, "deleted reminder and undone history cannot revive")
        try restart()
        server = staleBeforeDeletion
        success(await WebDavSync.syncNow(reminders: [], modelContext: c, transport: transport), "old writer losing tombstones repaired without resurrection")
        let afterStale = try c.fetch(FetchDescriptor<Reminder>())
        check(row.records.isEmpty && !afterStale.contains { $0.id == only.id }, "permanent deletion ledger survives stale file")
        try restart()
        // Raw stamp + ETag guard is intentionally stricter than content equivalence.
        row.note = "New local note"; check(ReminderActions.changed(row, context: c), "local concurrent edit")
        server = try mutate(server!, title: "Concurrent remote")
        conflict(await WebDavSync.syncNow(reminders: [], modelContext: c, transport: transport), "concurrent decision fixture")
        let guardPuts = puts; etag += "changed"
        failure(await WebDavSync.resolve(.local, context: c, transport: transport), "changed ETag invalidates stale conflict choice")
        check(puts == guardPuts, "stale choice performs zero PUT")
        conflict(await WebDavSync.syncNow(reminders: [], modelContext: c, transport: transport), "refresh detects current real conflict")
        refuseSnapshot = true
        failure(await WebDavSync.resolve(.remote, context: c, transport: transport), "backup failure stops resolution")
        check(row.note == "New local note" && puts == guardPuts, "backup failure leaves data and cloud unchanged")
        check(snapshots > 0, "resolutions retained snapshot-before-merge behavior")
        // A deletion-only local state is still a local side of a bilateral conflict.
        for key in keys { defaults.removeObject(forKey: key) }
        SyncDeletionLedger.store(reminders: [], records: [])
        refuseSnapshot = false; refuseUpload = false; server = nil
        let deletionBox = try ModelContainer(for: Reminder.self, ReminderRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let doomed = Reminder(title: "Delete-only local", firstTriggerAt: now, nextTriggerAt: now)
        deletionBox.mainContext.insert(doomed); try deletionBox.mainContext.save(); SyncStore.touchLocalChange()
        success(await WebDavSync.syncNow(reminders: [], modelContext: deletionBox.mainContext, transport: transport), "deletion-only baseline upload")
        let priorDeletionWire = server!
        check(ReminderActions.delete(doomed, context: deletionBox.mainContext), "local deletion persists tombstone")
        server = try mutate(priorDeletionWire, title: "Concurrent remote edit of deleted identity")
        conflict(await WebDavSync.syncNow(reminders: [], modelContext: deletionBox.mainContext, transport: transport), "empty local rows plus new tombstone still protect a true bilateral conflict")
        print("ALL synthetic startup conflict regressions passed: \(assertions) checks")
    }
}
