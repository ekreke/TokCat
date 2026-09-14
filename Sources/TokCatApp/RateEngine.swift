import Foundation
import TokCatCore
import TokCatSources

/// 一次采样后的快照，供 UI 展示。
struct RateSnapshot {
    let rate: Double
    let totalUnits: Double
    let totalUsage: TokenUsage
    let unitIsCurrency: Bool
    let eventCounts: [String: Int]
}

/// 速率引擎：周期性轮询各采集源，聚合样本并计算速率。
final class RateEngine {
    var onUpdate: ((RateSnapshot) -> Void)?

    private let sources: [TokenSource]
    private let aggregator: RateAggregator
    private let stateStore: SourceStateStore?
    private var timer: Timer?

    init(sources: [TokenSource],
         converter: TokenUnitConverter,
         window: TimeInterval = 15,
         stateStore: SourceStateStore? = nil) {
        self.sources = sources
        self.aggregator = RateAggregator(converter: converter, window: window)
        self.stateStore = stateStore
    }

    var allSources: [TokenSource] { sources }

    func start() {
        stop()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func updateConverter(_ converter: TokenUnitConverter) {
        aggregator.converter = converter
    }

    func resetTotals() {
        aggregator.reset()
    }

    private func tick() {
        let now = Date()
        var samples: [TokenSample] = []
        for source in sources where source.isEnabled {
            samples.append(contentsOf: source.poll(now: now))
        }
        aggregator.ingest(samples)
        let rate = aggregator.tick(now: now)
        stateStore?.saveIfNeeded(now: now)

        onUpdate?(RateSnapshot(
            rate: rate,
            totalUnits: aggregator.totalUnits,
            totalUsage: aggregator.totalUsage,
            unitIsCurrency: aggregator.converter.unitIsCurrency,
            eventCounts: aggregator.perSourceCount
        ))
    }
}
