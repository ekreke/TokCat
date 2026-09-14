import Foundation
import Darwin
import TokCatCore

/// opencode 采集源：只读轮询 SQLite `message` 表。
///
/// 数据库：`~/.local/share/opencode/opencode.db`
/// 行格式：`message.data.tokens.{input, output, reasoning, cache.{read, write}}`
///
/// opencode 会**在插入后继续更新**消息行（`time_updated > time_created`，token 逐步落定），
/// 因此不能只看新增行：这里按 `rowid` 窗口扫描近期行，按消息 id 记录上次累计值，
/// 只上报增量，避免重复计数或漏计。
public final class OpenCodeSource: TokenSource {
    public let id = "opencode"
    public let displayName = "opencode"
    public var isEnabled = true

    /// 每次扫描的 rowid 尾部窗口大小，覆盖正在流式写入的回合。
    private let rowidWindow = 2000
    private let pollLimit = 2000
    /// 记录增量所需保留的消息数上限。
    private let rememberedLimit = 5000

    private let path: String
    private let startFromNow: Bool
    private var db: SQLiteRO?
    private var cursorMs: Int64?
    private var lastUsageById: [String: TokenUsage] = [:]
    private var rememberOrder: [String] = []
    private var lastSignature: String?
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

        // 首次轮询从“当前时刻”开始，不回填历史。
        if cursorMs == nil {
            if startFromNow {
                cursorMs = Int64(now.timeIntervalSince1970 * 1000)
                lastSignature = databaseSignature()
                return []
            }
            cursorMs = 0
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
        let cursor = cursorMs ?? 0
        var candidates: [(id: String, updated: Int64)] = []

        // 常规运行只看 rowid 尾部窗口（正好等于单次上限，不会被截断）；
        // dump 等回填场景按 time_updated 分页，保证游标单调推进不漏行。
        if startFromNow {
            db.query(
                """
                SELECT id, time_updated FROM message
                WHERE rowid > (SELECT max(rowid) FROM message) - ?
                ORDER BY rowid
                """,
                bind: [.int(Int64(rowidWindow))]
            ) { row in
                appendCandidate(row, cursor: cursor, into: &candidates)
            }
        } else {
            db.query(
                "SELECT id, time_updated FROM message WHERE time_updated > ? ORDER BY time_updated ASC LIMIT ?",
                bind: [.int(cursor), .int(Int64(pollLimit))]
            ) { row in
                appendCandidate(row, cursor: cursor, into: &candidates)
            }
        }
        guard !candidates.isEmpty else { return [] }

        var samples: [TokenSample] = []
        var newCursor = cursor
        for candidate in candidates.prefix(pollLimit) {
            newCursor = max(newCursor, candidate.updated)
            guard let record = fetchRecord(db: db, id: candidate.id) else { continue }
            let previous = lastUsageById[candidate.id] ?? .zero
            let delta = record.usage - previous
            remember(candidate.id, usage: record.usage)
            guard !delta.isEmpty else { continue }
            samples.append(TokenSample(
                sourceId: id,
                id: "\(candidate.id)#\(candidate.updated)",
                at: now,
                model: record.model,
                usage: delta
            ))
        }
        cursorMs = newCursor
        return samples
    }

    private func appendCandidate(_ row: SQLiteRO.Row, cursor: Int64, into candidates: inout [(id: String, updated: Int64)]) {
        guard let messageId = row.string(0) else { return }
        let updated = row.int(1)
        // 用 `>=` 避免同毫秒时间戳的行被漏掉；重复处理由按 id 的增量计算保证幂等。
        if updated >= cursor {
            candidates.append((messageId, updated))
        }
    }

    private func fetchRecord(db: SQLiteRO, id messageId: String) -> (usage: TokenUsage, model: String?)? {
        var usage: TokenUsage?
        var model: String?
        db.query("SELECT data FROM message WHERE id = ?", bind: [.text(messageId)]) { row in
            guard let raw = row.string(0),
                  let object = JSON.parse(raw),
                  JSON.string(object, "role") == "assistant",
                  let tokens = JSON.dict(object, "tokens") else {
                return
            }
            let cache = JSON.dict(tokens, "cache")
            usage = TokenUsage(
                input: JSON.int(tokens, "input") ?? 0,
                output: JSON.int(tokens, "output") ?? 0,
                cacheRead: JSON.int(cache, "read") ?? 0,
                cacheWrite: JSON.int(cache, "write") ?? 0,
                reasoning: JSON.int(tokens, "reasoning") ?? 0
            )
            model = JSON.string(object, "modelID")
        }
        guard let usage else { return nil }
        return (usage, model)
    }

    private func remember(_ messageId: String, usage: TokenUsage) {
        if lastUsageById[messageId] == nil {
            rememberOrder.append(messageId)
        }
        lastUsageById[messageId] = usage
        let overflow = rememberOrder.count - rememberedLimit
        if overflow > 0 {
            for key in rememberOrder.prefix(overflow) {
                lastUsageById[key] = nil
            }
            rememberOrder.removeFirst(overflow)
        }
    }

    /// db 与 wal 的 mtime/size 指纹，用于判断是否有写入。
    private func databaseSignature() -> String? {
        var signature = ""
        for file in [path, path + "-wal"] {
            var info = stat()
            guard file.withCString({ stat($0, &info) }) == 0 else { return nil }
            signature += "\(info.st_mtimespec.tv_sec).\(info.st_mtimespec.tv_nsec):\(info.st_size)|"
        }
        return signature
    }
}
