# ArenaBridge

<img src="docs/icon.png" width="112" align="right" alt="ArenaBridge 图标">

**把远端 AI Agent 接进你的本地终端——但只在你说清楚的范围之内。** 原生 macOS App（SwiftUI），把「远端 Agent → 云服务器 → 反向隧道 → 本机 Mac」整条链路装进一个界面，并用 macOS 沙箱把 agent 锁死在你指定的目录里。

> **隐私边界：本软件不采集、不导出、不上传任何对话历史或会话内容。** 它只在服务器与本机之间传递 agent 的实时命令，运行目录 `~/.arena-bridge/` 只存放闸门文件与提示词快照，绝不触碰 opencode 数据库等会话数据；接入提示词里也明确禁止 agent 读取/上传对话上下文。

![ArenaBridge](docs/screenshot.png)

## 功能

| 页面 | 说明 |
| --- | --- |
| 概览 | 四项状态卡片（本机 sshd / 反向隧道 / 云服务器 / 目录限制）；一键启动停止隧道、全链路测试、打开 Arena、复制接入提示词 |
| 隧道 | 隧道开关（断线 5 秒自动重连）、运行时长、实时日志控制台（自动滚动） |
| 接入提示词 | 按服务器配置 + `~/.ssh/arena_server_key` 自动生成发给远端 agent 的接入指令，可复制 / 保存到本地 |
| 设置 | 服务器地址 / 用户 / 端口；密码安装公钥（不保存密码）；一键开启本机远程登录；重新生成接入密钥；**Arena 目录限制**（限制远端 agent 只能在指定目录工作）；Arena 网址；启动时自动开隧道 |

## 工作原理

```
远端 Agent 沙箱 ──ssh──► 云服务器 (sshd:22)
                            │  127.0.0.1:2222
                            ▲ 反向隧道（App 维持 ssh -N -R）
                            │
                        本机 Mac (sshd:22)
```

- **隧道**：`ssh -N -R 2222:localhost:22 user@server`，由 App 拉起并守护，断线 5 秒自动重连；隧道只绑服务器 `127.0.0.1`，公网扫不到。
- **服务器侧**：`~/enter_mac.sh` 封装了「从服务器进入 Mac」的命令，远端 agent 直接调用。
- **限制**：默认 agent 拥有完整 shell；开启目录限制后，它的每条命令先过 macOS `sandbox-exec` 沙箱，只能在你选定的目录内读写（见下文）。

## 架构

**全链路拓扑**（`docs/architecture_topology.png`，`swift make_arch.swift` 可重新生成）：

![全链路拓扑](docs/architecture_topology.png)

**App 内部架构**（`docs/architecture_app.png`）——视图层 → 状态服务层 → Shell 执行器 → 外部进程/文件，单向数据流：

![App 内部架构](docs/architecture_app.png)

## 目录限制（核心能力）

开启「设置 → Arena 目录限制」后，agent 的活动范围被锁死：

1. 打开开关，用「添加目录…」选择一个或多个允许目录（多选，可后续增删）。
2. App 会自动生成闸门三件套到 `~/.arena-bridge/`：`arena_gate.sh`（闸门脚本）、`allowed_dirs.conf`（允许清单）、`arena_jail.sb`（sandbox-exec profile），并通过 `~/.ssh/authorized_keys` 的 `command=` 把**服务器进入 Mac 的那把钥匙**（`arena_mac_key`，设置页可改路径）固定到闸门脚本上。
3. 之后 arena 经服务器进入本机的每条命令都会先经过闸门，由 macOS `sandbox-exec` 强制限制：
   - 允许目录：完整读写；`/tmp` 可作临时目录
   - 主目录其他位置：默认**读写都拒绝**（关闭「严格模式」后变为只读）
   - `~/.ssh`、`~/.gnupg`、`~/.aws`、`~/.config`、钥匙串等敏感位置与系统目录：一律禁止
   - 工具链（miniconda3 / cargo / nvm / pyenv / go 等）与系统运行时只读放行，保证编译、git 等能正常用
4. 允许目录之外的文件会被内核拒绝，`cd` 出去也落不了地；越界访问会返回 `Operation not permitted`。
5. 生成的接入提示词里会带上「目录限制」段落，agent 一拿到提示就知道边界；提示词同时明确禁止它读取或上传你的对话历史。
6. 关闭开关即刻恢复原状：App 自动把 `authorized_keys` 还原为普通公钥行（其他行原样保留）。

> 说明：限制发生在本机侧（kernel 沙箱），与服务器无关；即使服务器被入侵也绕不过这把闸。若系统缺少 `sandbox-exec`，闸门会退化为命令级路径校验并明确告警（强度低于沙箱，仅兜底）。

## 快速开始

1. 准备一台有公网 IP 的 Linux 服务器（Ubuntu 测试通过）；本机 macOS 14+。
2. 构建并运行：

   ```bash
   ./build.sh
   open build/ArenaBridge.app
   ```

3. 首次配置（设置页）：
   - 填服务器地址 / 用户名 / 端口 → 输入密码点「安装公钥」
   - 点「开启远程登录」授权本机 sshd（首次会弹管理员密码框）
   - 打开「Arena 目录限制」，添加允许目录，确认概览页四项状态全绿
4. 在远端 agent 的会话里粘贴「接入提示词」（概览页一键复制）。
5. 点「全链路测试」验证：命令会从服务器穿透到本机执行并原路返回。

> 提示：Mac 休眠会断开隧道，长任务建议接电源并开启防休眠；退出 App 会同时断开隧道。

## 构建环境

- macOS 14+，Xcode Command Line Tools（无需完整 Xcode）
- `swift build` 编译；`build.sh` 负责组装 `.app`、生成图标、ad-hoc 签名
- `swift make_arch.swift` 重新生成本文两张架构图

## 安全须知

- 这套方案本质是把本机 shell 交给远端 agent：只连接你信任的 agent / 服务，破坏性操作请先确认。
- 强烈建议开启「Arena 目录限制」，把远端 agent 锁在指定目录内（见上文），并定期检查服务器登录日志。
- 接入密钥（`~/.ssh/arena_server_key`）等同服务器密码，泄露后立即轮换；永远不要提交到任何仓库。
- 建议为远端接入使用专用密钥 / 专用账号。
- 本软件不接触任何会话/对话数据；也不要在「允许目录」里放你不想被 agent 看到的文件。

## 目录结构

```
Sources/ArenaBridge/
├── App.swift            # @main：窗口与依赖注入
├── AppModel.swift       # 状态中枢：配置、全链路测试、提示词生成、目录限制闸门部署
├── Config.swift         # AppConfig（UserDefaults 持久化，缺字段回落默认值）
├── Shell.swift          # 进程执行（超时 / 输出捕获）
├── TunnelManager.swift  # 反向隧道进程 + 日志 + 自动重连
├── StatusStore.swift    # 定时健康检查（sshd / 服务器 / 密钥）
└── Views/               # 概览 / 隧道 / 提示词 / 设置

make_arch.swift           # 架构图生成器 → docs/architecture_*.png
~/.arena-bridge/          # 运行目录（App 生成）：arena_gate.sh / allowed_dirs.conf / arena_jail.sb
```

## License

MIT
