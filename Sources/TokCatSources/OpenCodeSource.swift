import Foundation
import TokCatCore

/// opencode 采集源：只读轮询 SQLite `message` 表的 tokens 字段。
///
/// 数据库：`~/.local/share/opencode/opencode.db`
/// 行格式：`message.data.tokens.{input, output, reasoning, cache.{read, write}}`（reasoning 与 output 并列，需累计）
public final class OpenCodeSource: TokenSource {
    public let id = "opencode"
    public let displayName = "opencode"
    public var isEnabled = true

    private let path: String
    private let pollLimit = 2000
    private let startFromNow: Bool
    private var db: SQLiteRO?
    private var cursorMs: Int64?
    private var lastOpenAttempt: Date = .distantPast

    public init(path: String = AgentPaths.openCodeDB, startFromNow: Bool = true) {
        self.path = path
        self.startFromNow = startFromNow
        self.db = SQLiteRO(path: path)
    }

    public func poll(now: Date) -> [TokenSample] {
        if db == nil, now.timeIntervalSince(lastOpenAttempt) > 30 {
            lastOpenAttempt = now
            db = SQLiteRO(path: path)
        }
        guard let db else { return [] }

        // 首次轮询从“当前时刻”开始，避免回填海量历史。
        if cursorMs == nil {
            cursorMs = startFromNow ? Int64(now.timeIntervalSince1970 * 1000) : 0
        }
        let cursor = cursorMs ?? 0

        var results: [TokenSample] = []
        var newCursor = cursor
        db.query(
            "SELECT id, time_created, data FROM message WHERE time_created > ? ORDER BY time_created ASC LIMIT \(pollLimit)",
            bind: [.int(cursor)]
        ) { row in
            let timestamp = row.int(1)
            if timestamp > newCursor { newCursor = timestamp }
            guard let raw = row.string(2),
                  let object = JSON.parse(raw),
                  JSON.string(object, "role") == "assistant",
                  let tokens = JSON.dict(object, "tokens") else {
                return
            }
            let cache = JSON.dict(tokens, "cache")
            let usage = TokenUsage(
                input: JSON.int(tokens, "input") ?? 0,
                output: JSON.int(tokens, "output") ?? 0,
                cacheRead: JSON.int(cache, "read") ?? 0,
                cacheWrite: JSON.int(cache, "write") ?? 0,
                reasoning: JSON.int(tokens, "reasoning") ?? 0
            )
            guard !usage.isEmpty else { return }
            let messageId = row.string(0) ?? String(timestamp)
            let at = DateParsing.date(fromEpoch: Double(timestamp))
            results.append(TokenSample(
                sourceId: id,
                id: messageId,
                at: at,
                model: JSON.string(object, "modelID"),
                usage: usage
            ))
        }
        cursorMs = newCursor
        return results
    }
}
