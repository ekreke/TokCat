import Foundation

/// 递归扫描目录下所有 JSONL 文件并增量读取新增行。
public final class DirectoryTailer {
    public let sourceId: String
    public let root: URL
    public let fileExtension: String

    private let store: SourceStateStore
    private var tails: [String: FileTail] = [:]

    private var cachedFiles: [URL] = []
    private var lastEnumeration: Date = .distantPast
    /// 目录遍历较重（日志目录可能有上百个文件），按此间隔重建文件列表。
    private let enumerationInterval: TimeInterval = 5

    public init(sourceId: String, root: URL, fileExtension: String = "jsonl", store: SourceStateStore) {
        self.sourceId = sourceId
        self.root = root
        self.fileExtension = fileExtension
        self.store = store
    }

    /// 返回自上次以来新增的 (文件路径, 行内容)。
    public func pollNewLines(limit: Int = 20_000) -> [(path: String, line: String)] {
        let now = Date()
        if cachedFiles.isEmpty || now.timeIntervalSince(lastEnumeration) >= enumerationInterval {
            lastEnumeration = now
            cachedFiles = enumerateFiles()
        }

        var results: [(path: String, line: String)] = []
        for url in cachedFiles {
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

    private func enumerateFiles() -> [URL] {
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
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == fileExtension {
            files.append(url)
        }
        return files
    }
}
