#!/bin/bash
# ArenaBridge 上下文刷新：重生成 sessions_index.md（全部会话索引）
# 与 transcript_current.md（最近一次会话的完整转录）。
set -u
cd "$(dirname "$0")"

PY=python3
[ -x /usr/bin/python3 ] && PY=/usr/bin/python3

if [ ! -f "$PWD/export_session.py" ]; then
  echo "缺少 export_session.py（$PWD）"
  exit 1
fi

"$PY" export_session.py --list > sessions_index.md
LATEST=$(head -1 sessions_index.md | cut -d' ' -f1)

if [ -n "$LATEST" ] && [ "$LATEST" != "（暂无会话）" ]; then
  "$PY" export_session.py "$LATEST" > transcript_current.md
  echo "sessions_index: $(grep -c '^ses_' sessions_index.md) 个会话; transcript_current: $LATEST"
else
  : > transcript_current.md
  echo "未找到会话，transcript_current.md 已置空"
fi
