#!/usr/bin/env python3
"""Mock OpenAI /v1/chat/completions —— ask_user 历法澄清链路端到端测试用。

用法：python3 ReminderAppUITests/MockAIServer.py（监听 127.0.0.1:8899）
配套 AskUserCalendarUITests：按请求序号脚本应答（非按内容匹配——测的是
客户端链路，不是模型智力）。录制保留在内存：
  GET /state 返回全部录制摘要（供事后断言），GET /reset 清零。
  req0: 非流式 → ask_user(question="baba 2.10 是新历还是农历？", options=["新历","农历"])
  req1: 非流式 → create_reminder(lunar_birthday 2/10)
  req2: 流式   → 文本「已按农历创建：baba生日（农历） 2月10日 9:00」
  req3: 非流式 → create_reminder(lunar_birthday 2/11)   ← 模拟"沿用已确认历法"
  req4: 流式   → 文本「已按农历创建：mama生日（农历） 2月11日 9:00」
"""
import json
import threading
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = 8899
entries = []
dav_reads = 0
dav_writes = 0
dav_backup = json.loads((Path(__file__).parent.parent / "ReminderAppTests/fixtures/protocol_v3.json").read_text(encoding="utf-8"))


def tool_call(name, args):
    return {"id": "call-%s" % name, "type": "function",
            "function": {"name": name, "arguments": json.dumps(args, ensure_ascii=False)}}


def resp_tool(name, args):
    return {"id": "mock", "object": "chat.completion", "created": 0, "model": "mock",
            "choices": [{"index": 0,
                         "message": {"role": "assistant", "content": None,
                                     "tool_calls": [tool_call(name, args)]},
                         "finish_reason": "tool_calls"}],
            "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}}


def resp_text(text):
    return {"id": "mock", "object": "chat.completion", "created": 0, "model": "mock",
            "choices": [{"index": 0,
                         "message": {"role": "assistant", "content": text},
                         "finish_reason": "stop"}],
            "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}}


SCRIPT = [
    ("tool", "ask_user", {"question": "baba 2.10 是新历还是农历？",
                          "options": ["新历", "农历"]}),
    ("tool", "create_reminder", {"title": "baba生日（农历）", "kind": "date",
                                 "date_type": "lunar_birthday",
                                 "target_month": 2, "target_day": 10,
                                 "reminder_hour": 9, "reminder_minute": 0}),
    ("text", None, "已按农历创建：baba生日（农历） 2月10日 9:00"),
    ("tool", "create_reminder", {"title": "mama生日（农历）", "kind": "date",
                                 "date_type": "lunar_birthday",
                                 "target_month": 2, "target_day": 11,
                                 "reminder_hour": 9, "reminder_minute": 0}),
    ("text", None, "已按农历创建：mama生日（农历） 2月11日 9:00"),
]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(n) or b"{}")
        idx = len(entries)
        msgs = body.get("messages") or []
        entries.append({
            "index": idx,
            "stream": bool(body.get("stream")),
            "model": body.get("model"),
            "tool_names": [t.get("function", {}).get("name") for t in (body.get("tools") or [])],
            "system": next((m.get("content", "") for m in msgs if m.get("role") == "system"), ""),
            "messages": [{"role": m.get("role"), "content": m.get("content"),
                          "tool_calls": [(tc.get("function") or {}).get("name")
                                         for tc in (m.get("tool_calls") or [])]}
                         for m in msgs],
        })

        if idx >= len(SCRIPT):
            self._json(resp_text("剧本已结束"))
            return
        kind, name, payload = SCRIPT[idx]
        if body.get("stream"):
            self._sse(payload if kind == "text" else "")
        elif kind == "tool":
            self._json(resp_tool(name, payload))
        else:
            self._json(resp_text(payload))

    def do_PUT(self):
        global dav_writes, dav_backup
        dav_writes += 1
        dav_backup = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        self._json({"ok": True})

    def do_GET(self):
        global dav_reads, dav_writes
        if self.path == "/dav-state":
            self._json({"reads": dav_reads, "writes": dav_writes, "backup": dav_backup})
        elif self.path == "/dav-reset":
            dav_reads = 0; dav_writes = 0
            self._json({"ok": True})
        elif self.path == "/dav/reminder_backup.json":
            dav_reads += 1
            self._json(dav_backup)
        elif self.path.endswith("/state"):
            self._json({"requests": len(entries), "entries": entries})
        elif self.path.endswith("/reset"):
            entries.clear()
            self._json({"ok": True})
        else:
            self._json({"requests": len(entries)})

    def _json(self, obj):
        data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(200)
        self.send_header("ETag", '"uitest-dav-v1"')
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _sse(self, text):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        chunks = [text[i:i + 6] for i in range(0, len(text), 6)] or [""]
        for c in chunks:
            chunk = {"id": "m", "choices": [{"index": 0, "delta": {"content": c},
                                             "finish_reason": None}]}
            self.wfile.write(("data: " + json.dumps(chunk, ensure_ascii=False) + "\n\n").encode("utf-8"))
            self.wfile.flush()
        done = {"id": "m", "choices": [{"index": 0, "delta": {},
                                        "finish_reason": "stop"}],
                "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}}
        self.wfile.write(("data: " + json.dumps(done) + "\n\n").encode("utf-8"))
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()


class ModelsHandler(Handler):
    """Independent fixture: model/ping tests must not consume port8899's ask_user script."""
    def do_GET(self):
        if self.path.rstrip("/") == "/v1/models":
            self._json({"object": "list", "data": [
                {"id": "llama3.2", "object": "model"},
                {"id": "qwen2.5", "object": "model"},
            ]})
        else:
            self.send_error(404)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        self.rfile.read(length)
        self._json(resp_text("Mock model connection successful"))


if __name__ == "__main__":
    models = ThreadingHTTPServer(("127.0.0.1", 8898), ModelsHandler)
    threading.Thread(target=models.serve_forever, daemon=True).start()
    print("mock models8898 and scripted AI/WebDAV8899 ready", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
