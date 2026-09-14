import Foundation

/// 单个模型的定价（每百万 token 的美元单价）。
public struct ModelPricing: Equatable, Sendable {
    public var modelId: String
    public var inputCostPerMillion: Double
    public var outputCostPerMillion: Double
    public var cacheReadCostPerMillion: Double
    public var cacheWriteCostPerMillion: Double

    public init(
        modelId: String,
        inputCostPerMillion: Double,
        outputCostPerMillion: Double,
        cacheReadCostPerMillion: Double = 0,
        cacheWriteCostPerMillion: Double = 0
    ) {
        self.modelId = modelId
        self.inputCostPerMillion = inputCostPerMillion
        self.outputCostPerMillion = outputCostPerMillion
        self.cacheReadCostPerMillion = cacheReadCostPerMillion
        self.cacheWriteCostPerMillion = cacheWriteCostPerMillion
    }
}

/// 模型定价表，支持按模型名查询并折算金额。
public struct ModelPricingTable: Sendable {
    private let byNormalizedId: [String: ModelPricing]
    public let models: [ModelPricing]

    public init(models: [ModelPricing]) {
        self.models = models
        var map: [String: ModelPricing] = [:]
        for model in models {
            map[Self.normalize(model.modelId)] = model
        }
        self.byNormalizedId = map
    }

    public static let empty = ModelPricingTable(models: [])

    public var isEmpty: Bool { models.isEmpty }

    public func pricing(for model: String) -> ModelPricing? {
        byNormalizedId[Self.normalize(model)]
    }

    /// 按模型定价折算本次消耗的美元金额；模型未知时返回 nil。
    public func cost(of model: String, usage: TokenUsage) -> Double? {
        guard let p = pricing(for: model) else { return nil }
        let million = 1_000_000.0
        return Double(usage.input) / million * p.inputCostPerMillion
            + Double(usage.output) / million * p.outputCostPerMillion
            + Double(usage.cacheRead) / million * p.cacheReadCostPerMillion
            + Double(usage.cacheWrite) / million * p.cacheWriteCostPerMillion
    }

    /// 归一化模型名，抹平大小写、日期后缀、`-free`/`-latest` 等变体差异。
    static func normalize(_ model: String) -> String {
        var name = model.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let slash = name.lastIndex(of: "/") {
            name = String(name[name.index(after: slash)...])
        }
        for suffix in ["-free", ":free", "-latest", ":latest"] {
            if name.hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count))
            }
        }
        // 去除结尾的 -YYYYMMDD / -YYYY-MM-DD 日期后缀
        if let range = name.range(of: #"-\d{4}-?\d{2}-?\d{2}$"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        return name
    }
}
