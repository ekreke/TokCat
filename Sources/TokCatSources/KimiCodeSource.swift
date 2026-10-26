import Foundation
import TokCatCore

/// Kimi Code 会话日志采集源。
///
/// 文件：`~/.kimi-code/sessions/**/agents/*/wire.jsonl`
/// 只消费 `usage.record`，同一用量还会在 `step.end` 等事件中出现。
public final class KimiCodeSource: JSONLTokenSource {
    public init(store: SourceStateStore = SourceStateStore(),
                root: URL = AgentPaths.kimiCodeSessions) {
        super.init(
            id: "kimi",
            displayName: "Kimi Code",
            root: root,
            store: store
        )
    }

    public override func parse(path: String, line: String) -> TokenSample? {
        guard let object = JSON.parse(line),
              JSON.string(object, "type") == "usage.record",
              let usage = JSON.dict(object, "usage") else {
            return nil
        }

        let tokenUsage = TokenUsage(
            input: JSON.int(usage, "inputOther") ?? 0,
            output: JSON.int(usage, "output") ?? 0,
            cacheRead: JSON.int(usage, "inputCacheRead") ?? 0,
            cacheWrite: JSON.int(usage, "inputCacheCreation") ?? 0
        )
        guard !tokenUsage.isEmpty else { return nil }

        let timestamp = JSON.int(object, "time") ?? 0
        let agent = JSON.string(object, "agentId") ?? "main"
        return TokenSample(
            sourceId: id,
            id: "\(path)#\(agent)#\(timestamp)",
            at: DateParsing.parse(object["time"]) ?? Date(),
            model: JSON.string(object, "model"),
            usage: tokenUsage
        )
    }
}
