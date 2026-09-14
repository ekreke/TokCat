import Foundation

/// Hermes agent 预设（TokCat 目前只接 Hermes）。
public struct AgentPreset: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    /// 可执行文件名（PATH 里查找）。
    public let executable: String
    /// 启动 ACP 的参数。
    public let arguments: [String]
    /// 一键安装命令。
    public let installCommand: String?
    /// 安装后引导登录/配置的命令（在终端里执行）。
    public let loginCommand: String?
    /// 官方文档地址。
    public let docsURL: String?

    public init(
        id: String,
        displayName: String,
        executable: String,
        arguments: [String],
        installCommand: String? = nil,
        loginCommand: String? = nil,
        docsURL: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.executable = executable
        self.arguments = arguments
        self.installCommand = installCommand
        self.loginCommand = loginCommand
        self.docsURL = docsURL
    }
}

extension AgentPreset {
    /// Hermes（本地）。
    public static let hermes = AgentPreset(
        id: "hermes",
        displayName: "Hermes",
        executable: "hermes",
        arguments: ["acp"],
        installCommand: "curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash",
        loginCommand: "hermes acp --setup",
        docsURL: "https://hermes-agent.nousresearch.com/docs/user-guide/features/acp"
    )
}
