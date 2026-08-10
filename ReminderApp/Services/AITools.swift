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
                        "kind":          ["type": "string", "enum": ["cycle", "date", "rule"], "description": "周期提醒 / 日期提醒 / 规则提醒(第N周周X)"],
                        "cycle":         ["type": "string", "enum": ["daily","weekly","biweekly","monthly","quarterly","yearly"], "description": "周期类型，kind=cycle时必须"],
                        "custom_days":   ["type": "integer", "description": "自定义天数，cycle=custom时使用"],
                        "rule_period":   ["type": "string", "enum": ["monthly","quarterly","yearly"], "description": "规则频率，kind=rule时必须，如每季度/每年"],
                        "rule_week":     ["type": "integer", "description": "第几周 1-5，kind=rule时必须"],
                        "rule_weekday":  ["type": "integer", "description": "周几 1=周一...7=周日，kind=rule时必须"],
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
        ],
        [
            "type": "function",
            "function": [
                "name": "update_reminder",
                "description": "修改一个已有提醒的字段。用户说'把XX改成每周二''把交房租时间改到10点''把XX备注改成XXX'时调用。不传的字段保留原值。",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "title_keyword": ["type": "string", "description": "提醒标题关键词，用于定位"],
                        "new_title": ["type": "string", "description": "新的标题（可选）"],
                        "note": ["type": "string", "description": "新的备注（可选）"],
                        "cycle": ["type": "string", "enum": ["daily","weekly","biweekly","monthly","quarterly","yearly","custom","once"]],
                        "custom_days": ["type": "integer"],
                        "rule_period": ["type": "string", "enum": ["monthly","quarterly","yearly"]],
                        "rule_week": ["type": "integer"],
                        "rule_weekday": ["type": "integer"],
                        "date_type": ["type": "string", "enum": ["solar_birthday","lunar_birthday","holiday"]],
                        "target_month": ["type": "integer"],
                        "target_day": ["type": "integer"],
                        "holiday_name": ["type": "string"],
                        "advance_days": ["type": "integer"],
                        "reminder_hour": ["type": "integer"],
                        "reminder_minute": ["type": "integer"]
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
    - 用户要修改/调整已有提醒（改标题、改周期、改时间、改备注等） → 调用 update_reminder（只传要改的字段，其余保留原值）
    - 用户问'有什么提醒''列表' → 调用 list_reminders

    **生日 / 日期提醒（重要）：**
    - "X生日:新历/公历 M月D号" → kind=date, date_type=solar_birthday, target_month=M, target_day=D
    - "X生日:旧历/农历/阴历 M月初D / M月D号" → kind=date, date_type=lunar_birthday, target_month=M, target_day=D
    - "每年""周年" → kind=date, date_type=solar_birthday
    - "春节/中秋/端午/清明/国庆/元旦" → kind=date, date_type=holiday, holiday_name=名称

    **批量创建（关键）：** 若用户一次给出多个生日（例如"老公生日:新历9月5号 / 婆婆生日:农历7月初五 / 老娘生日:新历1月14号，旧历12月18 / 啊姨生日:新历7月14号，旧历6月15"），必须为每一个人分别调用一次 create_reminder（一次只创建一条），title 用"XX生日"。优先取"新历/公历"日期；若只给了"旧历/农历"，则使用 lunar_birthday 与对应月日。不要合并、也不要漏掉任何一个人。

    **周期提醒：**
    - 每天 → kind=cycle, cycle=daily
    - 每周/周一 → kind=cycle, cycle=weekly
    - 每月 → kind=cycle, cycle=monthly
    - 每年 → kind=cycle, cycle=yearly
    - 每 N 天 → kind=cycle, cycle=custom, custom_days=N

    **规则提醒（第N周周X，重要）：**
    - 每月/每季度/每年 第N周周X → kind=rule, rule_period=monthly/quarterly/yearly,
      rule_week=N(1-5), rule_weekday=周几(1=周一...7=周日)
    - 例「每季度第二周周二」→ kind=rule, rule_period=quarterly, rule_week=2, rule_weekday=2
    - 例「每年1、4、7、10月第一周周四报税」→ 这是每季度(1/4/7/10月)第一周周四：
      kind=rule, rule_period=quarterly, rule_week=1, rule_weekday=4
    - 「每月最后一个周五」等 → 近似用 rule_week=5（该月无第5周时自动跳过）

    **提醒时间：** 用 reminder_hour / reminder_minute 指定时分（默认 9:00）。日期类提醒会自动按目标月日计算，无需传 trigger_date。

    **回复风格：** 简洁友好，执行完告知创建了哪些提醒（例如"已创建 5 条生日提醒"）。
    """
}
