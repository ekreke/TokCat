import Foundation

/// 调试用：验证 Highlight.js 资源是否可加载（`TokCat highlightcheck`）。
enum HighlightCheck {
    static func run() {
        guard let highlighter = Highlighter() else {
            print("Highlighter 初始化失败：找不到 highlight.min.js / 默认主题资源")
            return
        }
        _ = highlighter.setTheme("atom-one-dark", withFont: "Menlo-Regular", ofSize: 12)
        let sample = highlighter.highlight("let a = 1 // hello", as: "swift")
        print("Highlighter 可用：主题 \(highlighter.availableThemes().count) 个，语言 \(highlighter.supportedLanguages().count) 个，示例高亮\(sample == nil ? "失败" : "成功")")
    }
}
