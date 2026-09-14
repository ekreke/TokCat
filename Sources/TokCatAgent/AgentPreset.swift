import Foundation

/// 一个可接入的 ACP agent 预设。
public struct AgentPreset: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    /// 可执行文件名（PATH 里查找）。
    public let executable: String
    /// 启动 ACP 的参数。
    public let arguments: [String]
    /// 一键安装命令（`/bin/zsh -lc` 执行）。自定义预设可为 nil。
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
    /// 自定义命令的预设 id。
    public static let customID = "custom"

    /// 本机常见、原生带 ACP 的 agent。
    public static let builtins: [AgentPreset] = [
        AgentPreset(
            id: "hermes",
            displayName: "Hermes",
            executable: "hermes",
            arguments: ["acp"],
            installCommand: "curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash",
            loginCommand: "hermes acp --setup",
            docsURL: "https://hermes-agent.nousresearch.com/docs/user-guide/features/acp"
        ),
        AgentPreset(
            id: "opencode",
            displayName: "OpenCode",
            executable: "opencode",
            arguments: ["acp"],
            installCommand: "brew install anomalyco/tap/opencode",
            loginCommand: "opencode auth login",
            docsURL: "https://opencode.ai/docs/acp/"
        ),
        AgentPreset(
            id: "gemini",
            displayName: "Gemini CLI",
            executable: "gemini",
            arguments: ["--acp"],
            installCommand: "brew install gemini-cli",
            loginCommand: "gemini",
            docsURL: "https://github.com/google-gemini/gemini-cli"
        ),
        AgentPreset(
            id: customID,
            displayName: "自定义命令",
            executable: "",
            arguments: [],
            installCommand: nil,
            loginCommand: nil,
            docsURL: nil
        ),
    ]

    public static func builtin(id: String) -> AgentPreset? {
        builtins.first { $0.id == id }
    }

    /// 把自定义命令字符串拆成可执行文件与参数（支持引号）。
    public static func parseCustomCommand(_ command: String) -> (executable: String, arguments: [String])? {
        let parts = command.split(separatedByWhitespaceRespectingQuotes: command)
        guard let first = parts.first, !first.isEmpty else { return nil }
        return (first, Array(parts.dropFirst()))
    }
}

private extension String {
    func split(separatedByWhitespaceRespectingQuotes: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        for character in self {
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == " " || character == "\t" {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
