import Foundation
import SwiftData
@main struct Migration28Check {
    @MainActor static func main() throws {
        let path=CommandLine.arguments[1]
        let container=try MigrationValues.container(path)
        defer { withExtendedLifetime(container) {} }
        let context=container.mainContext
        let old=try Data(contentsOf:URL(fileURLWithPath:path+".expected.json"))
        let policy=try Data(contentsOf:URL(fileURLWithPath:path+".policy.json"))
        let actual=try MigrationValues.bytes(context), actualPolicy=try Migration28Values.bytes(context)
        precondition(old==actual && policy==actualPolicy,"2.8 values or history changed")
        let rows=try context.fetch(FetchDescriptor<Reminder>())
        precondition(rows.count==5 && rows.allSatisfy { $0.scheduledOccurrenceAt==nil })
        try context.save()
        print("Populated v2.8.0 -> v2.9.0 migration passed: all original fields, policies, undo payloads and history retained")
    }
}
