import Foundation

/// 采集游标持久化：记录每个源、每个文件已消费的字节偏移。
public final class SourceStateStore {
    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("TokCat/state.json", isDirectory: false)
    }

    private let url: URL
    private var offsets: [String: [String: Int]] = [:]
    private var dirty = false
    private var lastSave = Date.distantPast
    private let saveInterval: TimeInterval = 5

    private struct Payload: Codable {
        var offsets: [String: [String: Int]]
    }

    public init(url: URL = SourceStateStore.defaultURL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            self.offsets = payload.offsets
        }
    }

    public func offset(source: String, path: String) -> Int {
        offsets[source]?[path] ?? 0
    }

    public func setOffset(_ value: Int, source: String, path: String) {
        var map = offsets[source] ?? [:]
        if map[path] == value { return }
        map[path] = value
        offsets[source] = map
        dirty = true
    }

    /// 清理已不存在的文件记录，避免状态无限增长。
    public func pruneMissingFiles() {
        let fm = FileManager.default
        for (source, map) in offsets {
            let kept = map.filter { fm.fileExists(atPath: $0.key) }
            if kept.count != map.count {
                offsets[source] = kept
                dirty = true
            }
        }
    }

    /// 按节流策略落盘。
    public func saveIfNeeded(now: Date = Date(), force: Bool = false) {
        guard dirty else { return }
        guard force || now.timeIntervalSince(lastSave) >= saveInterval else { return }
        save(now: now)
    }

    public func save(now: Date = Date()) {
        guard dirty else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let payload = Payload(offsets: offsets)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: url, options: .atomic)
        }
        dirty = false
        lastSave = now
    }
}
