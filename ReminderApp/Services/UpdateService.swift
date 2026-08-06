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
    static let releaseAPI = URL(string: "https://api.github.com/repos/\(repoName)/releases/latest")!

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// 检查 GitHub 最新 release；失败返回 nil（离线/限流静默降级）
    static func checkLatest() async -> AppUpdateInfo? {
        var request = URLRequest(url: releaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        // 国内访问 api.github.com 不稳定：失败重试一次
        for attempt in 0...1 {
            if let info = try await fetchOnce(request: request) { return info }
        }
        return nil
    }

    private static func fetchOnce(request: URLRequest) async -> AppUpdateInfo? {
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let html = json["html_url"] as? String,
                  let url = URL(string: html) else { return nil }
            let latest = tag.replacingOccurrences(of: "v", with: "")

            // 找第一个 .ipa 资产（iOS 自签场景）
            var ipaURL: URL? = nil
            if let assets = json["assets"] as? [[String: Any]] {
                for asset in assets {
                    if let name = asset["name"] as? String,
                       let browser = asset["browser_download_url"] as? String,
                       name.hasSuffix(".ipa"),
                       let u = URL(string: browser) {
                        ipaURL = u
                        break
                    }
                }
            }

            return AppUpdateInfo(
                latestVersion: latest,
                releaseURL: url,
                ipaURL: ipaURL,
                isNewer: isNewerVersion(latest, than: currentVersion)
            )
        } catch {
            return nil
        }
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