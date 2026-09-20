import Foundation

extension Bundle {
    /// TokCatApp 的 SPM 资源包（含动画素材与代码高亮主题）。
    ///
    /// 不用 `Bundle.module`：SwiftPM 6.1 生成的 accessor 只查 .app 根目录
    /// （`Bundle.main.bundleURL`）与构建机绝对路径——前者违反 macOS 签名规范
    /// （bundle 根不允许 Contents 以外的条目），后者在分发环境不存在，两种
    /// 情况都会直接 fatalError（v0.1.14 发布版崩溃的根因）。这里按实际
    /// 分发/开发布局手动查找：
    /// - .app 分发：`Contents/Resources/TokCat_TokCatApp.bundle`
    /// - swift run 开发：`.build/<config>/TokCat_TokCatApp.bundle`（与二进制同目录）
    ///
    /// 兜底返回 `Bundle.main` 而非 fatalError：资源缺失时优雅降级
    /// （动画包扫描为空、高亮 init 返回 nil），应用仍可运行。
    static let tokCatResources: Bundle = {
        let candidates = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
        ].compactMap { $0 }

        for candidate in candidates {
            if let bundle = Bundle(url: candidate.appendingPathComponent("TokCat_TokCatApp.bundle")) {
                return bundle
            }
        }
        return Bundle.main
    }()
}
