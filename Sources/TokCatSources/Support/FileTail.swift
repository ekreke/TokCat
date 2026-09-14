import Foundation
import Darwin

/// 单文件增量尾部读取器。
///
/// 只消费以换行符结束的完整行，游标始终停在最后一个换行符之后；
/// 文件被截断/轮转（大小小于游标）时自动归零。
public final class FileTail {
    public private(set) var offset: Int

    public init(offset: Int = 0) {
        self.offset = max(0, offset)
    }

    /// 读取自上次以来新增的完整行，并推进游标。
    public func readNewLines(at url: URL) -> [String] {
        var info = stat()
        // 用 POSIX stat 而非 FileManager.attributesOfItem：日志目录文件很多，
        // 后者会构造字典，轮询开销明显。
        guard url.path.withCString({ stat($0, &info) }) == 0 else { return [] }
        let size = Int(info.st_size)

        if size < offset { offset = 0 }
        guard size > offset else { return [] }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: UInt64(offset))
            let data = handle.readDataToEndOfFile()
            guard !data.isEmpty, let lastNewline = data.lastIndex(of: 0x0A) else {
                return []
            }
            let complete = data[data.startIndex...lastNewline]
            offset += complete.count
            let text = String(decoding: complete, as: UTF8.self)
            return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        } catch {
            return []
        }
    }
}
