import Foundation

/// 登入 shell 环境解析。
///
/// GUI 应用（从 Finder 启动）继承的是极简 PATH，通常找不到 `~/.local/bin`
/// 里的 hermes 等工具。这里用登入 shell 解析一次真实 PATH 并缓存。
public enum ShellEnvironment {
    private static let lock = NSLock()
    private static var cachedLoginPath: String?

    /// 登入 shell 的 PATH（带缓存）。
    public static func loginPath() -> String {
        lock.lock()
        if let cached = cachedLoginPath {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let resolved = resolveLoginPath() ?? fallbackPath()

        lock.lock()
        cachedLoginPath = resolved
        lock.unlock()
        return resolved
    }

    /// 供子进程使用的环境变量：把 PATH 换成登入 shell 的。
    public static func childEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = loginPath()
        return environment
    }

    /// 清除 PATH 缓存（安装/卸载后调用）。
    public static func invalidateCache() {
        lock.lock()
        cachedLoginPath = nil
        lock.unlock()
    }

    /// 在 PATH 中解析可执行文件的绝对路径。
    public static func resolve(_ executable: String) -> String? {
        guard !executable.isEmpty else { return nil }
        if executable.contains("/") {
            return FileManager.default.isExecutableFile(atPath: executable) ? executable : nil
        }
        var directories = loginPath().split(separator: ":").map(String.init)
        directories.append(contentsOf: fallbackDirectories)
        for directory in directories {
            let candidate = (directory as NSString).appendingPathComponent(executable)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func resolveLoginPath() -> String? {
        let marker = "__TOKCAT_PATH__"
        guard let output = capture(
            executable: "/bin/zsh",
            arguments: ["-lic", "printf '\(marker)%s' \"$PATH\""],
            timeout: 5
        ), let range = output.range(of: marker) else { return nil }
        let value = output[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static var fallbackDirectories: [String] {
        [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            ("~/.local/bin" as NSString).expandingTildeInPath,
            ("~/.hermes/bin" as NSString).expandingTildeInPath,
            ("~/.bun/bin" as NSString).expandingTildeInPath,
            ("~/.npm-global/bin" as NSString).expandingTildeInPath,
        ]
    }

    private static func fallbackPath() -> String {
        fallbackDirectories.joined(separator: ":")
    }

    /// 运行命令并捕获 stdout（带超时）。
    @discardableResult
    static func capture(executable: String, arguments: [String], timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = semaphore.wait(timeout: .now() + 1)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}

/// agent 可执行文件检测。
public enum AgentDetector {
    public enum Status: Equatable, Sendable {
        case ready(path: String)
        case missing
    }

    /// 检测本地 Hermes 是否可用（解析到可执行文件）。
    public static func localStatus() -> Status {
        if let path = ShellEnvironment.resolve(AgentPreset.hermes.executable) {
            return .ready(path: path)
        }
        return .missing
    }

    /// 本地启动配置；未找到可执行文件时返回 nil。
    public static func localLaunchConfiguration(cwd: String) -> ACPLaunchConfiguration? {
        guard let path = ShellEnvironment.resolve(AgentPreset.hermes.executable) else { return nil }
        return ACPLaunchConfiguration(
            executablePath: path,
            arguments: AgentPreset.hermes.arguments,
            cwd: cwd,
            environment: ShellEnvironment.childEnvironment()
        )
    }

    /// 远程（SSH）启动配置：`ssh <target> "<remote command>"`，`session/new` 用远端工作目录。
    public static func remoteLaunchConfiguration(
        _ config: RemoteSSHConfig,
        localCWD: String
    ) -> ACPLaunchConfiguration? {
        guard config.isConfigured,
              FileManager.default.isExecutableFile(atPath: SSHCommandBuilder.sshExecutable) else {
            return nil
        }
        return ACPLaunchConfiguration(
            executablePath: SSHCommandBuilder.sshExecutable,
            arguments: SSHCommandBuilder.arguments(config, command: config.remoteCommand),
            cwd: localCWD,
            sessionCWD: config.remoteWorkingDirectory,
            environment: ShellEnvironment.childEnvironment()
        )
    }
}
