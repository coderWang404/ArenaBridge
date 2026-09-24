import Foundation
import Combine

final class TunnelManager: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var logs: [String] = []
    @Published private(set) var startedAt: Date?
    @Published var enabled = false

    var config: AppConfig

    private var process: Process?
    private var pendingRestart: DispatchWorkItem?

    init(config: AppConfig) {
        self.config = config
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        if on {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard process == nil else { return }
        let keyPath = expandPath(config.tunnelKeyPath)
        guard FileManager.default.fileExists(atPath: keyPath) else {
            append("找不到密钥文件：\(keyPath)")
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        p.arguments = [
            "-N",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-o", "TCPKeepAlive=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "IdentitiesOnly=yes",
            "-i", keyPath,
            "-R", "\(config.remotePort):localhost:\(config.localPort)",
            "\(config.user)@\(config.host)"
        ]
        p.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.append(text)
        }
        p.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                guard let self else { return }
                self.process = nil
                self.isRunning = false
                self.startedAt = nil
                self.append("隧道进程退出（状态码 \(proc.terminationStatus)）")
                if self.enabled {
                    self.append("5 秒后自动重连…")
                    let item = DispatchWorkItem { [weak self] in self?.start() }
                    self.pendingRestart = item
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: item)
                }
            }
        }
        do {
            try p.run()
        } catch {
            append("启动失败：\(error.localizedDescription)")
            return
        }
        process = p
        isRunning = true
        startedAt = Date()
        append("隧道已启动：\(config.user)@\(config.host) 的 127.0.0.1:\(config.remotePort) → 本机 \(config.localPort)")
    }

    func stop() {
        enabled = false
        pendingRestart?.cancel()
        pendingRestart = nil
        if let p = process {
            append("正在停止隧道…")
            p.terminate()
        } else {
            isRunning = false
            startedAt = nil
        }
    }

    /// 退出 App 时同步清理隧道进程，避免留下孤儿 ssh 占住远端端口。
    func terminateNow() {
        enabled = false
        pendingRestart?.cancel()
        pendingRestart = nil
        if let p = process, p.isRunning {
            p.terminate()
            let deadline = Date().addingTimeInterval(1.5)
            while p.isRunning && Date() < deadline {
                usleep(30_000)
            }
            if p.isRunning {
                kill(p.processIdentifier, SIGKILL)
            }
        }
        process = nil
        isRunning = false
        startedAt = nil
    }

    func clearLogs() {
        logs.removeAll()
    }

    func append(_ text: String) {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let stamp = Self.formatter.string(from: Date())
            for line in lines {
                self.logs.append("[\(stamp)] \(line)")
            }
            if self.logs.count > 800 {
                self.logs.removeFirst(self.logs.count - 800)
            }
        }
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
