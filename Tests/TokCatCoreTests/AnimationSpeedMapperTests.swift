import XCTest
@testable import TokCatCore

final class AnimationSpeedMapperTests: XCTestCase {
    func testProgressBounds() {
        let mapper = AnimationSpeedMapper(sensitivity: 1, saturationRate: 300)
        XCTAssertEqual(mapper.progress(rate: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(mapper.progress(rate: 300), 1, accuracy: 0.0001)
        XCTAssertEqual(mapper.progress(rate: 100_000), 1, accuracy: 0.0001)
    }

    func testProgressMonotonic() {
        let mapper = AnimationSpeedMapper()
        var previous = -1.0
        for rate in stride(from: 0.0, through: 500.0, by: 25.0) {
            let p = mapper.progress(rate: rate)
            XCTAssertGreaterThanOrEqual(p, previous)
            previous = p
        }
    }

    func testFPSStaysWithinPackBounds() {
        let pack = TestAnimationTiming()
        let mapper = AnimationSpeedMapper()
        XCTAssertEqual(mapper.fps(rate: 0, pack: pack), pack.idleFPS, accuracy: 0.0001)
        XCTAssertEqual(mapper.fps(rate: 1_000_000, pack: pack), pack.maxFPS, accuracy: 0.0001)
    }

    func testHigherRateMeansShorterInterval() {
        let pack = TestAnimationTiming()
        let mapper = AnimationSpeedMapper()
        let slow = mapper.frameInterval(rate: 10, pack: pack)
        let fast = mapper.frameInterval(rate: 5_000, pack: pack)
        XCTAssertLessThan(fast, slow)
        XCTAssertGreaterThan(fast, 0)
    }
}

/// 跨平台的最小 `AnimationTiming` 实现（不涉及 AppKit，Windows 也能用）。
struct TestAnimationTiming: AnimationTiming {
    var idleFPS: Double = 2
    var maxFPS: Double = 24
}
