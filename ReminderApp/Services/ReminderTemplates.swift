import Foundation

/// 一键填入创建表单的提醒模板（报税 / 域名续期 / 生日）。
struct ReminderTemplate: Identifiable, Equatable {
    let id: String
    let title: String
    let note: String
    let kind: Kind
    let cycle: Cycle?
    let holidayAware: Bool
    let dateType: DateKind?
    let advanceDays: Int
    let subtitle: String

    enum Kind: String { case cycle, date }
    enum Cycle: String { case monthly, yearly }
    enum DateKind: String { case solarBirthday, lunarBirthday }

    static let all: [ReminderTemplate] = [
        ReminderTemplate(
            id: "tax",
            title: "报税",
            note: "工作日提醒，遇周末或法定节假日顺延到下一个工作日。",
            kind: .cycle,
            cycle: .monthly,
            holidayAware: true,
            dateType: nil,
            advanceDays: 0,
            subtitle: "每月 · 避开节假日"
        ),
        ReminderTemplate(
            id: "domain",
            title: "域名续期",
            note: "每年到期前开始提醒，可改提前天数。",
            kind: .date,
            cycle: nil,
            holidayAware: false,
            dateType: .solarBirthday,
            advanceDays: 30,
            subtitle: "每年 · 提前 30 天"
        ),
        ReminderTemplate(
            id: "birthday",
            title: "生日",
            note: "默认为公历生日，可改为农历。",
            kind: .date,
            cycle: nil,
            holidayAware: false,
            dateType: .solarBirthday,
            advanceDays: 3,
            subtitle: "公历每年 · 可改农历"
        )
    ]
}
