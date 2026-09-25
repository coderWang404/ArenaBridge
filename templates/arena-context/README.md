# Arena 上下文工作区

本目录由 ArenaBridge 管理，向远端 agent 提供本地 opencode 会话上下文：

| 文件 | 说明 |
| --- | --- |
| `transcript_current.md` | 最近一次会话的完整转录（`refresh.sh` 重生成） |
| `sessions_index.md` | 全部会话索引，格式：`ses_xxx \| 时间 \| 目录 \| 标题` |
| `export_session.py` | 导出任意会话转录：`python3 export_session.py <sessionID>`；`--list` 列出索引 |
| `refresh.sh` | 重生成上面两个文件；App「刷新上下文 / 重新导出会话」即调用它 |
| `arena_prompt.md` | 当前接入提示词快照（由 App 生成） |
| `arena_gate.sh` / `allowed_dirs.conf` / `arena_jail.sb` | 目录限制闸门（App 设置页管理，勿手改） |

数据来源：`~/.local/share/opencode/opencode.db`（只读打开，不影响 opencode 运行）。
