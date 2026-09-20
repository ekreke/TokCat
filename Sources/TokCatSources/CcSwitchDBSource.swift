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

    /// 需要排除的 `app_type` 集合，由引擎按「其他专门源的启用状态」同步。
    ///
    /// cc-switch 的代理日志覆盖的流量与各专门源（opencode/codex/claude/pi…）
    /// 完全重叠：专门源启用时必须排除对应记录，否则同一批请求被双计，
    /// 「单秒峰值/合计」等统计会接近翻倍。值为受控的源 id 常量（非用户输入）。
    public var excludedAppTypes: Set<String> = []

    private let path: String
    private static let pollLimit = 2000
    private let startFromNow: Bool
    private var db: SQLiteRO?
    private var cursorSeconds: Int64?
    private var lastOpenAttempt: Date = .distantPast

    public init(path: String = AgentPaths.ccSwitchDB, startFromNow: Bool = true) {
        self.path = path
        self.startFromNow = startFromNow
        self.db = SQLiteRO(path: path)
    }

    /// 构造增量查询 SQL；`excluding` 非空时排除对应 `app_type` 的记录。
    static func makeQuery(excluding: Set<String>) -> String {
        var sql = """
            SELECT request_id, model, input_tokens, output_tokens, cache_read_tokens,
                   cache_creation_tokens, created_at
            FROM proxy_request_logs
            WHERE created_at > ?
            """
        if !excluding.isEmpty {
            let list = excluding.sorted().map { "'\($0)'" }.joined(separator: ",")
            sql += "\nAND app_type NOT IN (\(list))"
        }
        sql += "\nORDER BY created_at ASC\nLIMIT \(pollLimit)"
        return sql
    }

    public func poll(now: Date) -> [TokenSample] {
        if db == nil, now.timeIntervalSince(lastOpenAttempt) > 30 {
            lastOpenAttempt = now
            db = SQLiteRO(path: path)
        }
        guard let db else { return [] }

        // 首次轮询从“当前时刻”开始，直接跳过查询以避免无谓的全表扫描。
        if cursorSeconds == nil {
            if startFromNow {
                cursorSeconds = Int64(now.timeIntervalSince1970)
                return []
            }
            cursorSeconds = 0
        }
        let cursor = cursorSeconds ?? 0

        var results: [TokenSample] = []
        var newCursor = cursor
        db.query(
            Self.makeQuery(excluding: excludedAppTypes),
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
