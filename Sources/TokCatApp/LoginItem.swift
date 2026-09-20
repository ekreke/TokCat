import Foundation
import ServiceManagement

/// 开机自启的底层机制。
enum LoginItemMechanism: Equatable {
    /// 系统登录项（`SMAppService.mainApp`），出现在「系统设置 → 通用 → 登录项」。
    case smAppService
    /// 用户级 LaunchAgent（`~/Library/LaunchAgents`），与代码签名无关。
    case launchAgent
}

/// 开机自启的当前状态。
enum LoginItemState: Equatable {
    case enabled(LoginItemMechanism)
    case disabled
    /// 已注册但等待用户在「系统设置 → 通用 → 登录项」中允许。
    case requiresApproval
    /// 非 `.app` 形态（例如 `swift run`），不支持自启。
    case unsupported
    case failed(String)

    var isOn: Bool {
        if case .enabled = self { return true }
        return false
    }
}

/// 开机自启管理。
///
/// 优先使用 `SMAppService.mainApp`（会出现在「系统设置 → 通用 → 登录项」）。
/// 但 ad-hoc 签名下该 API 可能「静默失败」：`register()` 不报错、`status` 报
/// `enabled`，而 BackgroundTaskManagement 数据库实际并未落库，重启后不会启动。
/// 此时回退到用户级 `LaunchAgent`（与签名无关，必定生效）。
enum LoginItemManager {
    static let launchAgentLabel = "com.ekreke.tokcat"

    /// 用户期望的自启开关；BTM 记录可能在覆盖安装后失效，启动时以此为准做自愈。
    private static let desiredKey = "loginItemDesired"
    private static var desiredEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: desiredKey) }
        set { UserDefaults.standard.set(newValue, forKey: desiredKey) }
    }

    /// 应用是否为 ad-hoc 签名（无 Team Identifier）。只探测一次并缓存。
    ///
    /// ad-hoc 签名每次覆盖安装 CDHash 都会变化，SMAppService 已注册的 BTM
    /// 记录会因此失效（升级后自启静默失效的根因），这类构建直接走 LaunchAgent。
    /// 注意只在 `enable()` 等可 spawn 命令的路径使用，避免破坏 `currentState()`
    /// 的轻量契约；`static let` 由 Swift 保证线程安全的一次性初始化。
    private static let adhocSigned: Bool = {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/codesign") else { return false }
        let result = run("/usr/bin/codesign", ["-dv", Bundle.main.bundlePath])
        return result.status == 0 && result.output.contains("TeamIdentifier=not set")
    }()

    static var isSupported: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    static var isEnabled: Bool {
        currentState().isOn
    }

    // MARK: - 查询

    /// 读取当前状态。轻量，可在主线程调用（不 spawn `launchctl`）。
    static func currentState() -> LoginItemState {
        guard isSupported else { return .unsupported }

        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled(.smAppService)
        case .requiresApproval:
            return .requiresApproval
        default:
            if launchAgentInstalled() {
                return .enabled(.launchAgent)
            }
            return .disabled
        }
    }

    // MARK: - 设置

    /// 开启 / 关闭开机自启。会 spawn 少量外部命令，建议在后台线程调用。
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> LoginItemState {
        guard isSupported else { return .unsupported }
        let state = enabled ? enable() : disable()
        // 统一在此维护期望标志：failed / unsupported 不改动原值。
        switch state {
        case .enabled, .requiresApproval:
            desiredEnabled = true
        case .disabled:
            desiredEnabled = false
        case .failed, .unsupported:
            break
        }
        return state
    }

    // MARK: - 启动自愈

    /// 启动时调用：用户期望开启但当前实际未注册（覆盖安装导致 BTM 记录
    /// 失效、LaunchAgent 被清理等），自动重新开启。会 spawn 命令，须在后台线程调用。
    @discardableResult
    static func healIfNeeded() -> LoginItemState {
        guard desiredEnabled, case .disabled = currentState() else { return currentState() }
        NSLog("TokCat: 检测到开机自启期望开启但注册已失效，自动恢复")
        return setEnabled(true)
    }

    private static func enable() -> LoginItemState {
        if adhocSigned {
            NSLog("TokCat: ad-hoc 签名，SMAppService 注册会在覆盖安装后失效，直接使用 LaunchAgent")
            return installLaunchAgentOrFail()
        }

        do {
            try SMAppService.mainApp.register()
        } catch {
            NSLog("TokCat: SMAppService 注册失败，回退 LaunchAgent: \(error)")
            return installLaunchAgentOrFail()
        }

        switch SMAppService.mainApp.status {
        case .enabled:
            // ad-hoc 下可能「假 enabled」：status 报 enabled，但 BTM 未落库。
            if waitForBackgroundItemRecorded() {
                return .enabled(.smAppService)
            }
            NSLog("TokCat: SMAppService 报 enabled 但未写入 BTM，回退 LaunchAgent")
            return installLaunchAgentOrFail()
        case .requiresApproval:
            return .requiresApproval
        default:
            NSLog("TokCat: SMAppService 注册后状态异常，回退 LaunchAgent")
            return installLaunchAgentOrFail()
        }
    }

    private static func disable() -> LoginItemState {
        var firstError: Error?
        if SMAppService.mainApp.status != .notRegistered {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                firstError = error
            }
        }
        let agentRemoved = uninstallLaunchAgent()

        if let error = firstError, !agentRemoved {
            NSLog("TokCat: 取消开机自启失败: \(error)")
            return .failed("取消开机自启失败：\(error.localizedDescription)")
        }
        return .disabled
    }

    // MARK: - LaunchAgent 回退

    static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(launchAgentLabel).plist")
    }

    static func launchAgentInstalled() -> Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    private static func installLaunchAgentOrFail() -> LoginItemState {
        // 回退前先注销 SMAppService，避免两套机制同时生效导致重复启动。
        if SMAppService.mainApp.status != .notRegistered {
            try? SMAppService.mainApp.unregister()
        }

        do {
            try writeLaunchAgent()
        } catch {
            NSLog("TokCat: 写入 LaunchAgent 失败: \(error)")
            return .failed("设置开机自启失败：\(error.localizedDescription)")
        }

        // 重新加载使配置生效。
        _ = run("/bin/launchctl", ["bootout", guiDomain, launchAgentURL.path])
        let bootstrap = run("/bin/launchctl", ["bootstrap", guiDomain, launchAgentURL.path])
        if bootstrap.status != 0 {
            let legacy = run("/bin/launchctl", ["load", launchAgentURL.path])
            if legacy.status != 0 {
                let detail = bootstrap.output.trimmingCharacters(in: .whitespacesAndNewlines)
                NSLog("TokCat: launchctl 加载 LaunchAgent 失败: \(detail)")
                return .failed("开机自启已写入，但 launchctl 加载失败：\(detail)")
            }
        }
        return .enabled(.launchAgent)
    }

    private static func writeLaunchAgent() throws {
        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try FileManager.default.createDirectory(
            at: launchAgentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: launchAgentURL, options: .atomic)
    }

    /// 移除 LaunchAgent；返回是否已移除或本就不存在。
    @discardableResult
    private static func uninstallLaunchAgent() -> Bool {
        guard launchAgentInstalled() else { return true }
        _ = run("/bin/launchctl", ["bootout", guiDomain, launchAgentURL.path])
        do {
            try FileManager.default.removeItem(at: launchAgentURL)
            return true
        } catch {
            NSLog("TokCat: 移除 LaunchAgent 失败: \(error)")
            return false
        }
    }

    // MARK: - 辅助

    private static var guiDomain: String {
        "gui/\(getuid())"
    }

    /// 二次校验：SMAppService 注册是否真的写入了 BackgroundTaskManagement 数据库。
    /// BTM 落库可能有延迟，最多等待约 3 秒；查询失败时保守返回 true（不误判）。
    private static func waitForBackgroundItemRecorded() -> Bool {
        for attempt in 0..<6 {
            if backgroundItemRecorded() { return true }
            if attempt < 5 { Thread.sleep(forTimeInterval: 0.5) }
        }
        return false
    }

    private static func backgroundItemRecorded() -> Bool {
        let result = run("/usr/bin/sfltool", ["dumpbtm"])
        guard result.status == 0 else { return true }
        return result.output.contains("Bundle Identifier: \(launchAgentLabel)")
    }

    /// 同步执行外部命令，返回退出码与合并后的输出。
    private static func run(_ launchPath: String, _ arguments: [String]) -> (status: Int32, output: String) {
        guard FileManager.default.isExecutableFile(atPath: launchPath) else {
            return (-1, "not found: \(launchPath)")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
