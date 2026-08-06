import Foundation
import Network

/// 近场分享：同一局域网内互传提醒
///
/// 发送方：内嵌 TCP 服务（NWListener），收到请求返回当前提醒的备份 JSON
/// 接收方：HTTP GET http://<ip>:47823/reminders.json 拉取并导入
enum NearbyShareService {
    static let port: UInt16 = 47823
    static let path = "/reminders.json"

    // MARK: - 服务端（发送方）

    /// 启动本地服务；jsonProvider 在每次请求时调用（返回最新数据的 JSON 字符串）
    @discardableResult
    static func startServer(jsonProvider: @escaping () -> String, onEvent: @escaping (String, Bool) -> Void) throws -> NWListener {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "NearbyShare", code: 1, userInfo: [NSLocalizedDescriptionKey: "无效端口"])
        }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: endpointPort)

        listener.newConnectionHandler = { (connection: NWConnection) in
            connection.start(queue: DispatchQueue.global())
            var sent = false

            // 挂起保护：30s 内未收到请求则断开，避免泄漏
            let hangGuard = DispatchWorkItem { [weak connection] in
                guard let connection else { return }
                connection.cancel()
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: hangGuard)

            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { (_, _, _, _) in
                hangGuard.cancel()
                guard !sent else { return }
                sent = true
                let body = jsonProvider()
                let header = "HTTP/1.1 200 OK\r\n"
                    + "Content-Type: application/json; charset=utf-8\r\n"
                    + "Content-Length: \(body.utf8.count)\r\n"
                    + "Connection: close\r\n\r\n"
                connection.send(content: Data((header + body).utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                onEvent("已发送给一台设备（\(body.utf8.count) 字节）", false)
            }
        }

        listener.stateUpdateHandler = { (state: NWListener.State) in
            switch state {
            case .ready:
                onEvent("服务已启动，等待对方连接...", false)
            case .failed(let error):
                // 端口占用等异步失败：cancel 释放监听，回传错误事件
                listener.cancel()
                onEvent("服务启动失败：\(error.localizedDescription)", true)
            default:
                break
            }
        }

        listener.start(queue: DispatchQueue.global())
        return listener
    }

    /// 本机局域网 IPv4：en0/en1 优先，其次第一个非 loopback 非 utun 的 IPv4（热点/VPN 场景兜底）
    static func localIPAddress() -> String? {
        var preferred: String?
        var fallback: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            let interface = ptr!.pointee
            let family = interface.ifa_addr.pointee.sa_family
            if family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                // 跳过回环与 VPN/隧道接口
                if name.hasPrefix("lo") || name.hasPrefix("utun") || name.hasPrefix("ipsec") { ptr = interface.ifa_next; continue }
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(interface.ifa_addr,
                            socklen_t(interface.ifa_addr.pointee.sa_len),
                            &host, socklen_t(host.count),
                            nil, 0, NI_NUMERICHOST)
                let ip = String(cString: host)
                guard !ip.isEmpty else { ptr = interface.ifa_next; continue }
                if name == "en0" || name == "en1" {
                    preferred = ip
                    break
                }
                if fallback == nil { fallback = ip }
            }
            ptr = interface.ifa_next
        }
        return preferred ?? fallback
    }

    // MARK: - 客户端（接收方）

    /// 从对方 IP 拉取备份 JSON；失败返回 nil
    static func fetch(from host: String) async -> String? {
        var h = host.trimmingCharacters(in: .whitespaces)
        // 完整 URL：直接取 host（兼容 http://ip:port / http://[ipv6]:port）
        if let url = URL(string: h), let urlHost = url.host, !urlHost.isEmpty {
            h = urlHost
        } else if h.contains(":") && !h.contains("/") {
            // 裸 ip:port → 只取 IP 段
            h = String(h.split(separator: ":").first ?? Substring(h))
        }
        // IPv6 需要方括号
        if h.contains(":") && !h.hasPrefix("[") {
            h = "[\(h)]"
        }
        guard let url = URL(string: "http://\(h):\(port)\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
