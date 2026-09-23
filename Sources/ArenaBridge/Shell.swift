import Foundation

enum Shell {
    static let baseEnvironment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let extra = "/opt/homebrew/bin:/usr/local/bin:\(home)/miniconda3/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = extra + ":" + (env["PATH"] ?? "")
        return env
    }()

    struct Result {
        let code: Int32
        let output: String
        var ok: Bool { code == 0 }
    }

    @discardableResult
    static func run(
        _ launchPath: String,
        _ arguments: [String],
        timeout: TimeInterval = 30,
        extraEnv: [String: String] = [:]
    ) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        var env = baseEnvironment
        for (key, value) in extraEnv { env[key] = value }
        process.environment = env
        process.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let lock = NSLock()
        var collected = Data()
        let readerDone = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            lock.lock()
            collected.append(data)
            lock.unlock()
            readerDone.signal()
        }

        do {
            try process.run()
        } catch {
            return Result(code: -1, output: "无法启动 \(launchPath)：\(error.localizedDescription)")
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(40_000)
        }
        var timedOut = false
        if process.isRunning {
            timedOut = true
            process.terminate()
        }
        process.waitUntilExit()
        _ = readerDone.wait(timeout: .now() + 3)

        lock.lock()
        let data = collected
        lock.unlock()
        let output = String(data: data, encoding: .utf8) ?? ""
        return Result(code: timedOut ? -2 : process.terminationStatus, output: timedOut ? output + "\n[命令超时]" : output)
    }

    static func runAsync(
        _ launchPath: String,
        _ arguments: [String],
        timeout: TimeInterval = 60,
        extraEnv: [String: String] = [:],
        completion: @escaping (Result) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = run(launchPath, arguments, timeout: timeout, extraEnv: extraEnv)
            DispatchQueue.main.async { completion(result) }
        }
    }
}
