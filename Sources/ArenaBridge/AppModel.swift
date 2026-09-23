import SwiftUI
import AppKit

final class AppModel: ObservableObject {
    @Published var config: AppConfig {
        didSet {
            config.save()
            tunnel.config = config
            status.config = config
        }
    }

    let tunnel: TunnelManager
    let status: StatusStore

    init() {
        let cfg = AppConfig.load()
        config = cfg
        tunnel = TunnelManager(config: cfg)
        status = StatusStore(config: cfg)
    }

    func onLaunch() {
        status.start()
        if config.autoStart && !tunnel.isRunning {
            tunnel.setEnabled(true)
        }
    }

    var contextDir: String { expandPath(config.contextDir) }

    func refreshContext(completion: ((String) -> Void)? = nil) {
        let script = contextDir + "/refresh.sh"
        guard FileManager.default.fileExists(atPath: script) else {
            completion?("未找到 \(script)")
            return
        }
        Shell.runAsync("/bin/bash", [script], timeout: 120) { result in
            let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            completion?(result.ok ? "上下文已刷新：\(text)" : "刷新失败：\(text)")
        }
    }

    func chainTest(completion: @escaping (String) -> Void) {
        let cfg = config
        let remoteCommand = "~/enter_mac.sh \"echo hello-from-arena-chain; hostname; whoami; date\""
        Shell.runAsync("/usr/bin/ssh", [
            "-i", expandPath(cfg.serverKeyPath),
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "IdentitiesOnly=yes",
            "\(cfg.user)@\(cfg.host)",
            remoteCommand
        ], timeout: 45) { result in
            let head = result.ok
                ? "全链路测试成功：arena 沙箱视角 → 服务器 → 反向隧道 → 本机 Mac"
                : "全链路测试失败（exit \(result.code)）"
            completion(head + "\n\n" + result.output)
        }
    }

    func generatePrompt() -> String {
        let keyPath = expandPath(config.serverKeyPath)
        let rawKey = (try? String(contentsOfFile: keyPath, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "(未找到 \(keyPath))"
        let key = rawKey.split(separator: "\n").joined(separator: "\n    ")
        return """
        【任务：接入我的本地 Mac 终端，并继续我的开发工作】

        我这边已经把反向隧道配置好了，你按下面步骤操作即可获得我本地 Mac 的完整终端。

        第一步：在沙箱里写入专用私钥（只需一次；若沙箱没有 ssh，先安装：apt-get install -y openssh-client）

            mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat > ~/.ssh/arena_server_key <<'KEYEOF'
            \(key)
            KEYEOF
            chmod 600 ~/.ssh/arena_server_key

        第二步：连接我的服务器

            ssh -i ~/.ssh/arena_server_key -o StrictHostKeyChecking=accept-new \(config.user)@\(config.host)

        第三步：从服务器进入我的 Mac（服务器上已备好进入密钥和脚本）

            ssh -i ~/.ssh/arena_server_key \(config.user)@\(config.host) '~/enter_mac.sh "echo CONNECTED; hostname; whoami"'

        或登录服务器后直接：

            ~/enter_mac.sh "命令"      # 在 Mac 上执行单条命令
            ~/enter_mac.sh             # 进入 Mac 的交互式 shell（配合 ssh -tt 使用）

        第四步：读取上下文，了解我的项目和之前的会话

            ssh -i ~/.ssh/arena_server_key \(config.user)@\(config.host) '~/enter_mac.sh "cat ~/arena-context/README.md"'
            ssh -i ~/.ssh/arena_server_key \(config.user)@\(config.host) '~/enter_mac.sh "cat ~/arena-context/transcript_current.md"'

        更多历史会话（按需导出）：

            ~/enter_mac.sh "python3 ~/arena-context/export_session.py --list"
            ~/enter_mac.sh "python3 ~/arena-context/export_session.py <sessionID>"

        完成以上步骤后，你就在我的 Mac 上拥有完整 shell 权限了（文件、终端、项目都在本地）。之后请像本地 agent 一样继续我的工作：
        - 我的项目主要在 ~/localprojects/ 下
        - 长命令建议写成脚本再执行，避免嵌套引号问题
        - 破坏性操作（删除、覆盖、推送）请先向我确认
        """
    }

    @discardableResult
    func writePromptFile() -> String {
        let text = generatePrompt()
        let path = contextDir + "/arena_prompt.md"
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openInFinder(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
