import Foundation
import SwiftData

enum MigrationValues {
    @MainActor static func populate(_ context: ModelContext) throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let r = Reminder(id: UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")!, title: "原有农历提醒", note: "保留全部旧值",
            kind: .date, cycle: .custom, customDays: 13, dateType: .lunarBirthday, targetMonth: 8, targetDay: 15,
            advanceDays: 7, reminderHour: 18, reminderMinute: 45, holidayID: "zhongqiu", rulePeriod: .yearly,
            ruleWeek: .w4, ruleWeekday: .fri, firstTriggerAt: date, nextTriggerAt: date.addingTimeInterval(500),
            status: .snoozed, priority: .high, retryStage: 3, isEnabled: false, holidayAware: true,
            createdAt: date.addingTimeInterval(-100), updatedAt: date.addingTimeInterval(100))
        r.lastRetryAt = date.addingTimeInterval(200)
        r.records = [ReminderRecord(id: UUID(uuidString: "bbbbbbbb-bbbb-4ccc-8ddd-eeeeeeeeeeee")!, performedAt: date, type: .confirm, note: "原有记录")]
        context.insert(r)
        for (i, status) in [ReminderStatus.pending, .active, .confirmed, .overdue].enumerated() {
            context.insert(Reminder(title: "status-\(i)", firstTriggerAt: date, nextTriggerAt: date.addingTimeInterval(Double(i)), status: status))
        }
        try context.save()
    }
    @MainActor static func bytes(_ context: ModelContext) throws -> Data {
        let rows = try context.fetch(FetchDescriptor<Reminder>()).sorted { $0.id.uuidString < $1.id.uuidString }.map { r -> [String: Any] in
            ["id": r.id.uuidString, "title": r.title, "note": r.note, "kind": r.kind.rawValue,
             "cycle": r.cycle.rawValue, "customDays": r.customDays, "dateType": r.dateType?.rawValue ?? "nil",
             "month": r.targetMonth, "day": r.targetDay, "advance": r.advanceDays, "hour": r.reminderHour,
             "minute": r.reminderMinute, "holiday": r.holidayID ?? "nil", "period": r.rulePeriod.rawValue,
             "week": r.ruleWeek.rawValue, "weekday": r.ruleWeekday.rawValue, "first": r.firstTriggerAt.timeIntervalSince1970,
             "next": r.nextTriggerAt.timeIntervalSince1970, "status": r.status.rawValue, "priority": r.priority.rawValue,
             "retry": r.retryStage, "lastRetry": r.lastRetryAt?.timeIntervalSince1970 ?? -1, "enabled": r.isEnabled,
             "holidayAware": r.holidayAware, "created": r.createdAt.timeIntervalSince1970, "updated": r.updatedAt.timeIntervalSince1970,
             "records": r.records.sorted { $0.id.uuidString < $1.id.uuidString }.map { ["id": $0.id.uuidString, "time": String($0.performedAt.timeIntervalSince1970), "type": $0.type, "note": $0.note] }]
        }
        return try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])
    }
    @MainActor static func container(_ path: String) throws -> ModelContainer {
        let schema = Schema(versionedSchema: ReminderSchemaV1.self)
        return try ModelContainer(for: schema, migrationPlan: ReminderMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, url: URL(fileURLWithPath: path))])
    }
}
