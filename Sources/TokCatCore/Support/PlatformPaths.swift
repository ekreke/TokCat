import Foundation

/// 跨平台常用目录解析。
///
/// Foundation 在 macOS 上把 `.applicationSupportDirectory` 解析为
/// `~/Library/Application Support`，在 Windows 上解析为 `%APPDATA%`，
/// 因此集中在这里，避免各处硬编码 `Library/Application Support`。
public enum PlatformPaths {
    /// 用户主目录。
    public static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    /// 应用数据根目录。
    public static var applicationSupport: URL {
        if let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return url
        }
        return home.appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    /// TokCat 自身的数据目录（状态、动画、设置）。
    public static var tokCatSupport: URL {
        applicationSupport.appendingPathComponent("TokCat", isDirectory: true)
    }

    /// 外部动画包目录。
    public static var animationsDirectory: URL {
        tokCatSupport.appendingPathComponent("Animations", isDirectory: true)
    }
}
