# 2.9 / Schema v4

源码版本 2.9.0（71），以 2.8.0（70）为升级基线。本分支未发布。

## 界面与行为

暖白纸色与深青绿色，减少多层阴影和高光；保留六种主题、系统深色模式及首页 / 日历 / 统计 / 设置四个 Tab。AI、语音、模板、批量管理、完整编辑、农历、节假日、勿扰、分享、小组件和原有导入导出入口均保留。

首页组合搜索、时间范围、类型筛选与时间 / 标题 / 优先级排序。健康卡只反映实际通知权限、iOS 待通知队列或 Android 精确闹钟授权，点击进入已有诊断与测试；不能据此宣称送达。创建页逐项编辑重试间隔和次数，显示三次周期安排与前三次重试。日历同屏展示当日安排并可创建当天提醒。统计支持周 / 月 / 全部与历史范围，完成、跳过和漏掉分别显示。

统计口径保持明确：完成与跳过按操作次数，完成天数按日期去重；漏掉为出现重试 / 通知记录的日期数量，是历史指标，不是“未送达”或“整次任务失败”的准确次数。仍保留既有热力与连续天数洞察。

## 持久化与协议

信封继续 `version: 1`，新增 `schemaVersion: 4`。v1–v3 可读。时间戳继续为毫秒，UUID 大小写归一。普通提醒与策略字段不变。

```json
{
  "version": 1,
  "schemaVersion": 4,
  "exportedAt": 1800000000000,
  "dataVersion": 8,
  "deletedReminderIds": ["aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"],
  "deletedRecordIds": ["11111111-2222-4333-8444-555555555555"],
  "reminders": [{
    "syncId": "22222222-3333-4444-8555-666666666666",
    "title": "Example",
    "firstTriggerAt": 1800000000000,
    "nextTriggerAt": 1800003600000,
    "scheduledOccurrenceAt": 1800000000000,
    "timeZoneMode": "deviceCalendar",
    "records": [{"id":"33333333-4444-4555-8666-777777777777","performedAt":1800000000000,"type":"confirm","note":""}]
  }]
}
```

- 稳定提醒 ID：iOS Reminder.id，Android syncId；Android 自增 ID 仅供本机外键 / 通知引用，不作为跨端身份。
- 稳定历史 ID：iOS 原有 UUID，Android 新增持久化 sync_id。迁移为每条存量记录生成一次 ID，后续导出 / 重导入不重建。type 对齐 confirm / snooze / trigger / skipped，Android 本地旧 action 值不变。
- 删除提醒与撤销完成分别产生 reminder / record 删除标记。合并以删除为优先，不按设备墙钟比较，不自动过期。冲突选择“本地”也保留双方删除标记。重复合并记录按 ID 去重。删除提醒时同时移除其历史（沿用 iOS 原有级联语义，Android 统一为相同行为）；操作前完整快照可用于恢复。
- Android Room 9→10 保留原列、数值 ID 与外键，新增 history sync_id / note、sync_deletions 表与 scheduled_occurrence_at；事务内写入删除 / 撤销标记。历史软删除行回填标记。
- iOS SwiftData 新增可选 scheduledOccurrenceAt，保留既有轻量迁移路线；删除账本存于应用 UserDefaults。合并和删除使用写前标记，完整 JSON 与 WebDAV 快照包含账本。启动时清理尚未落库的删除行。
- 备份与 WebDAV 导出包含历史及删除标记；单条分享卡片不携带全局删除标记，避免分享一条提醒误删整个目标设备的内容。

## 冲突、安全上传与恢复

仍在双端修改时停止，等待明确选择；仍先保存私有本地快照；仍使用 ETag / If-Match 或首次 If-None-Match。解析 / 备份 / 条件写入失败停止同步；网络等待不持有数据库变更锁；用户在等待期间的新操作不能被旧快照标记为已同步。

旧客户端能读提醒，但不知道 v4 删除与历史字段，上传会丢弃这些元数据。已有新客户端保留的删除账本能阻止同一稳定 ID 复活；在旧客户端覆盖远端后，不能把其输出当完整 v4 恢复源。两端都升级，并保留 v4 完整 JSON。没有稳定 ID 的古老 v1 文件无法可靠区分同名提醒与删除项。

删除标记不提供“撤销删除”，因此离线很久的设备也不能复活旧 ID。需要恢复时，先保留原备份，在副本中给目标提醒生成新 UUID（syncId），移除它的旧 id 与历史 records，再导入；不要把整个账本清空。新 ID 表示明确创建新提醒。应用仍提供原有创建撤销与完成撤销。

## 节假日与时区

节假日前移时保留 `scheduledOccurrenceAt`（原定周期时间），完成 / 跳过依据原定周期推进；重试或稍后不会把本次提前的时间当周期锚点。完成后重算仍从实际动作时刻开始。Android 对 2.8 仅有前移注释的提醒，通过原 firstTriggerAt 推导原定周期。

`timeZoneMode: deviceCalendar` 是当前既有语义的显式说明，而非固定时区或强制本地时刻模式：使用设备当前日历进行计算，原始时间戳不因时区变化重写。迁移不重新解释旧锚点。切换时区后应检查下次提醒。预览不联网预测尚未缓存的节假日，也不承诺实际送达。

## 签名与升级

Android 保留 com.reminderapp、原 signingConfigs.release、工作流 secrets 接线和证书 SHA-256 门禁：

`0ea509a1dc9461c291a2db47caf5f055d83e4108fb28c3e87ed4fa62bead7038`

iOS 保留 com.reminder.app、com.reminder.app.widget、group.com.reminder.app。工作流继续 CODE_SIGNING_ALLOWED=NO 的 unsigned IPA，不引入分发证书。两个目标版本一致为 2.9.0 / 71。

设备端存储迁移测试与真机原签名覆盖安装分别报告。模拟器 / debug APK 不能证明正式渠道覆盖升级或通知可靠送达。详见 [验证记录](validation-2.9.md)。
