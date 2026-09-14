import Foundation

/// Token 消耗的分类统计。
public struct TokenUsage: Equatable, Sendable {
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    public var cacheWrite: Int
    public var reasoning: Int

    public init(
        input: Int = 0,
        output: Int = 0,
        cacheRead: Int = 0,
        cacheWrite: Int = 0,
        reasoning: Int = 0
    ) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.reasoning = reasoning
    }

    public static let zero = TokenUsage()

    /// 所有分类求和。
    public var total: Int { input + output + cacheRead + cacheWrite + reasoning }

    /// 仅真实输入与输出（不含缓存与推理）。
    public var inputOutput: Int { input + output }

    public var isEmpty: Bool { total == 0 }

    public static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
            reasoning: lhs.reasoning + rhs.reasoning
        )
    }

    public static func += (lhs: inout TokenUsage, rhs: TokenUsage) {
        lhs = lhs + rhs
    }

    /// 逐字段相减（用于按消息累计值求增量），结果不为负。
    public static func - (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            input: max(0, lhs.input - rhs.input),
            output: max(0, lhs.output - rhs.output),
            cacheRead: max(0, lhs.cacheRead - rhs.cacheRead),
            cacheWrite: max(0, lhs.cacheWrite - rhs.cacheWrite),
            reasoning: max(0, lhs.reasoning - rhs.reasoning)
        )
    }
}

/// 一次 token 消耗事件（通常对应一次模型请求/一条会话记录）。
public struct TokenSample: Equatable, Sendable, Identifiable {
    /// 采集源标识，例如 "opencode" / "claude" / "codex" / "pi"。
    public let sourceId: String
    /// 事件唯一标识，用于去重。
    public let id: String
    /// 事件发生时间。
    public let at: Date
    /// 使用的模型名，用于定价换算（金额模式）。
    public let model: String?
    /// 本次消耗的分类统计。
    public let usage: TokenUsage

    public init(sourceId: String, id: String, at: Date, model: String? = nil, usage: TokenUsage) {
        self.sourceId = sourceId
        self.id = id
        self.at = at
        self.model = model
        self.usage = usage
    }
}
