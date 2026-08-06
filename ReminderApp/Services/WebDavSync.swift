import Foundation
import SwiftData
import WidgetKit

/// WebDAV 同步（与 Android 端同一策略：exportedAt 时间戳新者覆盖）
/// 注意单位：远程文件可能来自 Android（exportedAt 毫秒），统一转成秒比较
@MainActor
enum WebDavSync {
    private static let remoteFileName = "reminder_backup.json"

    enum SyncResult {
        case success
        case failure(String)
    }

    static func syncNow(reminders: [Reminder], modelContext: ModelContext) async -> SyncResult {
        guard SyncStore.isConfigured else {
            return .failure("请先配置 WebDAV 服务器")
        }

        let localVersion = SyncStore.lastLocalChange // 秒

        do {
            let remoteJson = try await download()

            guard let remoteJson else {
                // 远程无文件 → 上传本地
                let uploadJson = BackupHelper.exportJSON(
                    reminders,
                    exportedAt: max(Date().timeIntervalSince1970, localVersion + 1)
                )
                try await upload(uploadJson)
                SyncStore.setLastSync()
                return .success
            }

            guard let rawRemoteVersion = BackupHelper.exportedAt(of: remoteJson) else {
                return .failure("远程文件解析失败")
            }
            // 兼容 Android 的毫秒时间戳
            let remoteVersion = rawRemoteVersion > 1e11 ? rawRemoteVersion / 1000 : rawRemoteVersion

            if remoteVersion > localVersion {
                // 远程新 → 下载覆盖本地
                guard let items = BackupHelper.importJSON(remoteJson) else {
                    return .failure("远程文件解析失败")
                }
                replaceLocal(reminders, items: items, in: modelContext)
                SyncStore.setLastLocalChange(remoteVersion)
                SyncStore.setLastSync()
                return .success
            } else if localVersion > remoteVersion {
                // 本地新 → 上传
                let uploadJson = BackupHelper.exportJSON(
                    reminders,
                    exportedAt: max(Date().timeIntervalSince1970, remoteVersion + 1)
                )
                try await upload(uploadJson)
                SyncStore.setLastSync()
                return .success
            } else {
                SyncStore.setLastSync()
                return .success // 无变更
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - 覆盖本地

    private static func replaceLocal(
        _ current: [Reminder],
        items: [BackupHelper.BackupItem],
        in context: ModelContext
    ) {
        for r in current {
            context.delete(r)
        }
        for item in items {
            let reminder = BackupHelper.makeReminder(from: item)
            context.insert(reminder)
        }
        try? context.save()

        // 刷新小组件
        Task {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - WebDAV 请求

    private static func remoteURL() -> String {
        var base = SyncStore.url.trimmingCharacters(in: .whitespaces)
        if base.hasSuffix("/") { base.removeLast() }
        return "\(base)/\(remoteFileName)"
    }

    private static func authHeader() -> String {
        let raw = "\(SyncStore.username):\(SyncStore.password)"
        let encoded = Data(raw.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    private static func download() async throws -> String? {
        guard let url = URL(string: remoteURL()) else {
            throw SyncError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(authHeader(), forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { return nil }
        guard (200...299).contains(code) else {
            throw SyncError.http(code)
        }
        return String(data: data, encoding: .utf8)
    }

    private static func upload(_ json: String) async throws {
        guard let url = URL(string: remoteURL()) else {
            throw SyncError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 30
        request.setValue(authHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = json.data(using: .utf8)

        let (_, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            throw SyncError.http(code)
        }
    }

    private enum SyncError: LocalizedError {
        case invalidURL
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "WebDAV 地址无效"
            case .http(let code): return "HTTP \(code)"
            }
        }
    }
}
