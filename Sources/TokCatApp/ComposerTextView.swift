import AppKit
import SwiftUI

/// 多行输入框（包装 `NSTextView`），**固定高度 + 内部滚动**。
///
/// - `Enter` 发送，`Shift+Enter` 换行。
/// - `⌘V`：剪贴板有图片 → 图片附件；有文件 → 文件附件；否则文本粘贴。
///   通过**本地事件监听**拦截，不依赖 Edit 菜单启用状态。
/// - 高度由外部固定；内容超出后内部滚动并自动跟随光标。
/// - 占位符直接画在 `NSTextView` 内（避免与 SwiftUI 叠层文字互相覆盖）。
struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    var isEnabled: Bool
    var placeholder: String
    /// 自适应高度的上限（约弹窗可用高度的 20%）。
    var maxHeight: CGFloat
    var onSubmit: () -> Void
    var onPasteImage: (Data) -> Void
    var onPasteFiles: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PasteAwareTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 96))
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.registerForDraggedTypes([.fileURL, .tiff, .png])
        textView.placeholder = placeholder

        // 文档视图随滚动视图宽度自适应；高度随内容增长，超出滚动区域由滚动视图处理。
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        // 完全交给 widthTracksTextView，不再手动改 containerSize（避免布局错乱）。
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        textView.string = text
        textView.applyCallbacks(
            onSubmit: onSubmit,
            onPasteImage: onPasteImage,
            onPasteFiles: onPasteFiles
        )

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        context.coordinator.textView = textView
        context.coordinator.installPasteMonitor()
        return scroll
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.removePasteMonitor()
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        context.coordinator.parent = self
        textView.applyCallbacks(
            onSubmit: onSubmit,
            onPasteImage: onPasteImage,
            onPasteFiles: onPasteFiles
        )
        textView.isEditable = isEnabled
        textView.placeholder = placeholder
        // 仅在外部改动（如补全命令/清空）时回写，避免打断正在进行的输入。
        if textView.string != text {
            textView.string = text
            textView.needsDisplay = true
        }
        if focused, textView.window?.firstResponder !== textView {
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        let width = proposal.width ?? nsView.contentSize.width
        guard let textView = context.coordinator.textView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else {
            return CGSize(width: max(1, width), height: 52)
        }

        let font = textView.font ?? NSFont.systemFont(ofSize: 13)
        let lineHeight = max(1, layoutManager.defaultLineHeight(for: font))
        let insets = textView.textContainerInset.height * 2
        // 至少 2 行：保证完整占位符提示可换行显示。
        let minimum = lineHeight * 2 + insets

        // 关键：只把文本视图宽度对齐到提案宽度，让 widthTracksTextView 自行推导容器宽度；
        // 绝不手动改 container.containerSize（那是上一版布局错乱/抖动的根因）。
        if abs(textView.frame.width - width) > 0.5 {
            textView.frame.size.width = width
        }
        layoutManager.ensureLayout(for: container)

        // 按整行离散步进，消除亚像素高度摆动。
        let contentHeight = layoutManager.usedRect(for: container).height
        let lines = max(1, Int((contentHeight / lineHeight).rounded(.up)))
        let desired = CGFloat(lines) * lineHeight + insets

        var target = min(max(desired, minimum), max(maxHeight, minimum))
        // 1pt 迟滞，避免边界处来回抖动。
        let last = context.coordinator.lastMeasuredHeight
        if last >= minimum, abs(target - last) < 1 {
            target = last
        }
        context.coordinator.lastMeasuredHeight = target
        return CGSize(width: max(1, width), height: target)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        weak var textView: PasteAwareTextView?
        var lastMeasuredHeight: CGFloat = 0
        private var keyMonitor: Any?

        init(_ parent: ComposerTextView) {
            self.parent = parent
        }

        /// 用本地事件监听拦截 ⌘V（早于菜单/窗口派发，最可靠）。
        func installPasteMonitor() {
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard let self else { return event }
                return self.handleKeyDown(event)
            }
        }

        func removePasteMonitor() {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }

        private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command),
                  event.charactersIgnoringModifiers?.lowercased() == "v",
                  let textView,
                  textView.window?.firstResponder === textView,
                  event.window === textView.window else {
                return event
            }

            let pasteboard = NSPasteboard.general
            if let urls = PasteAwareTextView.fileURLs(from: pasteboard), !urls.isEmpty {
                parent.onPasteFiles(urls)
                return nil
            }
            if let data = PasteAwareTextView.imageData(from: pasteboard) {
                parent.onPasteImage(data)
                return nil
            }
            textView.paste(nil)
            return nil
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            textView.needsDisplay = true
            textView.scrollRangeToVisible(textView.selectedRange())
        }
    }
}

/// 拦截粘贴与回车、接收拖拽、并在空文本时绘制占位符的 `NSTextView`。
final class PasteAwareTextView: NSTextView {
    var placeholder: String?

    private var onSubmit: (() -> Void)?
    private var onPasteImage: ((Data) -> Void)?
    private var onPasteFiles: (([URL]) -> Void)?

    func applyCallbacks(
        onSubmit: @escaping () -> Void,
        onPasteImage: @escaping (Data) -> Void,
        onPasteFiles: @escaping ([URL]) -> Void
    ) {
        self.onSubmit = onSubmit
        self.onPasteImage = onPasteImage
        self.onPasteFiles = onPasteFiles
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, let placeholder, !placeholder.isEmpty else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.placeholderTextColor,
        ]
        let inset = textContainerInset
        let padding = textContainer?.lineFragmentPadding ?? 0
        let rect = NSRect(
            x: inset.width + padding,
            y: inset.height,
            width: max(0, bounds.width - inset.width * 2 - padding * 2),
            height: max(0, bounds.height - inset.height * 2)
        )
        (placeholder as NSString).draw(in: rect, withAttributes: attributes)
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let urls = Self.fileURLs(from: pasteboard), !urls.isEmpty {
            onPasteFiles?(urls)
            return
        }
        if let data = Self.imageData(from: pasteboard) {
            onPasteImage?(data)
            return
        }
        super.paste(sender)
    }

    /// 次级路径：菜单启用时也会走这里。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "v" {
            paste(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func insertNewline(_ sender: Any?) {
        if NSEvent.modifierFlags.contains(.shift) {
            super.insertNewline(sender)
        } else {
            onSubmit?()
        }
    }

    override func insertNewlineIgnoringFieldEditor(_ sender: Any?) {
        super.insertNewline(sender)
    }

    // MARK: - 拖拽

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard
        if Self.imageData(from: pasteboard) != nil || !(Self.fileURLs(from: pasteboard) ?? []).isEmpty {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        if let urls = Self.fileURLs(from: pasteboard), !urls.isEmpty {
            onPasteFiles?(urls)
            return true
        }
        if let data = Self.imageData(from: pasteboard) {
            onPasteImage?(data)
            return true
        }
        return super.performDragOperation(sender)
    }

    // MARK: - 剪贴板解析

    static func imageData(from pasteboard: NSPasteboard) -> Data? {
        if let data = pasteboard.data(forType: .png) { return data }
        if let data = pasteboard.data(forType: .tiff) { return data }
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let first = images.first {
            return first.pngData()
        }
        return nil
    }

    static func fileURLs(from pasteboard: NSPasteboard) -> [URL]? {
        pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
    }
}
