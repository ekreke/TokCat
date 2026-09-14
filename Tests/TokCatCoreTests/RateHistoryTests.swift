import XCTest
@testable import TokCatCore

final class RateHistoryTests: XCTestCase {
    func testRecordsAndAggregates() {
        let history = RateHistory(window: 60)
        let base = Date(timeIntervalSince1970: 1_000_000)

        history.record(sourceId: "opencode", usage: TokenUsage(input: 10), units: 10, at: base)
        history.record(sourceId: "claude", usage: TokenUsage(input: 20), units: 20, at: base.addingTimeInterval(1))

        let trend = history.trend(now: base.addingTimeInterval(2), aggregateSeconds: 5)
        XCTAssertEqual(trend.timestamps.count, 12)
        XCTAssertEqual(trend.total.reduce(0, +), 30, accuracy: 0.0001)
        XCTAssertEqual(trend.perSource["opencode"]?.reduce(0, +) ?? -1, 10, accuracy: 0.0001)
        XCTAssertEqual(trend.perSource["claude"]?.reduce(0, +) ?? -1, 20, accuracy: 0.0001)
    }

    func testPerSourceSeriesAlignedWithTimestamps() {
        let history = RateHistory(window: 30)
        let base = Date(timeIntervalSince1970: 5_000_000)
        history.record(sourceId: "a", usage: TokenUsage(input: 1), units: 1, at: base)
        history.record(sourceId: "b", usage: TokenUsage(input: 2), units: 2, at: base.addingTimeInterval(3))

        let trend = history.trend(now: base.addingTimeInterval(5), aggregateSeconds: 2)
        for (_, values) in trend.perSource {
            XCTAssertEqual(values.count, trend.timestamps.count)
        }
        // 各来源之和应等于总量
        for index in trend.total.indices {
            let sum = trend.perSource.values.reduce(0.0) { $0 + $1[index] }
            XCTAssertEqual(sum, trend.total[index], accuracy: 0.0001)
        }
    }

    func testWindowPrunesOldBuckets() {
        let history = RateHistory(window: 4)
        let base = Date(timeIntervalSince1970: 2_000_000)
        history.record(sourceId: "a", usage: TokenUsage(input: 5), units: 5, at: base)

        let trend = history.trend(now: base.addingTimeInterval(10), aggregateSeconds: 4)
        XCTAssertEqual(trend.total.reduce(0, +), 0, accuracy: 0.0001)
        XCTAssertEqual(trend.perSource["a"]?.reduce(0, +) ?? -1, 0, accuracy: 0.0001)
    }

    func testRingOverwriteWithinWindow() {
        let history = RateHistory(window: 4)
        let base = Date(timeIntervalSince1970: 3_000_000)
        history.record(sourceId: "a", usage: TokenUsage(input: 7), units: 7, at: base)
        history.record(sourceId: "a", usage: TokenUsage(input: 1), units: 1, at: base.addingTimeInterval(4))

        let trend = history.trend(now: base.addingTimeInterval(4), aggregateSeconds: 1)
        XCTAssertEqual(trend.total.reduce(0, +), 1, accuracy: 0.0001)
    }

    func testResetClears() {
        let history = RateHistory(window: 60)
        let now = Date()
        history.record(sourceId: "a", usage: TokenUsage(input: 100), units: 100, at: now)
        history.reset()
        let trend = history.trend(now: now, aggregateSeconds: 5)
        XCTAssertEqual(trend.total.reduce(0, +), 0, accuracy: 0.0001)
        XCTAssertTrue(trend.perSource.isEmpty)
    }
}
