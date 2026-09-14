import AppKit
import SwiftUI
import TokCatAgent

/// Chat 弹窗控制器：把 SwiftUI Chat 视图放进 `NSPopover`，左键点击状态栏图标时弹出。
///
/// 会话常驻：关闭弹窗不结束会话；只有换 Agent / 改目录 / `shutdown()` / 空闲回收才断开。
final class ChatPopoverController: NSObject, NSPopoverDelegate {
    let model = ChatSessionModel()
    private let popover = NSPopover()
    private let settings: AppSettings
    private var onSetup: (() -> Void)?

    private static let minSize = NSSize(width: 340, height: 360)
    private static let maxSize = NSSize(width: 900, height: 900)

    init(settings: AppSettings, onSetup: (() -> Void)? = nil) {
        self.settings = settings
        self.onSetup = onSetup
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: makeRootView(onSetup: onSetup))
        popover.contentSize = NSSize(width: settings.chatWidth, height: settings.chatHeight)
    }

    var isShown: Bool { popover.isShown }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        // 先显示弹窗，再后台解析/连接，避免主线程被 shell 阻塞导致“点了没反应”。
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        connect()
    }

    func close() {
        if popover.isShown { popover.performClose(nil) }
    }

    /// 主动断开（换 Agent / 改目录 / 退出时调用）。
    func shutdown() {
        model.shutdown()
    }

    func setSetupHandler(_ handler: @escaping () -> Void) {
        onSetup = handler
        if let hosting = popover.contentViewController as? NSHostingController<ChatView> {
            hosting.rootView = makeRootView(onSetup: handler)
        }
    }

    private func makeRootView(onSetup handler: (() -> Void)?) -> ChatView {
        ChatView(
            model: model,
            onSetup: handler,
            onResize: { [weak self] delta in self?.resize(by: delta) }
        )
    }

    /// 拖拽手柄回调：按增量调整弹窗尺寸并持久化。
    private func resize(by delta: CGSize) {
        var size = popover.contentSize
        size.width = min(max(size.width + delta.width, Self.minSize.width), Self.maxSize.width)
        size.height = min(max(size.height + delta.height, Self.minSize.height), Self.maxSize.height)
        guard size != popover.contentSize else { return }
        popover.contentSize = size
        settings.chatWidth = Double(size.width)
        settings.chatHeight = Double(size.height)
    }

    func popoverDidClose(_ notification: Notification) {
        // 保持长连接：不结束会话。
    }

    private func connect() {
        let mode = settings.hermesMode
        let localCWD = settings.agentWorkingDirectory
        let remote = settings.remoteSSHConfig
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let configuration: ACPLaunchConfiguration?
            let displayName: String
            switch mode {
            case .local:
                configuration = AgentDetector.localLaunchConfiguration(cwd: localCWD)
                displayName = "Hermes"
            case .remote:
                configuration = AgentDetector.remoteLaunchConfiguration(remote, localCWD: localCWD)
                displayName = "Hermes · \(remote.target)"
            }
            DispatchQueue.main.async {
                if let configuration {
                    self.model.ensureSession(configuration: configuration, displayName: displayName)
                } else {
                    let message: String
                    switch mode {
                    case .local:
                        message = "未检测到本地 hermes 可执行文件，请点「设置」安装或改用手动路径。"
                    case .remote:
                        message = "请先在「设置」里填写远程 Hermes 的 SSH 目标。"
                    }
                    self.model.reportUnavailable(displayName: displayName, message: message)
                }
            }
        }
    }
}
