import Foundation
import TokCatCore

/// 速率口径的用户可选项。
enum MetricKind: String, CaseIterable {
    case weighted
    case total
    case inputOutput
    case cost

    var displayName: String {
        switch self {
        case .weighted: return "加权 token"
        case .total: return "全部 token"
        case .inputOutput: return "仅 input + output"
        case .cost: return "金额 (USD, models.dev)"
        }
    }

    func makeMetric() -> RateMetric {
        switch self {
        case .weighted: return .weighted(.default)
        case .total: return .total
        case .inputOutput: return .inputOutput
        case .cost: return .cost
        }
    }
}

/// 用户偏好，基于 UserDefaults 持久化。
final class AppSettings {
    private let defaults = UserDefaults.standard

    private enum Key {
        static let animation = "animationIdentifier"
        static let metric = "metricKind"
        static let sensitivity = "sensitivity"
        static let saturationRate = "saturationRate"
        static let sourceOverrides = "sourceOverrides"
    }

    var animationIdentifier: String {
        get { defaults.string(forKey: Key.animation) ?? BuiltinCatPack.identifier }
        set { defaults.set(newValue, forKey: Key.animation) }
    }

    var metricKind: MetricKind {
        get { MetricKind(rawValue: defaults.string(forKey: Key.metric) ?? "") ?? .weighted }
        set { defaults.set(newValue.rawValue, forKey: Key.metric) }
    }

    var sensitivity: Double {
        get {
            let value = defaults.double(forKey: Key.sensitivity)
            return value > 0 ? value : 1
        }
        set { defaults.set(newValue, forKey: Key.sensitivity) }
    }

    var saturationRate: Double {
        get {
            let value = defaults.double(forKey: Key.saturationRate)
            return value > 0 ? value : 300
        }
        set { defaults.set(newValue, forKey: Key.saturationRate) }
    }

    func makeConverter(pricing: ModelPricingTable) -> TokenUnitConverter {
        TokenUnitConverter(metric: metricKind.makeMetric(), pricing: pricing)
    }

    // MARK: - 采集源开关

    private var sourceOverrides: [String: Bool] {
        get { defaults.dictionary(forKey: Key.sourceOverrides) as? [String: Bool] ?? [:] }
        set { defaults.set(newValue, forKey: Key.sourceOverrides) }
    }

    func isEnabled(_ source: TokenSource) -> Bool {
        sourceOverrides[source.id] ?? source.defaultEnabled
    }

    func setEnabled(_ enabled: Bool, for source: TokenSource) {
        var overrides = sourceOverrides
        overrides[source.id] = enabled
        sourceOverrides = overrides
    }

    /// 把偏好应用到采集源实例。
    func apply(to sources: [TokenSource]) {
        for source in sources {
            source.isEnabled = isEnabled(source)
        }
    }
}
