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

/// Hermes 接入方式。
enum HermesMode: String, CaseIterable {
    case local
    case remote

    var displayName: String {
        switch self {
        case .local: return "本地"
        case .remote: return "远程 (SSH)"
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
        static let hermesMode = "hermesMode"
        static let agentWorkingDirectory = "agentWorkingDirectory"
        static let sshTarget = "sshTarget"
        static let sshPort = "sshPort"
        static let sshIdentityFile = "sshIdentityFile"
        static let remoteCommand = "remoteCommand"
        static let remoteLoginShell = "remoteLoginShell"
        static let remoteWorkingDirectory = "remoteWorkingDirectory"
        static let chatWidth = "chatWidth"
        static let chatHeight = "chatHeight"
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

    // MARK: - Hermes 设置

    /// 本地 / 远程模式。
    var hermesMode: HermesMode {
        get { HermesMode(rawValue: defaults.string(forKey: Key.hermesMode) ?? "") ?? .local }
        set { defaults.set(newValue.rawValue, forKey: Key.hermesMode) }
    }

    /// 本地工作目录（本地模式）。
    var agentWorkingDirectory: String {
        get {
            let value = defaults.string(forKey: Key.agentWorkingDirectory) ?? ""
            return value.isEmpty ? FileManager.default.homeDirectoryForCurrentUser.path : value
        }
        set { defaults.set(newValue, forKey: Key.agentWorkingDirectory) }
    }

    /// SSH 目标（`~/.ssh/config` 别名或 `user@host`）。
    var sshTarget: String {
        get { defaults.string(forKey: Key.sshTarget) ?? "" }
        set { defaults.set(newValue, forKey: Key.sshTarget) }
    }

    /// SSH 端口（0 = 用默认/配置）。
    var sshPort: Int {
        get { defaults.integer(forKey: Key.sshPort) }
        set { defaults.set(newValue, forKey: Key.sshPort) }
    }

    /// SSH 私钥路径（留空用默认/agent）。
    var sshIdentityFile: String {
        get { defaults.string(forKey: Key.sshIdentityFile) ?? "~/.ssh/id_ed25519" }
        set { defaults.set(newValue, forKey: Key.sshIdentityFile) }
    }

    /// 远端启动命令。
    var remoteCommand: String {
        get { defaults.string(forKey: Key.remoteCommand) ?? "hermes acp" }
        set { defaults.set(newValue, forKey: Key.remoteCommand) }
    }

    /// 远端登录 shell 包装（如 `zsh -lic`）；留空表示直接执行。
    var remoteLoginShell: String {
        get { defaults.string(forKey: Key.remoteLoginShell) ?? "" }
        set { defaults.set(newValue, forKey: Key.remoteLoginShell) }
    }

    /// 远端工作目录（留空 = 远端 home）。
    var remoteWorkingDirectory: String {
        get { defaults.string(forKey: Key.remoteWorkingDirectory) ?? "" }
        set { defaults.set(newValue, forKey: Key.remoteWorkingDirectory) }
    }

    /// 组装远程 SSH 配置。
    var remoteSSHConfig: RemoteSSHConfig {
        RemoteSSHConfig(
            target: sshTarget,
            port: sshPort > 0 ? sshPort : nil,
            identityFile: sshIdentityFile.trimmingCharacters(in: .whitespaces).isEmpty ? nil : sshIdentityFile,
            remoteCommand: remoteCommand.trimmingCharacters(in: .whitespaces).isEmpty ? "hermes acp" : remoteCommand,
            loginShell: remoteLoginShell,
            remoteWorkingDirectory: remoteWorkingDirectory
        )
    }

    /// Chat 弹窗宽度（可拖动调整）。
    var chatWidth: Double {
        get {
            let value = defaults.double(forKey: Key.chatWidth)
            return value > 0 ? value : 440
        }
        set { defaults.set(newValue, forKey: Key.chatWidth) }
    }

    /// Chat 弹窗高度（可拖动调整）。
    var chatHeight: Double {
        get {
            let value = defaults.double(forKey: Key.chatHeight)
            return value > 0 ? value : 480
        }
        set { defaults.set(newValue, forKey: Key.chatHeight) }
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
