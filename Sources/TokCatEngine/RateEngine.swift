import Foundation
import TokCatCore
import TokCatSources

/// 一次采样后的快照，供 UI 展示（macOS 菜单栏 / Windows 托盘 / CLI 协议）。
public struct RateSnapshot {
    public let rate: Double
    public let totalUnits: Double
    public let totalUsage: TokenUsage
    public let unitIsCurrency: Bool
    public let eventCounts: [String: Int]
    public let trend: RateHistory.RateTrend
    /// 来源 id → 展示名称。
    public let sourceNames: [String: String]
    /// 趋势窗口（秒）。
    public let windowSeconds: Int

    public init(
        rate: Double,
        totalUnits: Double,
        totalUsage: TokenUsage,
        unitIsCurrency: Bool,
        eventCounts: [String: Int],
        trend: RateHistory.RateTrend,
        sourceNames: [String: String],
        windowSeconds: Int
    ) {
        self.rate = rate
        self.totalUnits = totalUnits
        self.totalUsage = totalUsage
        self.unitIsCurrency = unitIsCurrency
        self.eventCounts = eventCounts
        self.trend = trend
        self.sourceNames = sourceNames
        self.windowSeconds = windowSeconds
    }
}

/// 速率引擎：周期性轮询各采集源，聚合样本、计算速率并记录历史。
///
/// 采集与解析是重活（目录遍历、文件读取、SQLite 查询、JSON 解析），
/// 全部在后台串行队列执行，避免阻塞主线程导致动画卡顿；结果再回主线程。
///
/// 该类型位于共享层，macOS 外壳与跨平台 CLI 复用同一实现。
public final class RateEngine {
    /// 主线程回调。
    public var onUpdate: ((RateSnapshot) -> Void)?

    private let sources: [TokenSource]
    private let aggregator: RateAggregator
    private let history = RateHistory(window: 600)
    private let stateStore: SourceStateStore?
    private let queue = DispatchQueue(label: "tokcat.engine", qos: .utility)
    private var timer: DispatchSourceTimer?

    /// 趋势聚合粒度：1 秒，使"峰值"即最高 1 秒消耗（与速率同口径）。
    private let aggregateSeconds = 1
    private let sourceNames: [String: String]

    public init(sources: [TokenSource],
                converter: TokenUnitConverter,
                window: TimeInterval = 15,
                stateStore: SourceStateStore? = nil) {
        self.sources = sources
        self.aggregator = RateAggregator(converter: converter, window: window)
        self.stateStore = stateStore
        self.sourceNames = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0.displayName) })
    }

    public var allSources: [TokenSource] { sources }

    public func start() {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1.0, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    public func updateConverter(_ converter: TokenUnitConverter) {
        queue.async { [weak self] in
            self?.aggregator.converter = converter
            self?.history.reset()
        }
    }

    public func resetTotals() {
        queue.async { [weak self] in
            self?.aggregator.reset()
            self?.history.reset()
        }
    }

    private func tick() {
        let start = DispatchTime.now()
        let now = Date()

        var samples: [TokenSample] = []
        for source in sources where source.isEnabled {
            let sourceStart = DispatchTime.now()
            let produced = source.poll(now: now)
            if Debug.enabled {
                let ms = Double(DispatchTime.now().uptimeNanoseconds - sourceStart.uptimeNanoseconds) / 1_000_000
                if ms > 3 {
                    Debug.log(String(format: "  source %@ %.1fms samples=%d", source.id, ms, produced.count))
                }
            }
            samples.append(contentsOf: produced)
        }

        aggregator.ingest(samples)
        let rate = aggregator.tick(now: now)

        // 按来源分别累计本 tick 的消耗，供趋势图分客户端绘制。
        var perSource: [String: (units: Double, usage: TokenUsage)] = [:]
        for sample in samples {
            let units = aggregator.converter.units(for: sample)
            var entry = perSource[sample.sourceId] ?? (0, .zero)
            entry.units += units
            entry.usage += sample.usage
            perSource[sample.sourceId] = entry
        }
        for (sourceId, entry) in perSource {
            history.record(sourceId: sourceId, usage: entry.usage, units: entry.units, at: now)
        }

        stateStore?.saveIfNeeded(now: now)

        let snapshot = RateSnapshot(
            rate: rate,
            totalUnits: aggregator.totalUnits,
            totalUsage: aggregator.totalUsage,
            unitIsCurrency: aggregator.converter.unitIsCurrency,
            eventCounts: aggregator.perSourceCount,
            trend: history.trend(now: now, aggregateSeconds: aggregateSeconds),
            sourceNames: sourceNames,
            windowSeconds: history.window
        )

        if Debug.enabled {
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            Debug.log(String(format: "tick %.1fms samples=%d rate=%.1f trendSources=%d",
                             elapsedMs, samples.count, rate, perSource.count))
        }

        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(snapshot)
        }
    }
}
