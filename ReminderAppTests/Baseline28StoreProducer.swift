import Foundation
import SwiftData
@main struct Baseline28StoreProducer {
    @MainActor static func main() throws {
        let path=CommandLine.arguments[1]
        let container=try MigrationValues.container(path)
        defer { withExtendedLifetime(container) {} }
        let context=container.mainContext
        try MigrationValues.populate(context)
        for r in try context.fetch(FetchDescriptor<Reminder>()) {
            r.recurrenceMode="afterCompletion";r.reminderStyle="important";r.retryIntervalsMinutes=[15,45,180]
            r.maxReminderAttempts=7;r.quietStartMinute=1320;r.quietEndMinute=480;r.useAlarmKit=true
            r.policyMigrated=true;r.actionRevision=42;r.lastCompletedAt=Date(timeIntervalSince1970:1_799_000_000)
            r.undoCompletion=Data("persisted undo payload".utf8)
        }
        try context.save()
        try MigrationValues.bytes(context).write(to:URL(fileURLWithPath:path+".expected.json"))
        try Migration28Values.bytes(context).write(to:URL(fileURLWithPath:path+".policy.json"))
        print("Frozen v2.8.0 / build 70 model populated with non-default policies")
    }
}
