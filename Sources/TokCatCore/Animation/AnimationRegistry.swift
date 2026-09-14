import AppKit

/// 动画包注册表：内置包 + 外部目录动态加载。
public final class AnimationRegistry {
    public static let shared = AnimationRegistry()

    private var packs: [String: AnimationPack] = [:]
    private let lock = NSLock()

    public init() {}

    /// 默认的外部动画包目录：`~/Library/Application Support/TokCat/Animations`
    public static var defaultExternalDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("TokCat/Animations", isDirectory: true)
    }

    public func register(_ pack: AnimationPack) {
        lock.lock(); defer { lock.unlock() }
        packs[pack.identifier] = pack
    }

    public func pack(identifier: String) -> AnimationPack? {
        lock.lock(); defer { lock.unlock() }
        return packs[identifier]
    }

    public var allPacks: [AnimationPack] {
        lock.lock(); defer { lock.unlock() }
        return packs.values.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    public var defaultPack: AnimationPack? {
        pack(identifier: BuiltinCatPack.identifier) ?? allPacks.first
    }

    /// 注册内置包并扫描外部目录。返回加载到的外部包数量。
    @discardableResult
    public func loadAll(externalDirectory: URL = AnimationRegistry.defaultExternalDirectory) -> Int {
        register(BuiltinCatPack())
        return loadExternalPacks(from: externalDirectory)
    }

    /// 扫描外部目录，加载所有合法的动画包。
    @discardableResult
    public func loadExternalPacks(from directory: URL) -> Int {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var count = 0
        for entry in entries {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir, let pack = ImageSequenceAnimationPack(directory: entry) else { continue }
            register(pack)
            count += 1
        }
        return count
    }
}
