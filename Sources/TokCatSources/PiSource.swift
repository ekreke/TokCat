import Foundation
import TokCatCore

/// pi agent 会话日志采集源。
///
/// 文件：`~/.pi/agent/sessions/**/*.jsonl`
/// 字段：`message.usage.{input, output, cacheRead, cacheWrite, reasoning}`
public final class PiSource: JSONLTokenSource {
    public init(store: SourceStateStore = SourceStateStore(),
                root: URL = AgentPaths.piSessions) {
        super.init(
            id: "pi",
            displayName: "pi",
            root: root,
            store: store
        )
    }

    public override func parse(path: String, line: String) -> TokenSample? {
        guard let object = JSON.parse(line),
              let message = JSON.dict(object, "message"),
              JSON.string(message, "role") == "assistant",
              let usage = JSON.dict(message, "usage") else {
            return nil
        }

        let tokenUsage = TokenUsage(
            input: JSON.int(usage, "input") ?? 0,
            output: JSON.int(usage, "output") ?? 0,
            cacheRead: JSON.int(usage, "cacheRead") ?? 0,
            cacheWrite: JSON.int(usage, "cacheWrite") ?? 0
        )
        guard !tokenUsage.isEmpty else { return nil }

        let at = DateParsing.parse(object["timestamp"] ?? message["timestamp"]) ?? Date()
        let model = JSON.string(message, "model")
        let eventId = JSON.string(object, "id") ?? String(line.hashValue)
        return TokenSample(sourceId: id, id: "\(path)#\(eventId)", at: at, model: model, usage: tokenUsage)
    }
}
