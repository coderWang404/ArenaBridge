import SwiftUI

enum CheckState: Equatable {
    case unknown
    case checking
    case ok
    case fail

    var label: String {
        switch self {
        case .unknown: return "未知"
        case .checking: return "检查中"
        case .ok: return "正常"
        case .fail: return "异常"
        }
    }

    var color: Color {
        switch self {
        case .unknown: return .secondary
        case .checking: return .orange
        case .ok: return .green
        case .fail: return .red
        }
    }
}

final class StatusStore: ObservableObject {
    @Published var localSSHD: CheckState = .unknown
    @Published var serverReachable: CheckState = .unknown
    @Published var keyAuth: CheckState = .unknown
    @Published var contextReady: CheckState = .unknown
    @Published var lastChecked: Date?

    var config: AppConfig

    private var timer: Timer?
    private var tick = 0

    init(config: AppConfig) {
        self.config = config
    }

    var overall: CheckState {
        if localSSHD == .fail || serverReachable == .fail || keyAuth == .fail { return .fail }
        if localSSHD == .ok && serverReachable == .ok && keyAuth == .ok { return .ok }
        return .checking
    }

    var overallText: String {
        switch overall {
        case .ok: return "链路已连通"
        case .fail: return "链路未就绪"
        default: return "检查中…"
        }
    }

    func start() {
        checkAll()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            self?.checkAll()
        }
    }

    func checkAll() {
        tick += 1
        let doKeyCheck = tick == 1 || tick % 5 == 0
        let cfg = config
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let sshdOpen = Shell.run("/usr/bin/nc", ["-z", "-G", "1", "127.0.0.1", "22"], timeout: 5).ok
            let reachable = Shell.run("/usr/bin/nc", ["-z", "-G", "3", cfg.host, "22"], timeout: 8).ok
            var keyOK = false
            if reachable && doKeyCheck {
                let r = Shell.run("/usr/bin/ssh", [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "-o", "IdentitiesOnly=yes",
                    "-i", expandPath(cfg.tunnelKeyPath),
                    "\(cfg.user)@\(cfg.host)",
                    "echo arena-bridge-ok"
                ], timeout: 12)
                keyOK = r.ok && r.output.contains("arena-bridge-ok")
            }
            let dir = expandPath(cfg.contextDir)
            let contextOK = ["transcript_current.md", "arena_prompt.md"].allSatisfy {
                FileManager.default.fileExists(atPath: dir + "/" + $0)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.localSSHD = sshdOpen ? .ok : .fail
                self.serverReachable = reachable ? .ok : .fail
                if reachable && doKeyCheck {
                    self.keyAuth = keyOK ? .ok : .fail
                } else if !reachable {
                    self.keyAuth = .fail
                }
                self.contextReady = contextOK ? .ok : .fail
                self.lastChecked = Date()
            }
        }
    }
}
