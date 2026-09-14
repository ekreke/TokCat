import Foundation

/// 递归扫描目录下所有 JSONL 文件并增量读取新增行。
public final class DirectoryTailer {
    public let sourceId: String
    public let root: URL
    public let fileExtension: String

    private let store: SourceStateStore
    private var tails: [String: FileTail] = [:]

    public init(sourceId: String, root: URL, fileExtension: String = "jsonl", store: SourceStateStore) {
        self.sourceId = sourceId
        self.root = root
        self.fileExtension = fileExtension
        self.store = store
    }

    /// 返回自上次以来新增的 (文件路径, 行内容)。
    public func pollNewLines(limit: Int = 20_000) -> [(path: String, line: String)] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var results: [(path: String, line: String)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == fileExtension else { continue }
            let path = url.path
            let tail = tails[path] ?? FileTail(offset: store.offset(source: sourceId, path: path))
            tails[path] = tail
            for line in tail.readNewLines(at: url) {
                results.append((path, line))
                if results.count >= limit { break }
            }
            store.setOffset(tail.offset, source: sourceId, path: path)
            if results.count >= limit { break }
        }
        return results
    }
}
