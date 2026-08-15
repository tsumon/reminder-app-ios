import Foundation

/// v2.1.1: 本地自动备份——自签环境没有 iCloud，把数据定期写到「文件」App 可见的目录兜底。
/// 策略：启动时写一份当日备份；手动可随时再备份；保留最近 5 份。
enum LocalBackupService {

    private static var dir: URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let d = docs.appendingPathComponent("ReminderBackups", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static var backups: [URL] {
        guard let dir else { return [] }
        return (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } ?? []
    }

    /// 启动时调用：当日同名文件已存在则跳过（避免每次启动都写）
    static func backupOnLaunch(reminders: [Reminder]) {
        guard let dir else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let name = "reminder_backup_\(formatter.string(from: Date())).json"
        let target = dir.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: target.path) else { return }
        write(reminders, to: target)
    }

    /// 立即备份，返回文件 URL（失败返回 nil）
    @discardableResult
    static func backupNow(reminders: [Reminder]) -> URL? {
        guard let dir else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let target = dir.appendingPathComponent("reminder_backup_\(formatter.string(from: Date())).json")
        return write(reminders, to: target)
    }

    @discardableResult
    private static func write(_ reminders: [Reminder], to url: URL) -> URL? {
        let json = BackupHelper.exportJSON(reminders)
        do {
            try json.write(to: url, atomically: true, encoding: .utf8)
            trim()
            return url
        } catch {
            print("[LocalBackup] 写入失败: \(error)")
            return nil
        }
    }

    /// 只保留最近 5 份
    private static func trim() {
        let all = backups
        if all.count > 5 {
            for old in all.dropFirst(5) {
                try? FileManager.default.removeItem(at: old)
            }
        }
    }
}
