import Foundation

/// 流式文本节流器：把高频的增量更新合并为固定间隔刷新，避免每来一个 token
/// 就重解析整段 Markdown。
///
/// 时间与调度都可注入，便于单元测试。
public final class StreamingTextThrottle {
    /// 刷新间隔（秒）。
    public let interval: TimeInterval

    private let now: () -> Date
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void

    private var lastFlush: Date
    private var pendingWork: (() -> Void)?
    private var isPending = false

    public init(
        interval: TimeInterval = 0.15,
        now: @escaping () -> Date = Date.init,
        schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    ) {
        self.interval = max(0, interval)
        self.now = now
        self.schedule = schedule
        self.lastFlush = .distantPast
    }

    /// 提交一次更新。`flush` 会立即执行（距上次刷新已超过间隔），
    /// 或在间隔到期后执行一次；间隔内的多次提交会被合并为最后一次。
    public func submit(_ flush: @escaping () -> Void) {
        let current = now()
        if !isPending, current.timeIntervalSince(lastFlush) >= interval {
            lastFlush = current
            flush()
            return
        }

        pendingWork = flush
        guard !isPending else { return }

        isPending = true
        let delay = max(0, interval - current.timeIntervalSince(lastFlush))
        schedule(delay) { [weak self] in
            guard let self, let work = self.pendingWork else { return }
            self.isPending = false
            self.pendingWork = nil
            self.lastFlush = self.now()
            work()
        }
    }

    /// 立即刷新并取消待执行的节流刷新（用于回答结束/失败/取消）。
    public func force(_ flush: () -> Void) {
        isPending = false
        pendingWork = nil
        lastFlush = now()
        flush()
    }

    public func reset() {
        isPending = false
        pendingWork = nil
        lastFlush = .distantPast
    }
}
