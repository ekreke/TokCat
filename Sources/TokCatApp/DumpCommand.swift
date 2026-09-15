import Foundation
import TokCatCore
import TokCatSources

/// 调试用：一次性扫描本机所有采集源并打印统计，用于验证解析是否正常。
/// 用法：`TokCat dump`
enum DumpCommand {
    static func run() {
        let statePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokcat-dump-\(UUID().uuidString).json")
        let store = SourceStateStore(url: statePath)
        defer { try? FileManager.default.removeItem(at: statePath) }

        let sources: [TokenSource] = [
            OpenCodeSource(startFromNow: false),
            ClaudeCodeSource(store: store),
            CodexSource(store: store),
            PiSource(store: store),
            HermesSource(startFromNow: false),
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
}
