import AppKit
import SwiftUI

/// 承载「Agent 检测 / 一键安装」窗口的控制器。
final class AgentSetupController {
    private let model: AgentSetupModel
    private var window: NSWindow?

    init(settings: AppSettings) {
        self.model = AgentSetupModel(settings: settings)
    }

    func show() {
        model.refresh()
        if window == nil {
            let hosting = NSHostingController(rootView: AgentSetupView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "TokCat · Agent"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            self.window = window
        }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
