import Foundation

/// ACP 方法名与协议常量。
public enum ACPMethod {
    public static let initialize = "initialize"
    public static let authenticate = "authenticate"
    public static let sessionNew = "session/new"
    public static let sessionLoad = "session/load"
    public static let sessionResume = "session/resume"
    public static let sessionPrompt = "session/prompt"
    public static let sessionCancel = "session/cancel"
    public static let sessionSetMode = "session/set_mode"
    public static let sessionUpdate = "session/update"
    public static let requestPermission = "session/request_permission"
    public static let fsReadTextFile = "fs/read_text_file"
    public static let fsWriteTextFile = "fs/write_text_file"
}

/// ACP v1 协议版本号。
public let ACPProtocolVersion = 1

// MARK: - 内容块

/// ACP 内容块。目前只处理文本；其它类型保留原始 JSON 以便容错。
public struct ACPContentBlock: Codable, Equatable, Sendable {
    public var type: String
    public var text: String?

    public init(type: String = "text", text: String? = nil) {
        self.type = type
        self.text = text
    }

    public static func text(_ text: String) -> ACPContentBlock {
        ACPContentBlock(type: "text", text: text)
    }
}

// MARK: - initialize

/// 客户端实现信息。
public struct ACPImplementation: Codable, Equatable, Sendable {
    public var name: String
    public var title: String?
    public var version: String

    public init(name: String, title: String? = nil, version: String) {
        self.name = name
        self.title = title
        self.version = version
    }
}

/// 客户端声明支持的文件系统能力。
public struct ACPFileSystemCapabilities: Codable, Equatable, Sendable {
    public var readTextFile: Bool
    public var writeTextFile: Bool

    public init(readTextFile: Bool = false, writeTextFile: Bool = false) {
        self.readTextFile = readTextFile
        self.writeTextFile = writeTextFile
    }
}

/// initialize 请求的客户端能力。默认全部关闭：让 agent 走自带工具。
public struct ACPClientCapabilities: Codable, Equatable, Sendable {
    public var fs: ACPFileSystemCapabilities?
    public var terminal: Bool?

    public init(fs: ACPFileSystemCapabilities? = nil, terminal: Bool? = nil) {
        self.fs = fs
        self.terminal = terminal
    }
}

public struct ACPInitializeParams: Codable, Equatable, Sendable {
    public var protocolVersion: Int
    public var clientCapabilities: ACPClientCapabilities
    public var clientInfo: ACPImplementation?

    public init(
        protocolVersion: Int = ACPProtocolVersion,
        clientCapabilities: ACPClientCapabilities = ACPClientCapabilities(),
        clientInfo: ACPImplementation? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.clientCapabilities = clientCapabilities
        self.clientInfo = clientInfo
    }
}

public struct ACPAuthMethod: Codable, Equatable, Sendable {
    public var id: String
    public var name: String?
    public var description: String?
}

public struct ACPAgentCapabilities: Codable, Equatable, Sendable {
    public var loadSession: Bool?
    public var promptCapabilities: ACPPromptCapabilities?
}

public struct ACPPromptCapabilities: Codable, Equatable, Sendable {
    public var image: Bool?
    public var audio: Bool?
    public var embeddedContext: Bool?
}

public struct ACPInitializeResult: Codable, Equatable, Sendable {
    public var protocolVersion: Int?
    public var agentCapabilities: ACPAgentCapabilities?
    public var agentInfo: ACPImplementation?
    public var authMethods: [ACPAuthMethod]?
}

// MARK: - session/new

public struct ACPNewSessionParams: Codable, Equatable, Sendable {
    public var cwd: String
    public var mcpServers: [JSONValue]

    public init(cwd: String, mcpServers: [JSONValue] = []) {
        self.cwd = cwd
        self.mcpServers = mcpServers
    }
}

public struct ACPSessionMode: Codable, Equatable, Sendable {
    public var id: String
    public var name: String?
    public var description: String?
}

public struct ACPSessionModeState: Codable, Equatable, Sendable {
    public var currentModeId: String?
    public var availableModes: [ACPSessionMode]?
}

public struct ACPNewSessionResult: Codable, Equatable, Sendable {
    public var sessionId: String
    public var modes: ACPSessionModeState?
}

// MARK: - session/prompt

public struct ACPPromptParams: Codable, Equatable, Sendable {
    public var sessionId: String
    public var prompt: [ACPContentBlock]

    public init(sessionId: String, prompt: [ACPContentBlock]) {
        self.sessionId = sessionId
        self.prompt = prompt
    }
}

public struct ACPPromptResult: Codable, Equatable, Sendable {
    public var stopReason: String?
}

// MARK: - session/cancel 与 session/set_mode

public struct ACPSessionIDParams: Codable, Equatable, Sendable {
    public var sessionId: String

    public init(sessionId: String) {
        self.sessionId = sessionId
    }
}

public struct ACPSetModeParams: Codable, Equatable, Sendable {
    public var sessionId: String
    public var modeId: String

    public init(sessionId: String, modeId: String) {
        self.sessionId = sessionId
        self.modeId = modeId
    }
}

// MARK: - session/update

/// `session/update` 通知中 `update` 字段的强类型视图（只覆盖 TokCat 需要的子集）。
public enum ACPSessionUpdate: Equatable, Sendable {
    case agentMessageChunk(text: String)
    case agentThoughtChunk(text: String)
    case userMessageChunk(text: String)
    case toolCall(id: String, title: String?, kind: String?, status: String?)
    case toolCallUpdate(id: String, title: String?, status: String?)
    case plan(entries: [String])
    case sessionInfo(title: String?)
    case usage
    case availableCommands
    case unknown(kind: String)

    /// 从 `update` 对象的判别字段 `sessionUpdate` 解析。
    public init(json: JSONValue) {
        let kind = json["sessionUpdate"]?.stringValue ?? ""
        switch kind {
        case "agent_message_chunk":
            self = .agentMessageChunk(text: Self.text(from: json["content"]))
        case "agent_thought_chunk":
            self = .agentThoughtChunk(text: Self.text(from: json["content"]))
        case "user_message_chunk":
            self = .userMessageChunk(text: Self.text(from: json["content"]))
        case "tool_call":
            self = .toolCall(
                id: json["toolCallId"]?.stringValue ?? "",
                title: json["title"]?.stringValue,
                kind: json["kind"]?.stringValue,
                status: json["status"]?.stringValue
            )
        case "tool_call_update":
            self = .toolCallUpdate(
                id: json["toolCallId"]?.stringValue ?? "",
                title: json["title"]?.stringValue,
                status: json["status"]?.stringValue
            )
        case "plan":
            let entries = json["entries"]?.arrayValue?.compactMap { entry -> String? in
                entry["content"]?.stringValue
            } ?? []
            self = .plan(entries: entries)
        case "session_info_update":
            self = .sessionInfo(title: json["title"]?.stringValue)
        case "usage_update":
            self = .usage
        case "available_commands_update":
            self = .availableCommands
        default:
            self = .unknown(kind: kind)
        }
    }

    private static func text(from content: JSONValue?) -> String {
        content?["text"]?.stringValue ?? ""
    }
}

public struct ACPSessionUpdateParams: Equatable, Sendable {
    public var sessionId: String
    public var update: ACPSessionUpdate

    public init(sessionId: String, update: ACPSessionUpdate) {
        self.sessionId = sessionId
        self.update = update
    }

    public init(json: JSONValue) {
        self.sessionId = json["sessionId"]?.stringValue ?? ""
        self.update = ACPSessionUpdate(json: json["update"] ?? .null)
    }
}

// MARK: - session/request_permission

public struct ACPPermissionOption: Codable, Equatable, Sendable {
    public var optionId: String
    public var name: String?
    public var kind: String?
}

public struct ACPPermissionToolCall: Codable, Equatable, Sendable {
    public var toolCallId: String?
    public var title: String?
    public var kind: String?
    public var status: String?
}

public struct ACPPermissionParams: Codable, Equatable, Sendable {
    public var sessionId: String
    public var toolCall: ACPPermissionToolCall?
    public var options: [ACPPermissionOption]
}

/// `session/request_permission` 的响应结果。
public struct ACPPermissionResult: Codable, Equatable, Sendable {
    public struct Outcome: Codable, Equatable, Sendable {
        public var outcome: String
        public var optionId: String?
    }

    public var outcome: Outcome

    public static func selected(_ optionId: String) -> ACPPermissionResult {
        ACPPermissionResult(outcome: Outcome(outcome: "selected", optionId: optionId))
    }

    public static let cancelled = ACPPermissionResult(outcome: Outcome(outcome: "cancelled"))
}
