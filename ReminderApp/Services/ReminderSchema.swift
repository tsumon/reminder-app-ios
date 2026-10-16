import SwiftData

enum ReminderSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [Reminder.self, ReminderRecord.self] }
}

/// 迁移计划：v1 为唯一 schema，无迁移阶段
enum ReminderMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [ReminderSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

