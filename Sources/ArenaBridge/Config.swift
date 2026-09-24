import Foundation

func expandPath(_ path: String) -> String {
    (path as NSString).expandingTildeInPath
}

struct AppConfig: Codable, Equatable {
    var host: String = "1.2.3.4"
    var user: String = "admin"
    var remotePort: Int = 2222
    var localPort: Int = 22
    var autoStart: Bool = true
    var tunnelKeyPath: String = "~/.ssh/id_ed25519"
    var serverKeyPath: String = "~/.ssh/arena_server_key"
    var macKeyPath: String = "~/.ssh/arena_mac_key"
    var contextDir: String = "~/arena-context"
    var arenaURL: String? = nil
    var restrictionEnabled: Bool = false
    var strictReadMode: Bool = true
    var allowedDirs: [String] = []

    static let defaultsKey = "dev.arena.bridge.config"

    static func load() -> AppConfig {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else {
            return AppConfig()
        }
        return config
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case host, user, remotePort, localPort, autoStart
        case tunnelKeyPath, serverKeyPath, macKeyPath
        case contextDir, arenaURL
        case restrictionEnabled, strictReadMode, allowedDirs
    }

    init() {}

    // decodeIfPresent 保证旧版本持久化数据缺字段时回落到默认值，而不是整体解析失败
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? "1.2.3.4"
        user = try c.decodeIfPresent(String.self, forKey: .user) ?? "admin"
        remotePort = try c.decodeIfPresent(Int.self, forKey: .remotePort) ?? 2222
        localPort = try c.decodeIfPresent(Int.self, forKey: .localPort) ?? 22
        autoStart = try c.decodeIfPresent(Bool.self, forKey: .autoStart) ?? true
        tunnelKeyPath = try c.decodeIfPresent(String.self, forKey: .tunnelKeyPath) ?? "~/.ssh/id_ed25519"
        serverKeyPath = try c.decodeIfPresent(String.self, forKey: .serverKeyPath) ?? "~/.ssh/arena_server_key"
        macKeyPath = try c.decodeIfPresent(String.self, forKey: .macKeyPath) ?? "~/.ssh/arena_mac_key"
        contextDir = try c.decodeIfPresent(String.self, forKey: .contextDir) ?? "~/arena-context"
        arenaURL = try c.decodeIfPresent(String.self, forKey: .arenaURL)
        restrictionEnabled = try c.decodeIfPresent(Bool.self, forKey: .restrictionEnabled) ?? false
        strictReadMode = try c.decodeIfPresent(Bool.self, forKey: .strictReadMode) ?? true
        allowedDirs = try c.decodeIfPresent([String].self, forKey: .allowedDirs) ?? []
    }
}
