import Foundation
import TokCatCore
import TokCatAgent

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
        static let iconSize = "iconSize"
        static let maxFPS = "maxFPS"
        static let trendRangeMinutes = "trendRangeMinutes"
        static let agentPreset = "agentPreset"
        static let customAgentCommand = "customAgentCommand"
        static let agentWorkingDirectory = "agentWorkingDirectory"
    }

    static let defaultAnimationIdentifier = "runcat.cat"

    var animationIdentifier: String {
        get { defaults.string(forKey: Key.animation) ?? Self.defaultAnimationIdentifier }
        set { defaults.set(newValue, forKey: Key.animation) }
    }

    var metricKind: MetricKind {
        get { MetricKind(rawValue: defaults.string(forKey: Key.metric) ?? "") ?? .weighted }
        set { defaults.set(newValue.rawValue, forKey: Key.metric) }
    }

    var iconSize: Double {
        get {
            let value = defaults.double(forKey: Key.iconSize)
            return value > 0 ? value : 20
        }
        set { defaults.set(newValue, forKey: Key.iconSize) }
    }

    var maxFPS: Double {
        get {
            let value = defaults.double(forKey: Key.maxFPS)
            return value > 0 ? value : 24
        }
        set { defaults.set(newValue, forKey: Key.maxFPS) }
    }

    var trendRangeMinutes: Int {
        get {
            let value = defaults.integer(forKey: Key.trendRangeMinutes)
            return value > 0 ? value : 5
        }
        set { defaults.set(newValue, forKey: Key.trendRangeMinutes) }
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

    // MARK: - Chat / Agent 设置

    /// 当前选中的 agent 预设 id。
    var agentPresetId: String {
        get { defaults.string(forKey: Key.agentPreset) ?? "hermes" }
        set { defaults.set(newValue, forKey: Key.agentPreset) }
    }

    /// 自定义 agent 命令（预设为 `custom` 时使用）。
    var customAgentCommand: String {
        get { defaults.string(forKey: Key.customAgentCommand) ?? "" }
        set { defaults.set(newValue, forKey: Key.customAgentCommand) }
    }

    /// agent 工作目录。
    var agentWorkingDirectory: String {
        get {
            let value = defaults.string(forKey: Key.agentWorkingDirectory) ?? ""
            return value.isEmpty ? FileManager.default.homeDirectoryForCurrentUser.path : value
        }
        set { defaults.set(newValue, forKey: Key.agentWorkingDirectory) }
    }

    /// 当前预设（找不到时回退 hermes）。
    var agentPreset: AgentPreset {
        AgentPreset.builtin(id: agentPresetId) ?? AgentPreset.builtin(id: "hermes")!
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
