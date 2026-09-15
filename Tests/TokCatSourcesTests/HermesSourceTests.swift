import XCTest
import SQLite3
import TokCatCore
@testable import TokCatSources

final class HermesSourceTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testUsageReportedOnceAndOnlyDeltaAfterIncrement() throws {
        let dbPath = dir.appendingPathComponent("state.db").path
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbPath, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        exec(db, """
        CREATE TABLE session_model_usage (
            session_id TEXT NOT NULL,
            model TEXT NOT NULL,
            billing_provider TEXT NOT NULL DEFAULT '',
            billing_base_url TEXT NOT NULL DEFAULT '',
            billing_mode TEXT NOT NULL DEFAULT '',
            task TEXT NOT NULL DEFAULT '',
            input_tokens INTEGER NOT NULL DEFAULT 0,
            output_tokens INTEGER NOT NULL DEFAULT 0,
            cache_read_tokens INTEGER NOT NULL DEFAULT 0,
            cache_write_tokens INTEGER NOT NULL DEFAULT 0,
            reasoning_tokens INTEGER NOT NULL DEFAULT 0,
            last_seen REAL
        );
        """)
        exec(db, "INSERT INTO session_model_usage VALUES ('s1','deepseek-v4.1-flash','p','u','m','',100,20,5,0,7,1000.0);")

        let source = HermesSource(path: dbPath, startFromNow: false)
        let first = source.poll(now: Date())
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first[0].usage.input, 100)
        XCTAssertEqual(first[0].usage.output, 20)
        XCTAssertEqual(first[0].usage.cacheRead, 5)
        XCTAssertEqual(first[0].usage.reasoning, 7)
        XCTAssertEqual(first[0].usage.total, 132)
        XCTAssertEqual(first[0].model, "deepseek-v4.1-flash")

        // 游标推进后无变化时不应重复上报。
        XCTAssertTrue(source.poll(now: Date()).isEmpty)

        // 同一行原地累加：只上报增量。
        exec(db, "UPDATE session_model_usage SET input_tokens=130, output_tokens=25, reasoning_tokens=9, last_seen=1001.0 WHERE session_id='s1';")
        let second = source.poll(now: Date())
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second[0].usage.input, 30)
        XCTAssertEqual(second[0].usage.output, 5)
        XCTAssertEqual(second[0].usage.reasoning, 2)
        XCTAssertEqual(second[0].usage.cacheRead, 0)
    }

    private func exec(_ db: OpaquePointer?, _ sql: String) {
        var error: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(db, sql, nil, nil, &error)
        if code != SQLITE_OK, let error {
            XCTFail("SQL error: \(String(cString: error))")
            sqlite3_free(error)
        }
    }
}
