import Foundation
import TokCatCore

/// Claude Code 会话日志采集源。
///
/// 文件：`~/.claude/projects/**/*.jsonl`
/// 字段：`message.usage.{input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens}`
public final class ClaudeCodeSource: JSONLTokenSource {
    public init(store: SourceStateStore = SourceStateStore(),
                root: URL = AgentPaths.claudeProjects) {
        super.init(
            id: "claude",
            displayName: "Claude Code",
            root: root,
            store: store
        )
    }

    public override func parse(path: String, line: String) -> TokenSample? {
        guard let object = JSON.parse(line),
              let message = JSON.dict(object, "message"),
              let usage = JSON.dict(message, "usage") else {
            return nil
        }

        // Anthropic 语义：input 不含缓存读写，各字段互不重叠。
        let tokenUsage = TokenUsage(
            input: JSON.int(usage, "input_tokens") ?? 0,
            output: JSON.int(usage, "output_tokens") ?? 0,
            cacheRead: JSON.int(usage, "cache_read_input_tokens") ?? 0,
            cacheWrite: JSON.int(usage, "cache_creation_input_tokens") ?? 0
        )
        guard !tokenUsage.isEmpty else { return nil }

        let at = DateParsing.parse(object["timestamp"]) ?? Date()
        let model = JSON.string(message, "model")
        let requestId = JSON.string(message, "id")
            ?? JSON.string(object, "uuid")
            ?? "\(path)#\(line.hashValue)"
        return TokenSample(sourceId: id, id: requestId, at: at, model: model, usage: tokenUsage)
    }
}
