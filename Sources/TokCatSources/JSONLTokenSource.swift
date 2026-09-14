import Foundation
import TokCatCore

/// JSONL 采集源基类：负责目录增量读取与去重，子类只需实现单行解析。
open class JSONLTokenSource: TokenSource {
    public let id: String
    public let displayName: String
    public var isEnabled = true

    private let tailer: DirectoryTailer
    /// Codex 等源的模型名分散在其他事件里，按文件记录最近一次见到的模型。
    var modelByFile: [String: String] = [:]

    private var seen: Set<String> = []
    private let seenLimit = 100_000

    public init(
        id: String,
        displayName: String,
        root: URL,
        fileExtension: String = "jsonl",
        store: SourceStateStore
    ) {
        self.id = id
        self.displayName = displayName
        self.tailer = DirectoryTailer(sourceId: id, root: root, fileExtension: fileExtension, store: store)
    }

    /// 解析单行，返回本次消耗样本；无法识别时返回 nil。
    open func parse(path: String, line: String) -> TokenSample? { nil }

    public func poll(now: Date) -> [TokenSample] {
        var samples: [TokenSample] = []
        for (path, line) in tailer.pollNewLines() {
            guard let sample = parse(path: path, line: line) else { continue }
            let key = "\(sample.sourceId):\(sample.id)"
            if seen.contains(key) { continue }
            markSeen(key)
            samples.append(sample)
        }
        return samples
    }

    private func markSeen(_ key: String) {
        if seen.count >= seenLimit { seen.removeAll(keepingCapacity: true) }
        seen.insert(key)
    }

    /// 读取某个文件当前记录的模型。
    func model(for path: String) -> String? { modelByFile[path] }

    func setModel(_ model: String, for path: String) { modelByFile[path] = model }
}

/// 常用路径。
public enum AgentPaths {
    public static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    public static var claudeProjects: URL { home.appendingPathComponent(".claude/projects") }
    public static var codexSessions: URL { home.appendingPathComponent(".codex/sessions") }
    public static var piSessions: URL { home.appendingPathComponent(".pi/agent/sessions") }
    public static var openCodeDB: String { home.appendingPathComponent(".local/share/opencode/opencode.db").path }
    public static var ccSwitchDB: String { home.appendingPathComponent(".cc-switch/cc-switch.db").path }
    public static var ccSwitchPricing: String { home.appendingPathComponent(".cc-switch/model-pricing.json").path }
}
