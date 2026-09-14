import Foundation

/// 可插拔 token 采集源。
///
/// 实现者内部维护游标（文件偏移 / 时间戳 / 主键），`poll` 只返回自上次调用
/// 以来新增的事件，因此调用方无需去重。
public protocol TokenSource: AnyObject {
    /// 唯一标识，例如 "opencode" / "claude" / "codex" / "pi" / "cc-switch"。
    var id: String { get }
    /// 展示名称。
    var displayName: String { get }
    /// 是否启用。
    var isEnabled: Bool { get set }
    /// 首次运行时的默认启用状态。
    var defaultEnabled: Bool { get }
    /// 返回上次调用以来新增的 token 事件。
    func poll(now: Date) -> [TokenSample]
}

public extension TokenSource {
    var isEnabled: Bool {
        get { true }
        set {}
    }

    var defaultEnabled: Bool { true }
}
