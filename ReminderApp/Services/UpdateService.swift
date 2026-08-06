import Foundation

/// GitHub 在线升级检查（v1.8.7 自签分发：iOS 直接下载 .ipa 到本地文件 App）
///
/// iOS 自签场景：用户通过 AltStore/爱思/其他签名工具从文件 App 选取 ipa 安装。
/// App 检查到新版 → 下载 ipa 到 Documents/循环提醒/ 目录（文件 App 可见）→
/// 提示用户去文件 App 用自签工具签名安装。
struct AppUpdateInfo {
    let latestVersion: String
    let releaseURL: URL
    /// iOS .ipa 资产下载链接；找不到时为 nil
    let ipaURL: URL?
    /// 是否比当前版本新
    let isNewer: Bool
}

enum UpdateService {

    static let repoName = "tsumon/reminder-app-ios"
    static let repoURL = URL(string: "https://github.com/\(repoName)")!
    /// 检查源：releases.atom（HTML 域名走 CDN，无匿名 API 限流；api.github.com 常被限流 403）
    static let atomURL = URL(string: "https://github.com/\(repoName)/releases.atom")!
    /// 下载路径：latest/download 固定名（无需版本号/API，永远指向最新 Release 的该资产）
    static let ipaAssetURL = URL(string: "https://github.com/\(repoName)/releases/latest/download/ReminderApp.ipa")!
    /// 兜底：api.github.com（可能限流，仅当 atom 不可用时尝试）
    static let releaseAPI = URL(string: "https://api.github.com/repos/\(repoName)/releases/latest")!

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// 检查 GitHub 最新 release；失败返回 nil（离线/网络异常静默降级）
    /// 优先 releases.atom（不限流），重试 1 次；仍失败再兜底 api.github.com
    static func checkLatest() async -> AppUpdateInfo? {
        for _ in 0...1 {
            if let info = await fetchFromAtom() { return info }
        }
        return await fetchFromAPI()
    }

    /// releases.atom：解析第一个 <entry> 的 link(=release 页) 与 tag
    private static func fetchFromAtom() async -> AppUpdateInfo? {
        var request = URLRequest(url: atomURL)
        request.timeoutInterval = 15
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let xml = String(data: data, encoding: .utf8),
                  let first = regexFirst("<entry>(.*?)</entry>", in: xml),
                  let link = regexFirst("href=\"([^\"]*releases/tag/[^\"]*)\"", in: first),
                  let url = URL(string: link) else { return nil }
            // tag 优先从 link 的 /releases/tag/<tag> 提取：
            // atom 的 <title> 是 release 的 name，填了中文/描述名时会拿到非版本串
            let tag = regexFirst("releases/tag/([^/\"]+)", in: link)
                ?? regexFirst("<title[^>]*>(.*?)</title>", in: first)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag // 只去前缀 v，避免删掉版本串里的其它 v
            return AppUpdateInfo(
                latestVersion: latest,
                releaseURL: url,
                ipaURL: ipaAssetURL,
                isNewer: isNewerVersion(latest, than: currentVersion)
            )
        } catch {
            return nil
        }
    }

    /// 兜底：api.github.com 解析（可能被限流 403）
    private static func fetchFromAPI() async -> AppUpdateInfo? {
        var request = URLRequest(url: releaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let html = json["html_url"] as? String,
                  let url = URL(string: html) else { return nil }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag // 只去前缀 v，避免删掉版本串里的其它 v
            return AppUpdateInfo(
                latestVersion: latest,
                releaseURL: url,
                ipaURL: ipaAssetURL,
                isNewer: isNewerVersion(latest, than: currentVersion)
            )
        } catch {
            return nil
        }
    }

    /// 正则辅助：返回第一个捕获组（无匹配返回 nil）
    private static func regexFirst(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = re.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    /// 语义化版本比较：a > b ?
    static func isNewerVersion(_ a: String, than b: String) -> Bool {
        let av = a.split(separator: ".").compactMap { Int($0) }
        let bv = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(av.count, bv.count) {
            let x = i < av.count ? av[i] : 0
            let y = i < bv.count ? bv[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// 下载 .ipa 到 Documents/循环提醒/（iOS「文件」App 可见）
    /// 自签用户从文件 App 选此 ipa 用 AltStore/爱思等工具签名安装
    static func downloadIpa(from url: URL, version: String) async throws -> URL {
        let dir = try downloadsDirectory()
        let file = dir.appendingPathComponent("循环提醒-v\(version).ipa")
        // 覆盖旧文件，避免磁盘膨胀
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        try FileManager.default.moveItem(at: tempURL, to: file)
        return file
    }

    /// iOS 自签用户可见的下载目录（Documents/循环提醒）
    static func downloadsDirectory() throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let sub = docs.appendingPathComponent("循环提醒", isDirectory: true)
        if !FileManager.default.fileExists(atPath: sub.path) {
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        }
        return sub
    }
}