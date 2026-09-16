import AppKit
import SwiftUI

/// 单行文本输入框：直接包装 `NSTextView`，不经 field editor。
///
/// SwiftUI `TextField`（`SelectionTextField` cell → field editor）在
/// macOS 15.2 上点按/拖选可触发 TextKit 2 `synchronizeTextLayoutManagers`
/// 死循环（Apple 侧 bug，栈内全为框架帧），此视图绕开该路径；
/// 同时绝不访问 `layoutManager`（会在 TextKit 2 视图上挂载 TK1 双布局器）。
struct SingleLineTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = SingleLineTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 20))
        textView.font = .systemFont(ofSize: 13)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 4, height: 3)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        // 不折行：容器给超宽，文本横向增长，超出部分由光标跟随滚动可见。
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.placeholder = placeholder
        textView.string = text
        textView.delegate = context.coordinator
        textView.onEnter = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onSubmit?()
        }

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        scroll.borderType = .bezelBorder

        context.coordinator.textView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        if textView.placeholder != placeholder {
            textView.placeholder = placeholder
            textView.needsDisplay = true
        }
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SingleLineTextField
        weak var textView: SingleLineTextView?

        init(_ parent: SingleLineTextField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            // 粘贴多行时压平成单行（设置项均为单行值）。
            if textView.string.contains("\n") {
                let sanitized = textView.string.replacingOccurrences(of: "\n", with: " ")
                textView.string = sanitized
                textView.setSelectedRange(NSRange(location: sanitized.count, length: 0))
            }
            parent.text = textView.string
        }
    }
}

/// 带占位符绘制、回车交出焦点的单行 `NSTextView`。
final class SingleLineTextView: NSTextView {
    var placeholder: String = ""
    var onEnter: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func insertNewline(_ sender: Any?) {
        onEnter?()
        window?.makeFirstResponder(nil)
    }

    override func insertTab(_ sender: Any?) {
        window?.selectNextKeyView(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty, let font else { return }
        let origin = NSPoint(
            x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
            y: textContainerInset.height
        )
        (placeholder as NSString).draw(
            at: origin,
            withAttributes: [
                .font: font,
                .foregroundColor: NSColor.placeholderTextColor
            ]
        )
    }
}

/// 只读可选中的等宽日志视图（自带滚动），替代 `Text + .textSelection(.enabled)`
/// 以避开 SwiftUI 文本交互路径上的同类 TextKit 2 死循环风险；更新时自动滚到底部。
struct ReadOnlyLogTextView: NSViewRepresentable {
    var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.string = text

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        scroll.borderType = .lineBorder
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            textView.scrollToEndOfDocument(nil)
        }
    }
}
