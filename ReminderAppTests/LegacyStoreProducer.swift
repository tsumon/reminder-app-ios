import Foundation
@main struct LegacyStoreProducer {
    @MainActor static func main() throws {
        let path = CommandLine.arguments[1]
        let container = try MigrationValues.container(path)
        try MigrationValues.populate(container.mainContext)
        try MigrationValues.bytes(container.mainContext).write(to: URL(fileURLWithPath: path + ".expected.json"))
        print("Original v2.7.2 populated store saved: \(path)")
    }
}
