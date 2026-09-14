import Foundation

/// 滑动窗口速率计算器：对随时间到来的“消耗单位”求单位时间速率，并做 EMA 平滑。
///
/// 约定每个采样周期（通常 1 秒）调用一次 `rate(at:)`，此时 EMA 才有物理意义。
public final class RateCalculator {
    /// 滑动窗口长度（秒）。
    public var window: TimeInterval
    /// EMA 平滑系数，0 表示不平滑，越接近 1 越平滑。
    public var smoothing: Double

    private struct Event {
        let at: Date
        let units: Double
    }

    private var events: [Event] = []
    private var smoothed: Double = 0

    public init(window: TimeInterval = 15, smoothing: Double = 0.35) {
        self.window = max(1, window)
        self.smoothing = min(max(smoothing, 0), 1)
    }

    /// 累加一段消耗单位。
    public func add(units: Double, at date: Date) {
        guard units > 0 else { return }
        events.append(Event(at: date, units: units))
    }

    /// 折算并返回当前速率（单位/秒），同时推进 EMA。
    @discardableResult
    public func rate(at now: Date) -> Double {
        let cutoff = now.addingTimeInterval(-window)
        if let idx = events.firstIndex(where: { $0.at >= cutoff }) {
            if idx > 0 { events.removeFirst(idx) }
        } else {
            events.removeAll(keepingCapacity: true)
        }

        let sum = events.reduce(0.0) { $0 + $1.units }
        let raw = sum / window
        if smoothing <= 0 {
            smoothed = raw
        } else {
            smoothed += smoothing * (raw - smoothed)
        }
        return smoothed
    }

    /// 当前平滑后的速率，不推进 EMA。
    public var currentRate: Double { smoothed }

    public func reset() {
        events.removeAll(keepingCapacity: true)
        smoothed = 0
    }
}
