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

        // cc-switch 聚合源覆盖与专门源相同的流量：专门源启用时排除对应
        // app_type，避免同一批请求被双计（峰值/合计接近翻倍）。
        if let ccSwitch = sources.first(where: { $0.id == "cc-switch" }) as? CcSwitchDBSource {
            ccSwitch.excludedAppTypes = Set(
                sources.filter { $0.isEnabled && $0.id != "cc-switch" }.map(\.id)
            )
        }

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

        // 逐样本处理：按事件时间写入历史，使"单秒峰值/合计"落在真实的秒上；
        // 超出历史窗口的旧样本不会被任何秒匹配到，自然被忽略。
        for sample in samples {
            let units = aggregator.converter.units(for: sample)
            aggregator.ingest(sample, units: units)
            history.record(sourceId: sample.sourceId, usage: sample.usage, units: units, at: sample.at)
        }
        let rate = aggregator.tick(now: now)

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
                             elapsedMs, samples.count, rate, Set(samples.map(\.sourceId)).count))
        }

        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(snapshot)
        }
    }
}
