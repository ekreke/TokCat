import Foundation
import TokCatCore

/// Codex 会话日志采集源。
///
/// 文件：`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`
/// 字段：`event_msg.token_count.info.last_token_usage`（单次请求增量，最适合算速率）
///
/// 注意：Codex 的 `input_tokens` 含缓存命中，需扣除 `cached_input_tokens` 避免重复计数；
/// `reasoning_output_tokens` 是 `output_tokens` 的子集，不再单独累计。
public final class CodexSource: JSONLTokenSource {
    public init(store: SourceStateStore = SourceStateStore(),
                root: URL = AgentPaths.codexSessions) {
        super.init(
            id: "codex",
            displayName: "Codex",
            root: root,
            store: store
        )
    }

    public override func parse(path: String, line: String) -> TokenSample? {
        guard let object = JSON.parse(line),
              let payload = JSON.dict(object, "payload") else {
            return nil
        }

        if let model = JSON.string(payload, "model"), !model.isEmpty {
            setModel(model, for: path)
        }

        guard JSON.string(payload, "type") == "token_count",
              let info = JSON.dict(payload, "info"),
              let last = JSON.dict(info, "last_token_usage") else {
            return nil
        }

        let rawInput = JSON.int(last, "input_tokens") ?? 0
        let cached = JSON.int(last, "cached_input_tokens") ?? 0
        let tokenUsage = TokenUsage(
            input: max(0, rawInput - cached),
            output: JSON.int(last, "output_tokens") ?? 0,
            cacheRead: cached,
            cacheWrite: JSON.int(last, "cache_write_input_tokens") ?? 0
        )
        guard !tokenUsage.isEmpty else { return nil }

        let at = DateParsing.parse(object["timestamp"]) ?? Date()
        let eventId = JSON.int(object, "ordinal").map(String.init)
            ?? String(line.hashValue)
        return TokenSample(
            sourceId: id,
            id: "\(path)#\(eventId)",
            at: at,
            model: model(for: path),
            usage: tokenUsage
        )
    }
}
