import XCTest
@testable import TokCatCore

final class TrendMathTests: XCTestCase {
    func testMovingAverageFlattensSpike() {
        let values: [Double] = [0, 0, 0, 100, 0, 0, 0]
        let smoothed = TrendMath.movingAverage(values, window: 5)
        // 尖刺被前后各 2 个邻居摊平，峰值显著降低。
        XCTAssertLessThan(smoothed.max()!, 100)
        XCTAssertGreaterThan(smoothed.max()!, 0)
        // 对称数据的中心点 = 100/5。
        XCTAssertEqual(smoothed[3], 20, accuracy: 0.0001)
    }

    func testMovingAverageKeepsCountAndBoundaries() {
        let values: [Double] = [1, 2, 3]
        let smoothed = TrendMath.movingAverage(values, window: 3)
        XCTAssertEqual(smoothed.count, values.count)
        // 边界窗口自动收窄：(1+2)/2 = 1.5。
        XCTAssertEqual(smoothed[0], 1.5, accuracy: 0.0001)
        XCTAssertEqual(smoothed[2], 2.5, accuracy: 0.0001)
    }

    func testMovingAveragePassthroughForTinyInputs() {
        XCTAssertEqual(TrendMath.movingAverage([5], window: 5), [5])
        XCTAssertEqual(TrendMath.movingAverage([1, 2, 3], window: 1), [1, 2, 3])
        XCTAssertEqual(TrendMath.movingAverage([] as [Double], window: 3), [])
    }

    func testNiceMax() {
        XCTAssertEqual(TrendMath.niceMax(0), 1)
        XCTAssertEqual(TrendMath.niceMax(0.4), 0.5, accuracy: 0.0001)
        XCTAssertEqual(TrendMath.niceMax(1), 1)
        XCTAssertEqual(TrendMath.niceMax(1.5), 2)
        XCTAssertEqual(TrendMath.niceMax(3), 5)
        XCTAssertEqual(TrendMath.niceMax(7), 10)
        XCTAssertEqual(TrendMath.niceMax(230), 500)
    }
}
