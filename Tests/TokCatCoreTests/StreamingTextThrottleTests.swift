import XCTest
@testable import TokCatCore

final class StreamingTextThrottleTests: XCTestCase {
    /// 可手动推进的时钟 + 可手动触发的调度器。
    private final class Clock {
        var now = Date(timeIntervalSince1970: 0)
        var scheduled: [(delay: TimeInterval, work: () -> Void)] = []
        var flushes = 0
    }

    private final class Harness {
        let clock: Clock
        let throttle: StreamingTextThrottle

        init(interval: TimeInterval = 0.15) {
            let clock = Clock()
            self.clock = clock
            self.throttle = StreamingTextThrottle(
                interval: interval,
                now: { clock.now },
                schedule: { delay, work in clock.scheduled.append((delay, work)) }
            )
        }

        func advance(_ seconds: TimeInterval) {
            clock.now = clock.now.addingTimeInterval(seconds)
        }

        func submit() {
            let clock = self.clock
            throttle.submit { clock.flushes += 1 }
        }

        func fireScheduled() {
            guard !clock.scheduled.isEmpty else { return }
            let work = clock.scheduled.removeFirst().work
            work()
        }
    }

    func testFirstSubmitFlushesImmediately() {
        let harness = Harness()
        harness.submit()
        XCTAssertEqual(harness.clock.flushes, 1)
        XCTAssertTrue(harness.clock.scheduled.isEmpty)
    }

    func testCoalescesWithinInterval() {
        let harness = Harness()
        harness.submit()                                   // 立即
        XCTAssertEqual(harness.clock.flushes, 1)

        harness.advance(0.05)
        harness.submit()                                   // 排入延迟
        harness.advance(0.03)
        harness.submit()                                   // 合并
        XCTAssertEqual(harness.clock.flushes, 1)
        XCTAssertEqual(harness.clock.scheduled.count, 1)

        harness.fireScheduled()                            // 一次性刷新
        XCTAssertEqual(harness.clock.flushes, 2)

        harness.advance(0.2)                               // 越过间隔
        harness.submit()                                   // 立即
        XCTAssertEqual(harness.clock.flushes, 3)
    }

    func testForceFlushesAndCancelsPending() {
        let harness = Harness()
        harness.submit()
        harness.advance(0.05)
        harness.submit()                                   // 待执行
        XCTAssertEqual(harness.clock.flushes, 1)

        let clock = harness.clock
        harness.throttle.force { clock.flushes += 1 }      // 强制
        XCTAssertEqual(harness.clock.flushes, 2)

        harness.fireScheduled()                            // 旧任务应被取消
        XCTAssertEqual(harness.clock.flushes, 2)
    }

    func testResetAllowsImmediateFlush() {
        let harness = Harness()
        harness.submit()
        harness.advance(0.05)
        harness.submit()                                   // 待执行
        harness.throttle.reset()
        harness.submit()                                   // reset 后立即
        XCTAssertEqual(harness.clock.flushes, 2)
    }
}
