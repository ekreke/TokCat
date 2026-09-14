import AppKit
import SwiftUI

/// 承载「Hermes 设置」窗口的控制器。
final class HermesSettingsController {
    private let model: HermesSettingsModel
    private var window: NSWindow?

    init(settings: AppSettings, onChange: @escaping () -> Void) {
        self.model = HermesSettingsModel(settings: settings, onChange: onChange)
    }

    func show() {
        model.refreshLocal()
        if window == nil {
            let hosting = NSHostingController(rootView: HermesSettingsView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "TokCat · Hermes 设置"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 560, height: 680))
            window.contentMinSize = NSSize(width: 520, height: 520)
            self.window = window
        }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
