import AppKit
import MarkdownUI
import SwiftUI

/// Chat 回答的 Markdown 渲染：MarkdownUI 负责块级/行内样式，HighlighterSwift
/// （Highlight.js）负责代码块语法高亮。
struct ChatMarkdownView: View {
    let markdown: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Markdown(markdown)
            .markdownTheme(.tokcatCompact)
            .markdownCodeSyntaxHighlighter(
                colorScheme == .dark
                    ? HighlightjsCodeSyntaxHighlighter.dark
                    : HighlightjsCodeSyntaxHighlighter.light
            )
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                NSWorkspace.shared.open(url)
                return .handled
            })
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 语法高亮

/// 用 Highlight.js 高亮代码块，并按 `语言 + 源码` 缓存结果。
///
/// 缓存很关键：流式渲染时同一个代码块会被反复请求，Highlight.js 走
/// JavaScriptCore，虽然单次约几十毫秒，但重复调用会明显拖慢刷新。
final class HighlightjsCodeSyntaxHighlighter: CodeSyntaxHighlighter {
    static let light = HighlightjsCodeSyntaxHighlighter(theme: "atom-one-light")
    static let dark = HighlightjsCodeSyntaxHighlighter(theme: "atom-one-dark")

    private let highlighter: Highlighter?
    private let cache = NSCache<NSString, NSAttributedString>()

    private init(theme: String) {
        let highlighter = Highlighter()
        if let highlighter {
            _ = highlighter.setTheme(theme, withFont: "Menlo-Regular", ofSize: 12)
        }
        self.highlighter = highlighter
        cache.countLimit = 300
    }

    func highlightCode(_ code: String, language: String?) -> Text {
        guard let highlighter else { return Text(code) }

        let key = "\(language ?? "")\u{1}\(code)" as NSString
        if let cached = cache.object(forKey: key) {
            return Text(AttributedString(cached))
        }
        guard let highlighted = highlighter.highlight(code, as: language) else {
            return Text(code)
        }
        let sanitized = Self.sanitize(highlighted)
        cache.setObject(sanitized, forKey: key)
        return Text(AttributedString(sanitized))
    }

    /// 去掉 Highlighter 自带的字体/背景色/段距，交给 MarkdownUI 主题控制，
    /// 只保留 token 的前景色。
    private static func sanitize(_ attributed: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let full = NSRange(location: 0, length: mutable.length)
        mutable.removeAttribute(.backgroundColor, range: full)
        mutable.removeAttribute(.font, range: full)
        mutable.removeAttribute(.paragraphStyle, range: full)
        return mutable
    }
}

// MARK: - 紧凑主题

extension MarkdownUI.Theme {
    /// 在 `.basic` 基础上收窄标题与间距，适配窄弹窗。
    static let tokcatCompact = MarkdownUI.Theme()
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.85))
        }
        .heading1 { configuration in
            configuration.label
                .markdownMargin(top: .em(0.8), bottom: .em(0.35))
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.35))
                }
        }
        .heading2 { configuration in
            configuration.label
                .markdownMargin(top: .em(0.8), bottom: .em(0.35))
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.2))
                }
        }
        .heading3 { configuration in
            configuration.label
                .markdownMargin(top: .em(0.7), bottom: .em(0.3))
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.08))
                }
        }
        .heading4 { configuration in
            configuration.label
                .markdownMargin(top: .em(0.6), bottom: .em(0.25))
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1))
                }
        }
        .heading5 { configuration in
            configuration.label
                .markdownMargin(top: .em(0.6), bottom: .em(0.25))
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(0.9))
                }
        }
        .heading6 { configuration in
            configuration.label
                .markdownMargin(top: .em(0.6), bottom: .em(0.25))
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(0.85))
                }
        }
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.12))
                .markdownMargin(top: .zero, bottom: .em(0.6))
        }
        .blockquote { configuration in
            configuration.label
                .markdownTextStyle {
                    FontStyle(.italic)
                }
                .relativePadding(.leading, length: .em(1.5))
                .relativePadding(.trailing, length: .em(0.5))
        }
        .codeBlock { configuration in
            ScrollView(.horizontal) {
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.12))
                    .relativePadding(.leading, length: .rem(0.8))
                    .relativePadding(.trailing, length: .rem(0.4))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.85))
                    }
            }
            .markdownMargin(top: .zero, bottom: .em(0.6))
        }
        .table { configuration in
            ScrollView(.horizontal) {
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
            }
            .markdownMargin(top: .zero, bottom: .em(0.6))
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 {
                        FontWeight(.semibold)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.12))
                .relativePadding(.horizontal, length: .em(0.6))
                .relativePadding(.vertical, length: .em(0.28))
        }
        .thematicBreak {
            Divider().markdownMargin(top: .em(1.2), bottom: .em(1.2))
        }
}
