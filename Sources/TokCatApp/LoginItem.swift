import Foundation
import ServiceManagement

/// 开机自启管理。基于 `SMAppService`，仅在打包为 .app 后可用。
enum LoginItemManager {
    static var isSupported: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    static var isEnabled: Bool {
        guard isSupported else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        guard isSupported else { return false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("TokCat: 设置开机自启失败: \(error)")
            return false
        }
    }
}
