import Foundation
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
        /// conflict=true：检测到上次同步后双端都有修改，已按版本覆盖（UI 提示用户，v2.0.16）
        case success(conflict: Bool)
        case failure(String)
    }

    static func syncNow(reminders: [Reminder], modelContext: ModelContext) async -> SyncResult {
        guard SyncStore.isConfigured else {
            return .failure("请先配置 WebDAV 服务器")
        }

        do {
            let remoteJson = try await download()

            // v2.0.22: 下载完成后重新读取当前提醒——网络 await 期间主线程用户可能
            // 新建/编辑提醒，调用方传入的 reminders 快照已经过期；
            // 用旧快照导出/比较会把用户刚做的改动覆盖掉（或上传旧数据）。
            let currentReminders = (try? modelContext.fetch(FetchDescriptor<Reminder>())) ?? reminders

            // ⚠️ 版本必须在 download() 之后读取：网络 await 期间主线程
            // 用户可能新建/编辑提醒（touchLocalChange），用旧快照比较会把新数据误判为「远程新」而覆盖丢失
            // v2.0.17: 单调版本（localVer）为判新主依据；墙钟（localChange）仅兜底（旧文件/升级前本地无版本）
            let localChange = SyncStore.lastLocalChange // 秒
            let localVer = SyncStore.localVersion
            // v2.0.21 F1: 首次同步 + 上次同步版本必须在分支改写前快照，否则冲突判定会拿到刚写入的新值恒 false
            let firstSync = SyncStore.isFirstSync
            let lastSyncVer = SyncStore.lastSyncVersion

            guard let remoteJson else {
                // 远程无文件 → 上传本地
                let exportedAt = max(Date().timeIntervalSince1970, localChange + 1)
                let uploadJson = BackupHelper.exportJSON(currentReminders, exportedAt: exportedAt)
                try await upload(uploadJson)
                // 对齐版本，但要防止「回退」：上传期间用户编辑会抬高 lastLocalChange，
                // 直接 set 会把版本回退成旧值，导致该编辑永远不同步
                SyncStore.setLastLocalChange(max(exportedAt, SyncStore.lastLocalChange))
                // v2.0.17: 记录已同步版本，防下轮误判（上传 dataVersion = 当前本地版本）
                SyncStore.setLastSyncVersion(SyncStore.localVersion)
                SyncStore.setLastSync()
                SyncStore.setHasSyncedOnce()
                return .success(conflict: false)
            }

            guard let rawRemoteVersion = BackupHelper.exportedAt(of: remoteJson) else {
                return .failure("远程文件解析失败")
            }
            // 兼容 Android 的毫秒时间戳
            let remoteVersion = rawRemoteVersion > 1e11 ? rawRemoteVersion / 1000 : rawRemoteVersion
            // v2.0.17: 远程单调版本（旧文件无 dataVersion → 0，判新回退时间戳）
            let remoteDataVersion = BackupHelper.dataVersion(of: remoteJson)

            // v2.0.21 F1: 首次同步的冲突判定依据「两边都有数据」（版本不可比，无法用版本差判断）
            let remoteHasData = BackupHelper.itemCount(of: remoteJson) > 0
            let localHasData = !currentReminders.isEmpty

            // v2.0.17 判新：双方都有单调版本 → 版本比较；任一为 0（旧文件/升级前）→ 时间戳兜底
            // v2.0.21 F1: 首次同步两边版本不同源（远程是历史累计、本地从 0 起）→ 一律回退时间戳，
            //             否则永远判「远程新」，本机新建的提醒会被静默覆盖。
            // v2.0.21 F2: 版本相等（双端自同一基线各改相同次数）时用时间戳决胜，
            //             否则两个判新都是 false → 落入「无变更」→ 双方改动都不同步且不提示。
            let versionedCompare = !firstSync && remoteDataVersion > 0 && localVer > 0
            let remoteIsNewer: Bool
            let localIsNewer: Bool
            if versionedCompare && remoteDataVersion != localVer {
                remoteIsNewer = remoteDataVersion > localVer
                localIsNewer = localVer > remoteDataVersion
            } else {
                remoteIsNewer = remoteVersion > localChange
                localIsNewer = localChange > remoteVersion
            }

            if remoteIsNewer {
                // 远程新 → 下载覆盖本地
                guard let items = BackupHelper.importJSON(remoteJson) else {
                    return .failure("远程文件解析失败")
                }
                // 保存失败时不更新版本号，避免本地旧数据与远程版本对齐后永远无法再同步
                guard replaceLocal(currentReminders, items: items, in: modelContext) else {
                    return .failure("本地数据写入失败，未应用远程数据，请检查存储空间后重试")
                }
                // v2.0.17: 下载后本地数据 = 远程数据 → 单调版本对齐远程（旧文件 dataVersion=0 时保持本地版本）
                if remoteDataVersion > 0 {
                    SyncStore.setLocalVersion(remoteDataVersion)
                }
                // v2.0.16/17 冲突提示：上次同步后本地也改过（版本化判定；旧文件回退不提示）
                let conflict = isConflict(
                    firstSync: firstSync,
                    localHasData: localHasData,
                    remoteHasData: remoteHasData,
                    localVer: localVer,
                    remoteDataVersion: remoteDataVersion,
                    lastSyncVer: lastSyncVer
                )
                if remoteDataVersion > 0 {
                    SyncStore.setLastSyncVersion(remoteDataVersion)
                }
                SyncStore.setLastLocalChange(remoteVersion)
                SyncStore.setLastSync()
                SyncStore.setHasSyncedOnce()
                return .success(conflict: conflict)
            } else if localIsNewer {
                // 本地新 → 上传
                let exportedAt = max(Date().timeIntervalSince1970, remoteVersion + 1)
                let uploadJson = BackupHelper.exportJSON(currentReminders, exportedAt: exportedAt)
                try await upload(uploadJson)
                // v2.0.16/17 冲突提示：上次同步后远程也改过（版本化判定）
                let conflict = isConflict(
                    firstSync: firstSync,
                    localHasData: localHasData,
                    remoteHasData: remoteHasData,
                    localVer: localVer,
                    remoteDataVersion: remoteDataVersion,
                    lastSyncVer: lastSyncVer
                )
                // 同上：max 防止上传期间新编辑的版本被回退
                SyncStore.setLastLocalChange(max(exportedAt, SyncStore.lastLocalChange))
                SyncStore.setLastSyncVersion(localVer)
                SyncStore.setLastSync()
                SyncStore.setHasSyncedOnce()
                return .success(conflict: conflict)
            } else {
                // 版本与时间戳都相等 → 两边确为同一份数据，无变更
                // （F2：版本相等但时间戳不同的情况已在上面用时间戳决胜，不会落到这里）
                SyncStore.setLastSync()
                SyncStore.setHasSyncedOnce()
                return .success(conflict: false)
            }
        } catch {
            return .failure(friendlyMessage(error))
        }
    }

    // MARK: - 冲突判定（v2.0.21）

    /// 是否需要提示「已按版本覆盖」。
    ///
    /// - 首次同步：无 lastSyncVersion 基线可比，只要两边都有数据就意味着一方内容会被整体覆盖 → 提示
    /// - 后续同步：自上次同步后双端都推进过版本 → 提示
    private static func isConflict(
        firstSync: Bool,
        localHasData: Bool,
        remoteHasData: Bool,
        localVer: Int,
        remoteDataVersion: Int,
        lastSyncVer: Int
    ) -> Bool {
        if firstSync {
            return localHasData && remoteHasData
        }
        return lastSyncVer > 0 && localVer > lastSyncVer && remoteDataVersion > lastSyncVer
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

    // MARK: - 覆盖本地

    private static func replaceLocal(
        _ current: [Reminder],
        items: [BackupHelper.BackupItem],
        in context: ModelContext
    ) -> Bool {
        // 先清空旧通知，避免被删提醒的「幽灵通知」继续到点弹出
        NotificationManager.shared.removeAllPendingNotifications()

        var inserted: [Reminder] = []
        for r in current {
            context.delete(r)
        }
        for item in items {
            let reminder = BackupHelper.makeReminder(from: item)
            context.insert(reminder)
            inserted.append(reminder)
        }
        // 保存失败必须让调用方知道：否则版本号已对齐、本地又是旧数据，后续永远无法恢复
        do {
            try context.save()
        } catch {
            print("[WebDAV] 覆盖本地保存失败: \(error)")
            return false
        }

        // 远程覆盖本地后必须重排通知，否则新导入的提醒「存在但永不提醒」
        Task {
            for reminder in inserted where reminder.isEnabled {
                await ReminderEngine.shared.scheduleAllNotifications(for: reminder)
            }
        }

        // 刷新小组件
        Task {
            WidgetCenter.shared.reloadAllTimelines()
        }
        return true
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
        // E4: 解码失败必须抛错而不是返回 nil——nil 会被 syncNow 当「远程无文件」→ 上传覆盖唯一备份
        guard let decoded = String(data: data, encoding: .utf8) else {
            throw SyncError.invalidUTF8
        }
        return decoded
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
