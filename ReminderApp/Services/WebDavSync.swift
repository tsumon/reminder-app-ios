import Foundation
import CryptoKit
import SwiftData
import WidgetKit

/// WebDAV 同步（与 Android 端同一策略：exportedAt 时间戳新者覆盖）
/// 注意单位：远程文件可能来自 Android（exportedAt 毫秒），统一转成秒比较
@MainActor
enum WebDavSync {
    private static let remoteFileName = "reminder_backup.json"
    /// 批次3 功能4: 日历订阅用的 .ics 文件名（与备份 JSON 同目录）
    static let remoteICSFileName = "reminders.ics"

    enum SyncResult {
        case success(conflict: Bool)
        case conflict
        case failure(String)
    }
    enum ConflictChoice { case local, remote }
    struct Remote { let json: String?; let etag: String? }
    struct Conflict { let remote: Remote; let generation: Int }
    private static var pending: Conflict?
    private static var busy = false
    private static let remoteStampKey = "sync_remote_stamp_v3"

    static func stamp(_ json: String?) -> String {
        guard let json else { return "missing" }
        return SHA256.hash(data: Data(json.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    @MainActor struct Transport {
        var download: () async throws -> Remote
        var upload: (String, Remote) async throws -> Void
        var restore: () async -> Void
        var isConfigured: Bool = true
        static var live: Transport { Transport(download: { try await WebDavSync.download() },
            upload: { try await WebDavSync.upload($0, replacing: $1) }, restore: {
                #if os(iOS)
                await ReminderEngine.shared.ensureRetryChains()
                #endif
            }, isConfigured: SyncStore.isConfigured) }
    }
    static func syncNow(reminders: [Reminder], modelContext: ModelContext, transport: Transport? = nil) async -> SyncResult {
        let transport = transport ?? .live
        guard transport.isConfigured else { return .failure("请先配置 WebDAV 服务器") }
        guard !busy else { return .failure("同步正在进行") }
        busy = true; defer { busy = false }
        do {
            let remote = try await transport.download()
            let current = try modelContext.fetch(FetchDescriptor<Reminder>())
            let generation = SyncStore.localVersion
            let localChanged = generation != SyncStore.lastSyncVersion
            let oldStamp = UserDefaults.standard.string(forKey: remoteStampKey)
            let remoteChanged = oldStamp != stamp(remote.json)
            if let json = remote.json, BackupHelper.importJSON(json) == nil { return .failure("远程文件解析失败，未写入任何数据") }
            if remote.json != nil && !current.isEmpty && remoteChanged && (localChanged || oldStamp == nil) {
                pending = Conflict(remote: remote, generation: generation)
                return .conflict
            }
            if remote.json == nil || (localChanged && !remoteChanged) {
                return try await uploadSnapshot(current, generation: generation, remote: remote, transport: transport)
            }
            if remoteChanged, let json = remote.json {
                return try await applyRemote(json, current: current, remote: remote, context: modelContext, transport: transport)
            }
            SyncStore.setLastSync(); SyncStore.setHasSyncedOnce()
            return .success(conflict: false)
        } catch { return .failure(friendlyMessage(error)) }
    }
    static func resolve(_ choice: ConflictChoice, context: ModelContext, transport: Transport? = nil) async -> SyncResult {
        let transport = transport ?? .live
        guard !busy, let conflict = pending else { return .failure("请重新同步以获取最新冲突") }
        busy = true; defer { busy = false }
        do {
            let latest = try await transport.download()
            guard SyncStore.localVersion == conflict.generation, stamp(latest.json) == stamp(conflict.remote.json), latest.etag == conflict.remote.etag else {
                pending = nil; return .failure("数据在选择期间发生变化，请重新同步")
            }
            let current = try context.fetch(FetchDescriptor<Reminder>())
            try snapshotLocal(current)
            pending = nil
            switch choice {
            case .local:
                SyncStore.setLocalVersion(max(conflict.generation, BackupHelper.dataVersion(of: latest.json ?? "")) + 1)
                return try await uploadSnapshot(current, generation: SyncStore.localVersion, remote: latest, transport: transport)
            case .remote:
                guard let json = latest.json else { return .failure("远程备份已不存在，请重新同步") }
                return try await applyRemote(json, current: current, remote: latest, context: context, transport: transport)
            }
        } catch { return .failure(friendlyMessage(error)) }
    }
    private static func uploadSnapshot(_ current: [Reminder], generation: Int, remote: Remote, transport: Transport) async throws -> SyncResult {
        // Serialize values and capture the generation on this actor before suspending.
        let snapshot = SyncRevisionSnapshot(reminders: current)
        guard snapshot.generation == generation else { return .failure("本地数据已变化，请重新同步") }
        let json = snapshot.json
        try await transport.upload(json, remote)
        snapshot.acknowledge()
        UserDefaults.standard.set(stamp(json), forKey: remoteStampKey)
        SyncStore.setLastSync(); SyncStore.setHasSyncedOnce()
        return .success(conflict: false)
    }
    private static func applyRemote(_ json: String, current: [Reminder], remote: Remote, context: ModelContext, transport: Transport) async throws -> SyncResult {
        guard let items = BackupHelper.importJSON(json) else { return .failure("远程文件解析失败") }
        try snapshotLocal(current)
        guard mergeRemote(current, items: items, in: context) else { return .failure("本地写入失败，数据已回滚") }
        let incomingGeneration = BackupHelper.dataVersion(of: json)
        let previousGeneration = SyncStore.localVersion
        let incomingIDs = Set(items.compactMap(\.stableID))
        let hasLocalOnly = current.contains { !incomingIDs.contains($0.id) }
        // A selected lower counter or retained local rows create a new shared revision.
        let mustPublish = hasLocalOnly || incomingGeneration <= previousGeneration
        let mergedGeneration = mustPublish ? max(previousGeneration, incomingGeneration) + 1 : incomingGeneration
        SyncStore.setLocalVersion(mergedGeneration)
        SyncStore.setLastSyncVersion(mustPublish ? max(0, mergedGeneration - 1) : mergedGeneration)
        UserDefaults.standard.set(stamp(json), forKey: remoteStampKey)
        SyncStore.setLastSync(); SyncStore.setHasSyncedOnce()
        if mustPublish {
            let merged = try context.fetch(FetchDescriptor<Reminder>())
            do {
                let result = try await uploadSnapshot(merged, generation: mergedGeneration, remote: remote, transport: transport)
                await transport.restore()
                return result
            } catch { await transport.restore(); throw error }
        }
        await transport.restore()
        return .success(conflict: false)
    }

    // MARK: - 测试连接（添加 WebDAV 时验证账号/路径，坚果云友好提示）

    /// 完整读写测试：PROPFIND 根目录 + PUT 测试文件 + DELETE 清理。
    /// 仅 PROPFIND 通过不算成功——很多账号只读不开写（如坚果云第三方登录受限），
    /// 必须实际能写才算配置成功。
    /// 参数可传当前输入（不落盘，供「测试连接」用）；缺省读已保存配置。
    static func testConnection(
        url inputURL: String? = nil,
        username inputUsername: String? = nil,
        password inputPassword: String? = nil
    ) async -> SyncResult {
        let baseURL = (inputURL ?? SyncStore.url).trimmingCharacters(in: .whitespaces)
        let user = inputUsername ?? SyncStore.username
        let pass = inputPassword ?? SyncStore.password
        guard !baseURL.isEmpty, !user.isEmpty, !pass.isEmpty else {
            return .failure("请先填写 WebDAV 地址、用户名和应用密码")
        }
        guard let baseU = URL(string: baseURL), baseU.scheme != nil else {
            return .failure(friendlyMessage(SyncError.invalidURL))
        }
        // 临时使用输入值（不覆盖已保存配置）
        let auth = "Basic \(Data("\(user):\(pass)".utf8).base64EncodedString())"

        // 1. 验证读权限
        do {
            try await propfindRoot(baseU, auth: auth)
        } catch {
            return .failure(friendlyMessage(error))
        }

        // 2. 验证写权限：PUT 一个随机文件
        let testName = ".reminder_test_\(UUID().uuidString.prefix(8))"
        let testURL = baseU.appendingPathComponent(testName)
        do {
            try await putTestFile(at: testURL, auth: auth)
        } catch let se as SyncError {
            if case .http(let code) = se {
                return .failure(writeFailureHint(code: code))
            }
            return .failure(friendlyMessage(se))
        } catch {
            return .failure(friendlyMessage(error))
        }

        // 3. 清理测试文件（失败也不影响结论）
        try? await deleteTestFile(at: testURL, auth: auth)
        return .success(conflict: false)
    }

    /// PROPFIND 验证读权限
    private static func propfindRoot(_ url: URL, auth: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.timeoutInterval = 15
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue("0", forHTTPHeaderField: "Depth")

        let (_, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        // 207 Multi-Status 是 PROPFIND 的正常成功响应
        guard (200...299).contains(code) || code == 207 else {
            throw SyncError.http(code)
        }
    }

    /// PUT 测试文件验证写权限
    private static func putTestFile(at url: URL, auth: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 15
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("ok".utf8)

        let (_, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            throw SyncError.http(code)
        }
    }

    /// DELETE 清理测试文件
    private static func deleteTestFile(at url: URL, auth: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 10
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        _ = try await URLSession.shared.data(for: request)
    }

    /// 「可读但不可写」的精准提示（testConnection 第二步失败时使用）
    private static func writeFailureHint(code: Int) -> String {
        switch code {
        case 401:
            return "账号或密码错误（HTTP 401）：坚果云请用「应用密码」——网页端 → 账户信息 → 安全选项 → 添加应用密码，不能用登录密码。"
        case 403:
            return "账号只读不可写（HTTP 403）：可能原因：① 第三方登录注册的坚果云账号（如 Google/微信登录）不支持 WebDAV 写入，请用坚果云独立注册的账号；② 账号未在网页端启用 WebDAV（账户信息 → 安全选项）。"
        case 404:
            return "账号只读不可写（HTTP 404）：可能原因：① 第三方登录注册的坚果云账号不支持 WebDAV 写入，请用坚果云独立注册的账号；② 应用密码生成后未刷新权限，删除旧密码重新生成一次。"
        case 405:
            return "服务器不允许写入（HTTP 405）：地址可能不是 WebDAV 路径，请确认填 https://dav.jianguoyun.com/dav/（坚果云以 /dav/ 结尾）。"
        default:
            return Localized("可读但不可写（HTTP %d）：账号可能被禁用 WebDAV，或地址权限不足，请联系服务器管理员。", code)
        }
    }

    /// 把错误转成可操作的中文提示（尤其坚果云 401 应用密码）
    static func friendlyMessage(_ error: Error) -> String {
        if let se = error as? SyncError {
            switch se {
            case .invalidURL:
                return "WebDAV 地址无效。示例：https://dav.jianguoyun.com/dav/（坚果云必须以 /dav/ 结尾）"
            case .invalidUTF8:
                return "远程文件不是有效文本（文件可能已损坏），未覆盖本地数据"
            case .http(let code):
                switch code {
                case 401:
                    return "认证失败（HTTP 401）：请确认用户名；密码必须是坚果云「应用密码」——在坚果云网页端「账户信息 → 安全选项 → 添加应用密码」生成，不能用登录密码。"
                case 403:
                    return "无权限（HTTP 403）：请检查该 WebDAV 路径是否可写（如 dav.jianguoyun.com/dav/ 根目录）。"
                case 404:
                    return "目录不存在（HTTP 404）：请确认 WebDAV 地址指向已存在的目录，坚果云请填 https://dav.jianguoyun.com/dav/（根目录），不要带不存在的子路径。"
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

    // MARK: - 合并远程数据（阶段2：按 id upsert，不再整库 delete/reinsert）

    /// 用远程数据合并本地：
    /// - 远程条目按 id（跨端稳定 UUID）匹配本地 → 更新现有对象（引用不失效、操作记录保留）
    /// - 无 id 的旧协议条目 → 指纹匹配（识别上轮已导入的条目）→ 更新；否则插入
    /// - 本地有而远程没有的条目保留（无 tombstone，无法区分「远端已删」与「远端从未有过」，保守不删）
    /// - 覆盖前自动存本地 JSON 快照（可恢复；保留最近 5 份）
    private static func mergeRemote(
        _ current: [Reminder],
        items: [BackupHelper.BackupItem],
        in context: ModelContext
    ) -> Bool {
        do {
            try ReminderMerge.apply(items, current: current, context: context)
            WidgetCenter.shared.reloadAllTimelines()
            return true
        } catch { return false }
    }

    /// 阶段2: 合并前把当前本地全量导出为 JSON 快照（可恢复；保留最近 5 份）
    private static func snapshotLocal(_ reminders: [Reminder]) throws {
        let fm = FileManager.default
        guard let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("webdav_snapshots", isDirectory: true) else { throw SyncError.invalidURL }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd_HHmmss"
        stamp.locale = Locale(identifier: "en_US_POSIX")
        let file = dir.appendingPathComponent("before_\(stamp.string(from: Date())).json")
        let json = BackupHelper.exportJSON(reminders)
        try json.write(to: file, atomically: true, encoding: .utf8)

        // 只保留最近 5 份
        let entries = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix("before_") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } ?? []
        if entries.count > 5 {
            for old in entries.dropFirst(5) {
                try? fm.removeItem(at: old)
            }
        }
    }

    // MARK: - WebDAV 请求

    private static func remoteURL() -> String { remoteURL(remoteFileName) }

    private static func remoteURL(_ fileName: String) -> String {
        var base = SyncStore.url.trimmingCharacters(in: .whitespaces)
        if base.hasSuffix("/") { base.removeLast() }
        return "\(base)/\(fileName)"
    }

    // MARK: - 批次3 功能4: 日历订阅链接

    /// 把当前全部提醒导出为 .ics 上传到 WebDAV 目录，返回该文件的 WebDAV URL。
    ///
    /// 注意这个 URL 需要账号密码，系统日历不能直接订阅——网盘的正确姿势是上传后
    /// 在网页端对该文件「创建分享链接」，再把分享直链填进日历订阅。UI 会连同指引一起展示。
    /// 每次调用覆盖同名文件，订阅端下次刷新即可拿到最新日程。
    static func uploadICS(reminders: [Reminder]) async -> ICSUploadResult {
        guard SyncStore.isConfigured else {
            return .failure("请先配置 WebDAV 服务器".localized)
        }
        guard !reminders.isEmpty else {
            return .failure("当前没有可导出的提醒".localized)
        }
        do {
            let ics = IcsExporter.generateICS(reminders: reminders)
            try await uploadRaw(ics, fileName: remoteICSFileName, contentType: "text/calendar; charset=utf-8")
            return .success(url: remoteURL(remoteICSFileName), count: reminders.count)
        } catch {
            return .failure(friendlyMessage(error))
        }
    }

    enum ICSUploadResult {
        case success(url: String, count: Int)
        case failure(String)
    }

    /// 通用 PUT：404 时先 MKCOL 建目录再重试一次（与 upload 同策略）
    private static func uploadRaw(_ content: String, fileName: String, contentType: String) async throws {
        guard let url = URL(string: remoteURL(fileName)) else {
            throw SyncError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 30
        request.setValue(authHeader(), forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = content.data(using: .utf8)

        let (_, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 {
            try? await mkcolIfNeeded()
            let (_, retryResp) = try await URLSession.shared.data(for: request)
            let retryCode = (retryResp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(retryCode) else { throw SyncError.http(retryCode) }
            return
        }
        guard (200...299).contains(code) else { throw SyncError.http(code) }
    }

    private static func authHeader() -> String {
        let raw = "\(SyncStore.username):\(SyncStore.password)"
        let encoded = Data(raw.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    private static func download() async throws -> Remote {
        guard let url = URL(string: remoteURL()) else {
            throw SyncError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(authHeader(), forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { return Remote(json: nil, etag: nil) }
        guard (200...299).contains(code) else {
            throw SyncError.http(code)
        }
        // E4: 解码失败必须抛错而不是返回 nil——nil 会被 syncNow 当「远程无文件」→ 上传覆盖唯一备份
        guard let decoded = String(data: data, encoding: .utf8) else {
            throw SyncError.invalidUTF8
        }
        return Remote(json: decoded, etag: (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag"))
    }

    private static func upload(_ json: String, replacing remote: Remote) async throws {
        guard let url = URL(string: remoteURL()) else {
            throw SyncError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 30
        request.setValue(authHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        if remote.json == nil { request.setValue("*", forHTTPHeaderField: "If-None-Match") }
        else if let etag = remote.etag { request.setValue(etag, forHTTPHeaderField: "If-Match") }
        else { throw NSError(domain: "WebDAV", code: 1, userInfo: [NSLocalizedDescriptionKey: "服务器未提供 ETag，无法安全覆盖现有备份。请启用 ETag 或导出本地备份。" ]) }
        request.httpBody = json.data(using: .utf8)

        let (_, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 {
            // 坚果云等服务器要求目录已存在：先 MKCOL 创建父目录再重试一次
            try? await mkcolIfNeeded()
            let (_, retryResp) = try await URLSession.shared.data(for: request)
            let retryCode = (retryResp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(retryCode) else {
                throw SyncError.http(retryCode)
            }
            return
        }
        guard (200...299).contains(code) else {
            throw SyncError.http(code)
        }
    }

    /// 确保 WebDAV 目录存在（MKCOL；已存在时服务器返回 405/301 属正常，忽略）
    private static func mkcolIfNeeded() async throws {
        guard let url = URL(string: SyncStore.url.trimmingCharacters(in: .whitespaces)) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "MKCOL"
        request.timeoutInterval = 15
        request.setValue(authHeader(), forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
    }

    private enum SyncError: LocalizedError {
        case invalidURL
        case http(Int)
        case invalidUTF8

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "WebDAV 地址无效"
            case .http(let code): return "HTTP \(code)"
            case .invalidUTF8: return "远程文件不是有效文本（文件可能已损坏），未覆盖本地数据"
            }
        }
    }
}
