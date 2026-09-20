import XCTest
@testable import TokCatSources

final class CcSwitchDBSourceTests: XCTestCase {
    func testMakeQueryWithoutExclusions() {
        let sql = CcSwitchDBSource.makeQuery(excluding: [])
        XCTAssertFalse(sql.contains("NOT IN"))
        XCTAssertTrue(sql.contains("created_at > ?"))
        XCTAssertTrue(sql.contains("ORDER BY created_at ASC"))
    }

    func testMakeQueryExcludesSingleAppType() {
        let sql = CcSwitchDBSource.makeQuery(excluding: ["opencode"])
        XCTAssertTrue(sql.contains("app_type NOT IN ('opencode')"))
    }

    func testMakeQueryExcludesMultipleAppTypes() {
        let sql = CcSwitchDBSource.makeQuery(excluding: ["opencode", "claude", "codex"])
        XCTAssertTrue(sql.contains("app_type NOT IN ("))
        for appType in ["opencode", "claude", "codex"] {
            XCTAssertTrue(sql.contains("'\(appType)'"))
        }
    }
}
