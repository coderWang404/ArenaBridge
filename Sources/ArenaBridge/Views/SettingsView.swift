import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var status: StatusStore

    @State private var password = ""
    @State private var message = ""
    @State private var manualDir = ""

    var body: some View {
        Form {
            Section("服务器") {
                TextField("主机 / IP", text: $model.config.host)
                TextField("用户名", text: $model.config.user)
                TextField("远程端口", value: $model.config.remotePort, format: .number)
                HStack {
                    SecureField("SSH 密码（仅用于安装公钥，不保存）", text: $password)
                    Button("安装公钥") { installKey() }
                        .disabled(password.isEmpty)
                }
                if !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("本机") {
                LabeledContent("远程登录 (sshd)", value: status.localSSHD.label)
                HStack {
                    Button("开启远程登录") { enableRemoteLogin() }
                    Button("打开共享设置") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Sharing-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("立即检查") { status.checkAll() }
                }
            }

            Section("密钥") {
                TextField("隧道密钥", text: $model.config.tunnelKeyPath)
                TextField("Arena 接入密钥", text: $model.config.serverKeyPath)
                TextField("Mac 接入密钥（服务器进入本机用）", text: $model.config.macKeyPath)
                Button("重新生成 Arena 接入密钥") { regenerateServerKey() }
            }

            Section("Arena 目录限制") {
                Toggle("启用目录限制", isOn: Binding(
                    get: { model.config.restrictionEnabled },
                    set: { model.setRestrictionEnabled($0) }
                ))
                VStack(alignment: .leading, spacing: 8) {
                    if model.config.allowedDirs.isEmpty {
                        Text(model.config.restrictionEnabled
                             ? "尚未添加允许目录——Arena 将被完全拒绝访问，请先添加。"
                             : "先添加允许的目录，再打开上面的开关。")
                            .font(.caption)
                            .foregroundStyle(model.config.restrictionEnabled ? .red : .secondary)
                    } else {
                        ForEach(model.config.allowedDirs, id: \.self) { dir in
                            HStack(spacing: 8) {
                                Image(systemName: "folder")
                                    .foregroundStyle(.secondary)
                                Text(model.shortenPath(dir))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button {
                                    model.removeAllowedDir(dir)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                                .help("移除 \(dir)")
                            }
                        }
                    }
                    Button("添加目录…") { pickAllowedDirs() }
                    Toggle("严格模式：同时禁止读取允许目录之外的文件", isOn: Binding(
                        get: { model.config.strictReadMode },
                        set: { model.setStrictReadMode($0) }
                    ))
                    if model.config.restrictionEnabled {
                        Text("""
                        已启用：Arena 经服务器进入本机的每条命令都会经过 macOS 沙箱强制限制。
                        只能在上面目录内读写；~/arena-context（会话上下文）始终可读写；
                        ~/.ssh、钥匙串等敏感位置与系统目录一律禁止；关闭严格模式后，其他位置的文件变为只读。
                        关闭开关即刻恢复原状（自动还原 ~/.ssh/authorized_keys）。
                        """)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("""
                        启用后，Arena 经服务器进入本机的每条命令都会经过 macOS 沙箱强制限制：
                        只能在上面选择的目录内读写文件；~/arena-context（会话上下文）始终可读写；
                        ~/.ssh、钥匙串等敏感位置与系统目录一律禁止；关闭严格模式后，其他位置的文件变为只读。
                        """)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
                if !model.restrictionStatus.isEmpty {
                    Text(model.restrictionStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Arena") {
                TextField("Arena 网址", text: Binding(
                    get: { model.config.arenaURL ?? "https://arena.ai" },
                    set: { model.config.arenaURL = $0 }
                ))
                Button("在默认浏览器中打开") { model.openArena() }
            }

            Section("启动") {
                Toggle("启动 App 时自动开启隧道", isOn: $model.config.autoStart)
            }

            Section("关于") {
                LabeledContent("版本", value: "1.0")
                Text("Arena Agent → 阿里云服务器 → 反向隧道 → 本机 Mac。把本地终端借给 Arena 上选中的 agent，并把会话上下文一并交底。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func pickAllowedDirs() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        panel.title = "选择 Arena 允许工作的目录"
        if panel.runModal() == .OK {
            model.addAllowedDirs(panel.urls.map(\.path))
        }
    }

    private func installKey() {
        let pubPath = expandPath(model.config.tunnelKeyPath) + ".pub"
        guard let pub = try? String(contentsOfFile: pubPath, encoding: .utf8) else {
            message = "找不到公钥文件：\(pubPath)"
            return
        }
        let script = """
        set timeout 30
        spawn ssh -o StrictHostKeyChecking=accept-new -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1 $env(SSH_USER)@$env(SSH_HOST) "mkdir -p ~/.ssh && chmod 700 ~/.ssh && (grep -qF '$env(PUBKEY)' ~/.ssh/authorized_keys 2>/dev/null || echo '$env(PUBKEY)' >> ~/.ssh/authorized_keys); chmod 600 ~/.ssh/authorized_keys; echo KEY_INSTALLED_OK"
        expect {
            -re "(?i)password:" { send "$env(SSH_PASS)\\r"; exp_continue }
            "KEY_INSTALLED_OK" { exp_continue }
            -re "(?i)permission denied" { puts "AUTH_FAILED"; exit 2 }
            timeout { puts "TIMEOUT"; exit 1 }
            eof { }
        }
        """
        let tmp = NSTemporaryDirectory() + "arena_bridge_install.exp"
        try? script.write(toFile: tmp, atomically: true, encoding: .utf8)
        message = "正在安装公钥…"
        Shell.runAsync("/usr/bin/expect", [tmp], timeout: 40, extraEnv: [
            "SSH_USER": model.config.user,
            "SSH_HOST": model.config.host,
            "SSH_PASS": password,
            "PUBKEY": pub.trimmingCharacters(in: .whitespacesAndNewlines)
        ]) { result in
            message = result.ok ? "公钥安装完成，可点击「立即检查」验证" : "安装失败：\(result.output)"
            password = ""
            status.checkAll()
        }
    }

    private func enableRemoteLogin() {
        let script = "do shell script \"launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist; launchctl kickstart -k system/com.openssh.sshd\" with administrator privileges"
        message = "请在弹窗中输入本机管理员密码…"
        Shell.runAsync("/usr/bin/osascript", ["-e", script], timeout: 180) { result in
            message = result.ok ? "远程登录已开启" : "开启失败：\(result.output)"
            status.checkAll()
        }
    }

    private func regenerateServerKey() {
        let path = expandPath(model.config.serverKeyPath)
        try? FileManager.default.removeItem(atPath: path)
        try? FileManager.default.removeItem(atPath: path + ".pub")
        let result = Shell.run("/usr/bin/ssh-keygen", [
            "-t", "ed25519", "-N", "", "-C", "arena-agent-server", "-f", path
        ], timeout: 15)
        if result.ok {
            message = "已生成新密钥：\(path)（记得重新复制接入提示词发给 Arena，并重新安装到服务器）"
        } else {
            message = "生成失败：\(result.output)"
        }
    }
}
