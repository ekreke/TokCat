import XCTest
@testable import TokCatSources

final class TokCatSourcesSmokeTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertEqual(TokCatSourcesInfo.version, "0.1.0")
    }
}
