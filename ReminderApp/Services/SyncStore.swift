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
    }

    /// 同步下载覆盖本地后，将本地版本对齐到远程版本（秒）
    static func setLastLocalChange(_ value: TimeInterval) {
        defaults.set(value, forKey: kLastChange)
    }

    static func setLastSync() {
        defaults.set(Date().timeIntervalSince1970, forKey: kLastSync)
    }
}

#if canImport(Security)
/// 极简 Keychain 封装：把少量敏感字段（如 WebDAV 密码）加密存于 Keychain，
/// 而非明文 UserDefaults。
private struct KeychainHelper {
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
