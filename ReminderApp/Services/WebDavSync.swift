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
            return .failure(friendlyMessage(error))
        }
    }

    // MARK: - 测试连接（添加 WebDAV 时验证账号/路径，坚果云友好提示）

    /// PROPFIND 验证连通性与认证；成功返回 .success
    static func testConnection() async -> SyncResult {
        guard SyncStore.isConfigured else {
            return .failure("请先填写 WebDAV 地址、用户名和应用密码")
        }
        do {
            let url = SyncStore.url.trimmingCharacters(in: .whitespaces)
            guard let u = URL(string: url) else { throw SyncError.invalidURL }
            var request = URLRequest(url: u)
            request.httpMethod = "PROPFIND"
            request.timeoutInterval = 15
            request.setValue(authHeader(), forHTTPHeaderField: "Authorization")
            request.setValue("0", forHTTPHeaderField: "Depth")

            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            // 207 Multi-Status 是 PROPFIND 的正常成功响应
            guard (200...299).contains(code) || code == 207 else {
                throw SyncError.http(code)
            }
            return .success
        } catch {
            return .failure(friendlyMessage(error))
        }
    }

    /// 把错误转成可操作的中文提示（尤其坚果云 401 应用密码）
    static func friendlyMessage(_ error: Error) -> String {
        if let se = error as? SyncError {
            switch se {
            case .invalidURL:
                return "WebDAV 地址无效。示例：https://dav.jianguoyun.com/dav/（坚果云必须以 /dav/ 结尾）"
            case .http(let code):
                switch code {
                case 401:
                    return "认证失败（HTTP 401）：请确认用户名；密码必须是坚果云「应用密码」——在坚果云网页端「账户信息 → 安全选项 → 添加应用密码」生成，不能用登录密码。"
                case 403:
                    return "无权限（HTTP 403）：请检查该 WebDAV 路径是否可写（如 dav.jianguoyun.com/dav/ 根目录）。"
                case 405:
                    return "服务器不支持该操作（HTTP 405）：请确认填的是 WebDAV 地址（如 …/dav/），不是网盘网页地址。"
                case 409:
                    return "资源冲突（HTTP 409）。"
                case 423:
                    return "资源被锁定（HTTP 423）。"
                case 507:
                    return "存储空间不足（HTTP 507）。"
                default:
                    return "HTTP \(code)：请检查服务器地址/账号，或稍后重试。"
                }
            }
        }
        if let ue = error as? URLError {
            switch ue.code {
            case .timedOut: return "连接超时：请检查网络或服务器地址。"
            case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
                return "无法连接服务器：请检查网络和地址。"
            case .userAuthenticationRequired: return "认证失败：请检查用户名和应用密码。"
            default: break
            }
        }
        return error.localizedDescription
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
