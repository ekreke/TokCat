import Foundation
import TokCatCore

/// 模拟 token 采集源：产生带随机突发/回落的活动信号，用于开发期驱动动画。
final class FakeTokenSource: TokenSource {
    let id = "simulated"
    let displayName = "模拟数据"
    var isEnabled = false
    var defaultEnabled: Bool { false }

    private var lastPoll: Date?
    private var envelope: Double = 0.2

    /// 峰值速率（token/秒）。
    private let peakTokensPerSecond: Double

    init(peakTokensPerSecond: Double = 4000) {
        self.peakTokensPerSecond = peakTokensPerSecond
    }

    func poll(now: Date) -> [TokenSample] {
        let dt = lastPoll.map { max(0, now.timeIntervalSince($0)) } ?? 1
        lastPoll = now

        envelope += Double.random(in: -0.3...0.3)
        envelope = min(max(envelope, 0), 1)

        let burst = Double.random(in: 0...1) < 0.15 ? Double.random(in: 0.7...1.0) : envelope
        let intensity = max(burst, envelope)

        let total = Int((intensity * peakTokensPerSecond * dt).rounded())
        guard total > 0 else { return [] }

        let input = Int(Double(total) * 0.5)
        let output = Int(Double(total) * 0.1)
        let cacheRead = max(0, total - input - output)
        let usage = TokenUsage(input: input, output: output, cacheRead: cacheRead)

        return [TokenSample(sourceId: id, id: UUID().uuidString, at: now, model: "simulated", usage: usage)]
    }
}
