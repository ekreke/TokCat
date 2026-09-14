import Foundation

/// 面向 UI 的统一 agent 事件（脱离 ACP 细节）。
public enum AgentEvent: Equatable, Sendable {
    /// 回答正文增量。
    case agentText(String)
    /// 模型思考增量。
    case agentThought(String)
    /// 工具开始执行。
    case toolCall(title: String)
    /// 工具状态更新。
    case toolUpdate(title: String?, status: String?)
    /// 计划/待办更新。
    case plan([String])
}

extension ACPSessionUpdate {
    /// 把协议层更新映射成 UI 事件；不需要展示的更新返回 nil。
    public var agentEvent: AgentEvent? {
        switch self {
        case let .agentMessageChunk(text):
            return text.isEmpty ? nil : .agentText(text)
        case let .agentThoughtChunk(text):
            return text.isEmpty ? nil : .agentThought(text)
        case let .toolCall(_, title, kind, _):
            return .toolCall(title: title ?? kind ?? "工具")
        case let .toolCallUpdate(_, title, status):
            return .toolUpdate(title: title, status: status)
        case let .plan(entries):
            return entries.isEmpty ? nil : .plan(entries)
        case .userMessageChunk, .sessionInfo, .usage, .availableCommands, .unknown:
            return nil
        }
    }
}
