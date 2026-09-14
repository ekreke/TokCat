import Foundation

/// 远程 Hermes 的 SSH 连接配置。
///
/// 通过 `ssh <target> "<remoteCommand>"` 把远端的 `hermes acp` 的 stdio
/// 转发到本地，ACP 客户端无需任何协议改动。
public struct RemoteSSHConfig: Equatable, Sendable {
    /// `~/.ssh/config` 别名（如 `be-tools`）或 `user@host`。
    public var target: String
    /// SSH 端口；留空用默认/配置。
    public var port: Int?
    /// 私钥路径（会展开 `~`）。GUI 应用可能没有 `SSH_AUTH_SOCK`，建议显式指定。
    public var identityFile: String?
    /// 远端启动命令，如 `hermes acp`。
    public var remoteCommand: String
    /// 登录 shell 包装（如 `zsh -lic`），解决非交互 SSH 的 PATH 问题；留空表示直接执行。
    public var loginShell: String
    /// 远端工作目录（传给 `session/new`）；留空表示远端 home。
    public var remoteWorkingDirectory: String

    public init(
        target: String = "",
        port: Int? = nil,
        identityFile: String? = "~/.ssh/id_ed25519",
        remoteCommand: String = "hermes acp",
        loginShell: String = "",
        remoteWorkingDirectory: String = ""
    ) {
        self.target = target
        self.port = port
        self.identityFile = identityFile
        self.remoteCommand = remoteCommand
        self.loginShell = loginShell
        self.remoteWorkingDirectory = remoteWorkingDirectory
    }

    public var isConfigured: Bool {
        !target.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// 生成 SSH 命令行（纯字符串逻辑，可单测）。
public enum SSHCommandBuilder {
    /// ssh 可执行文件路径。
    public static let sshExecutable = "/usr/bin/ssh"

    /// `remoteCommand` 在实际运行前套上登录 shell 包装。
    public static func effectiveRemoteCommand(_ config: RemoteSSHConfig, command: String) -> String {
        let shell = config.loginShell.trimmingCharacters(in: .whitespaces)
        guard !shell.isEmpty else { return command }
        return "\(shell) \(singleQuote(command))"
    }

    /// ssh 参数（不含可执行文件）。
    public static func arguments(_ config: RemoteSSHConfig, command: String) -> [String] {
        var args = ["-T"]
        args += ["-o", "BatchMode=yes"]
        args += ["-o", "StrictHostKeyChecking=accept-new"]
        args += ["-o", "ServerAliveInterval=30"]
        args += ["-o", "ServerAliveCountMax=3"]
        if let port = config.port, port > 0 {
            args += ["-p", String(port)]
        }
        if let identity = config.identityFile?.trimmingCharacters(in: .whitespaces), !identity.isEmpty {
            args += ["-i", (identity as NSString).expandingTildeInPath]
        }
        args.append(config.target.trimmingCharacters(in: .whitespaces))
        args.append(effectiveRemoteCommand(config, command: command))
        return args
    }

    /// 完整可执行 shell 命令（用于「测试连接」与日志）。
    public static func shellCommand(_ config: RemoteSSHConfig, command: String) -> String {
        let parts = [sshExecutable] + arguments(config, command: command)
        return parts.map(singleQuote).joined(separator: " ")
    }

    /// 连通性自检命令（`hermes acp --check`）。
    public static func checkCommand(_ config: RemoteSSHConfig) -> String {
        config.remoteCommand + " --check"
    }

    /// POSIX 单引号转义。
    static func singleQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
