import Foundation
import TokCatCore

/// 采集源工厂：构造默认采集源集合。
public enum SourceFactory {
    /// 默认源：四个本地 agent 日志源 + 可选的 cc-switch 聚合源。
    public static func makeDefault(store: SourceStateStore = SourceStateStore()) -> [TokenSource] {
        [
            OpenCodeSource(),
            ClaudeCodeSource(store: store),
            CodexSource(store: store),
            PiSource(store: store),
            CcSwitchDBSource(),
        ]
    }
}
