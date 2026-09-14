import Foundation
import CSQLite

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// 只读 SQLite 连接封装（面向轮询读取，简单且无第三方依赖）。
public final class SQLiteRO {
    public enum Value {
        case int(Int64)
        case double(Double)
        case text(String)
        case null
    }

    private var db: OpaquePointer?

    public init?(path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            if handle != nil { sqlite3_close(handle) }
            return nil
        }
        // 让读取在数据库被写入时更耐心一些，避免瞬时锁冲突直接失败。
        sqlite3_busy_timeout(handle, 500)
        self.db = handle
    }

    deinit {
        if db != nil { sqlite3_close(db) }
    }

    public func query(_ sql: String, bind: [Value] = [], _ rowHandler: (Row) -> Void) {
        guard let db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
        defer { sqlite3_finalize(stmt) }

        for (index, value) in bind.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .int(let v): sqlite3_bind_int64(stmt, position, v)
            case .double(let v): sqlite3_bind_double(stmt, position, v)
            case .text(let v): sqlite3_bind_text(stmt, position, v, -1, SQLITE_TRANSIENT)
            case .null: sqlite3_bind_null(stmt, position)
            }
        }

        while sqlite3_step(stmt) == SQLITE_ROW {
            rowHandler(Row(stmt: stmt))
        }
    }

    public struct Row {
        let stmt: OpaquePointer

        public func isNull(_ index: Int32) -> Bool {
            sqlite3_column_type(stmt, index) == SQLITE_NULL
        }

        public func int(_ index: Int32) -> Int64 {
            sqlite3_column_int64(stmt, index)
        }

        public func double(_ index: Int32) -> Double {
            sqlite3_column_double(stmt, index)
        }

        public func string(_ index: Int32) -> String? {
            guard let cString = sqlite3_column_text(stmt, index) else { return nil }
            return String(cString: cString)
        }
    }
}
