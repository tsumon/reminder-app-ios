import Foundation
import Darwin

/// 崩溃监控 + 埋点基础设施（v1.8.7 任务⑥）— 镜像 Android TelemetryService.kt
///
/// 先做本地基础设施，后续填 Bugly/AppCenter 的 AppID 即可启用真实上报：
/// - 崩溃捕获：NSSetUncaughtExceptionHandler（OC 异常）+ signal handler（SIGABRT/SIGSEGV 等）
/// - 埋点事件：JSON Lines 写 Application Support/telemetry/
/// - 可插拔上报接口：CrashReporting / EventReporting，默认本地文件实现，
///   未来替换为 Bugly/AppCenter 实现即可（无需改业务代码）
enum TelemetryService {

    // MARK: - 可插拔上报接口

    protocol CrashReporting {
        func reportCrash(_ reason: String, stack: String)
    }

    protocol EventReporting {
        func reportEvent(_ name: String, params: [String: String])
    }

    /// 默认实现：写本地日志文件（不上传）
    final class LocalFileReporter: CrashReporting, EventReporting {
        static let shared = LocalFileReporter()

        func reportCrash(_ reason: String, stack: String) {
            writeLine(#"{"type":"crash","time":"\#(Self.now())","reason":"\#(escape(reason))","stack":"\#(escape(stack))"}"#)
        }

        func reportEvent(_ name: String, params: [String: String]) {
            let paramsJSON = params.map { "\"\(escape($0.key))\":\"\(escape($0.value))\"" }
                .joined(separator: ",")
            writeLine(#"{"type":"event","name":"\#(escape(name))","time":"\#(Self.now())","params":{\#(paramsJSON)}}"#)
        }

        private func writeLine(_ line: String) {
            guard let url = Self.eventFileURL() else { return }
            let data = (line + "\n").data(using: .utf8)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                if let data { handle.write(data) }
                try? handle.close()
            } else {
                try? data?.write(to: url, options: .atomic)
            }
        }

        private static func eventFileURL() -> URL? {
            guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
            let sub = dir.appendingPathComponent("telemetry", isDirectory: true)
            try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            return sub.appendingPathComponent("events.jsonl")
        }

        private static func now() -> String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
            return f.string(from: Date())
        }
    }

    /// 上报器（默认本地文件；接入 Bugly/AppCenter 时替换）
    static var crashReporter: CrashReporting = LocalFileReporter.shared
    static var eventReporter: EventReporting = LocalFileReporter.shared

    // MARK: - 安装

    private static var installed = false

    /// 在 App 启动时调用一次
    static func install() {
        guard !installed else { return }
        installed = true

        // OC 异常（NSException）：顶层函数引用（@convention(c) 不能捕获上下文）
        NSSetUncaughtExceptionHandler(telemetryExceptionHandler)

        // 信号崩溃（SIGSEGV/SIGABRT 等）
        installSignalHandlers()

        logEvent("app_start")
        print("[Telemetry] 崩溃监控+埋点已安装（本地文件模式，可插拔上报）")
    }

    // MARK: - 埋点

    /// 记录一条埋点事件（业务代码调用，如 confirm / snooze / reminder_created）
    static func logEvent(_ name: String, params: [String: String] = [:]) {
        eventReporter.reportEvent(name, params: params)
    }

    // MARK: - Signal handlers

    private static func installSignalHandlers() {
        // 顶层函数引用（不捕获上下文，可转 @convention(c) 函数指针）
        for sig in [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP] {
            signal(sig, telemetrySignalHandler)
        }
    }
}

/// OC 异常 handler：顶层函数（@convention(c) 不允许捕获上下文）
func telemetryExceptionHandler(_ exception: NSException) {
    let stack = exception.callStackSymbols.joined(separator: "\n")
    TelemetryService.crashReporter.reportCrash(
        "\(exception.name.rawValue): \(exception.reason ?? "")", stack: stack
    )
}

/// signal handler：POSIX 异步安全，只做 open/write/close，然后恢复默认并重抛
func telemetrySignalHandler(_ sig: Int32) {
    let msg = "{\"type\":\"crash\",\"time\":\(Date().timeIntervalSince1970),\"signal\":\(sig)}\n"
    msg.withCString { buf in
        if let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let sub = dir.appendingPathComponent("telemetry", isDirectory: true)
            try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            let path = sub.appendingPathComponent("events.jsonl").path
            let fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
            if fd >= 0 {
                write(fd, buf, strlen(buf))
                close(fd)
            }
        }
    }
    signal(sig, SIG_DFL)
    raise(sig)
}

/// RFC 安全转义（JSON 字符串）
private func escape(_ s: String) -> String {
    s
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
}
