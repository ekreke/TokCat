import Foundation

/// 速率聚合器：接收各采集源的样本，折算为单位并计算速率与累计量。
public final class RateAggregator {
    public var converter: TokenUnitConverter {
        didSet { /* 口径切换后历史累计不重算，实时速率按新口径继续累加 */ }
    }
    public let calculator: RateCalculator

    /// 本次运行以来的累计消耗单位。
    public private(set) var totalUnits: Double = 0
    /// 本次运行以来的累计 token 分类统计。
    public private(set) var totalUsage: TokenUsage = .zero
    /// 各来源累计事件数。
    public private(set) var perSourceCount: [String: Int] = [:]

    public init(converter: TokenUnitConverter = TokenUnitConverter(metric: .default),
                window: TimeInterval = 15,
                smoothing: Double = 0.35) {
        self.converter = converter
        self.calculator = RateCalculator(window: window, smoothing: smoothing)
    }

    /// 摄入一批样本。
    public func ingest(_ samples: [TokenSample]) {
        for sample in samples {
            let units = converter.units(for: sample)
            calculator.add(units: units, at: sample.at)
            totalUnits += units
            totalUsage += sample.usage
            perSourceCount[sample.sourceId, default: 0] += 1
        }
    }

    /// 推进一个采样周期并返回当前速率（单位/秒）。
    @discardableResult
    public func tick(now: Date) -> Double {
        calculator.rate(at: now)
    }

    public func reset() {
        calculator.reset()
        totalUnits = 0
        totalUsage = .zero
        perSourceCount = [:]
    }
}
