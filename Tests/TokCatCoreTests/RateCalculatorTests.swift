import XCTest
@testable import TokCatCore

final class RateCalculatorTests: XCTestCase {
    func testConstantRate() {
        let calc = RateCalculator(window: 10, smoothing: 0)
        let t0 = Date(timeIntervalSince1970: 1_000)
        calc.add(units: 100, at: t0)
        XCTAssertEqual(calc.rate(at: t0), 10, accuracy: 0.0001)
    }

    func testWindowPrunesOldEvents() {
        let calc = RateCalculator(window: 10, smoothing: 0)
        let t0 = Date(timeIntervalSince1970: 1_000)
        calc.add(units: 100, at: t0)
        XCTAssertEqual(calc.rate(at: t0), 10, accuracy: 0.0001)

        let later = t0.addingTimeInterval(11)
        XCTAssertEqual(calc.rate(at: later), 0, accuracy: 0.0001)
    }

    func testZeroAndNegativeUnitsIgnored() {
        let calc = RateCalculator(window: 10, smoothing: 0)
        let t0 = Date(timeIntervalSince1970: 1_000)
        calc.add(units: 0, at: t0)
        calc.add(units: -5, at: t0)
        XCTAssertEqual(calc.rate(at: t0), 0, accuracy: 0.0001)
    }

    func testEMASmoothsTowardRaw() {
        let calc = RateCalculator(window: 10, smoothing: 0.5)
        let t0 = Date(timeIntervalSince1970: 1_000)
        calc.add(units: 100, at: t0)
        // raw = 10 -> smoothed = 0 + 0.5*10 = 5
        XCTAssertEqual(calc.rate(at: t0), 5, accuracy: 0.0001)
        // 无新事件，raw 仍为 10 -> 5 + 0.5*5 = 7.5
        XCTAssertEqual(calc.rate(at: t0), 7.5, accuracy: 0.0001)
    }

    func testReset() {
        let calc = RateCalculator(window: 10, smoothing: 0)
        let t0 = Date(timeIntervalSince1970: 1_000)
        calc.add(units: 100, at: t0)
        _ = calc.rate(at: t0)
        calc.reset()
        XCTAssertEqual(calc.currentRate, 0, accuracy: 0.0001)
    }
}
