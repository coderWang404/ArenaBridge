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
    var contextDir: String = "~/arena-context"

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
}
