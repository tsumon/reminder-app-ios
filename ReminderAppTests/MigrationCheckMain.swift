import Foundation
import SwiftData
@main struct MigrationCheck {
    @MainActor static func main() throws {
        let path = CommandLine.arguments[1]
        let container = try MigrationValues.container(path)
        let expected = try Data(contentsOf: URL(fileURLWithPath: path + ".expected.json"))
        let actual = try MigrationValues.bytes(container.mainContext)
        precondition(actual == expected, "Old fields/IDs/history changed")
        let rows = try container.mainContext.fetch(FetchDescriptor<Reminder>())
        precondition(rows.count == 5)
        for r in rows {
            precondition(r.recurrenceMode == "fixed" && r.reminderStyle == "persistent")
            precondition(r.retryIntervalsMinutes == [60, 240, 720, 1440] && r.maxReminderAttempts == 5)
            precondition(r.quietStartMinute == nil && r.quietEndMinute == nil && r.actionRevision == 0)
        }
        try container.mainContext.save()
        print("Real populated v2.7.2 -> v2.8 migration passed; every old property and record retained")
    }
}
