import Foundation
import TokCatCore
import TokCatSources
import TokCatAgent

/// TokCat 常驻 CLI（Windows 适配的协议引擎雏形）。
///
/// 当前提供跨平台可用的 `dump` 诊断命令；后续将在此实现
/// stdin/stdout JSON-Lines 协议（engine / hermes / agent 命令）。
///
/// 用法：
///   TokCatCli dump      扫描本机所有采集源并打印统计
///   TokCatCli version   打印版本

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "dump"

switch command {
case "dump":
    runDump()
case "version", "--version", "-v":
    print("TokCatCli \(TokCatVersion.string)")
default:
    FileHandle.standardError.write(Data("未知命令: \(command)\n用法: TokCatCli [dump|version]\n".utf8))
    exit(2)
}

/// 版本号（Windows 无 Info.plist，使用编译期常量）。
enum TokCatVersion {
    static let string = "0.1.0"
}

/// 一次性扫描所有采集源并打印统计，用于验证解析与路径解析是否正常。
func runDump() {
    let statePath = FileManager.default.temporaryDirectory
        .appendingPathComponent("tokcat-dump-\(UUID().uuidString).json")
    let store = SourceStateStore(url: statePath)
    defer { try? FileManager.default.removeItem(at: statePath) }

    print("app support: \(PlatformPaths.tokCatSupport.path)")
    print("home: \(PlatformPaths.home.path)")

    let sources: [TokenSource] = [
        OpenCodeSource(startFromNow: false),
        ClaudeCodeSource(store: store),
        CodexSource(store: store),
        PiSource(store: store),
        CcSwitchDBSource(startFromNow: false),
    ]

    let pricing = ModelPricingStore.loadDefault()
    print("model pricing loaded: \(pricing.models.count) models")

    for source in sources {
        var count = 0
        var total = 0
        var usage = TokenUsage.zero
        var lastModel: String?
        var firstAt: Date?
        var lastAt: Date?
        for _ in 0..<200 {
            let samples = source.poll(now: Date())
            if samples.isEmpty { break }
            count += samples.count
            for sample in samples {
                total += sample.usage.total
                usage += sample.usage
                if sample.model != nil { lastModel = sample.model }
                firstAt = firstAt ?? sample.at
                if lastAt == nil || sample.at > lastAt! { lastAt = sample.at }
            }
        }
        let span = (firstAt != nil && lastAt != nil) ? lastAt!.timeIntervalSince(firstAt!) : 0
        print("""
        [\(source.id)] samples=\(count) total=\(total) \
        in=\(usage.input) out=\(usage.output) cacheR=\(usage.cacheRead) cacheW=\(usage.cacheWrite) reason=\(usage.reasoning) \
        span=\(Int(span))s model=\(lastModel ?? "-")
        """)
    }
}
