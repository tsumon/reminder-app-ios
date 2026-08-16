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
"weekday":  ["type": "integer", "description": "【每周/每两周提醒必须填】用户指定的星期：1=周一…7=周日。例：「每周日打针」→ cycle=weekly, weekday=7；「每周三开会」→ weekday=3"],
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
        ],
        [
            "type": "function",
            "function": [
                "name": "import_tasks",
                "description": "把用户给的多段待办文本批量解析为多条提醒并预览，确认后再批量创建",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "items": [
                            "type": "array",
                            "description": "逐条待办，每条解析为一条提醒。一行同时含新历+旧历生日时必须拆成两条 item（solar_birthday 与 lunar_birthday 各一条，title 加（公历）/（农历）后缀），不许只取其一",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "title":         ["type": "string", "description": "提醒标题"],
                                    "note":          ["type": "string", "description": "备注（可选）"],
                                    "kind":          ["type": "string", "enum": ["cycle", "date", "rule"], "description": "周期/日期/规则"],
                                    "cycle":         ["type": "string", "enum": ["daily","weekly","biweekly","monthly","quarterly","yearly","custom","once"], "description": "周期类型"],
                                    "custom_days":   ["type": "integer", "description": "自定义天数"],
                                    "rule_period":   ["type": "string", "enum": ["monthly","quarterly","yearly"], "description": "规则频率"],
                                    "rule_week":     ["type": "integer", "description": "第几周 1-5"],
                                    "rule_weekday":  ["type": "integer", "description": "周几 1=周一...7=周日"],
                                    "date_type":     ["type": "string", "enum": ["solar_birthday","lunar_birthday","holiday"], "description": "日期子类型"],
                                    "target_month":  ["type": "integer", "description": "目标月 1-12"],
                                    "target_day":    ["type": "integer", "description": "目标日 1-31"],
                                    "holiday_name":  ["type": "string", "description": "节假日名称"],
                                    "advance_days":  ["type": "integer", "description": "提前天数，默认3"],
                                    "reminder_hour": ["type": "integer", "description": "小时 0-23，默认9"],
                                    "reminder_minute": ["type": "integer", "description": "分钟 0-59，默认0"]
                                ]
                            ]
                        ]
                    ],
                    "required": ["items"]
                ]
            ]
        ]
    ]

    // MARK: - 系统提示词

    /// v2.4.1: 当前日期上下文（模型不知道"今天"是几号，必须注入才能算对"下周日"）
    private static var todayContext: String {
        let cal = Calendar.current
        let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let dow = max(0, cal.component(.weekday, from: Date()) - 1)
        return String(
            format: "今天是 %d年%d月%d日（%@）。用户说「下周日」「明天」等相对时间时，必须基于这个日期计算 trigger_date（yyyy-MM-dd）。\n",
            cal.component(.year, from: Date()),
            cal.component(.month, from: Date()),
            cal.component(.day, from: Date()),
            weekdays[min(dow, 6)]
        )
    }

    static let systemPrompt = todayContext + """

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

    **批量创建（关键）：** 若用户一次给出多个生日，必须为**每个人、每个日期**分别调用一次 create_reminder（一次只创建一条）。v2.4.8 fix：同一人同时给出"新历/公历"和"旧历/农历"两个日期时，**必须创建两条**——一条 date_type=solar_birthday（title 后缀"（公历）"），一条 date_type=lunar_birthday（title 后缀"（农历）"），不可只取其一。只给了一个历法的日期时建对应一条。注意"旧历，12月18"这类用逗号代替冒号的写法也要解析。示例"老娘生日:新历1月14号，旧历12月18"→ 两条：〔老娘生日（公历）, solar 1/14〕+〔老娘生日（农历）, lunar 12/18〕。不要漏掉任何一个人或任何一个日期。

    **批量整理（关键）：** 若用户粘贴了一段包含多条待办的文字（聊天记录 / 便签 / 需求文档 / 多行清单），→ 调用 import_tasks，把每段解析为一条提醒（尽量补全 title / 周期 / 时间），批量预览确认后再创建。不要逐条调用 create_reminder。

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
