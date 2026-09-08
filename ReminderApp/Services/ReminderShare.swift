import Foundation
#if canImport(UIKit)
import UIKit
import SwiftUI
#endif

/// 提醒详情分享：自然语言一段 + `.ics` 文件。
enum ReminderShare {
    static func plainText(title: String, cycleLabel: String, nextTrigger: Date, note: String) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "yyyy年M月d日 HH:mm"
        var lines = [
            "提醒：\(title)",
            "周期：\(cycleLabel)",
            "下次触发：\(df.string(from: nextTrigger))"
        ]
        if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("备注：\(note)")
        }
        return lines.joined(separator: "\n")
    }

    static func writeICSFile(named title: String, contents: String) -> URL {
        let safe = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let trimmed = safe.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = (trimmed.isEmpty ? "reminder" : String(trimmed.prefix(40))) + ".ics"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

#if canImport(UIKit) && canImport(SwiftUI)
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
