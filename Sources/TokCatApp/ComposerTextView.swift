import AppKit
import SwiftUI

/// 多行输入框（包装 `NSTextView`），**可变高度 + 内部滚动**。
///
/// - `Enter` 发送，`Shift+Enter` 换行。
/// - `⌘V`：剪贴板有图片 → 图片附件；有文件 → 文件附件；否则文本粘贴。
/// - 高度由 AppKit 侧**实测**并通过 `height` 绑定回传给 SwiftUI，
///   不使用 `sizeThatFits`（避免「SwiftUI 布局 ↔ AppKit 布局」来回触发导致的抖动）。
struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    /// AppKit 实测高度（SwiftUI 只负责应用 frame）。
    @Binding var height: CGFloat
    @Binding var focused: Bool
    var isEnabled: Bool
    /// 自适应高度的上限。
    var maxHeight: CGFloat
    var onSubmit: () -> Void
    var onPasteImage: (Data) -> Void
    var onPasteFiles: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PasteAwareTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 34))
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.registerForDraggedTypes([.fileURL, .tiff, .png])

        // 文档视图随滚动视图宽度自适应；高度随内容增长，超出滚动区域由滚动视图处理。
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        textView.string = text
        textView.applyCallbacks(
            onSubmit: onSubmit,
            onPasteImage: onPasteImage,
            onPasteFiles: onPasteFiles
        )
        textView.onSizeChanged = { [weak coordinator = context.coordinator] in
            coordinator?.recomputeHeight()
        }

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        context.coordinator.textView = textView
        context.coordinator.installPasteMonitor()
        context.coordinator.recomputeHeight()
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
        // 仅在外部改动（如补全命令/清空）时回写，避免打断正在进行的输入。
        if textView.string != text {
            textView.string = text
        }
        if focused, textView.window?.firstResponder !== textView {
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
        context.coordinator.recomputeHeight()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        weak var textView: PasteAwareTextView?
        private var keyMonitor: Any?
        private var lastDispatchedHeight: CGFloat = 0

        init(_ parent: ComposerTextView) {
            self.parent = parent
        }

        /// 由 AppKit 实测内容高度，按整行取整并 clamp 到上限，变化 ≥1pt 才回写绑定。
        func recomputeHeight() {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let container = textView.textContainer,
                  textView.bounds.width > 0 else { return }

            let font = textView.font ?? NSFont.systemFont(ofSize: 13)
            let lineHeight = max(1, layoutManager.defaultLineHeight(for: font))
            let insets = textView.textContainerInset.height * 2

            layoutManager.ensureLayout(for: container)
            let contentHeight = layoutManager.usedRect(for: container).height
            let lines = max(1, Int((contentHeight / lineHeight).rounded(.up)))
            let desired = CGFloat(lines) * lineHeight + insets

            let upper = max(parent.maxHeight, minimumHeight())
            let target = min(max(desired, minimumHeight()), upper)
            if abs(target - lastDispatchedHeight) >= 1 {
                lastDispatchedHeight = target
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.parent.height = target
                }
            }
        }

        private func minimumHeight() -> CGFloat {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let font = textView.font ?? textView.font else { return 34 }
            let lineHeight = max(1, layoutManager.defaultLineHeight(for: font))
            return lineHeight + textView.textContainerInset.height * 2
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
            textView.scrollRangeToVisible(textView.selectedRange())
            recomputeHeight()
        }
    }
}

/// 拦截粘贴与回车、接收拖拽的 `NSTextView`。
final class PasteAwareTextView: NSTextView {
    private var onSubmit: (() -> Void)?
    private var onPasteImage: ((Data) -> Void)?
    private var onPasteFiles: (([URL]) -> Void)?
    var onSizeChanged: (() -> Void)?

    func applyCallbacks(
        onSubmit: @escaping () -> Void,
        onPasteImage: @escaping (Data) -> Void,
        onPasteFiles: @escaping ([URL]) -> Void
    ) {
        self.onSubmit = onSubmit
        self.onPasteImage = onPasteImage
        self.onPasteFiles = onPasteFiles
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

    // MARK: - 尺寸变化回调

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onSizeChanged?()
    }

    override func layout() {
        super.layout()
        onSizeChanged?()
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
