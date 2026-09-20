import Foundation
import TokCatCore

/// ZCode（智谱 GLM coding CLI）会话日志采集源。
///
/// 文件：`~/.zcode/cli/agents/sess_*/agent_*/transcript.jsonl`
/// 字段：`type == "model_complete"` 事件的 `payload.usage`（单次请求增量，最适合算速率）；
/// 模型名分散在 `model_network_status` 事件的 `payload.model.modelId`，按文件记录。
///
/// 注意：`inputTokens` 含缓存命中（实测 totalTokens = inputTokens + outputTokens），
/// 需扣除 `cacheReadTokens` 避免重复计数；部分事件的 usage 带 `reasoningTokens`，
/// 实测为 `outputTokens` 的子集，与 Codex 同理不重复累计。
public final class ZCodeSource: JSONLTokenSource {
    public init(store: SourceStateStore = SourceStateStore(),
                root: URL = AgentPaths.zcodeAgents) {
        super.init(
            id: "zcode",
            displayName: "ZCode",
            root: root,
            store: store
        )
    }

    public override func parse(path: String, line: String) -> TokenSample? {
        guard let object = JSON.parse(line),
              let payload = JSON.dict(object, "payload") else {
            return nil
        }

        let type = JSON.string(object, "type")

        if type == "model_network_status",
           let model = JSON.dict(payload, "model").flatMap({ JSON.string($0, "modelId") }),
           !model.isEmpty {
            setModel(model, for: path)
            return nil
        }

        guard type == "model_complete",
              let usage = JSON.dict(payload, "usage") else {
            return nil
        }

        let rawInput = JSON.int(usage, "inputTokens") ?? 0
        let cached = JSON.int(usage, "cacheReadTokens") ?? 0
        let tokenUsage = TokenUsage(
            input: max(0, rawInput - cached),
            output: JSON.int(usage, "outputTokens") ?? 0,
            cacheRead: cached,
            cacheWrite: JSON.int(usage, "cacheWriteTokens") ?? 0
        )
        guard !tokenUsage.isEmpty else { return nil }

        let at = DateParsing.parse(object["timestamp"]) ?? Date()
        let eventId = JSON.string(object, "id") ?? String(line.hashValue)
        return TokenSample(
            sourceId: id,
            id: "\(path)#\(eventId)",
            at: at,
            model: model(for: path),
            usage: tokenUsage
        )
    }
}
