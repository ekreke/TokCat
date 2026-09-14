import Foundation

/// 简易调试日志，设置环境变量 `TOKCAT_DEBUG=1` 后输出到 stderr。
enum Debug {
    static let enabled = ProcessInfo.processInfo.environment["TOKCAT_DEBUG"] == "1"

    static func log(_ message: String) {
        guard enabled else { return }
        FileHandle.standardError.write(Data("[TokCat] \(message)\n".utf8))
    }
}
