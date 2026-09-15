import Foundation
import TokCatCore

/// Hermes 采集源：只读轮询 `~/.hermes/state.db` 的 `session_model_usage` 表。
///
/// 该表按 `(session_id, model, billing_provider, billing_base_url, billing_mode, task)`
/// 聚合累计值，并会**原地递增**（每次 API 调用后更新），因此不能只看新增行：
/// 这里按主键记住上次累计值，只上报增量，避免重复计数或漏计。
/// 字段与 `TokenUsage` 一一对应（input/output/cacheRead/cacheWrite/reasoning）。
public final class HermesSource: TokenSource {
    public let id = "hermes"
    public let displayName = "Hermes"
    public var isEnabled = true

    /// 记录增量所需保留的主键数上限。
    private let rememberedLimit = 5000
    /// 单次扫描行数上限。
    private let pollLimit = 2000

    private let path: String
    private let startFromNow: Bool
    private var db: SQLiteRO?
    /// `last_seen`（epoch 秒）游标。
    private var cursor: Double?
    private var lastUsageByKey: [String: TokenUsage] = [:]
    private var rememberOrder: [String] = []
    private var lastSignature: String?
    private var lastOpenAttempt: Date = .distantPast

    public init(path: String = AgentPaths.hermesDB, startFromNow: Bool = true) {
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

        if cursor == nil {
            if startFromNow {
                // 预填当前各行累计值，避免首轮把历史算作增量。
                seedRemembered(db: db)
                cursor = now.timeIntervalSince1970
                lastSignature = databaseSignature()
                return []
            }
            cursor = 0
        }

        // 数据库文件未变化时无需查询（空闲时几乎零开销）。
        // dump 等回填场景需要连续读取，跳过该优化。
        if startFromNow {
            let signature = databaseSignature()
            if let signature, signature == lastSignature { return [] }
            lastSignature = signature
        }

        return collect(db: db, now: now)
    }

    private func collect(db: SQLiteRO, now: Date) -> [TokenSample] {
        let cursorValue = cursor ?? 0
        var rows: [(key: String, model: String, usage: TokenUsage, lastSeen: Double)] = []

        db.query(
            """
            SELECT session_id, model, billing_provider, billing_base_url, billing_mode, task,
                   input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, reasoning_tokens,
                   last_seen
            FROM session_model_usage
            WHERE last_seen >= ?
            ORDER BY last_seen ASC
            LIMIT ?
            """,
            bind: [.double(cursorValue), .int(Int64(pollLimit))]
        ) { row in
            rows.append((
                key: HermesSource.primaryKey(row),
                model: row.string(1) ?? "",
                usage: HermesSource.usage(row, offset: 6),
                lastSeen: row.double(11)
            ))
        }
        guard !rows.isEmpty else { return [] }

        var samples: [TokenSample] = []
        var newCursor = cursorValue
        for row in rows {
            newCursor = max(newCursor, row.lastSeen)
            let previous = lastUsageByKey[row.key] ?? .zero
            let delta = row.usage - previous
            remember(row.key, usage: row.usage)
            guard !delta.isEmpty else { continue }
            samples.append(TokenSample(
                sourceId: id,
                id: "\(row.key)#\(Int(row.lastSeen))",
                at: now,
                model: row.model.isEmpty ? nil : row.model,
                usage: delta
            ))
        }
        cursor = newCursor
        return samples
    }

    /// 首次 startFromNow 时，把当前各行累计值记入记忆表（不上报）。
    private func seedRemembered(db: SQLiteRO) {
        db.query(
            """
            SELECT session_id, model, billing_provider, billing_base_url, billing_mode, task,
                   input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, reasoning_tokens
            FROM session_model_usage
            """
        ) { row in
            remember(HermesSource.primaryKey(row), usage: HermesSource.usage(row, offset: 6))
        }
    }

    private func remember(_ key: String, usage: TokenUsage) {
        if lastUsageByKey[key] == nil {
            rememberOrder.append(key)
        }
        lastUsageByKey[key] = usage
        let overflow = rememberOrder.count - rememberedLimit
        if overflow > 0 {
            for old in rememberOrder.prefix(overflow) {
                lastUsageByKey[old] = nil
            }
            rememberOrder.removeFirst(overflow)
        }
    }

    private static func primaryKey(_ row: SQLiteRO.Row) -> String {
        [
            row.string(0) ?? "",
            row.string(1) ?? "",
            row.string(2) ?? "",
            row.string(3) ?? "",
            row.string(4) ?? "",
            row.string(5) ?? "",
        ].joined(separator: "|")
    }

    private static func usage(_ row: SQLiteRO.Row, offset: Int32) -> TokenUsage {
        TokenUsage(
            input: Int(row.int(offset)),
            output: Int(row.int(offset + 1)),
            cacheRead: Int(row.int(offset + 2)),
            cacheWrite: Int(row.int(offset + 3)),
            reasoning: Int(row.int(offset + 4))
        )
    }

    /// db 与 wal 的 mtime/size 指纹，用于判断是否有写入。
    private func databaseSignature() -> String? {
        var signature = ""
        for file in [path, path + "-wal"] {
            guard let info = FileStat(path: file) else { return nil }
            signature += info.signature + "|"
        }
        return signature
    }
}
