import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// 跨平台文件元数据：大小 + 修改时间（秒/纳秒）。
///
/// 采集器用它判断文件是否变化（增量读取的游标归零、数据库指纹），
/// 因此封装掉各平台的 `stat` 差异：
/// - Darwin：走 POSIX `stat`（日志目录文件多，避免 `FileManager` 构造字典的开销）。
/// - 其它平台（Windows/Linux）：回退到 `FileManager.attributesOfItem`。
public struct FileStat {
    public let size: Int
    public let mtimeSeconds: Int
    public let mtimeNanos: Int

    /// 读取路径的元数据；文件不存在或读取失败返回 nil。
    public init?(path: String) {
        #if canImport(Darwin)
        var info = stat()
        guard path.withCString({ stat($0, &info) }) == 0 else { return nil }
        self.size = Int(info.st_size)
        self.mtimeSeconds = Int(info.st_mtimespec.tv_sec)
        self.mtimeNanos = Int(info.st_mtimespec.tv_nsec)
        #else
        // TODO(windows): 可换成 WinSDK `GetFileAttributesExW` 以避免构造字典的开销。
        let fm = FileManager.default
        guard let attributes = try? fm.attributesOfItem(atPath: path) else { return nil }
        self.size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let date = (attributes[.modificationDate] as? Date) ?? .distantPast
        let interval = date.timeIntervalSince1970
        self.mtimeSeconds = Int(interval.rounded(.down))
        self.mtimeNanos = Int(((interval - interval.rounded(.down)) * 1_000_000_000).rounded())
        #endif
    }

    /// `mtime` 指纹串（用于判断文件是否变化）。
    public var signature: String {
        "\(mtimeSeconds).\(mtimeNanos):\(size)"
    }
}
