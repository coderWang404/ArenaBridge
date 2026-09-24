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

    @Published var restrictionStatus = ""

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

    // MARK: - 目录限制（Arena Gate）

    var gateScriptPath: String { contextDir + "/arena_gate.sh" }
    var gateConfPath: String { contextDir + "/allowed_dirs.conf" }
    var gateProfilePath: String { contextDir + "/arena_jail.sb" }
    var authorizedKeysPath: String { NSHomeDirectory() + "/.ssh/authorized_keys" }

    func setRestrictionEnabled(_ on: Bool) {
        guard on != config.restrictionEnabled else { return }
        if on {
            let macPub = expandPath(config.macKeyPath) + ".pub"
            guard FileManager.default.fileExists(atPath: macPub) else {
                restrictionStatus = "找不到 Mac 接入公钥 \(macPub)，请先在「设置 → 密钥」确认路径"
                return
            }
            guard !config.allowedDirs.isEmpty else {
                restrictionStatus = "请先添加至少一个允许目录"
                return
            }
            config.restrictionEnabled = true
            deployGate()
        } else {
            uninstallGate()
        }
    }

    func addAllowedDirs(_ paths: [String]) {
        for var p in paths {
            p = normalizeDir(expandPath(p))
            guard !p.isEmpty, !config.allowedDirs.contains(p) else { continue }
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: p, isDirectory: &isDir) {
                try? FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true)
            }
            config.allowedDirs.append(p)
        }
        if config.restrictionEnabled {
            deployGate()
        } else {
            restrictionStatus = "已保存 \(config.allowedDirs.count) 个允许目录（尚未启用）"
        }
    }

    func removeAllowedDir(_ path: String) {
        config.allowedDirs.removeAll { $0 == path }
        if config.restrictionEnabled {
            deployGate()
        } else {
            restrictionStatus = "已移除目录"
        }
    }

    func setStrictReadMode(_ strict: Bool) {
        guard strict != config.strictReadMode else { return }
        config.strictReadMode = strict
        if config.restrictionEnabled { deployGate() }
    }

    /// 生成闸门三件套并改写 ~/.ssh/authorized_keys，把 Arena 的 Mac 接入密钥绑定到闸门。
    /// authorizedKeysOverride / artifactsDirOverride 仅用于测试，默认写入真实路径。
    @discardableResult
    func deployGate(authorizedKeysOverride: String? = nil, artifactsDirOverride: String? = nil) -> String {
        let fm = FileManager.default
        let ctxDir = artifactsDirOverride ?? contextDir
        let confPath = ctxDir + "/allowed_dirs.conf"
        let scriptPath = ctxDir + "/arena_gate.sh"
        let profilePath = ctxDir + "/arena_jail.sb"
        let authKeys = authorizedKeysOverride ?? authorizedKeysPath

        let allowed = config.allowedDirs.map { normalizeDir(expandPath($0)) }
        guard !allowed.isEmpty else {
            restrictionStatus = "允许目录为空，未部署"
            return restrictionStatus
        }

        if !fm.fileExists(atPath: ctxDir) {
            try? fm.createDirectory(atPath: ctxDir, withIntermediateDirectories: true)
        }

        do {
            try (allowed.joined(separator: "\n") + "\n")
                .write(toFile: confPath, atomically: true, encoding: .utf8)
            try Self.gateScript(confPath: confPath, profilePath: profilePath)
                .write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
            try jailProfile(allowedDirs: allowed)
                .write(toFile: profilePath, atomically: true, encoding: .utf8)
        } catch {
            restrictionStatus = "写入闸门文件失败：\(error.localizedDescription)"
            return restrictionStatus
        }

        let patch = rewriteAuthorizedKeys(at: authKeys, commandPath: scriptPath)
        let count = allowed.count
        if !config.restrictionEnabled && authorizedKeysOverride == nil {
            config.restrictionEnabled = true
        }
        restrictionStatus = "目录限制已部署（\(count) 个允许目录）：\(patch)"
        return restrictionStatus
    }

    @discardableResult
    func uninstallGate(authorizedKeysOverride: String? = nil) -> String {
        let patch = rewriteAuthorizedKeys(at: authorizedKeysOverride ?? authorizedKeysPath, commandPath: nil)
        config.restrictionEnabled = false
        restrictionStatus = "目录限制已关闭：\(patch)"
        return restrictionStatus
    }

    /// 在 authorized_keys 中增删闸门的 command= 绑定；install = nil 时还原为普通公钥行。
    private func rewriteAuthorizedKeys(at path: String, commandPath: String?) -> String {
        let begin = "# >>> arena-bridge directory restriction >>>"
        let end = "# <<< arena-bridge directory restriction <<<"

        let macPubPath = expandPath(config.macKeyPath) + ".pub"
        guard let pubFull = try? String(contentsOfFile: macPubPath, encoding: .utf8) else {
            return "找不到 Mac 接入公钥：\(macPubPath)"
        }
        let pubTokens = pubFull
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n")[0]
            .split(separator: " ", omittingEmptySubsequences: true)
        guard pubTokens.count >= 2 else { return "公钥格式异常：\(macPubPath)" }
        let pubBody = pubTokens[0] + " " + pubTokens[1]

        let existing = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let lines = existing.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // 剥掉旧的管理块，收集其中的公钥行（卸载时还原）
        var previousManaged: String?
        var cleaned: [String] = []
        var skipping = false
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t == begin { skipping = true; continue }
            if t == end { skipping = false; continue }
            if skipping {
                previousManaged = line
                continue
            }
            cleaned.append(line)
        }

        var out: [String] = []
        var inserted = false
        for line in cleaned {
            guard !inserted, line.contains(pubBody) else {
                out.append(line)
                continue
            }
            inserted = true
            if let cmd = commandPath {
                out.append(contentsOf: managedLine(command: cmd, existingLine: line))
            } else {
                out.append(stripCommandOption(previousManaged ?? line))
            }
        }
        if !inserted {
            // authorized_keys 里没有这把钥匙（含此前被闸门接管过的行）
            let restored = previousManaged ?? ("no-port-forwarding,no-agent-forwarding,no-x11-forwarding,no-user-rc " + pubBody)
            while out.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { out.removeLast() }
            out.append("")
            if commandPath != nil {
                out.append(contentsOf: managedLine(command: commandPath!, existingLine: restored))
            } else {
                out.append(stripCommandOption(restored))
            }
        }

        let dir = (path as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: dir) {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir)
        }
        var text = out.joined(separator: "\n")
        while text.hasSuffix("\n") { text.removeLast() }
        if !existing.hasPrefix("\n") {
            while text.hasPrefix("\n") { text.removeFirst() }
        }
        text += "\n"
        do {
            try text.write(toFile: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        } catch {
            return "写入 authorized_keys 失败：\(error.localizedDescription)"
        }
        return commandPath != nil
            ? (inserted ? "已绑定到现有 Mac 接入密钥" : "已追加 Mac 接入公钥")
            : "已还原 Mac 接入密钥"
    }

    private func managedLine(command: String, existingLine: String) -> [String] {
        let begin = "# >>> arena-bridge directory restriction >>>"
        let end = "# <<< arena-bridge directory restriction <<<"
        let tokens = existingLine
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        let (options, keyPart) = splitOptions(tokens)
        var prefix = "command=\"\(command)\""
        if !options.isEmpty { prefix += "," + options.joined(separator: ",") }
        return [begin, (prefix + " " + keyPart).trimmingCharacters(in: .whitespaces), end]
    }

    private func stripCommandOption(_ line: String) -> String {
        let tokens = line
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        let (options, keyPart) = splitOptions(tokens)
        let optionsPart = options.joined(separator: ",")
        return ([optionsPart, keyPart].filter { !$0.isEmpty }).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    /// 拆出 authorized_keys 行的选项列表（去逗号分段，剔除 command=）与密钥部分。
    /// 注意选项可能全部连在密钥类型前的同一个 token 里（command="..." 与逗号选项无空格）。
    private func splitOptions(_ tokens: [String]) -> (options: [String], keyPart: String) {
        var options: [String] = []
        var keyIndex = 0
        for (i, t) in tokens.enumerated() {
            if t.hasPrefix("ssh-") || t.hasPrefix("ecdsa-") || t.hasPrefix("sk-") {
                keyIndex = i
                break
            }
            for part in t.split(separator: ",", omittingEmptySubsequences: false) {
                let s = String(part)
                if !s.isEmpty && !s.hasPrefix("command=") { options.append(s) }
            }
        }
        let keyPart = tokens.isEmpty ? "" : tokens[keyIndex...].joined(separator: " ")
        return (options, keyPart)
    }

    // sandbox-exec profile：注意 satelbelt 规则「后匹配者胜出」，
    // 因此先写 sensitive/home 的 deny，再写允许目录与工具链的 allow。
    private func jailProfile(allowedDirs: [String]) -> String {
        let home = NSHomeDirectory()
        func q(_ s: String) -> String { "\"\(s)\"" }
        var rules: [String] = [";; ArenaBridge 目录限制 profile —— 由 ArenaBridge 自动生成，请勿手改"]
        for sensitive in [".ssh", ".gnupg", ".aws", ".kube", ".docker", ".config", ".netrc", "Library/Keychains", ".password-store", ".terraform.d"] {
            rules.append("(deny file-read* file-write* (subpath \(q(home + "/" + sensitive))))")
        }
        if config.strictReadMode {
            rules.append("(deny file-read* file-write* (subpath \(q(home))))")
        } else {
            rules.append("(deny file-write* (subpath \(q(home))))")
        }
        for dir in allowedDirs {
            rules.append("(allow file-read* file-write* (subpath \(q(dir))))")
        }
        rules.append("(allow file-read* file-write* (subpath \(q(contextDir))))")
        for tool in ["miniconda3", ".cargo", ".rustup", ".nvm", ".pyenv", ".rbenv", "go", ".local", ".npm", ".cache", ".volta", ".deno", ".bun", ".m2", ".gradle", ".sdkman", ".gem"] {
            rules.append("(allow file-read* (subpath \(q(home + "/" + tool))))")
        }
        rules.append("(allow file-read* (subpath \"/opt/homebrew\") (subpath \"/usr/local\") (subpath \"/usr\") (subpath \"/bin\") (subpath \"/sbin\") (subpath \"/opt\") (subpath \"/Library\") (subpath \"/System\") (subpath \"/private/etc\") (subpath \"/private/var\") (subpath \"/tmp\") (subpath \"/dev\"))")
        rules.append("(deny file-write* (subpath \"/System\") (subpath \"/bin\") (subpath \"/sbin\") (subpath \"/usr\") (subpath \"/Library\") (subpath \"/private/etc\") (subpath \"/private/var/db\"))")
        rules.append("(allow default)")
        return "(version 1)\n" + rules.joined(separator: "\n") + "\n"
    }

    private func normalizeDir(_ p: String) -> String {
        var r = p
        while r.count > 1 && r.hasSuffix("/") { r = String(r.dropLast()) }
        return r
    }

    func shortenPath(_ p: String) -> String {
        p.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    static func gateScript(confPath: String, profilePath: String) -> String {
        #"""
        #!/bin/bash
        # ArenaBridge 目录限制闸门 —— 由 ArenaBridge App 自动生成，请勿手工修改。
        # 通过 ~/.ssh/authorized_keys 的 command= 绑定到「服务器进入 Mac 的钥匙」：
        # 远端 agent 每次经服务器进入本机，都会先经过本脚本，命令被限制在允许目录内。
        set -u

        CONF="\#(confPath)"
        PROFILE="\#(profilePath)"

        export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/miniconda3/bin:/usr/bin:/bin:/usr/sbin:/sbin"

        log() { echo "[arena-gate] $*" >&2; }

        [ -r "$CONF" ] || { log "未找到允许目录配置 $CONF，已拒绝访问。"; exit 1; }
        ALLOWED=()
        while IFS= read -r line; do
          line="${line#"${line%%[![:space:]]*}"}"
          line="${line%"${line##*[![:space:]]}"}"
          [ -n "$line" ] && ALLOWED+=("$line")
        done < "$CONF"
        [ "${#ALLOWED[@]}" -gt 0 ] || { log "允许目录为空，已拒绝访问。"; exit 1; }

        have_sandbox() { [ -x /usr/bin/sandbox-exec ] && [ -r "$PROFILE" ]; }

        # —— 兜底校验（无 sandbox-exec 时）：解析命令里的绝对路径，拒绝越界 ——
        normalize_path() {
          local p="$1" out=() s r=""
          case "$p" in "~/"*) p="$HOME/${p#\~/}" ;; "~") p="$HOME" ;; esac
          [[ "$p" = /* ]] || p="$HOME/$p"
          local IFS='/'
          for s in $p; do
            case "$s" in
              ""|".") ;;
              "..") [ "${#out[@]}" -gt 0 ] && unset 'out[${#out[@]}-1]' ;;
              *) out+=("$s") ;;
            esac
          done
          for s in "${out[@]:-}"; do [ -n "$s" ] && r="$r/$s"; done
          printf '%s' "${r:-/}"
        }

        is_within() {
          local p="$1" r="${2%/}"
          [ "$p" = "$r" ] && return 0
          case "$p" in "$r"/*) return 0 ;; esac
          return 1
        }

        validate_command() {
          local cmd="$1" tok np root ok
          for tok in $cmd; do
            tok="${tok#*=}"
            case "$tok" in
              /*|~/*) ;;
              *) continue ;;
            esac
            np="$(normalize_path "$tok")"
            ok=0
            for root in "${ALLOWED[@]}" "$HOME/arena-context" /usr /bin /sbin /opt /usr/local /opt/homebrew /Library /System /private/etc /private/var /tmp /etc /dev; do
              if is_within "$np" "$root"; then ok=1; break; fi
            done
            if [ "$ok" -eq 0 ]; then
              log "路径不在允许目录内，已拒绝：$tok"
              return 1
            fi
          done
          return 0
        }

        if have_sandbox; then
          # 先落入允许目录，避免 shell-init: getcwd 警告
          work="${ALLOWED[0]}"
          for d in "${ALLOWED[@]}"; do
            case "${SSH_ORIGINAL_COMMAND:-}" in *"$d"*) work="$d"; break ;; esac
          done
          cd "$work" 2>/dev/null || true
          if [ -n "${SSH_ORIGINAL_COMMAND:-}" ]; then
            exec /usr/bin/sandbox-exec -f "$PROFILE" /bin/bash -c "$SSH_ORIGINAL_COMMAND"
          fi
          # 交互式会话：落在允许目录里的受限 shell
          exec /usr/bin/sandbox-exec -f "$PROFILE" /bin/bash -il
        fi

        log "警告：sandbox-exec 不可用，退化为命令级路径校验。"
        cd "${ALLOWED[0]}" 2>/dev/null || true
        if [ -n "${SSH_ORIGINAL_COMMAND:-}" ]; then
          validate_command "$SSH_ORIGINAL_COMMAND" || exit 1
          exec /bin/bash -c "$SSH_ORIGINAL_COMMAND"
        fi
        exec /bin/bash -il
        """#
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
        \(restrictionNote)
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

    private var restrictionNote: String {
        guard config.restrictionEnabled, !config.allowedDirs.isEmpty else { return "" }
        let dirs = config.allowedDirs.map { "        \(expandPath($0))" }.joined(separator: "\n")
        let extra = config.strictReadMode
            ? "允许目录之外的文件既不可读也不可写"
            : "允许目录之外的文件只读、不可修改"
        return """

        【目录限制】你只能在以下目录内工作（本机 App 已强制沙箱限制）：
        \(dirs)
        \(extra)，cd 到这些目录之外会失败；需要新目录时向我申请。
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

    var arenaPageURL: String {
        if let url = config.arenaURL?.trimmingCharacters(in: .whitespaces), !url.isEmpty {
            return url
        }
        return "https://arena.ai"
    }

    func openArena() {
        guard let url = URL(string: arenaPageURL) else { return }
        NSWorkspace.shared.open(url)
    }

    func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openInFinder(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
