import Foundation

/// 各 token 分类在“加权”口径下的权重系数。
public struct TokenWeights: Equatable, Sendable {
    public var input: Double
    public var output: Double
    public var cacheRead: Double
    public var cacheWrite: Double
    public var reasoning: Double

    public init(
        input: Double = 1,
        output: Double = 1,
        cacheRead: Double = 0.1,
        cacheWrite: Double = 0.1,
        reasoning: Double = 1
    ) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.reasoning = reasoning
    }

    /// 默认权重：缓存命中不会让动画疯跑。
    public static let `default` = TokenWeights()

    /// 各分类等权（等价于全部求和）。
    public static let equal = TokenWeights(input: 1, output: 1, cacheRead: 1, cacheWrite: 1, reasoning: 1)

    public func apply(to usage: TokenUsage) -> Double {
        Double(usage.input) * input
            + Double(usage.output) * output
            + Double(usage.cacheRead) * cacheRead
            + Double(usage.cacheWrite) * cacheWrite
            + Double(usage.reasoning) * reasoning
    }
}

/// 速率口径：把一次 token 消耗折算为标量“消耗单位”。
public enum RateMetric: Equatable, Sendable {
    /// 加权 token（可配置权重）。
    case weighted(TokenWeights)
    /// 所有分类求和。
    case total
    /// 仅 input + output。
    case inputOutput
    /// 按模型定价折算成美元（金额模式）。
    case cost

    public static let `default` = RateMetric.weighted(.default)
}

/// 把 `TokenSample` 折算为消耗单位的转换器。
public struct TokenUnitConverter: Sendable {
    public let metric: RateMetric
    public let pricing: ModelPricingTable?

    public init(metric: RateMetric, pricing: ModelPricingTable? = nil) {
        self.metric = metric
        self.pricing = pricing
    }

    /// 单位：加权 token 数（weighted/total/inputOutput）或美元（cost）。
    public func units(for sample: TokenSample) -> Double {
        switch metric {
        case .weighted(let weights):
            return weights.apply(to: sample.usage)
        case .total:
            return Double(sample.usage.total)
        case .inputOutput:
            return Double(sample.usage.inputOutput)
        case .cost:
            guard let pricing, let model = sample.model,
                  let cost = pricing.cost(of: model, usage: sample.usage) else {
                return 0
            }
            return cost
        }
    }

    /// 该口径下速率单位是否代表美元。
    public var unitIsCurrency: Bool {
        if case .cost = metric { return true }
        return false
    }
}
