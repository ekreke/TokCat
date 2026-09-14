import XCTest
import CSQLite
import TokCatCore
@testable import TokCatSources

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class DatabaseSourceTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testOpenCodeSource() throws {
        let dbPath = dir.appendingPathComponent("opencode.db").path
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbPath, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        exec(db, "CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);")

        let data = """
        {"role":"assistant","modelID":"glm-5.2","tokens":{"total":29783,"input":467,"output":241,"reasoning":1043,"cache":{"write":0,"read":28032}}}
        """
        let escaped = data.replacingOccurrences(of: "'", with: "''")
        exec(db, "INSERT INTO message VALUES ('m1','s1',1789364689000,1789364689000,'\(escaped)');")

        let source = OpenCodeSource(path: dbPath, startFromNow: false)
        let sample = try XCTUnwrap(source.poll(now: Date()).first)
        XCTAssertEqual(sample.usage.input, 467)
        XCTAssertEqual(sample.usage.output, 241)
        XCTAssertEqual(sample.usage.reasoning, 1043)
        XCTAssertEqual(sample.usage.cacheRead, 28032)
        XCTAssertEqual(sample.model, "glm-5.2")
        // reasoning 与 output 并列，需计入总量
        XCTAssertEqual(sample.usage.total, 29783)
        // 游标推进后不应重复
        XCTAssertTrue(source.poll(now: Date()).isEmpty)
    }

    func testCcSwitchSource() throws {
        let dbPath = dir.appendingPathComponent("cc-switch.db").path
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbPath, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        exec(db, """
        CREATE TABLE proxy_request_logs (
            request_id TEXT PRIMARY KEY, model TEXT,
            input_tokens INTEGER, output_tokens INTEGER,
            cache_read_tokens INTEGER, cache_creation_tokens INTEGER,
            created_at INTEGER
        );
        """)
        exec(db, "INSERT INTO proxy_request_logs VALUES ('r1','gpt-5.6-luna',100,20,5,0,1789359377);")

        let source = CcSwitchDBSource(path: dbPath, startFromNow: false)
        let sample = try XCTUnwrap(source.poll(now: Date()).first)
        XCTAssertEqual(sample.usage.input, 100)
        XCTAssertEqual(sample.usage.output, 20)
        XCTAssertEqual(sample.usage.cacheRead, 5)
        XCTAssertEqual(sample.model, "gpt-5.6-luna")
        XCTAssertTrue(source.poll(now: Date()).isEmpty)
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
