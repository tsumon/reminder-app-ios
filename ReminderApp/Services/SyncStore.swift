import Foundation
#if canImport(Security)
import Security
#endif

/// WebDAV 同步设置存储（UserDefaults + Keychain）
enum SyncStore {
    private static let defaults = UserDefaults.standard
    private static let kURL = "sync_url"
    private static let kUser = "sync_user"
    private static let kPass = "sync_pass"
    private static let kAuto = "sync_auto"
    private static let kLastChange = "sync_last_local_change"
    private static let kLastSync = "sync_last_sync"
    // v2.0.17: 单调版本——墙钟可回拨/双端时钟有偏差，判新改用自增版本，时间戳仅兜底
    private static let kLocalVersion = "sync_local_version"
    private static let kLastSyncVersion = "sync_last_sync_version"

    static var url: String { defaults.string(forKey: kURL) ?? "" }
    static var username: String { defaults.string(forKey: kUser) ?? "" }

    /// 密码存于 Keychain，避免明文写入 UserDefaults
    static var password: String {
        get { KeychainHelper.read(service: "reminder_webdav", account: "password") ?? "" }
        set { KeychainHelper.save(newValue, service: "reminder_webdav", account: "password") }
    }

    static var autoSync: Bool { defaults.bool(forKey: kAuto) }

    /// 本地数据最后一次变更（秒）
    static var lastLocalChange: TimeInterval { defaults.double(forKey: kLastChange) }
    static var lastSyncAt: TimeInterval { defaults.double(forKey: kLastSync) }

    /// 本地自增单调版本（v2.0.17：判新主依据，防墙钟回拨/时钟偏差）
    static var localVersion: Int { defaults.integer(forKey: kLocalVersion) }
    /// 上次成功同步时的本地版本（冲突判定用；0 = 从未同步过）
    static var lastSyncVersion: Int { defaults.integer(forKey: kLastSyncVersion) }

    static var isConfigured: Bool {
        !url.isEmpty && !username.isEmpty && !password.isEmpty
    }

    static func save(url: String, username: String, password: String, autoSync: Bool) {
        defaults.set(url.trimmingCharacters(in: .whitespaces), forKey: kURL)
        defaults.set(username.trimmingCharacters(in: .whitespaces), forKey: kUser)
        self.password = password // 经 setter 存入 Keychain
        defaults.set(autoSync, forKey: kAuto)
    }

    /// 标记本地数据发生了变更（秒）
    static func touchLocalChange() {
        defaults.set(Date().timeIntervalSince1970, forKey: kLastChange)
        // v2.0.17: 单调版本同步 +1（判新主依据）
        defaults.set(localVersion + 1, forKey: kLocalVersion)
    }

    /// 同步下载覆盖本地后，将本地版本对齐到远程版本（秒）
    static func setLastLocalChange(_ value: TimeInterval) {
        defaults.set(value, forKey: kLastChange)
    }

    /// v2.0.17: 对齐本地单调版本（下载覆盖后 = 远程 dataVersion）
    static func setLocalVersion(_ value: Int) {
        defaults.set(value, forKey: kLocalVersion)
    }

    /// v2.0.17: 记录上次成功同步时的本地版本
    static func setLastSyncVersion(_ value: Int) {
        defaults.set(value, forKey: kLastSyncVersion)
    }

    static func setLastSync() {
        defaults.set(Date().timeIntervalSince1970, forKey: kLastSync)
    }
}

#if canImport(Security)
/// 极简 Keychain 封装：把少量敏感字段（如 WebDAV 密码、AI API Key）加密存于 Keychain，
/// 而非明文 UserDefaults。internal 可见性，供 AISettings 等复用。
struct KeychainHelper {
    static func save(_ value: String, service: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        let addQuery = query.merging([
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]) { _, new in new }
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
#endif
