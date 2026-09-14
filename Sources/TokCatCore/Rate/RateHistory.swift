import Foundation

/// 速率历史：按秒记录、按来源拆分的环形缓冲，用于绘制"最近 N 分钟"的趋势图。
///
/// 存原始 `TokenUsage` 与消耗单位，因此切换速率口径时可直接按新口径重算，
/// 无需在记录时就固定口径。
public final class RateHistory {
    /// 趋势数据：一条共享时间轴 + 总量 + 各来源序列（均与 `timestamps` 等长、对齐）。
    public struct RateTrend: Sendable {
        public let timestamps: [Date]
        public let total: [Double]
        public let perSource: [String: [Double]]

        public init(timestamps: [Date], total: [Double], perSource: [String: [Double]]) {
            self.timestamps = timestamps
            self.total = total
            self.perSource = perSource
        }
    }

    /// 窗口长度（秒）。
    public let window: Int

    private var slotSecond: [Int]
    private var slotUnits: [Double]
    private var slotUsage: [TokenUsage]
    private var sourceSlotUnits: [String: [Double]]

    public init(window: Int = 300) {
        self.window = max(1, window)
        self.slotSecond = Array(repeating: Int.min, count: self.window)
        self.slotUnits = Array(repeating: 0, count: self.window)
        self.slotUsage = Array(repeating: .zero, count: self.window)
        self.sourceSlotUnits = [:]
    }

    /// 记录某个来源的一次消耗。
    public func record(sourceId: String, usage: TokenUsage, units: Double, at date: Date) {
        let second = Int(date.timeIntervalSince1970)
        let index = ((second % window) + window) % window

        if slotSecond[index] != second {
            slotSecond[index] = second
            slotUnits[index] = 0
            slotUsage[index] = .zero
            for key in sourceSlotUnits.keys {
                sourceSlotUnits[key]?[index] = 0
            }
        }

        slotUnits[index] += units
        slotUsage[index] += usage

        var ring = sourceSlotUnits[sourceId] ?? Array(repeating: 0, count: window)
        ring[index] += units
        sourceSlotUnits[sourceId] = ring
    }

    /// 生成趋势数据：`aggregateSeconds` 秒合成一个点，时间升序。
    public func trend(now: Date = Date(), aggregateSeconds: Int = 1) -> RateTrend {
        let aggregate = max(1, aggregateSeconds)
        let nowSecond = Int(now.timeIntervalSince1970)
        let startSecond = nowSecond - window + 1

        var timestamps: [Date] = []
        var total: [Double] = []
        var perSource: [String: [Double]] = [:]
        for key in sourceSlotUnits.keys { perSource[key] = [] }

        var accTotal = 0.0
        var accSource: [String: Double] = [:]
        var count = 0

        func flush(at second: Int) {
            timestamps.append(Date(timeIntervalSince1970: Double(second)))
            total.append(accTotal)
            for key in perSource.keys { perSource[key]?.append(accSource[key] ?? 0) }
            accTotal = 0
            accSource.removeAll(keepingCapacity: true)
            count = 0
        }

        for second in startSecond...nowSecond {
            let index = ((second % window) + window) % window
            if slotSecond[index] == second {
                accTotal += slotUnits[index]
                for (key, ring) in sourceSlotUnits {
                    let value = ring[index]
                    if value != 0 { accSource[key, default: 0] += value }
                }
            }
            count += 1
            if count == aggregate { flush(at: second) }
        }
        if count > 0 { flush(at: nowSecond) }

        return RateTrend(timestamps: timestamps, total: total, perSource: perSource)
    }

    public func reset() {
        slotSecond = Array(repeating: Int.min, count: window)
        slotUnits = Array(repeating: 0, count: window)
        slotUsage = Array(repeating: .zero, count: window)
        sourceSlotUnits.removeAll(keepingCapacity: true)
    }
}
