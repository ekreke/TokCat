import AppKit
import SwiftUI
import TokCatAgent

/// Chat 弹窗控制器：把 SwiftUI Chat 视图放进 `NSPopover`，左键点击状态栏图标时弹出。
///
/// 会话生命周期：打开即启动一个 ACP 会话，关闭弹窗即结束进程（“单次会话”）。
final class ChatPopoverController: NSObject, NSPopoverDelegate {
    let model = ChatSessionModel()
    private let popover = NSPopover()
    private let settings: AppSettings
    private var onSetup: (() -> Void)?

    init(settings: AppSettings, onSetup: (() -> Void)? = nil) {
        self.settings = settings
        self.onSetup = onSetup
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: ChatView(model: model, onSetup: onSetup))
        popover.contentSize = NSSize(width: 380, height: 420)
    }

    var isShown: Bool { popover.isShown }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        startSession()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func close() {
        if popover.isShown { popover.performClose(nil) }
    }

    func setSetupHandler(_ handler: @escaping () -> Void) {
        onSetup = handler
        if let hosting = popover.contentViewController as? NSHostingController<ChatView> {
            hosting.rootView = ChatView(model: model, onSetup: handler)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        model.stop()
    }

    private func startSession() {
        let preset = settings.agentPreset
        guard let configuration = AgentDetector.launchConfiguration(
            for: preset,
            customCommand: settings.customAgentCommand,
            cwd: settings.agentWorkingDirectory
        ) else {
            model.reportUnavailable(
                displayName: preset.displayName,
                message: "未检测到 \(preset.displayName) 可执行文件，请在右键菜单「Agent」里安装或配置。"
            )
            return
        }
        model.start(configuration: configuration, displayName: preset.displayName)
    }
}
