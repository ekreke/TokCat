import Foundation
import TokCatCore

/// cc-switch 采集源（可选）：直接读取其已聚合的请求日志。
///
/// 数据库：`~/.cc-switch/cc-switch.db` 表 `proxy_request_logs`
/// 一个源即可覆盖 claude/codex/opencode/pi（取决于 cc-switch 是否在运行采集）。
public final class CcSwitchDBSource: TokenSource {
    public let id = "cc-switch"
    public let displayName = "cc-switch (聚合)"
    public var isEnabled = false
    public var defaultEnabled: Bool { false }

    private let path: String
    private let pollLimit = 2000
    private let startFromNow: Bool
    private var db: SQLiteRO?
    private var cursorSeconds: Int64?
    private var lastOpenAttempt: Date = .distantPast

    public init(path: String = AgentPaths.ccSwitchDB, startFromNow: Bool = true) {
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

        if cursorSeconds == nil {
            cursorSeconds = startFromNow ? Int64(now.timeIntervalSince1970) : 0
        }
        let cursor = cursorSeconds ?? 0

        var results: [TokenSample] = []
        var newCursor = cursor
        db.query(
            """
            SELECT request_id, model, input_tokens, output_tokens, cache_read_tokens,
                   cache_creation_tokens, created_at
            FROM proxy_request_logs
            WHERE created_at > ?
            ORDER BY created_at ASC
            LIMIT \(pollLimit)
            """,
            bind: [.int(cursor)]
        ) { row in
            let createdAt = row.int(6)
            if createdAt > newCursor { newCursor = createdAt }
            let usage = TokenUsage(
                input: Int(row.int(2)),
                output: Int(row.int(3)),
                cacheRead: Int(row.int(4)),
                cacheWrite: Int(row.int(5))
            )
            guard !usage.isEmpty else { return }
            let requestId = row.string(0) ?? String(createdAt)
            results.append(TokenSample(
                sourceId: self.id,
                id: requestId,
                at: Date(timeIntervalSince1970: Double(createdAt)),
                model: row.string(1),
                usage: usage
            ))
        }
        cursorSeconds = newCursor
        return results
    }
}
