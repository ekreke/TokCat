import Foundation
import TokCatCore
import TokCatEngine

/// 注册随 App 打包的内置动画包（`Sources/TokCatApp/Resources/`）。
///
/// 目前包含复用自 RunCat365（Apache-2.0）的猫精灵图，见仓库根 `THIRD_PARTY_NOTICES.md`。
enum BundledAnimations {
    @discardableResult
    static func register() -> Int {
        // SPM 资源包在不同形态下 resourceURL 指向不同层级，逐个候选尝试。
        let bundle = Bundle.module
        var candidates: [URL] = []
        if let resourceURL = bundle.resourceURL {
            candidates.append(resourceURL)
            candidates.append(resourceURL.appendingPathComponent("Resources", isDirectory: true))
        }
        candidates.append(bundle.bundleURL.appendingPathComponent("Resources", isDirectory: true))

        let fm = FileManager.default
        var seen: Set<String> = []
        var count = 0

        for root in candidates {
            guard let entries = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for entry in entries {
                let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                guard isDirectory,
                      let pack = ImageSequenceAnimationPack(directory: entry),
                      !seen.contains(pack.identifier) else {
                    continue
                }
                seen.insert(pack.identifier)
                AnimationRegistry.shared.register(pack)
                count += 1
                Debug.log("已加载内置动画包: \(pack.displayName) @ \(entry.path)")
            }
        }

        if Debug.enabled, count == 0 {
            Debug.log("未找到内置动画包，候选目录: \(candidates.map(\.path))")
        }
        return count
    }
}
