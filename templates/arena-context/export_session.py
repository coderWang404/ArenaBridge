#!/usr/bin/env python3
"""ArenaBridge 会话导出工具：从 opencode 本地数据库读取会话，生成 Markdown 转录。

用法：
    export_session.py --list            列出最近会话索引（ID | 时间 | 目录 | 标题）
    export_session.py <sessionID>       导出指定会话的完整转录到 stdout
"""
import datetime
import json
import os
import sqlite3
import sys

DB = os.path.expanduser("~/.local/share/opencode/opencode.db")
LIMIT = 50


def fmt_time(ms):
    try:
        return datetime.datetime.fromtimestamp(ms / 1000).strftime("%Y-%m-%d %H:%M")
    except Exception:
        return "—"


def one_line(s):
    return " ".join(str(s or "").split()).replace(" | ", " / ")


def connect():
    if not os.path.exists(DB):
        sys.stderr.write(f"找不到 opencode 数据库：{DB}\n")
        sys.exit(1)
    conn = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    return conn


def list_sessions(conn):
    rows = conn.execute(
        "SELECT id, title, directory, time_updated FROM session "
        "ORDER BY time_updated DESC LIMIT ?", (LIMIT,)
    ).fetchall()
    if not rows:
        print("（暂无会话）")
    for r in rows:
        print(f"{r['id']} | {fmt_time(r['time_updated'])} | {r['directory']} | {one_line(r['title'])}")


def render_parts(conn, message_id):
    chunks = []
    for p in conn.execute(
        "SELECT data FROM part WHERE message_id = ? ORDER BY time_created", (message_id,)
    ).fetchall():
        try:
            d = json.loads(p["data"])
        except Exception:
            continue
        t = d.get("type")
        if t == "text":
            txt = (d.get("text") or "").strip()
            if txt:
                chunks.append(txt)
        elif t == "reasoning":
            txt = (d.get("text") or "").strip()
            if txt:
                if len(txt) > 600:
                    txt = txt[:600] + " …（截断）"
                chunks.append(f"> [推理摘要] {txt}")
        elif t == "tool":
            tool = d.get("tool", "?")
            st = d.get("state") or {}
            inp = st.get("input") or {}
            brief = (
                inp.get("command") or inp.get("filePath") or inp.get("pattern")
                or inp.get("prompt") or inp.get("description") or ""
            )
            brief = one_line(brief).replace("\n", " ")[:160]
            chunks.append(f"`[工具] {tool}` {brief}".rstrip())
    return "\n\n".join(chunks)


def model_name(s):
    try:
        m = json.loads(s["model"] or "{}")
        return f"{m.get('providerID', '?')}/{m.get('id', '?')}" if m else "—"
    except Exception:
        return str(s["model"] or "—")


def export_session(conn, sid):
    s = conn.execute("SELECT * FROM session WHERE id = ?", (sid,)).fetchone()
    if not s:
        sys.stderr.write(f"未找到会话 {sid}（可先用 --list 查看）\n")
        sys.exit(1)
    out = [
        f"# {one_line(s['title'])}",
        "",
        f"- 会话 ID：{sid}",
        f"- 项目目录：{s['directory']}",
        f"- 模型：{model_name(s)}",
        f"- 最近更新：{fmt_time(s['time_updated'])}",
        "",
    ]
    for m in conn.execute(
        "SELECT * FROM message WHERE session_id = ? ORDER BY time_created", (sid,)
    ).fetchall():
        try:
            d = json.loads(m["data"])
        except Exception:
            continue
        role = d.get("role", "?")
        ts = fmt_time((d.get("time") or {}).get("created", m["time_created"]))
        header = "## 用户" if role == "user" else "## 助手"
        body = render_parts(conn, m["id"]) or "（无文本内容）"
        out.append(f"{header}（{ts}）")
        out.append("")
        out.append(body)
        out.append("")
    print("\n".join(out))


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("用法：export_session.py --list | export_session.py <sessionID>\n")
        sys.exit(2)
    conn = connect()
    if sys.argv[1] == "--list":
        list_sessions(conn)
    else:
        export_session(conn, sys.argv[1])
    conn.close()


if __name__ == "__main__":
    main()
