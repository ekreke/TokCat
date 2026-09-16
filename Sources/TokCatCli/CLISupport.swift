import Foundation

/// 构建版本号（由 CI/发布注入）。
enum TokCatVersion {
    static var string: String { TokCatBuildVersion.string }
}

/// 协议输出（stdout 只放 JSON-Lines；日志走 stderr）。
let stdoutLock = NSLock()

func emit(_ object: [String: Any]) {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object) else { return }
    var line = data
    line.append(0x0A)
    stdoutLock.lock()
    FileHandle.standardOutput.write(line)
    stdoutLock.unlock()
}

func emitOK(_ id: Any?) {
    emit(["id": id ?? NSNull(), "ok": true])
}

func emitError(_ id: Any?, _ message: String) {
    emit(["id": id ?? NSNull(), "ok": false, "error": message])
}
