import Foundation

/// WebDAV 同步设置存储（UserDefaults）
enum SyncStore {
    private static let defaults = UserDefaults.standard
    private static let kURL = "sync_url"
    private static let kUser = "sync_user"
    private static let kPass = "sync_pass"
    private static let kAuto = "sync_auto"
    private static let kLastChange = "sync_last_local_change"
    private static let kLastSync = "sync_last_sync"

    static var url: String { defaults.string(forKey: kURL) ?? "" }
    static var username: String { defaults.string(forKey: kUser) ?? "" }
    static var password: String { defaults.string(forKey: kPass) ?? "" }
    static var autoSync: Bool { defaults.bool(forKey: kAuto) }

    /// 本地数据最后一次变更（秒）
    static var lastLocalChange: TimeInterval { defaults.double(forKey: kLastChange) }
    static var lastSyncAt: TimeInterval { defaults.double(forKey: kLastSync) }

    static var isConfigured: Bool {
        !url.isEmpty && !username.isEmpty && !password.isEmpty
    }

    static func save(url: String, username: String, password: String, autoSync: Bool) {
        defaults.set(url.trimmingCharacters(in: .whitespaces), forKey: kURL)
        defaults.set(username.trimmingCharacters(in: .whitespaces), forKey: kUser)
        defaults.set(password, forKey: kPass)
        defaults.set(autoSync, forKey: kAuto)
    }

    /// 标记本地数据发生了变更（秒）
    static func touchLocalChange() {
        defaults.set(Date().timeIntervalSince1970, forKey: kLastChange)
    }

    /// 同步下载覆盖本地后，将本地版本对齐到远程版本（秒）
    static func setLastLocalChange(_ value: TimeInterval) {
        defaults.set(value, forKey: kLastChange)
    }

    static func setLastSync() {
        defaults.set(Date().timeIntervalSince1970, forKey: kLastSync)
    }
}
