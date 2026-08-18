import Foundation

/// 跨端备份/同步协议回归检查（阶段2）
///
/// 以 macOS 命令行工具形式运行（无需 iOS 模拟器 / host app），
/// 直接把产品代码 BackupHelper.swift + Reminder 模型编译进来断言协议事实。
/// 覆盖：schemaVersion、跨端稳定 id、holidayId 统一、旧协议（v1）兼容、
/// 导出字段双写（isCritical camelCase + is_critical snake）。
/// fixture 与 Android 仓库 app/src/test/resources/fixtures/ 内容完全一致（双端共享）。
@main
struct BackupProtocolCheck {

    static var failures = 0

    static func check(_ name: String, _ cond: Bool) {
        print((cond ? "PASS " : "FAIL ") + name)
        if !cond { failures += 1 }
    }

    static func fixture(_ name: String) -> String {
        // 用 #filePath 定位仓库内的 fixtures 目录（与运行 cwd 无关，CI/本地都稳定）
        let sourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = sourceDir.appendingPathComponent("fixtures").appendingPathComponent(name)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            print("FAIL 找不到 fixture: \(url.path)")
            failures += 1
            return ""
        }
        return content
    }

    static func main() {
        // exit() 会丢弃 stdout 块缓冲（管道/重定向下无输出），置无缓冲便于 CI 捕获
        setvbuf(stdout, nil, _IONBF, 0)

        // 1. 协议 v2 fixture 完整解析
        let v2 = fixture("protocol_v2.json")
        check("v2 fixture schemaVersion == 2 (得 \(BackupHelper.schemaVersion(of: v2)))",
              BackupHelper.schemaVersion(of: v2) == 2)
        check("v2 fixture dataVersion == 42 (得 \(BackupHelper.dataVersion(of: v2)))",
              BackupHelper.dataVersion(of: v2) == 42)

        let items = BackupHelper.importJSON(v2) ?? []
        check("v2 fixture 解析出 4 条 (得 \(items.count))", items.count == 4)

        // 2. 跨端稳定 id 原样保留
        check("v2 第一条 syncId 保留 (得 \(items.first?.syncId ?? "nil"))",
              items[0].syncId == "8f14e45f-ceea-4b5f-8d1a-9c3f2b7e5d01")
        // Android 本地自增数字 id 被容忍（不解析崩溃）
        check("v2 第一条 Android 数字 id 被忽略 (得 \(String(describing: items[0].id?.stringValue)))",
              items[0].id?.stringValue == nil)

        // 3. holidayId 优先于 holidayName
        check("v2 节假日 holidayId == zhongqiu (得 \(items[1].holidayId ?? "nil"))",
              items[1].holidayId == "zhongqiu")
        check("v2 节假日 holidayName 也读入 (得 \(items[1].holidayName ?? "nil"))",
              items[1].holidayName == "中秋节")

        // 4. isCritical camelCase
        check("v2 第一条 isCritical == true", items[0].isCritical == true)
        check("v2 第二条 isCritical == false", items[1].isCritical == false)
        // v2.4.10: 避开节假日/周末（导出字段 + 导入解析）
        check("v2 第一条 holidayAware == true", items[0].holidayAware == true)
        check("v2 第二条 holidayAware == false", items[1].holidayAware == false)

        // 5. makeReminder：id / holidayID 正确落到模型
        let r0 = BackupHelper.makeReminder(from: items[0])
        check("makeReminder id 沿用跨端 UUID (得 \(r0.id.uuidString))",
              r0.id.uuidString.lowercased() == "8f14e45f-ceea-4b5f-8d1a-9c3f2b7e5d01")
        let r1 = BackupHelper.makeReminder(from: items[1])
        check("makeReminder holidayID == zhongqiu (得 \(r1.holidayID ?? "nil"))",
              r1.holidayID == "zhongqiu")
        check("makeReminder 状态保留 notifying→pending (得 \(r1.status.rawValue))",
              r1.status == .pending)
        let r3 = BackupHelper.makeReminder(from: items[3])
        check("makeReminder overdue 保留 (得 \(r3.status.rawValue))",
              r3.status == .overdue)
        check("makeReminder confirmed 保留 (得 \(BackupHelper.makeReminder(from: items[2]).status.rawValue))",
              BackupHelper.makeReminder(from: items[2]).status == .confirmed)

        // 6. 旧协议（v1）兼容
        let v1 = fixture("protocol_v1_legacy.json")
        check("v1 fixture schemaVersion 缺省视为 1 (得 \(BackupHelper.schemaVersion(of: v1)))",
              BackupHelper.schemaVersion(of: v1) == 1)
        let v1Items = BackupHelper.importJSON(v1) ?? []
        check("v1 fixture 解析出 2 条 (得 \(v1Items.count))", v1Items.count == 2)
        check("v1 无 syncId → nil（导入时重新生成 UUID）",
              v1Items[0].syncId == nil)
        check("v1 缺 isCritical 键 → nil（旧协议 is_critical 不被读取）",
              v1Items[0].isCritical == nil)
        check("v1 旧 iOS 导出 holidayName 塞 ID → makeReminder holidayID 兜底 (得 \(BackupHelper.makeReminder(from: v1Items[1]).holidayID ?? "nil"))",
              BackupHelper.makeReminder(from: v1Items[1]).holidayID == "zhongqiu")
        let v1New = BackupHelper.makeReminder(from: v1Items[0])
        check("v1 无 id → makeReminder 生成新 UUID (\(v1New.id.uuidString))",
              UUID(uuidString: v1New.id.uuidString) != nil)

        // 7. 导出：schemaVersion=2 + syncId + 双写 isCritical
        let exported = BackupHelper.exportJSON([r0, r1], exportedAt: 1_755_255_000)
        check("导出包含 schemaVersion: 2", exported.contains("\"schemaVersion\" : 2"))
        check("导出包含跨端 syncId", exported.lowercased().contains("8f14e45f-ceea-4b5f-8d1a-9c3f2b7e5d01"))
        check("导出包含 holidayId", exported.contains("\"holidayId\" : \"zhongqiu\""))
        check("导出包含 isCritical", exported.contains("\"isCritical\" : false"))
        check("导出包含 holidayAware", exported.contains("\"holidayAware\" : false"))

        // 8. 导出-导入往返：id 稳定
        let roundtrip = BackupHelper.importJSON(exported) ?? []
        check("导出-导入往返 2 条 (得 \(roundtrip.count))", roundtrip.count == 2)
        check("往返 syncId 不变 (得 \(roundtrip[0].syncId ?? "nil"))",
              roundtrip[0].syncId == r0.id.uuidString)
        check("往返 holidayId 不变 (得 \(roundtrip[1].holidayId ?? "nil"))",
              roundtrip[1].holidayId == "zhongqiu")

        print(failures == 0 ? "== ALL PROTOCOL REGRESSION PASS ==" : "== \(failures) FAILURES ==")
        exit(failures == 0 ? 0 : 1)
    }
}
