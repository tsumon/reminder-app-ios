import Foundation

/// AI 可调用的工具定义 + 执行桥接
struct AITools {

    // MARK: - 工具 JSON Schema（OpenAI Function Calling 格式）

    static let definitions: [[String: Any]] = [
        [
            "type": "function",
            "function": [
                "name": "create_reminder",
                "description": "创建一个新的循环提醒或日期提醒。用户说'每天提醒我喝水''下周一提醒我开会''每年提醒我妈生日'时调用。",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "title":         ["type": "string", "description": "提醒标题"],
                        "note":          ["type": "string", "description": "备注（可选）"],
                        "kind":          ["type": "string", "enum": ["cycle", "date"], "description": "周期提醒还是日期提醒"],
                        "cycle":         ["type": "string", "enum": ["daily","weekly","biweekly","monthly","quarterly","yearly"], "description": "周期类型，kind=cycle时必须"],
                        "custom_days":   ["type": "integer", "description": "自定义天数，cycle=custom时使用"],
                        "date_type":     ["type": "string", "enum": ["solar_birthday","lunar_birthday","holiday"], "description": "日期提醒子类型，kind=date时必须"],
                        "target_month":  ["type": "integer", "description": "目标月份 1-12，日期类必须"],
                        "target_day":    ["type": "integer", "description": "目标日期 1-31，日期类必须"],
                        "holiday_name":  ["type": "string", "description": "节假日名称，date_type=holiday时使用，如春节/中秋/国庆"],
                        "advance_days":  ["type": "integer", "description": "提前几天预告，默认3"],
                        "reminder_hour": ["type": "integer", "description": "提醒时间-小时 0-23，默认9"],
                        "reminder_minute": ["type": "integer", "description": "提醒时间-分钟 0-59，默认0"],
                        "trigger_date":  ["type": "string", "description": "首次触发日期 yyyy-MM-dd，不填则取最近合理的未来时间"],
                        "trigger_time":  ["type": "string", "description": "首次触发时间 HH:mm，默认09:00"]
                    ],
                    "required": ["title", "kind"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "list_reminders",
                "description": "列出所有提醒，查看当前有哪些提醒。",
                "parameters": [
                    "type": "object",
                    "properties": [:],
                    "required": []
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "confirm_reminder",
                "description": "确认完成一个提醒（标记为已处理、周期前进）。用户说'已经做完了''确认了''标记完成'时调用。",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "title_keyword": ["type": "string", "description": "提醒标题关键词，用于匹配要确认的提醒"]
                    ],
                    "required": ["title_keyword"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "snooze_reminder",
                "description": "推迟一个提醒15分钟。用户说'稍后再提醒''等会再说'时调用。",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "title_keyword": ["type": "string", "description": "提醒标题关键词"]
                    ],
                    "required": ["title_keyword"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "delete_reminder",
                "description": "删除一个提醒。用户说'删除XX提醒''取消XX'时调用。",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "title_keyword": ["type": "string", "description": "提醒标题关键词"]
                    ],
                    "required": ["title_keyword"]
                ]
            ]
        ]
    ]

    // MARK: - 系统提示词

    static let systemPrompt = """
    你是一个循环提醒助手，帮用户管理重复提醒事项。

    **核心规则：**
    - 用户描述提醒需求时 → 调用 create_reminder
    - 用户要确认某个提醒已完成 → 调用 confirm_reminder
    - 用户要推迟某个提醒 → 调用 snooze_reminder
    - 用户要删除提醒 → 调用 delete_reminder
    - 用户问'有什么提醒''列表' → 调用 list_reminders

    **周期与日期参数：**
    - "每天" → kind=cycle, cycle=daily
    - "每周/周一" → kind=cycle, cycle=weekly
    - "每月" → kind=cycle, cycle=monthly
    - "每年/生日" → kind=date, date_type=solar_birthday
    - "农历生日/阴历生日" → kind=date, date_type=lunar_birthday
    - "春节/中秋/端午/清明/国庆/元旦" → kind=date, date_type=holiday

    **回复风格：** 简洁友好，每次只做一件事，执行完告知结果。
    """
}
